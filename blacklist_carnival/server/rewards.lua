-- Idempotent reward (item) delivery with staff reconciliation.
--
-- Lifecycle of a carnival_rewards row:
--   awaiting_approval -> approved -> delivering -> delivered
--   pending/failed ---------------> delivering -> delivered | failed | pending (offline)
--   delivering (found after a restart) -> unknown  (never replayed automatically)
--   any non-delivered -> cancelled (staff, with reason)
--
-- A reward row is created with a unique idempotency key BEFORE any item moves, and
-- delivery claims the row with a guarded UPDATE, so a retried callback, a
-- reconnect or two staff clicking "retry" can never deliver twice.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Rewards = {}
Carnival.Rewards = Rewards

function Rewards.isPermitted(item)
    if type(item) ~= 'string' or item == '' then return false end
    if C.TICKET_ITEM_COLOUR[item] then return false end
    return Carnival.Config.permittedRewardItems()[item] == true
end

local function sourceForCitizen(cid)
    local p = Carnival.Participants.getByCitizen(cid)
    if p then
        local s = Carnival.Participants.sourceOf(p.id)
        if s then return s end
    end
    local ok, player = pcall(function() return exports.qbx_core:GetPlayerByCitizenId(cid) end)
    if ok and player and player.PlayerData then return player.PlayerData.source end
    return nil
end

-- opts: participantId, source, item, count, metadata, key, requiresApproval, note
-- Returns reward row, created(bool) | nil, code, message
function Rewards.create(opts)
    local e = Carnival.Events.active
    if not e then return nil, 'no_event' end
    local p = Carnival.Participants.get(opts.participantId)
    if not p then return nil, 'not_found', 'Participant not found.' end
    if not Rewards.isPermitted(opts.item) then
        Carnival.Monitor.log('error', 'reward', 'reward_item_not_permitted', { participantId = p.id, details = { item = tostring(opts.item), source = opts.source } })
        return nil, 'item_not_permitted', 'That item is not a permitted reward.'
    end
    local count = math.tointeger(opts.count) or 0
    if count < 1 or count > Carnival.Config.get().rewards.maxCount then
        return nil, 'bad_quantity', 'Invalid reward quantity.'
    end
    local existing = Carnival.Db.single('SELECT * FROM carnival_rewards WHERE event_id = ? AND idempotency_key = ?', { e.id, opts.key })
    if existing then return existing, false end
    local now = os.time()
    local id = Carnival.Db.insertRow('carnival_rewards', {
        event_id = e.id, participant_id = p.id, citizenid = p.citizenid, source = opts.source,
        item = opts.item, count = count, metadata = opts.metadata and json.encode(opts.metadata) or nil,
        status = opts.requiresApproval and 'awaiting_approval' or 'pending',
        requires_approval = opts.requiresApproval and 1 or 0, idempotency_key = opts.key,
        note = opts.note, created_at = now, updated_at = now,
    })
    if not id then
        existing = Carnival.Db.single('SELECT * FROM carnival_rewards WHERE event_id = ? AND idempotency_key = ?', { e.id, opts.key })
        if existing then return existing, false end
        return nil, 'database_error', 'Reward could not be recorded.'
    end
    Carnival.Monitor.log('info', 'reward', 'reward_created', { participantId = p.id, details = { rewardId = id, item = opts.item, count = count, source = opts.source, approval = opts.requiresApproval } })
    Carnival.Push.invalidate('rewards')
    return Carnival.Db.single('SELECT * FROM carnival_rewards WHERE id = ?', { id }), true
end

local function recordAttempt(rewardId, attempt, result, err, actor)
    Carnival.Db.insertRow('carnival_reward_attempts', {
        reward_id = rewardId, attempt = attempt, result = result, error = err,
        actor = actor and actor.license or nil, created_at = os.time(),
    })
end

