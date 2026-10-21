-- Participants cache + registration.
--
-- Participants are keyed by (event_id, citizenid). The source <-> participant
-- binding is rebuilt whenever a character loads, so reconnecting players
-- recover their registration, colour, ticket and score automatically.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local S = C.STATES

local P = {}
Carnival.Participants = P
local Registration = {}
Carnival.Registration = Registration

P.byId = {}
local byCitizen = {}
local srcById = {}
local idBySrc = {}

local function cacheRow(r)
    P.byId[r.id] = r
    byCitizen[r.citizenid] = r.id
end

function P.get(id) return P.byId[id] end
function P.sourceOf(id) return srcById[id] end
function P.idOfSource(src) return idBySrc[src] end
function P.getBySource(src)
    local id = idBySrc[src]
    return id and P.byId[id] or nil
end
function P.getByCitizen(cid)
    local id = byCitizen[cid]
    return id and P.byId[id] or nil
end

function P.count()
    return U.count(P.byId)
end

function P.countActive()
    local n = 0
    for _, p in pairs(P.byId) do if p.status == 'active' then n = n + 1 end end
    return n
end

function P.onlineCount()
    local n = 0
    for id in pairs(srcById) do
        if P.byId[id] and P.byId[id].status == 'active' then n = n + 1 end
    end
    return n
end

-- Active participants of a group. onlineOnly filters to connected players.
function P.members(colour, onlineOnly)
    local out = {}
    for _, p in pairs(P.byId) do
        if p.colour == colour and p.status == 'active' and (not onlineOnly or srcById[p.id]) then
            out[#out + 1] = p
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function P.loadForEvent(eventId)
    P.byId, byCitizen, srcById, idBySrc = {}, {}, {}, {}
    if not eventId then
        Carnival.Tickets.loadForEvent(nil)
        return
    end
    local rows = Carnival.Db.query('SELECT * FROM carnival_participants WHERE event_id = ?', { eventId }) or {}
    for _, r in ipairs(rows) do cacheRow(r) end
    for _, s in ipairs(Carnival.Identity.online()) do
        local cid = Carnival.Identity.citizenid(s)
        if cid and byCitizen[cid] then
            srcById[byCitizen[cid]] = s
            idBySrc[s] = byCitizen[cid]
        end
    end
    Carnival.Tickets.loadForEvent(eventId)
end

-- Lightweight summary for staff tables.
function P.summary(p)
    return {
        id = p.id, name = p.display_name, colour = p.colour, status = p.status,
        total = p.total_score, online = srcById[p.id] ~= nil, registeredAt = p.registered_at,
        replacements = p.replacements, completed = Carnival.Rotation.completedFor(p.id),
    }
end

-- What the participant UI shows about the player themselves.
function P.ownState(src)
    local e = Carnival.Events.active
    local base = { registered = false, canRegister = Registration.isOpen(), serverTime = os.time() }
    if not e then return base end
    local p = P.getBySource(src)
    if not p then return base end
    local ticket = Carnival.Tickets.current(p.id)
    local rot = Carnival.Rotation.participantView(p)
    return {
        registered = true,
        serverTime = os.time(),
        id = p.id,
        name = p.display_name,
        colour = p.colour,
        status = p.status,
        total = p.total_score,
        rank = Carnival.Leaderboard.rankOf(p.id),
        ticket = ticket and { serial = ticket.serial, virtual = Carnival.Db.bool(ticket.is_virtual), status = ticket.status } or nil,
        canReplaceTicket = Carnival.Config.get().registration.allowSelfReplacement,
        breakdown = Carnival.Scoring.breakdown(p.id),
        completed = rot.completed,
        current = rot.current,
        next = rot.next,
        walkup = rot.walkup == true,
        finished = rot.finished == true,
        eventId = e.id,
    }
end

function P.pushOwn(id)
    local s = srcById[id]
    if s then Carnival.Push.send(s, 'participant', P.ownState(s)) end
end

function P.pushAll()
    for _, s in ipairs(Carnival.Identity.online()) do
        Carnival.Push.send(s, 'participant', P.ownState(s))
    end
end

-- Update a cached row after a DB write.
function P.refresh(id)
    local r = Carnival.Db.single('SELECT * FROM carnival_participants WHERE id = ?', { id })
    if r then cacheRow(r) end
    return r
end

---------------------------------------------------------------------------
-- Binding sources to participants (login / reconnect / logout)
---------------------------------------------------------------------------
function P.bind(src)
    if not Carnival.ready then return end
    P.unbind(src, true)
    local cid = Carnival.Identity.citizenid(src)
    if not cid then return end
    local id = byCitizen[cid]
    if id then
        srcById[id] = src
        idBySrc[src] = id
        Carnival.Db.update('UPDATE carnival_participants SET last_seen_at = ? WHERE id = ?', { os.time(), id })
        Carnival.Monitor.log('info', 'player', 'participant_connected', { participantId = id, actor = Carnival.Identity.actor(src) })
        local t = Carnival.Tickets.current(id)
        if t and t.status == 'pending_delivery' then
            CreateThread(function() Carnival.Tickets.deliverPending(id, Carnival.Identity.SYSTEM) end)
        end
        Carnival.Attractions.playerLoaded(src, P.byId[id])
        if Carnival.Config.get().rewards.retryOnLogin then
            Carnival.Rewards.retryPendingFor(id)
        end
        Carnival.Push.invalidate('participants', 'dashboard')
    end
    Carnival.Push.bootstrap(src)
end

function P.unbind(src, silent)
    local id = idBySrc[src]
    if not id then return end
    idBySrc[src] = nil
    if srcById[id] == src then srcById[id] = nil end
    Carnival.Db.update('UPDATE carnival_participants SET last_seen_at = ? WHERE id = ?', { os.time(), id })
    if not silent then
        Carnival.Monitor.log('info', 'player', 'participant_disconnected', { participantId = id })
        Carnival.Attractions.playerDropped(src, P.byId[id])
        Carnival.Push.invalidate('participants', 'dashboard')
    end
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    if src then P.bind(src) end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    P.unbind(src)
end)

