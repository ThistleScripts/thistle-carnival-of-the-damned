-- Prize counter: a per-character wallet of prize points and a shop to spend them.
--
-- Points are credited automatically from game scores (Scoring.award calls
-- Shop.credit for every positive, non-staff transaction), at `shop.earnPercent`
-- prize points per 100 game points. Staff adjustments and corrections never
-- earn prize points. Wallets are keyed by citizenid and carry over between
-- nights.
--
-- Every balance change is a row in carnival_prize_ledger with a unique
-- idempotency key (score:<txId>, buy:<citizenid>:<requestId>, ...), written in
-- one transaction with the wallet update, so a replayed credit or a retried
-- purchase can never apply twice. Purchases take the points first and refund
-- them if the item cannot be handed over.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Shop = {}
Carnival.Shop = Shop

local DAY = 86400
local sourceByCitizen = {}   -- citizenid -> last known source (for wallet pushes)

local function cfg() return Carnival.Config.get().shop end

local function publicWallet(row, currency)
    return {
        balance = row and row.balance or 0,
        earned = row and row.earned_total or 0,
        spent = row and row.spent_total or 0,
        currency = currency or cfg().currency,
    }
end

function Shop.wallet(cid)
    return Carnival.Db.single('SELECT * FROM carnival_prize_wallets WHERE citizenid = ?', { cid })
end

local function ensureWallet(cid, name)
    local now = os.time()
    Carnival.Db.query([[INSERT INTO carnival_prize_wallets (citizenid, display_name, balance, earned_total, spent_total, created_at, updated_at)
        VALUES (?, ?, 0, 0, 0, ?, ?) ON DUPLICATE KEY UPDATE display_name = COALESCE(VALUES(display_name), display_name)]], { cid, name, now, now })
end

local function pushWallet(cid, extra)
    local src = sourceByCitizen[cid]
    if not src or not GetPlayerName(tostring(src)) then return end
    local w = publicWallet(Shop.wallet(cid))
    for k, v in pairs(extra or {}) do w[k] = v end
    Carnival.Push.send(src, 'wallet', w)
end

-- Apply one ledger entry. entry: { kind, delta, key, eventId?, scoreTxId?, item?, count?, unitPrice?, reason?, actor? }
-- Returns true, { id, balance, duplicate } | false, code, message
local function apply(cid, name, entry)
    ensureWallet(cid, name)
    return Carnival.withLock('wallet:' .. cid, function()
        local existing = Carnival.Db.single('SELECT id, balance_after FROM carnival_prize_ledger WHERE idempotency_key = ?', { entry.key })
        if existing then return true, { id = existing.id, balance = existing.balance_after, duplicate = true } end
        local w = Shop.wallet(cid)
        if not w then return false, 'database_error', 'Your wallet could not be loaded.' end
        local balance = w.balance + entry.delta
        if balance < 0 then return false, 'insufficient', 'You do not have enough points.' end
        local now = os.time()
        local actor = entry.actor
        local insSql, insParams = Carnival.Db.buildInsert('carnival_prize_ledger', {
            citizenid = cid, kind = entry.kind, delta = entry.delta, balance_after = balance,
            event_id = entry.eventId, score_tx_id = entry.scoreTxId, item = entry.item, item_count = entry.count,
            unit_price = entry.unitPrice, reason = entry.reason and U.sanitizeText(entry.reason, 500) or nil,
            staff_license = actor and actor.license ~= 'system' and actor.license or nil,
            staff_name = actor and actor.license ~= 'system' and actor.name or nil,
            idempotency_key = entry.key, created_at = now,
        })
        local earned = entry.kind == 'earned' and entry.delta or 0
        local spent = entry.kind == 'purchase' and -entry.delta or (entry.kind == 'refund' and -entry.delta or 0)
        local ok = Carnival.Db.transaction({
            { query = insSql, values = insParams },
            { query = [[UPDATE carnival_prize_wallets SET balance = balance + ?, earned_total = earned_total + ?,
                spent_total = spent_total + ?, updated_at = ? WHERE citizenid = ?]],
              values = { entry.delta, earned, spent, now, cid } },
        })
        if not ok then
            local dup = Carnival.Db.single('SELECT id, balance_after FROM carnival_prize_ledger WHERE idempotency_key = ?', { entry.key })
            if dup then return true, { id = dup.id, balance = dup.balance_after, duplicate = true } end
            return false, 'database_error', 'The points could not be saved.'
        end
        local id = Carnival.Db.scalar('SELECT id FROM carnival_prize_ledger WHERE idempotency_key = ?', { entry.key })
        return true, { id = id, balance = balance, duplicate = false }
    end)