-- Attempt delivery. Returns status string.
function Rewards.deliver(rewardId, actor)
    local claimed = Carnival.Db.update(
        "UPDATE carnival_rewards SET status = 'delivering', attempts = attempts + 1, updated_at = ? WHERE id = ? AND status IN ('pending', 'failed', 'approved')",
        { os.time(), rewardId })
    local r = Carnival.Db.single('SELECT * FROM carnival_rewards WHERE id = ?', { rewardId })
    if not r then return 'not_found' end
    if not claimed or claimed < 1 then return r.status end -- someone else holds it or it is final

    local function finish(status, err)
        Carnival.Db.updateRow('carnival_rewards', {
            status = status, last_error = err or Carnival.Db.NULL, updated_at = os.time(),
            delivered_at = status == 'delivered' and os.time() or Carnival.Db.NULL,
        }, 'id = ? AND status = ?', { rewardId, 'delivering' })
        recordAttempt(rewardId, r.attempts, status, err, actor)
        Carnival.Monitor.log(status == 'delivered' and 'info' or 'warning', 'reward', 'reward_delivery', {
            eventId = r.event_id, participantId = r.participant_id, actor = actor, result = status,
            details = { rewardId = rewardId, item = r.item, count = r.count, error = err },
        })
        Carnival.Push.invalidate('rewards', 'dashboard')
        return status
    end

    if not Rewards.isPermitted(r.item) then return finish('failed', 'item_no_longer_permitted') end
    if not Carnival.Inventory.itemExists(r.item) then return finish('failed', 'item_not_registered') end
    local src = sourceForCitizen(r.citizenid)
    if not src then return finish('pending', 'player_offline') end
    local md = Carnival.Db.decode(r.metadata, nil)
    if not Carnival.Inventory.canCarry(src, r.item, r.count, md) then
        Carnival.Push.notify(src, 'Prize waiting', 'Your pockets are full. Make space and your carnival prize will be delivered.', 'warning')
        return finish('failed', 'inventory_full')
    end
    local ok, err = Carnival.Inventory.addItem(src, r.item, r.count, md)
    if not ok then return finish('failed', tostring(err)) end
    Carnival.Push.notify(src, 'Prize received', ('%dx %s'):format(r.count, Carnival.Inventory.itemLabel(r.item)), 'success', 'treat_sparkle')
    return finish('delivered')
end

-- Statuses an automatic retry may pick up (never 'unknown': a delivery cut off
-- by a restart may already have reached the player and needs a human check).
local RETRYABLE_ERRORS_SKIP = { item_no_longer_permitted = true, item_not_registered = true }

-- Retry every undelivered prize of one character, from any night.
function Rewards.retryForCitizen(cid)
    if not cid then return 0 end
    local rows = Carnival.Db.query([[SELECT id, last_error FROM carnival_rewards
        WHERE citizenid = ? AND status IN ('pending', 'failed', 'approved') ORDER BY id]], { cid }) or {}
    local n = 0
    for _, r in ipairs(rows) do
        if not RETRYABLE_ERRORS_SKIP[r.last_error or ''] then
            Rewards.deliver(r.id, Carnival.Identity.SYSTEM)
            n = n + 1
        end
    end
    return n
end

-- Every few minutes, try again for everyone online who is still owed a prize
-- (full pockets, or offline when the night ended) - no staff needed.
local lastSweep = 0
function Rewards.sweep(now)
    now = now or os.time()
    local every = (Carnival.Config.get().rewards.retryMinutes or 0) * 60
    if every <= 0 or now - lastSweep < every then return end
    lastSweep = now
    local rows = Carnival.Db.query([[SELECT DISTINCT citizenid FROM carnival_rewards
        WHERE status IN ('pending', 'failed', 'approved')]]) or {}
    for _, r in ipairs(rows) do
        if sourceForCitizen(r.citizenid) then Rewards.retryForCitizen(r.citizenid) end
    end
end
Carnival.onTick('rewards_retry', function(now) Rewards.sweep(now) end)

function Rewards.retryPendingFor(pid)
    local rows = Carnival.Db.query("SELECT id FROM carnival_rewards WHERE participant_id = ? AND status IN ('pending', 'failed', 'approved')", { pid }) or {}
    for _, r in ipairs(rows) do Rewards.deliver(r.id, Carnival.Identity.SYSTEM) end
end

-- After a restart any reward caught mid-delivery is marked unknown for staff review.
function Rewards.recover(eventId)
    local n = Carnival.Db.update("UPDATE carnival_rewards SET status = 'unknown', last_error = 'interrupted_during_delivery', updated_at = ? WHERE status = 'delivering'", { os.time() })
    if n and n > 0 then
        Carnival.Monitor.log('warning', 'recovery', 'rewards_need_reconciliation', { eventId = eventId, details = { count = n } })
    end
end

local function staffChange(src, id, fromStatuses, toStatus, reason, action, extra)
    local r = Carnival.Db.single('SELECT * FROM carnival_rewards WHERE id = ?', { id })
    if not r then return nil, 'not_found', 'Reward not found.' end
    local allowed = U.toSet(fromStatuses)
    if not allowed[r.status] then return nil, 'invalid', ('Reward is %s.'):format(r.status) end
    local actor = Carnival.Identity.actor(src)
    local set = { status = toStatus, updated_at = os.time(), note = reason }
    for k, v in pairs(extra or {}) do set[k] = v end
    local n = Carnival.Db.updateRow('carnival_rewards', set, 'id = ? AND status = ?', { id, r.status })
    if not n or n < 1 then return nil, 'conflict', 'The reward changed meanwhile.' end
    recordAttempt(id, r.attempts, toStatus, reason, actor)
    Carnival.Audit.record(actor, action, { eventId = r.event_id, targetType = 'reward', targetId = id, reason = reason,
        details = { item = r.item, count = r.count, participant = r.participant_id, from = r.status, to = toStatus } })
    Carnival.Push.invalidate('rewards', 'dashboard')
    return true