AddEventHandler('playerDropped', function()
    P.unbind(source)
end)

-- Clients announce themselves on resource start (covers restarts of this resource
-- while players are already logged in).
RegisterNetEvent('blacklist_carnival:server:clientReady', function()
    local src = source
    if Carnival.ready then P.bind(src) end
end)

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
function Registration.isOpen()
    local e = Carnival.Events.active
    if not e then return false end
    if e.state == S.REG_OPEN then return true end
    -- walk-up carnivals sell tickets for as long as they are open
    if e.mode == 'walkup' then return C.LATE_REG_STATES[e.state] == true end
    local cfg = Carnival.Config.get()
    if cfg.registration.lateRegistration.enabled and C.LATE_REG_STATES[e.state] then
        local round = Carnival.Rotation.currentRoundNumber()
        return round <= cfg.registration.lateRegistration.maxRound
    end
    return false
end

-- opts: { actor = identity (staff), colour = forced colour (staff), skipDistance = bool }
function Registration.register(src, opts)
    opts = opts or {}
    local e = Carnival.Events.active
    if not e then return nil, 'no_event', 'There is no carnival running right now.' end
    if not Registration.isOpen() then return nil, 'registration_closed', 'Registration is closed.' end
    local ident = Carnival.Identity.get(src)
    if not ident then return nil, 'no_character', 'Your character is not loaded.' end
    local cfg = Carnival.Config.get()

    if not opts.skipDistance then
        local near = Carnival.Identity.within(src, cfg.registration.entrance, cfg.registration.validationDistance)
        if not near then
            Carnival.Monitor.security(src, 'registration_out_of_range', {}, 'registration')
            return nil, 'too_far', 'You need to be at the ticket booth.'
        end
    end

    return Carnival.withLock('registration', function()
        if byCitizen[ident.citizenid] then
            local existing = P.byId[byCitizen[ident.citizenid]]
            Carnival.Monitor.log('info', 'duplicate', 'duplicate_registration', { participantId = existing.id, actor = Carnival.Identity.actor(src) })
            return nil, 'already_registered', 'You are already registered for this event.'
        end
        if P.count() >= cfg.registration.maxParticipants then
            return nil, 'event_full', 'The carnival is full.'
        end

        local colour, method
        if opts.colour then
            colour, method = opts.colour, 'manual'
            if not Carnival.Groups.hasCapacity(colour) then
                return nil, 'group_full', ('The %s group is full.'):format(colour)
            end
        else
            colour, method = Carnival.Groups.allocate()
            if colour == nil and method ~= 'manual' then
                return nil, 'groups_full', 'Every group is full.'
            end
        end

        local actor = opts.actor or Carnival.Identity.actor(src)
        local now = os.time()
        local id = Carnival.Db.insertRow('carnival_participants', {
            event_id = e.id, citizenid = ident.citizenid, license = ident.license, display_name = ident.name,
            colour = colour, status = 'active', registered_by = opts.actor and opts.actor.license or nil,
            registered_round = Carnival.Rotation.currentRoundNumber(), registered_at = now, last_seen_at = now,
        })
        if not id then
            Carnival.Monitor.log('error', 'registration', 'registration_failed', { actor = actor, details = { reason = 'database' } })
            return nil, 'database_error', 'Registration could not be saved. Please try again.'
        end
        Carnival.Db.insertRow('carnival_group_assignments', {
            event_id = e.id, participant_id = id, to_colour = colour, method = method,
            actor = actor.license, reason = 'Registration', created_at = now,
        })
        local row = P.refresh(id)
        srcById[id] = src
        idBySrc[src] = id

        Carnival.Monitor.log('info', 'registration', 'participant_registered', { participantId = id, actor = actor, details = { colour = colour, method = method, late = e.state ~= S.REG_OPEN } })
        if opts.actor then
            Carnival.Audit.record(opts.actor, 'participant_registered_by_staff', { targetType = 'participant', targetId = id, details = { colour = colour, citizenid = ident.citizenid } })
        end

        local ticketOk, ticketErr
        if colour then
            ticketOk, ticketErr = Carnival.Tickets.issue(row, actor, 'Registration')
        end
        Carnival.Scoring.ensureParticipant(id)
        P.pushOwn(id)
        Carnival.Push.eventState()
        Carnival.Push.invalidate('participants', 'dashboard')
        Carnival.Leaderboard.markDirty()
        return { id = id, colour = colour, ticketIssued = ticketOk == true, ticketError = ticketErr }
    end)
