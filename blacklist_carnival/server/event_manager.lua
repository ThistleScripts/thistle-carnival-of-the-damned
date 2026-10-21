-- Event lifecycle: creation, server-authoritative state machine, history, recovery.
--
-- One event may be non-terminal (active) at a time. Creating a new event never
-- touches earlier events; completed/cancelled events remain queryable forever.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local S = C.STATES
local Events = {}
Carnival.Events = Events

Events.active = nil   -- carnival_events row of the active event

function Events.activeId()
    return Events.active and Events.active.id or nil
end

function Events.state()
    return Events.active and Events.active.state or nil
end

function Events.isWalkup()
    return Events.active ~= nil and Events.active.mode == 'walkup'
end

function Events.isLive()
    return Events.active ~= nil and C.LIVE_STATES[Events.active.state] == true
end

function Events.get(id)
    return Carnival.Db.single('SELECT * FROM carnival_events WHERE id = ?', { id })
end

local function reloadActive()
    Events.active = Carnival.Db.single("SELECT * FROM carnival_events WHERE state NOT IN ('completed', 'cancelled') ORDER BY id DESC LIMIT 1")
    return Events.active
end

-- Who may request a transition into each state.
local TRANSITION_PERMISSION = {
    paused = 'events.operate',
    running = 'events.operate',          -- resume; starting from `ready` is checked separately
    between_rounds = 'events.operate',
}

function Events.transitionPermission(from, to)
    if to == S.RUNNING and from == S.READY then return 'events.manage' end
    return TRANSITION_PERMISSION[to] or 'events.manage'
end

function Events.publicState()
    local e = Events.active
    if not e then return { active = false, serverTime = os.time() } end
    local rot = Carnival.Rotation and Carnival.Rotation.publicState() or {}
    local cfg = Carnival.Config.get()
    return {
        active = true,
        id = e.id,
        name = e.name,
        description = e.description,
        state = e.state,
        mode = e.mode,
        stateLabel = C.STATE_LABELS[e.state],
        resumeState = e.resume_state,
        serverTime = os.time(),
        round = rot.round,
        totalRounds = rot.totalRounds,
        roundState = rot.roundState,
        roundEndsAt = rot.roundEndsAt,
        roundRemaining = rot.roundRemaining,
        nextRoundAt = rot.nextRoundAt,
        overtime = rot.overtime,
        registrationOpen = Carnival.Registration and Carnival.Registration.isOpen() or false,
        participantCount = Carnival.Participants and Carnival.Participants.count() or 0,
        maxParticipants = cfg and cfg.registration.maxParticipants or 0,
    }
end

local function snapshotSettings(eventId, reason)
    local info = Carnival.Config.versionInfo()
    Carnival.Db.insertRow('carnival_event_settings', {
        event_id = eventId, reason = reason,
        global_version = info.global and info.global.version or nil,
        event_version = info.event and info.event.version or nil,
        data = json.encode(Carnival.Config.get()), created_at = os.time(),
    })
end
Events.snapshotSettings = snapshotSettings

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------
function Events.create(src, fields)
    if Events.active then return nil, 'invalid', 'Another event is still active. Complete or cancel it first.' end
    local actor = Carnival.Identity.actor(src)
    local cfg = Carnival.Config.get()
    local now = os.time()
    local id = Carnival.Db.insertRow('carnival_events', {
        name = fields.name or cfg.general.eventName,
        description = fields.description or cfg.general.description,
        state = S.CONFIGURING,
        mode = fields.mode or cfg.general.mode,
        template_of = fields.templateOf,
        registration_opens_at = fields.registrationOpensAt,
        registration_closes_at = fields.registrationClosesAt,
        scheduled_start = fields.scheduledStart,
        scheduled_end = fields.scheduledEnd,
        created_by = actor.license,
        created_at = now, updated_at = now,
    })
    if not id then return nil, 'database_error', 'The event could not be created.' end
    Carnival.Db.insertRow('carnival_event_transitions', {
        event_id = id, from_state = S.INACTIVE, to_state = S.CONFIGURING, actor = actor.license, actor_name = actor.name,
        reason = fields.templateOf and ('Created from template #' .. fields.templateOf) or 'Created', created_at = now,
    })
    reloadActive()
    Carnival.Audit.record(actor, 'event_created', { eventId = id, targetType = 'event', targetId = id, details = { name = fields.name, templateOf = fields.templateOf } })
    Carnival.Discord.send('event', 'Event created', ('#%d %s'):format(id, fields.name or cfg.general.eventName), 0x6e0f1d)
    Carnival.Participants.loadForEvent(id)
    Carnival.Scoring.loadForEvent(id)
    Carnival.Config.loadEventScope(id)
    Carnival.Perms.loadAssignments()
    Carnival.Push.eventState()
    Carnival.Push.invalidate('dashboard', 'events')
    return id
