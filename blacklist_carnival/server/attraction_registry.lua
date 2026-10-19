-- Attraction registry, shared lifecycle interface, readiness and eligibility.
--
-- Each attraction module registers:
-- {
--   id = 'wheel',
--   onSessionStart(session), onSessionEnd(session, status),
--   onTimerExpired(session) -> 'complete' | 'hold',
--   isBusy(session) -> bool,          -- mid-run work that must not be interrupted
--   onPause(), onResume(), onEventEnd(reason), recover(event),
--   onPlayerLoaded(src, participant), onPlayerDropped(src, participant),
--   staffSummary() -> table           -- short status for dashboards
-- }
-- All functions are optional.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local SS = C.SESSION_STATUS
local Attractions = {}
Carnival.Attractions = Attractions

local defs = {}
local statusOverride = {}   -- [attractionId] = { status, note }
local onDuty = {}           -- [src] = attractionId

function Attractions.register(def)
    assert(C.ATTRACTION_INDEX[def.id], 'unknown attraction ' .. tostring(def.id))
    defs[def.id] = def
end

function Attractions.get(id) return defs[id] end

local function each(fnName, ...)
    for id, def in pairs(defs) do
        if def[fnName] then
            local ok, err = pcall(def[fnName], ...)
            if not ok then
                Carnival.Monitor.log('error', 'attraction', 'handler_failed', { attractionId = id, details = { handler = fnName, error = tostring(err) } })
            end
        end
    end
end

local function call(id, fnName, ...)
    local def = defs[id]
    if not def or not def[fnName] then return nil end
    local ok, a, b = pcall(def[fnName], ...)
    if not ok then
        Carnival.Monitor.log('error', 'attraction', 'handler_failed', { attractionId = id, details = { handler = fnName, error = tostring(a) } })
        return nil
    end
    return a, b
end

function Attractions.sessionStarted(s) call(s.attraction_id, 'onSessionStart', s) end
function Attractions.sessionEnded(s, status) call(s.attraction_id, 'onSessionEnd', s, status) end
function Attractions.sessionBusy(s) return call(s.attraction_id, 'isBusy', s) == true end
function Attractions.timerExpired(s) return call(s.attraction_id, 'onTimerExpired', s) or 'complete' end
function Attractions.pauseAll() each('onPause') end
function Attractions.resumeAll() each('onResume') end
function Attractions.eventEnded(reason) each('onEventEnd', reason) end
function Attractions.playerLoaded(src, p) each('onPlayerLoaded', src, p) end
function Attractions.playerDropped(src, p) each('onPlayerDropped', src, p) end

function Attractions.recover(e)
    statusOverride = {}
    for _, r in ipairs(Carnival.Db.query('SELECT * FROM carnival_attraction_status WHERE event_id = ?', { e.id }) or {}) do
        statusOverride[r.attraction_id] = { status = r.status, note = r.note }
    end
    each('recover', e)
end