end

function Registration.setStatus(src, pid, status, reason)
    local p = P.byId[pid]
    if not p then return nil, 'not_found', 'Participant not found.' end
    if p.status == status then return nil, 'invalid', 'Participant is already ' .. status .. '.' end
    local n = Carnival.Db.update('UPDATE carnival_participants SET status = ?, status_reason = ? WHERE id = ? AND status = ?', { status, reason, pid, p.status })
    if not n or n < 1 then return nil, 'database_error' end
    P.refresh(pid)
    local actor = Carnival.Identity.actor(src)
    Carnival.Audit.record(actor, status == 'removed' and 'participant_removed' or 'participant_reinstated', {
        targetType = 'participant', targetId = pid, reason = reason, details = { name = p.display_name },
    })
    P.pushOwn(pid)
    local ps = P.sourceOf(pid)
    if ps then
        Carnival.Push.notify(ps, 'Carnival', status == 'removed' and 'You have been removed from the event.' or 'You have been reinstated to the event.', status == 'removed' and 'error' or 'success')
    end
    Carnival.Leaderboard.markDirty()
    Carnival.Push.invalidate('participants', 'dashboard')
    return true
end

function Registration.search(filters, page, pageSize)
    local eventId = filters.eventId or Carnival.Events.activeId()
    if not eventId then return {}, 0 end
    local where, params = { 'event_id = ?' }, { eventId }
    if filters.query then
        where[#where + 1] = '(display_name LIKE ? OR citizenid = ? OR CAST(id AS CHAR) = ?)'
        params[#params + 1] = '%' .. filters.query .. '%'
        params[#params + 1] = filters.query
        params[#params + 1] = filters.query
    end
    if filters.colour then where[#where + 1] = 'colour = ?' params[#params + 1] = filters.colour end
    if filters.status then where[#where + 1] = 'status = ?' params[#params + 1] = filters.status end
    local whereSql = ' WHERE ' .. table.concat(where, ' AND ')
    local total = Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_participants' .. whereSql, params) or 0
    local lp = { table.unpack(params) }
    lp[#lp + 1] = pageSize
    lp[#lp + 1] = (page - 1) * pageSize
    local order = filters.sort == 'score' and 'total_score DESC, id ASC' or 'id ASC'
    local rows = Carnival.Db.query('SELECT id, citizenid, display_name, colour, status, total_score, replacements, registered_at, last_seen_at FROM carnival_participants'
        .. whereSql .. ' ORDER BY ' .. order .. ' LIMIT ? OFFSET ?', lp) or {}
    for _, r in ipairs(rows) do
        r.online = srcById[r.id] ~= nil and eventId == Carnival.Events.activeId()
    end
    return rows, total
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local Api = Carnival.Api

Api.register('participant.state', {
    rate = 'participant',
    handler = function(ctx) return P.ownState(ctx.source) end,
})

Api.register('registration.register', {
    rate = 'action',
    handler = function(ctx)
        return Registration.register(ctx.source)
    end,
})

Api.register('participants.search', {
    perm = 'participants.view', rate = 'staff',
    handler = function(ctx, payload)
        local page = V.int(payload.page or 1, 1, 100000) or 1
        local filters = {
            query = payload.query and payload.query ~= '' and V.string(payload.query, 64) or nil,
            colour = payload.colour and V.colour(payload.colour) or nil,
            status = payload.status and V.oneOf(payload.status, { 'active', 'removed' }) or nil,
            sort = payload.sort == 'score' and 'score' or 'id',
        }
        -- Historical events require the history permission.
        if payload.eventId then
            local eid = V.id(payload.eventId)
            if eid and eid ~= Carnival.Events.activeId() and not ctx:has('events.history') then return nil, 'forbidden' end
            filters.eventId = eid
        end
        local pageSize = V.int(payload.pageSize or 25, 5, 100) or 25
        local rows, total = Registration.search(filters, page, pageSize)
        return { rows = rows, total = total, page = page, pageSize = pageSize }
    end,
})

Api.register('participants.get', {
    perm = 'participants.view', rate = 'staff',
    handler = function(ctx, payload)
        local id, err = V.id(payload.id)
        if not id then return nil, 'invalid', 'id ' .. err end
        local p = Carnival.Db.single('SELECT * FROM carnival_participants WHERE id = ?', { id })
        if not p then return nil, 'not_found' end
        if p.event_id ~= Carnival.Events.activeId() and not ctx:has('events.history') then return nil, 'forbidden' end
        local canSensitive = ctx:has('participants.manage')
        if not canSensitive then p.license = nil end
        return {
            participant = p,
            online = srcById[id] ~= nil,
            tickets = Carnival.Db.query('SELECT id, colour, item_name, serial, is_virtual, status, delivery_error, issue_reason, issued_at, invalidated_at, invalidated_reason FROM carnival_tickets WHERE participant_id = ? ORDER BY id DESC', { id }) or {},
            groups = Carnival.Db.query('SELECT * FROM carnival_group_assignments WHERE participant_id = ? ORDER BY id DESC', { id }) or {},
            participation = Carnival.Db.query('SELECT * FROM carnival_attraction_participation WHERE participant_id = ? ORDER BY completed_at', { id }) or {},
            breakdown = Carnival.Db.query('SELECT attraction_id, points, positive, negative, tx_count FROM carnival_score_summaries WHERE participant_id = ?', { id }) or {},
            transactions = ctx:has('scores.view') and (Carnival.Db.query('SELECT * FROM carnival_score_transactions WHERE participant_id = ? ORDER BY id DESC LIMIT 200', { id }) or {}) or {},
            rewards = Carnival.Db.query('SELECT * FROM carnival_rewards WHERE participant_id = ? ORDER BY id DESC', { id }) or {},
        }
    end,
})

Api.register('participants.remove', {
    perm = 'participants.manage', rate = 'staff',
    handler = function(ctx, payload)
        local id, err = V.id(payload.id)
        if not id then return nil, 'invalid', 'id ' .. err end
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        return Registration.setStatus(ctx.source, id, 'removed', reason)
    end,
})

Api.register('participants.reinstate', {
    perm = 'participants.manage', rate = 'staff',
    handler = function(ctx, payload)
        local id, err = V.id(payload.id)
        if not id then return nil, 'invalid', 'id ' .. err end
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        return Registration.setStatus(ctx.source, id, 'active', reason)
    end,
})

-- Staff registers an online player (optionally into a chosen group).
Api.register('participants.registerPlayer', {
    perm = 'participants.manage', rate = 'staff',
    handler = function(ctx, payload)
        local target, err = V.int(payload.source, 1, 65535)
        if not target or not GetPlayerName(target) then return nil, 'invalid', 'Player is not online.' end
        local colour = payload.colour and V.colour(payload.colour) or nil
        if payload.colour and not colour then return nil, 'invalid', 'Invalid colour.' end
        return Registration.register(target, { actor = ctx.actor, colour = colour, skipDistance = true })
    end,
})

Api.register('participants.unregisteredOnline', {
    perm = 'participants.manage', rate = 'staff',
    handler = function()
        local out = {}
        for _, s in ipairs(Carnival.Identity.online()) do
            if not idBySrc[s] then
                local ident = Carnival.Identity.get(s)
                if ident and not byCitizen[ident.citizenid] then
                    out[#out + 1] = { source = s, name = ident.name }
                end
            end
        end
        table.sort(out, function(a, b) return a.name < b.name end)
        return out
    end,
})