end

-- Create a new event using an earlier event as a template (name, description and
-- its event-specific settings). History of the template is untouched.
function Events.duplicate(src, templateId, name)
    local t = Events.get(templateId)
    if not t then return nil, 'not_found', 'Template event not found.' end
    local id, code, msg = Events.create(src, { name = name or (t.name .. ' (copy)'), description = t.description, templateOf = templateId })
    if not id then return nil, code, msg end
    local row = Carnival.Db.single("SELECT data FROM carnival_config_versions WHERE scope = 'event' AND event_id = ? AND is_active = 1 ORDER BY version DESC LIMIT 1", { templateId })
    if row then
        Carnival.Config.save(src, 'event', Carnival.Db.decode(row.data, {}), 'Copied from event #' .. templateId, true)
    end
    return id
end

function Events.update(src, id, fields)
    local e = Events.get(id)
    if not e then return nil, 'not_found' end
    if C.TERMINAL_STATES[e.state] then return nil, 'invalid', 'Completed or cancelled events cannot be edited.' end
    local set = { updated_at = os.time() }
    for k, col in pairs({ name = 'name', description = 'description', registrationOpensAt = 'registration_opens_at',
        registrationClosesAt = 'registration_closes_at', scheduledStart = 'scheduled_start', scheduledEnd = 'scheduled_end' }) do
        if fields[k] ~= nil then set[col] = fields[k] == false and Carnival.Db.NULL or fields[k] end
    end
    Carnival.Db.updateRow('carnival_events', set, 'id = ?', { id })
    Carnival.Audit.record(Carnival.Identity.actor(src), 'event_updated', { eventId = id, targetType = 'event', targetId = id, details = fields })
    if Events.activeId() == id then reloadActive() Carnival.Push.eventState() end
    Carnival.Push.invalidate('dashboard', 'events')
    return true
end

---------------------------------------------------------------------------
-- State machine
---------------------------------------------------------------------------