---------------------------------------------------------------------------
-- Readiness
---------------------------------------------------------------------------
function Attractions.dutyStaff(attractionId)
    local out = {}
    for src, a in pairs(onDuty) do
        if a == attractionId and GetPlayerName(src) then
            out[#out + 1] = { source = src, name = Carnival.Identity.characterName(src) }
        end
    end
    return out
end

function Attractions.readiness(id)
    local cfg = Carnival.Config.get().attractions[id]
    local duty = Attractions.dutyStaff(id)
    local res = { available = true, status = 'ready', reason = nil, performers = #duty, duty = duty }
    if not cfg or not cfg.enabled then
        res.available, res.status, res.reason = false, 'disabled', 'disabled in configuration'
    elseif statusOverride[id] and statusOverride[id].status == 'unavailable' then
        res.available, res.status, res.reason = false, 'unavailable', statusOverride[id].note or 'marked unavailable by staff'
    elseif cfg.requiresPerformer and #duty == 0 then
        res.available, res.status, res.reason = false, 'no_performer', 'no performer on duty'
    end
    return res
end

function Attractions.setStatus(src, id, status, note)
    local e = Carnival.Events.active
    if not e then return nil, 'no_event' end
    local actor = Carnival.Identity.actor(src)
    Carnival.Db.query([[INSERT INTO carnival_attraction_status (event_id, attraction_id, status, note, updated_by, updated_at) VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE status = VALUES(status), note = VALUES(note), updated_by = VALUES(updated_by), updated_at = VALUES(updated_at)]],
        { e.id, id, status, note, actor.license, os.time() })
    statusOverride[id] = { status = status, note = note }
    Carnival.Audit.record(actor, 'attraction_status_changed', { targetType = 'attraction', targetId = id, reason = note, details = { status = status } })
    Carnival.Push.invalidate('rotation', 'dashboard', 'attractions')
    return true
end

function Attractions.overview()
    local out = {}
    for _, id in ipairs(C.ATTRACTIONS) do
        local s = Carnival.Rotation.sessionFor(id)
        local summary = call(id, 'staffSummary')
        out[#out + 1] = {
            id = id, label = Carnival.Config.get().attractions[id].label,
            staffJudged = C.STAFF_JUDGED[id] == true,
            readiness = Attractions.readiness(id),
            session = s and { id = s.id, colour = s.colour, status = s.status, startedAt = s.started_at } or nil,
            summary = summary,
        }
    end
    return out
end

---------------------------------------------------------------------------
-- Eligibility: the single gate every participant attraction request passes.
-- opts = { point = coords, distance = number, requireSession = bool (default true),
--          allowStates = set, skipTicket = bool, skipDistance = bool }
-- Returns participant, session | nil, code, message
---------------------------------------------------------------------------
function Attractions.eligibility(src, attractionId, opts)
    opts = opts or {}
    local e = Carnival.Events.active
    if not e then return nil, 'no_event', 'There is no carnival running.' end
    local allowed = opts.allowStates or C.LIVE_STATES
    if not allowed[e.state] then
        if e.state == C.STATES.PAUSED then return nil, 'paused', 'The carnival is paused.' end
        return nil, 'not_live', 'This attraction is not open right now.'
    end
    local p = Carnival.Participants.getBySource(src)
    if not p then return nil, 'not_registered', 'You need a carnival ticket. Visit the ticket booth.' end
    if p.status ~= 'active' then return nil, 'inactive', 'Your registration is not active.' end
    if p.event_id ~= e.id then return nil, 'stale_event', 'Your ticket is for a different event.' end

    local session
    if opts.requireSession ~= false then
        session = p.colour and Carnival.Rotation.sessionForColour(p.colour) or nil
        if not session or session.attraction_id ~= attractionId then
            return nil, 'wrong_attraction', 'Your group is not scheduled here right now.'
        end
        if session.status ~= SS.ACTIVE then
            return nil, 'session_not_active', 'This attraction is not open for your group yet.'
        end
        local cfg = Carnival.Config.get()
        if not cfg.scoring.allowRepeatAfterTransfer and Carnival.Rotation.hasCompleted(p.id, attractionId) then
            return nil, 'already_completed', 'You have already completed this attraction.'
        end
    end

    if not opts.skipDistance then
        local a = Carnival.Config.get().attractions[attractionId]
        local point = opts.point or a.location
        local maxDist = opts.distance or a.validationDistance
        local near, d = Carnival.Identity.within(src, point, maxDist)
        if not near then
            Carnival.Monitor.log('warning', 'security', 'request_out_of_range', {
                participantId = p.id, attractionId = attractionId, actor = Carnival.Identity.actor(src),
                details = { distance = d and U.round(d, 1) or nil, max = maxDist },
            })
            return nil, 'too_far', 'You are too far away.'
        end
    end

    if not opts.skipTicket then
        local ok, why = Carnival.Tickets.verify(src, p)
        if not ok then
            Carnival.Monitor.log('info', 'ticket_validation', 'attraction_ticket_rejected', { participantId = p.id, attractionId = attractionId, result = why })
            if why == 'ticket_pending' then return nil, 'ticket_pending', 'Collect your ticket from the ticket booth first.' end
            return nil, why, 'Show your valid carnival ticket. Lost it? Visit the ticket booth.'
        end
    end
    return p, session
end

-- Staff helper: staff operating an attraction must hold the permission; returns
-- the active session of that attraction (if any).
function Attractions.requireOperator(ctx, attractionId)
    if not ctx:has('attractions.operate.' .. attractionId) then
        Carnival.Monitor.security(ctx.source, 'permission_denied', { attraction = attractionId }, 'permission')
        return nil, 'forbidden', 'You are not an operator of this attraction.'
    end
    return Carnival.Rotation.activeSessionFor(attractionId) or false
end

AddEventHandler('playerDropped', function()
    if onDuty[source] then
        local a = onDuty[source]
        onDuty[source] = nil
        Carnival.Monitor.log('info', 'attraction', 'staff_off_duty', { attractionId = a, details = { reason = 'disconnected' } })
        Carnival.Push.invalidate('rotation', 'attractions')
    end
end)

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local Api = Carnival.Api

Api.register('attractions.overview', {
    perm = 'panel.staff', rate = 'staff',
    handler = function() return Attractions.overview() end,
})

Api.register('attractions.setStatus', {
    perm = 'events.operate', rate = 'staff',
    handler = function(ctx, payload)
        local id = V.attraction(payload.attractionId)
        if not id then return nil, 'invalid', 'Invalid attraction.' end
        local status = V.oneOf(payload.status, { 'available', 'unavailable' })
        if not status then return nil, 'invalid', 'Invalid status.' end
        local note, nerr = V.reason(payload.note, status == 'unavailable')
        if not note then return nil, 'invalid', nerr end
        return Attractions.setStatus(ctx.source, id, status, note)
    end,
})

Api.register('staff.checkIn', {
    perm = 'panel.staff', rate = 'staff',
    handler = function(ctx, payload)
        local id = V.attraction(payload.attractionId)
        if not id then return nil, 'invalid', 'Invalid attraction.' end
        if not ctx:has('attractions.operate.' .. id) then return nil, 'forbidden', 'You are not assigned to this attraction.' end
        onDuty[ctx.source] = id
        Carnival.Monitor.log('info', 'attraction', 'staff_on_duty', { attractionId = id, actor = ctx.actor })
        Carnival.Push.invalidate('rotation', 'attractions')
        -- a held session may now be startable
        return { attraction = id }
    end,
})

Api.register('staff.checkOut', {
    perm = 'panel.staff', rate = 'staff',
    handler = function(ctx)
        local a = onDuty[ctx.source]
        onDuty[ctx.source] = nil
        if a then
            Carnival.Monitor.log('info', 'attraction', 'staff_off_duty', { attractionId = a, actor = ctx.actor })
            Carnival.Push.invalidate('rotation', 'attractions')
        end
        return true
    end,
})

function Attractions.dutyOf(src) return onDuty[src] end