end

-- Called by Scoring.award after a positive game score was written.
-- p: participant row, tx: { id, delta }
function Shop.credit(p, tx, eventId)
    local c = cfg()
    if not p or not p.citizenid or not tx or not tx.id or (tx.delta or 0) <= 0 then return end
    local amount = math.floor(tx.delta * c.earnPercent / 100)
    if amount <= 0 then return end
    local ok, res = apply(p.citizenid, p.display_name, {
        kind = 'earned', delta = amount, key = 'score:' .. tx.id, eventId = eventId, scoreTxId = tx.id,
    })
    if ok and not res.duplicate then
        local src = Carnival.Participants.sourceOf(p.id)
        if src then sourceByCitizen[p.citizenid] = src end
        pushWallet(p.citizenid, { delta = amount })
    end
end

-- Admin correction of a wallet. requestId keeps UI retries idempotent.
function Shop.adjust(src, cid, delta, reason, requestId)
    if delta == 0 then return nil, 'invalid', 'Adjustment cannot be zero.' end
    if not Shop.wallet(cid) then return nil, 'not_found', 'That player has no prize wallet yet.' end
    local actor = Carnival.Identity.actor(src)
    local ok, res, msg = apply(cid, nil, { kind = 'adjust', delta = delta, key = 'adjust:' .. requestId, reason = reason, actor = actor })
    if not ok then return nil, res, msg end
    if not res.duplicate then
        Carnival.Audit.record(actor, 'prize_points_adjusted', { targetType = 'wallet', targetId = cid, reason = reason,
            details = { delta = delta, balance = res.balance } })
        pushWallet(cid)
        Carnival.Push.invalidate('shop')
    end
    return { balance = res.balance }
end

---------------------------------------------------------------------------
-- Catalogue
---------------------------------------------------------------------------
local function itemInfo(name)
    local ok, item = pcall(function() return exports[Config.Inventory.resource]:Items(name) end)
    if ok and type(item) == 'table' then return item end
    return nil
end

local function entryFor(name)
    for _, it in ipairs(cfg().items) do
        if it.item == name and it.enabled then return it end
    end
    return nil
end

local function boughtToday(cid, item)
    return tonumber(Carnival.Db.scalar([[SELECT COALESCE(SUM(item_count), 0) FROM carnival_prize_ledger
        WHERE citizenid = ? AND item = ? AND kind = 'purchase' AND created_at >= ?]], { cid, item, os.time() - DAY })) or 0
end

local function refundedToday(cid, item)
    return tonumber(Carnival.Db.scalar([[SELECT COALESCE(SUM(item_count), 0) FROM carnival_prize_ledger
        WHERE citizenid = ? AND item = ? AND kind = 'refund' AND created_at >= ?]], { cid, item, os.time() - DAY })) or 0
end

local function usedToday(cid, item)
    return math.max(0, boughtToday(cid, item) - refundedToday(cid, item))
end