local function preconditions(e, to)
    local cfg = Carnival.Config.get()
    if to == S.REG_OPEN then
        if not cfg.registration.virtualTickets and Config.Inventory.RequireItemDefinitions then
            local res = Carnival.Inventory.validateDefinitions(true)
            local missingTickets = {}
            for _, m in ipairs(res.missing) do
                if C.TICKET_ITEM_COLOUR[m] then missingTickets[#missingTickets + 1] = m end
            end
            if not res.inventoryRunning then return 'ox_inventory is not running; physical tickets cannot be issued.' end
            if #missingTickets > 0 then return 'Ticket items are missing from ox_inventory: ' .. table.concat(missingTickets, ', ') end
        end
    elseif to == S.READY then
        local counts = Carnival.Groups.counts()
        if counts.total == 0 then return 'No participants are registered.' end
        if counts.unassigned > 0 then return ('%d participant(s) have no group colour yet.'):format(counts.unassigned) end
    elseif to == S.RUNNING and e.state == S.READY then
        local _, merr = V.rotationMatrix(cfg.rotation.matrix, Carnival.Groups.enabledColours())
        if merr then return 'Rotation matrix is invalid: ' .. merr end
    elseif to == S.BETWEEN and e.state == S.PAUSED then
        if e.resume_state ~= S.BETWEEN then return 'Resume the event instead.' end
    elseif to == S.RUNNING and e.state == S.PAUSED then
        if e.resume_state ~= S.RUNNING then return 'Resume the event instead.' end
    end
    return nil
end

-- Persist a transition atomically. Returns true or nil, code, message.
local function persistTransition(e, to, actor, reason, extraSet)
    local now = os.time()
    local set = { state = to, updated_at = now }
    for k, v in pairs(extraSet or {}) do set[k] = v end
    local upd, updParams = Carnival.Db.buildUpdate('carnival_events', set, 'id = ? AND state = ?', { e.id, e.state })
    local ins, insParams = Carnival.Db.buildInsert('carnival_event_transitions', {
        event_id = e.id, from_state = e.state, to_state = to, actor = actor.license, actor_name = actor.name,
        reason = (reason and reason ~= '') and reason or nil, created_at = now,
    })
    local ok = Carnival.Db.transaction({ { query = upd, values = updParams }, { query = ins, values = insParams } })
    if not ok then return nil, 'database_error', 'The state change could not be saved.' end
    -- verify the guarded update applied (protects against concurrent transitions)
    local fresh = Events.get(e.id)
    if not fresh or fresh.state ~= to then return nil, 'conflict', 'The event state changed meanwhile. Refresh and try again.' end
    return true
end

-- Side effects after a successful transition. Failures pause the event.
local function afterTransition(from, to, actor, reason)
    local e = Events.active
    if to == S.RUNNING and from == S.READY then
        snapshotSettings(e.id, 'start')
        Carnival.Rotation.startEvent(actor)
    elseif to == S.PAUSED then
        Carnival.Rotation.pause(actor)
    elseif from == S.PAUSED and (to == S.RUNNING or to == S.BETWEEN) then
        Carnival.Rotation.resume(actor)
    elseif to == S.FINAL then
        Carnival.Rotation.finish(actor)
        local ok, err = Carnival.Leaderboard.freeze(actor, 'Final results')
        if not ok then
            Carnival.Monitor.log('critical', 'event_state', 'freeze_failed', { actor = actor, details = { error = err } })
        end
    elseif to == S.COMPLETED then
        snapshotSettings(e.id, 'completed')
    elseif to == S.CANCELLED then
        Carnival.Rotation.cancel(actor, reason)
        snapshotSettings(e.id, 'cancelled')
    end
end

function Events.transition(src, to, reason, opts)
    opts = opts or {}
    return Carnival.withLock('event_state', function()
        local e = Events.active
        if not e then return nil, 'invalid', 'There is no active event.' end
        local from = e.state
        if not C.TRANSITIONS[from] or not C.TRANSITIONS[from][to] then
            Carnival.Monitor.log('warning', 'event_state', 'invalid_transition', { actor = Carnival.Identity.actor(src), details = { from = from, to = to } })
            return nil, 'invalid_transition', ('Cannot go from %s to %s.'):format(C.STATE_LABELS[from] or from, C.STATE_LABELS[to] or to)
        end
        if src ~= 0 and not opts.system then
            local perm = Events.transitionPermission(from, to)
            if not Carnival.Perms.has(src, perm) then
                Carnival.Monitor.security(src, 'permission_denied', { action = 'event_transition', to = to, permission = perm }, 'permission')
                return nil, 'forbidden', 'You do not have permission to do that.'
            end
        end
        if to == S.CANCELLED and (not reason or #reason < 3) then
            return nil, 'invalid', 'A reason is required to cancel an event.'
        end
        if not opts.force then
            local why = preconditions(e, to)
            if why then return nil, 'precondition', why end
        end

        local actor = opts.actor or Carnival.Identity.actor(src)
        local extra = {}
        if to == S.PAUSED then extra.resume_state = from end
        if from == S.PAUSED then extra.resume_state = Carnival.Db.NULL end
        if to == S.RUNNING and from == S.READY then extra.started_at = os.time() end
        if C.TERMINAL_STATES[to] then
            extra.ended_at = os.time()
            if reason and reason ~= '' then extra.end_reason = reason end
        end
        local ok, code, msg = persistTransition(e, to, actor, reason, extra)
        if not ok then return nil, code, msg end
        reloadActive()
        if not Events.active then
            -- terminal: keep a reference to the finished event for side effects
            Events.active = Events.get(e.id)
        end

        Carnival.Monitor.log('info', 'event_state', 'state_changed', { eventId = e.id, actor = actor, result = to, details = { from = from, to = to, reason = reason } })
        Carnival.Audit.record(actor, 'event_state_changed', { eventId = e.id, targetType = 'event', targetId = e.id, reason = reason, details = { from = from, to = to } })
        Carnival.Discord.send('event', 'Event state: ' .. (C.STATE_LABELS[to] or to), ('#%d %s\n%s → %s%s'):format(e.id, e.name, from, to, reason and reason ~= '' and ('\n' .. reason) or ''), 0x6e0f1d)

        local sok, serr = pcall(afterTransition, from, to, actor, reason)
        if not sok then
            Carnival.Monitor.log('critical', 'event_state', 'transition_side_effect_failed', { eventId = e.id, details = { from = from, to = to, error = tostring(serr) } })
        end

        if C.TERMINAL_STATES[to] then
            Events.active = nil
            Carnival.Config.loadEventScope(nil)
            Carnival.Perms.loadAssignments()
        end
        Carnival.Push.eventState()
        Carnival.Participants.pushAll()
        Carnival.Push.invalidate('dashboard', 'events', 'rotation')
        return { from = from, to = to }
    end)
end

-- Resume a paused event into the state it was paused from.
function Events.resume(src, reason)
    local e = Events.active
    if not e or e.state ~= S.PAUSED then return nil, 'invalid', 'The event is not paused.' end
    return Events.transition(src, e.resume_state or S.RUNNING, reason)
end

---------------------------------------------------------------------------
-- Recovery
---------------------------------------------------------------------------
function Events.recover()
    reloadActive()
    local e = Events.active
    if not e then
        Carnival.Monitor.log('info', 'recovery', 'no_active_event', {})
        return
    end
    Carnival.Monitor.log('info', 'recovery', 'event_loaded', { eventId = e.id, details = { state = e.state, round = e.current_round } })
    Carnival.Config.loadEventScope(e.id, true)
    Carnival.Participants.loadForEvent(e.id)
    Carnival.Scoring.loadForEvent(e.id)
    Carnival.Rotation.recover(e)
    Carnival.Attractions.recover(e)
    Carnival.Rewards.recover(e.id)

    -- walk-up events stay open through restarts (nothing is mid-round)
    if (e.state == S.RUNNING or e.state == S.BETWEEN) and Config.Recovery.PauseRunningEventOnStart and e.mode ~= 'walkup' then
        local ok, code, msg = Events.transition(0, S.PAUSED, 'Automatically paused after a resource/server restart', { system = true, actor = Carnival.Identity.SYSTEM })
        if not ok then
            Carnival.Monitor.log('error', 'recovery', 'auto_pause_failed', { eventId = e.id, details = { code = code, message = msg } })
        else
            Carnival.Monitor.log('warning', 'recovery', 'event_paused_after_restart', { eventId = e.id, details = { previous = e.state } })
        end
    end
end

-- Admin recovery actions for an interrupted event.
function Events.recoveryAction(src, action, reason)
    local actor = Carnival.Identity.actor(src)
    if action == 'reload' then
        Events.recover()
    elseif action == 'force_pause' then
        local e = Events.active
        if not e or e.state == S.PAUSED then return nil, 'invalid', 'Nothing to pause.' end
        local ok, code, msg = Events.transition(src, S.PAUSED, reason, { force = true })
        if not ok then return nil, code, msg end
    elseif action == 'recheck_rewards' then
        Carnival.Rewards.recover(Events.activeId())
    else
        return nil, 'invalid', 'Unknown recovery action.'
    end
    Carnival.Audit.record(actor, 'event_recovery_action', { targetType = 'event', targetId = Events.activeId(), reason = reason, details = { action = action } })
    return true
end

---------------------------------------------------------------------------
-- Walk-up mode: the carnival opens itself and stays open, no staff needed.
-- When general.mode is 'walkup' and no event is active, a walk-up event is
-- created and moved straight to running; registration stays open while it
-- runs. Finalising or cancelling it ends that night: a fresh carnival opens.
---------------------------------------------------------------------------
local WALKUP_PATH = {
    [S.CONFIGURING] = S.REG_OPEN,
    [S.REG_OPEN] = S.REG_CLOSED,
    [S.REG_CLOSED] = S.READY,
    [S.READY] = S.RUNNING,
}
local walkupRetryAt = 0
local walkupLastError = nil

local function walkupFailed(step, code, msg)
    walkupRetryAt = os.time() + 60
    local text = ('%s: %s'):format(step, msg or code or '?')
    if text ~= walkupLastError then
        walkupLastError = text
        Carnival.Monitor.log('error', 'event_state', 'walkup_open_failed', { details = { step = step, code = code, message = msg } })
    end
end

local walkupBusy = false

local function ensureWalkup()
    if Carnival.Config.get().general.mode ~= 'walkup' then return end
    local SYSTEM = Carnival.Identity.SYSTEM
    if not Events.active then
        local id, code, msg = Events.create(0, { mode = 'walkup' })
        if not id then return walkupFailed('create', code, msg) end
        Carnival.Monitor.log('info', 'event_state', 'walkup_event_created', { eventId = id })
    end
    if Events.active.mode ~= 'walkup' then return end
    for _ = 1, 4 do
        local to = WALKUP_PATH[Events.active.state]
        if not to then break end
        -- the ticket item check still applies when opening registration
        local ok, code, msg = Events.transition(0, to, 'Walk-up carnival opens automatically',
            { system = true, actor = SYSTEM, force = to ~= S.REG_OPEN })
        if not ok then return walkupFailed(to, code, msg) end
    end
    if walkupLastError then
        walkupLastError = nil
        Carnival.Monitor.log('info', 'event_state', 'walkup_open_recovered', { eventId = Events.activeId() })
    end
end

function Events.ensureWalkup()
    if not Carnival.ready or walkupBusy or os.time() < walkupRetryAt then return end
    walkupBusy = true
    local ok, err = pcall(ensureWalkup)
    walkupBusy = false
    if not ok then walkupFailed('error', 'internal_error', tostring(err)) end
end

local walkupCheckedAt = 0
Carnival.onTick('walkup', function(now)
    if now - walkupCheckedAt < 5 then return end
    walkupCheckedAt = now
    Events.ensureWalkup()
end)

---------------------------------------------------------------------------
-- History
---------------------------------------------------------------------------
function Events.list(page, pageSize, filters)
    filters = filters or {}
    local where, params = {}, {}
    if filters.state then where[#where + 1] = 'state = ?' params[#params + 1] = filters.state end
    if filters.search then where[#where + 1] = 'name LIKE ?' params[#params + 1] = '%' .. filters.search .. '%' end
    local whereSql = #where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or ''
    local total = Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_events' .. whereSql, params) or 0
    local lp = { table.unpack(params) }
    lp[#lp + 1] = pageSize
    lp[#lp + 1] = (page - 1) * pageSize
    local rows = Carnival.Db.query([[SELECT e.*, (SELECT COUNT(*) FROM carnival_participants p WHERE p.event_id = e.id) AS participant_count
        FROM carnival_events e]] .. whereSql .. ' ORDER BY e.id DESC LIMIT ? OFFSET ?', lp) or {}
    return rows, total
end

function Events.transitions(eventId)
    return Carnival.Db.query('SELECT * FROM carnival_event_transitions WHERE event_id = ? ORDER BY id DESC LIMIT 200', { eventId }) or {}
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local Api = Carnival.Api

local function eventFields(payload)
    local out = {}
    if payload.name ~= nil then
        local v, err = V.string(payload.name, 96)
        if not v then return nil, 'name ' .. err end
        out.name = v
    end
    if payload.description ~= nil then
        local v, err = V.text(payload.description, 1000, true)
        if not v then return nil, 'description ' .. err end
        out.description = v
    end
    for _, k in ipairs({ 'registrationOpensAt', 'registrationClosesAt', 'scheduledStart', 'scheduledEnd' }) do
        if payload[k] ~= nil then
            if payload[k] == false or payload[k] == 0 then
                out[k] = false
            else
                local v, err = V.int(payload[k], 1000000000, 4102444800)
                if not v then return nil, k .. ' ' .. err end
                out[k] = v
            end
        end
    end
    return out
end

Api.register('events.list', {
    perm = 'events.history', rate = 'admin',
    handler = function(ctx, payload)
        local page = V.int(payload.page or 1, 1, 100000) or 1
        local state = payload.state and V.oneOf(payload.state, U.keys(C.STATE_LABELS)) or nil
        local search = payload.search and V.string(payload.search, 64, true) or nil
        local rows, total = Events.list(page, 20, { state = state, search = search ~= '' and search or nil })
        return { rows = rows, total = total, page = page, pageSize = 20 }
    end,
})

Api.register('events.get', {
    perm = 'events.history', rate = 'admin',
    handler = function(ctx, payload)
        local id, err = V.id(payload.id)
        if not id then return nil, 'invalid', 'id ' .. err end
        local e = Events.get(id)
        if not e then return nil, 'not_found' end
        local results = Carnival.Leaderboard.resultVersions(id)
        local settings = Carnival.Db.query('SELECT id, reason, global_version, event_version, created_at FROM carnival_event_settings WHERE event_id = ? ORDER BY id DESC', { id }) or {}
        return {
            event = e,
            transitions = Events.transitions(id),
            results = results,
            settingsSnapshots = settings,
            stats = Carnival.Db.single([[SELECT
                (SELECT COUNT(*) FROM carnival_participants WHERE event_id = ?) AS participants,
                (SELECT COUNT(*) FROM carnival_score_transactions WHERE event_id = ?) AS transactions,
                (SELECT COUNT(*) FROM carnival_rewards WHERE event_id = ?) AS rewards]], { id, id, id }),
        }
    end,
})

Api.register('events.create', {
    perm = { 'panel.admin', 'events.manage' }, rate = 'admin',
    handler = function(ctx, payload)
        local fields, err = eventFields(payload)
        if not fields then return nil, 'invalid', err end
        for k, v in pairs(fields) do if v == false then fields[k] = nil end end
        local id, code, msg = Events.create(ctx.source, fields)
        if not id then return nil, code, msg end
        return { id = id }
    end,
})

Api.register('events.duplicate', {
    perm = { 'panel.admin', 'events.manage' }, rate = 'admin',
    handler = function(ctx, payload)
        local id, err = V.id(payload.id)
        if not id then return nil, 'invalid', 'id ' .. err end
        local name = payload.name and V.string(payload.name, 96) or nil
        local newId, code, msg = Events.duplicate(ctx.source, id, name)
        if not newId then return nil, code, msg end
        return { id = newId }
    end,
})

Api.register('events.update', {
    perm = { 'panel.admin', 'events.manage' }, rate = 'admin',
    handler = function(ctx, payload)
        local id, err = V.id(payload.id)
        if not id then return nil, 'invalid', 'id ' .. err end
        local fields, ferr = eventFields(payload)
        if not fields then return nil, 'invalid', ferr end
        return Events.update(ctx.source, id, fields)
    end,
})

-- Permission is checked inside Events.transition (depends on the target state).
Api.register('events.transition', {
    anyPerm = { 'events.manage', 'events.operate' }, rate = 'staff',
    handler = function(ctx, payload)
        local to = V.oneOf(payload.to, U.keys(C.STATE_LABELS))
        if not to then return nil, 'invalid', 'Unknown target state.' end
        local reason, rerr = V.reason(payload.reason, to == S.CANCELLED)
        if not reason then return nil, 'invalid', rerr end
        return Events.transition(ctx.source, to, reason)
    end,
})

Api.register('events.resume', {
    perm = 'events.operate', rate = 'staff',
    handler = function(ctx, payload)
        local reason = V.reason(payload.reason, false) or ''
        return Events.resume(ctx.source, reason)
    end,
})

Api.register('events.recover', {
    perm = { 'panel.admin', 'events.manage' }, rate = 'admin',
    handler = function(ctx, payload)
        local action = V.oneOf(payload.action, { 'reload', 'force_pause', 'recheck_rewards' })
        if not action then return nil, 'invalid', 'Unknown recovery action.' end
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        return Events.recoveryAction(ctx.source, action, reason)
    end,
})

Api.register('event.public', {
    rate = 'participant',
    handler = function()
        return Events.publicState()
    end,
})