end

function Rewards.approve(src, id, reason)
    local ok, code, msg = staffChange(src, id, { 'awaiting_approval' }, 'approved', reason, 'reward_approved', { approved_by = Carnival.Identity.actor(src).license })
    if not ok then return nil, code, msg end
    return { status = Rewards.deliver(id, Carnival.Identity.actor(src)) }
end

function Rewards.retry(src, id)
    local r = Carnival.Db.single('SELECT status FROM carnival_rewards WHERE id = ?', { id })
    if not r then return nil, 'not_found' end
    if r.status == 'unknown' then
        return nil, 'invalid', 'Delivery state is unknown. Check the player inventory, then mark delivered or reset to pending.'
    end
    Carnival.Audit.record(Carnival.Identity.actor(src), 'reward_retry', { targetType = 'reward', targetId = id })
    return { status = Rewards.deliver(id, Carnival.Identity.actor(src)) }
end

function Rewards.markDelivered(src, id, reason)
    return staffChange(src, id, { 'pending', 'failed', 'unknown', 'approved' }, 'delivered', reason, 'reward_marked_delivered', { delivered_at = os.time() })
end

function Rewards.resetPending(src, id, reason)
    return staffChange(src, id, { 'unknown', 'failed' }, 'pending', reason, 'reward_reset_pending')
end

function Rewards.cancel(src, id, reason)
    return staffChange(src, id, { 'pending', 'failed', 'unknown', 'awaiting_approval', 'approved' }, 'cancelled', reason, 'reward_cancelled')
end

function Rewards.list(filters, page, pageSize)
    local where, params = {}, {}
    if filters.eventId then where[#where + 1] = 'r.event_id = ?' params[#params + 1] = filters.eventId end
    if filters.status then where[#where + 1] = 'r.status = ?' params[#params + 1] = filters.status end
    if filters.participantId then where[#where + 1] = 'r.participant_id = ?' params[#params + 1] = filters.participantId end
    if filters.outstanding then where[#where + 1] = "r.status NOT IN ('delivered', 'cancelled')" end
    local whereSql = #where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or ''
    local total = Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_rewards r' .. whereSql, params) or 0
    local lp = { table.unpack(params) }
    lp[#lp + 1] = pageSize
    lp[#lp + 1] = (page - 1) * pageSize
    local rows = Carnival.Db.query('SELECT r.*, p.display_name FROM carnival_rewards r JOIN carnival_participants p ON p.id = r.participant_id'
        .. whereSql .. ' ORDER BY r.id DESC LIMIT ? OFFSET ?', lp) or {}
    for _, r in ipairs(rows) do r.metadata = nil end
    return rows, total
end

function Rewards.outstandingCount(eventId)
    if not eventId then return 0 end
    return Carnival.Db.scalar("SELECT COUNT(*) FROM carnival_rewards WHERE event_id = ? AND status NOT IN ('delivered', 'cancelled')", { eventId }) or 0
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local Api = Carnival.Api

Api.register('rewards.list', {
    perm = 'rewards.manage', rate = 'staff',
    handler = function(ctx, payload)
        local page = V.int(payload.page or 1, 1, 100000) or 1
        local eventId = payload.eventId and V.id(payload.eventId) or Carnival.Events.activeId()
        if eventId and eventId ~= Carnival.Events.activeId() and not ctx:has('events.history') then return nil, 'forbidden' end
        local rows, total = Rewards.list({
            eventId = eventId,
            status = payload.status and V.oneOf(payload.status, { 'pending', 'failed', 'delivered', 'cancelled', 'unknown', 'awaiting_approval', 'approved', 'delivering' }) or nil,
            participantId = payload.participantId and V.id(payload.participantId) or nil,
            outstanding = payload.outstanding == true,
        }, page, 25)
        return { rows = rows, total = total, page = page, pageSize = 25 }
    end,
})

local function rewardAction(name, fn, needsReason)
    Api.register('rewards.' .. name, {
        perm = 'rewards.manage', rate = 'staff',
        handler = function(ctx, payload)
            local id, err = V.id(payload.id)
            if not id then return nil, 'invalid', 'id ' .. err end
            local reason, rerr = V.reason(payload.reason, needsReason)
            if not reason then return nil, 'invalid', rerr end
            return fn(ctx.source, id, reason)
        end,
    })
end
rewardAction('approve', Rewards.approve, false)
rewardAction('retry', Rewards.retry, false)
rewardAction('markDelivered', Rewards.markDelivered, true)
rewardAction('resetPending', Rewards.resetPending, true)
rewardAction('cancel', Rewards.cancel, true)