function Shop.catalogue(cid)
    local out = {}
    for _, it in ipairs(cfg().items) do
        if it.enabled and not C.TICKET_ITEM_COLOUR[it.item] then
            local info = itemInfo(it.item)
            local entry = {
                item = it.item,
                label = (it.label and it.label ~= '') and it.label or (info and info.label) or it.item,
                description = (it.description and it.description ~= '') and it.description or (info and info.description) or nil,
                price = it.price,
                dailyLimit = it.dailyLimit,
            }
            if cid and it.dailyLimit > 0 then entry.remainingToday = math.max(0, it.dailyLimit - usedToday(cid, it.item)) end
            out[#out + 1] = entry
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Purchases
---------------------------------------------------------------------------
local function nearCounter(src)
    local c = cfg()
    return Carnival.Identity.within(src, c.location, c.validationDistance)
end

function Shop.buy(src, item, count, requestId)
    local c = cfg()
    if not c.enabled then return nil, 'closed', ('%s is closed.'):format(c.label) end
    local cid = Carnival.Identity.citizenid(src)
    if not cid then return nil, 'no_character', 'Load a character first.' end
    sourceByCitizen[cid] = src
    if not nearCounter(src) then return nil, 'too_far', ('You need to be at %s.'):format(c.label) end
    local it = entryFor(item)
    if not it or C.TICKET_ITEM_COLOUR[item] then return nil, 'not_for_sale', 'That is not for sale.' end
    if it.dailyLimit > 0 and usedToday(cid, item) + count > it.dailyLimit then
        return nil, 'limit', ('You can only buy %d of those a day.'):format(it.dailyLimit)
    end
    local cost = it.price * count
    local w = Shop.wallet(cid)
    if not w or w.balance < cost then
        return nil, 'insufficient', ('You need %d %s for that.'):format(cost, c.currency)
    end
    if not Carnival.Inventory.canCarry(src, item, count) then
        return nil, 'cannot_carry', 'You cannot carry that.'
    end

    local key = ('buy:%s:%s'):format(cid, requestId)
    local ok, res, msg = apply(cid, Carnival.Identity.characterName(src), {
        kind = 'purchase', delta = -cost, key = key, item = item, count = count, unitPrice = it.price,
        eventId = Carnival.Events.activeId(),
    })
    if not ok then return nil, res, msg end
    if res.duplicate then return { balance = res.balance, item = item, count = count, duplicate = true } end

    local added, err = Carnival.Inventory.addItem(src, item, count)
    if not added then
        local rok = apply(cid, nil, {
            kind = 'refund', delta = cost, key = 'refund:' .. res.id, item = item, count = count, unitPrice = it.price,
            reason = 'item could not be delivered: ' .. tostring(err),
        })
        Carnival.Monitor.log('warning', 'shop', 'purchase_refunded', { details = { citizenid = cid, item = item, count = count, error = tostring(err), refunded = rok } })
        pushWallet(cid)
        return nil, 'delivery_failed', rok and 'The item could not be handed over; your points were refunded.'
            or 'The item could not be handed over and the refund failed. Please contact staff.'
    end

    Carnival.Audit.record(Carnival.Identity.actor(src), 'prize_purchase', { targetType = 'item', targetId = item,
        details = { count = count, cost = cost, balance = res.balance, citizenid = cid } })
    Carnival.Monitor.log('info', 'shop', 'prize_purchase', { details = { citizenid = cid, item = item, count = count, cost = cost } })
    pushWallet(cid)
    Carnival.Push.invalidate('shop')
    return { balance = res.balance, item = item, count = count, cost = cost }
end

---------------------------------------------------------------------------
-- Admin views
---------------------------------------------------------------------------
function Shop.overview()
    local since = os.time() - DAY
    local totals = Carnival.Db.single([[SELECT COUNT(*) AS wallets, COALESCE(SUM(balance), 0) AS outstanding,
        COALESCE(SUM(earned_total), 0) AS earned, COALESCE(SUM(spent_total), 0) AS spent FROM carnival_prize_wallets]]) or {}
    local today = Carnival.Db.single([[SELECT COUNT(*) AS purchases, COALESCE(-SUM(delta), 0) AS spent
        FROM carnival_prize_ledger WHERE kind = 'purchase' AND created_at >= ?]], { since }) or {}
    local popular = Carnival.Db.query([[SELECT item, SUM(item_count) AS sold, -SUM(delta) AS points FROM carnival_prize_ledger
        WHERE kind = 'purchase' GROUP BY item ORDER BY sold DESC LIMIT 10]]) or {}
    local recent = Carnival.Db.query([[SELECT l.id, l.citizenid, w.display_name, l.kind, l.delta, l.balance_after, l.item, l.item_count,
            l.reason, l.staff_name, l.created_at
        FROM carnival_prize_ledger l LEFT JOIN carnival_prize_wallets w ON w.citizenid = l.citizenid
        WHERE l.kind <> 'earned' ORDER BY l.id DESC LIMIT 40]]) or {}
    local top = Carnival.Db.query([[SELECT citizenid, display_name, balance, earned_total, spent_total, updated_at
        FROM carnival_prize_wallets ORDER BY balance DESC LIMIT 25]]) or {}
    return {
        currency = cfg().currency,
        totals = {
            wallets = tonumber(totals.wallets) or 0, outstanding = tonumber(totals.outstanding) or 0,
            earned = tonumber(totals.earned) or 0, spent = tonumber(totals.spent) or 0,
            purchasesToday = tonumber(today.purchases) or 0, spentToday = tonumber(today.spent) or 0,
        },
        popular = U.map(popular, function(r) return { item = r.item, sold = tonumber(r.sold) or 0, points = tonumber(r.points) or 0 } end),
        recent = recent,
        wallets = top,
    }
end

function Shop.search(query)
    local q = '%' .. U.sanitizeText(query or '', 64):gsub('[%%_]', '') .. '%'
    return Carnival.Db.query([[SELECT citizenid, display_name, balance, earned_total, spent_total, updated_at
        FROM carnival_prize_wallets WHERE display_name LIKE ? OR citizenid LIKE ? ORDER BY balance DESC LIMIT 25]], { q, q }) or {}
end

AddEventHandler('playerDropped', function()
    local src = source
    for cid, s in pairs(sourceByCitizen) do
        if s == src then sourceByCitizen[cid] = nil end
    end
end)

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local Api = Carnival.Api

Api.register('shop.open', {
    rate = 'participant',
    handler = function(ctx)
        local c = cfg()
        if not c.enabled then return nil, 'closed', ('%s is closed.'):format(c.label) end
        local cid = Carnival.Identity.citizenid(ctx.source)
        if not cid then return nil, 'no_character', 'Load a character first.' end
        sourceByCitizen[cid] = ctx.source
        return { label = c.label, currency = c.currency, earnPercent = c.earnPercent, wallet = publicWallet(Shop.wallet(cid), c.currency), items = Shop.catalogue(cid) }
    end,
})

Api.register('shop.wallet', {
    rate = 'participant',
    handler = function(ctx)
        local cid = Carnival.Identity.citizenid(ctx.source)
        if not cid then return publicWallet(nil) end
        sourceByCitizen[cid] = ctx.source
        return publicWallet(Shop.wallet(cid))
    end,
})

Api.register('shop.buy', {
    rate = 'action',
    handler = function(ctx, payload)
        local v, code, msg = Api.validate(payload, {
            item = function(x) return V.string(x, 64) end,
            count = function(x) return V.int(x, 1, 20) end,
            requestId = V.requestId,
        })
        if not v then return nil, code, msg end
        return Shop.buy(ctx.source, v.item, v.count, v.requestId)
    end,
})

Api.register('shop.overview', {
    perm = 'shop.manage', rate = 'admin',
    handler = function() return Shop.overview() end,
})

Api.register('shop.search', {
    perm = 'shop.manage', rate = 'admin',
    handler = function(_, payload) return { wallets = Shop.search(payload.query) } end,
})

Api.register('shop.adjust', {
    perm = 'shop.manage', rate = 'admin',
    handler = function(ctx, payload)
        local v, code, msg = Api.validate(payload, {
            citizenid = function(x) return V.string(x, 64) end,
            delta = function(x) return V.int(x, -1000000, 1000000) end,
            reason = function(x) return V.reason(x, true) end,
            requestId = V.requestId,
        })
        if not v then return nil, code, msg end
        return Shop.adjust(ctx.source, v.citizenid, v.delta, v.reason, v.requestId)
    end,
})
