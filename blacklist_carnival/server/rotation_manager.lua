-- Six-colour rotation: rounds, per-group attraction sessions, timers and overrides.
--
-- A round has one session per enabled colour; the matrix decides which attraction
-- each colour visits. The round timer runs on the server. When it expires,
-- attractions are completed automatically unless a run is still in progress
-- (a show, mystery or maze run): the round goes into overtime until it ends.
--
-- Walk-up events have no rounds. Each participant works through their colour's
-- column of the matrix at their own pace. An attraction keeps one open walk-up
-- session; players whose next game it is join it when they arrive, and leave it
-- once they have played (or the group run they joined has finished).

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local S, SS = C.STATES, C.SESSION_STATUS
local Rotation = {}
Carnival.Rotation = Rotation

local round = nil              -- current carnival_rounds row
local sessions = {}            -- [colour] = session row (current round)
local completedByColour = {}   -- [colour] = { attraction = status }
local completedByPid = {}      -- [pid] = { attractionId, ... }
local warningsSent = {}
local transitionPausedRemaining = nil
local walkup = {}              -- [attractionId] = open walk-up session row (+ lastActivity)
local joined = {}              -- [sessionId] = { [participantId] = true } players in a walk-up session

local function cfg() return Carnival.Config.get() end
local function matrix() return cfg().rotation.matrix end

function Rotation.totalRounds() return #matrix() end
function Rotation.currentRoundNumber() return round and round.round_number or 0 end
function Rotation.currentRound() return round end

local function reset()
    round, sessions, completedByColour, completedByPid, warningsSent = nil, {}, {}, {}, {}
    transitionPausedRemaining = nil
    walkup, joined = {}, {}
end

function Rotation.recover(e)
    reset()
    if not e then return end
    for _, r in ipairs(Carnival.Db.query("SELECT colour, attraction_id, status FROM carnival_attraction_sessions WHERE event_id = ? AND kind = 'round' AND status IN ('completed', 'skipped')", { e.id }) or {}) do
        completedByColour[r.colour] = completedByColour[r.colour] or {}
        completedByColour[r.colour][r.attraction_id] = r.status
    end
    for _, r in ipairs(Carnival.Db.query("SELECT participant_id, attraction_id FROM carnival_attraction_participation WHERE event_id = ? AND status = 'completed'", { e.id }) or {}) do
        completedByPid[r.participant_id] = completedByPid[r.participant_id] or {}
        table.insert(completedByPid[r.participant_id], r.attraction_id)
    end
    for _, s in ipairs(Carnival.Db.query("SELECT * FROM carnival_attraction_sessions WHERE event_id = ? AND kind = 'walkup' AND status = 'active'", { e.id }) or {}) do
        s.lastActivity = os.time()
        joined[s.id] = {}
        for _, m in ipairs(Carnival.Db.query('SELECT participant_id FROM carnival_session_members WHERE session_id = ? AND left_at IS NULL', { s.id }) or {}) do
            joined[s.id][m.participant_id] = true
        end
        walkup[s.attraction_id] = s
    end
    round = Carnival.Db.single('SELECT * FROM carnival_rounds WHERE event_id = ? ORDER BY round_number DESC LIMIT 1', { e.id })
    if round then
        for _, s in ipairs(Carnival.Db.query('SELECT * FROM carnival_attraction_sessions WHERE event_id = ? AND round_number = ?', { e.id, round.round_number }) or {}) do
            sessions[s.colour] = s
        end
        if round.paused_remaining == nil and round.state == 'active' and e.state == S.PAUSED then
            -- paused before the restart without a stored remainder: freeze at current remaining
            round.paused_remaining = math.max(0, (round.ends_at or os.time()) - os.time())
        end
    end
    Carnival.Monitor.log('info', 'recovery', 'rotation_recovered', { eventId = e.id, details = { round = round and round.round_number, sessions = U.count(sessions) } })
end

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------
function Rotation.sessionForColour(colour) return sessions[colour] end

function Rotation.sessionById(id)
    for _, s in pairs(sessions) do if s.id == id then return s end end
    for _, s in pairs(walkup) do if s.id == id then return s end end
    return nil
end

-- Active session for an attraction in the current round (one at most).
function Rotation.activeSessionFor(attractionId)
    if walkup[attractionId] then return walkup[attractionId] end
    for _, s in pairs(sessions) do
        if s.attraction_id == attractionId and s.status == SS.ACTIVE then return s end
    end
    return nil
end

function Rotation.sessionFor(attractionId)
    if walkup[attractionId] then return walkup[attractionId] end
    for _, s in pairs(sessions) do
        if s.attraction_id == attractionId then return s end
    end
    return nil
end

function Rotation.isWalkup()
    return Carnival.Events.isWalkup()
end

-- Participants taking part in a session: the joined players of a walk-up
-- session, or the colour group of a round session.
function Rotation.sessionMembers(s, onlineOnly)
    if s.kind ~= 'walkup' then return Carnival.Participants.members(s.colour, onlineOnly) end
    local out = {}
    for pid in pairs(joined[s.id] or {}) do
        local p = Carnival.Participants.get(pid)
        if p and p.status == 'active' and (not onlineOnly or Carnival.Participants.sourceOf(pid)) then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Rotation.sessionIncludes(s, p)
    if not s or not p then return false end
    if s.kind == 'walkup' then return joined[s.id] ~= nil and joined[s.id][p.id] == true end
    return p.colour ~= nil and p.colour == s.colour
end

-- The session a participant plays an attraction in (nil if they are not there).
function Rotation.participantSession(p, attractionId)
    if not p then return nil end
    local s = walkup[attractionId]
    if s then return (joined[s.id] or {})[p.id] and s or nil end
    s = p.colour and sessions[p.colour]
    return (s and s.attraction_id == attractionId) and s or nil
end

-- Send a push to everyone taking part in a session.
function Rotation.pushSession(s, channel, data)
    if s.kind ~= 'walkup' then return Carnival.Push.group(s.colour, channel, data) end
    for _, p in ipairs(Rotation.sessionMembers(s, true)) do
        Carnival.Push.send(Carnival.Participants.sourceOf(p.id), channel, data)
    end
end

function Rotation.nextAttractionFor(colour)
    local n = Rotation.currentRoundNumber()
    local row = matrix()[n + 1]
    return row and row[C.COLOUR_INDEX[colour]] or nil
end

function Rotation.completedForColour(colour)
    local out = {}
    for a, st in pairs(completedByColour[colour] or {}) do out[#out + 1] = { attraction = a, status = st } end
    return out
end

function Rotation.completedFor(pid)
    return completedByPid[pid] or {}
end

function Rotation.hasCompleted(pid, attractionId)
    for _, a in ipairs(completedByPid[pid] or {}) do
        if a == attractionId then return true end
    end
    return false
end

function Rotation.participantView(p)
    if Rotation.isWalkup() then return Rotation.walkupView(p) end
    local s = p.colour and sessions[p.colour]
    return {
        completed = Rotation.completedFor(p.id),
        current = s and { attraction = s.attraction_id, status = s.status, sessionId = s.id, delayedUntil = s.delayed_until } or nil,
        next = p.colour and Rotation.nextAttractionFor(p.colour) or nil,
    }
end

-- True once the current round's timer has expired (held sessions finish their
-- work and then complete themselves).
function Rotation.inOvertime()
    return round ~= nil and round.state == 'active' and Carnival.Db.bool(round.overtime)
end

-- Complete a held session after its attraction finished during overtime.
function Rotation.completeIfOvertime(sessionId, note)
    if Rotation.isWalkup() or not Rotation.inOvertime() then return end
    local s = Rotation.sessionById(sessionId)
    if s and s.status == SS.ACTIVE then Rotation.completeSession(s.id, Carnival.Identity.SYSTEM, note) end
end

-- A group run (show, maze run, mystery) has finished: a walk-up visit is
-- complete for everyone who took part; a round session only completes here if
-- the round timer already expired.
function Rotation.runFinished(sessionId, note)
    if not Rotation.isWalkup() then return Rotation.completeIfOvertime(sessionId, note) end
    local s = Rotation.sessionById(sessionId)
    if s and s.status == SS.ACTIVE then Rotation.completeSession(s.id, Carnival.Identity.SYSTEM, note) end
end

function Rotation.publicState()
    local e = Carnival.Events.active
    if Rotation.isWalkup() then return { round = 0, totalRounds = Rotation.totalRounds(), walkup = true } end
    if not round then return { round = 0, totalRounds = Rotation.totalRounds() } end
    local paused = e and e.state == S.PAUSED
    return {
        round = round.round_number,
        totalRounds = Rotation.totalRounds(),
        roundState = round.state,
        roundEndsAt = (not paused and round.state == 'active') and round.ends_at or nil,
        roundRemaining = paused and round.paused_remaining or nil,
        overtime = Carnival.Db.bool(round.overtime),
        nextRoundAt = (e and e.state == S.BETWEEN) and round.next_round_at or nil,
    }
end

-- Full grid for staff: every round x colour with session status.
function Rotation.staffState()
    local e = Carnival.Events.active
    local grid = {}
    local m = matrix()
    for r = 1, #m do
        grid[r] = {}
        for i, c in ipairs(C.COLOURS) do grid[r][c] = { attraction = m[r][i], status = 'scheduled' } end
    end
    if e then
        for _, s in ipairs(Carnival.Db.query('SELECT id, round_number, colour, attraction_id, status, started_at, completed_at, note, delayed_until FROM carnival_attraction_sessions WHERE event_id = ?', { e.id }) or {}) do
            if grid[s.round_number] then
                grid[s.round_number][s.colour] = { attraction = s.attraction_id, status = s.status, sessionId = s.id,
                    startedAt = s.started_at, completedAt = s.completed_at, note = s.note, delayedUntil = s.delayed_until }
            end
        end
    end
    local current = {}
    for _, c in ipairs(C.COLOURS) do
        local s = sessions[c]
        if s then
            current[#current + 1] = {
                colour = c, sessionId = s.id, attraction = s.attraction_id, status = s.status,
                delayedUntil = s.delayed_until,
                online = #Carnival.Participants.members(c, true), members = #Carnival.Participants.members(c, false),
                readiness = Carnival.Attractions.readiness(s.attraction_id),
            }
        end
    end
    local pub = Rotation.publicState()
    pub.grid = grid
    pub.current = current
    pub.enabledColours = Carnival.Groups.enabledColours()
    pub.serverTime = os.time()
    pub.allRoundsDone = round ~= nil and round.state == 'completed' and round.round_number >= Rotation.totalRounds()
    pub.walkupSessions = {}
    for _, a in ipairs(C.ATTRACTIONS) do
        local s = walkup[a]
        if s then
            pub.walkupSessions[#pub.walkupSessions + 1] = {
                sessionId = s.id, attraction = a, startedAt = s.started_at, busy = Carnival.Attractions.sessionBusy(s),
                players = U.map(Rotation.sessionMembers(s, false), function(p)
                    return { id = p.id, name = p.display_name, colour = p.colour, online = Carnival.Participants.sourceOf(p.id) ~= nil }
                end),
            }
        end
    end
    return pub
end

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------
local function attractionLabel(id)
    local a = cfg().attractions[id]
    return a and a.label or C.ATTRACTION_LABELS[id] or id
end

local function notifyGroup(colour, title, text, nType, sound)
    Carnival.Push.group(colour, 'notify', { title = title, description = text, type = nType or 'inform', sound = sound })
end

local function pushRotationChanged()
    Carnival.Push.eventState()
    Carnival.Participants.pushAll()
    Carnival.Push.invalidate('rotation', 'dashboard')
    Carnival.Leaderboard.markDirty()
end

---------------------------------------------------------------------------
-- Session lifecycle
---------------------------------------------------------------------------
local function setSession(s, set)
    Carnival.Db.updateRow('carnival_attraction_sessions', set, 'id = ?', { s.id })
    for k, v in pairs(set) do
        if v == Carnival.Db.NULL then s[k] = nil else s[k] = v end
    end
end

local function activate(s, actor)
    setSession(s, { status = SS.ACTIVE, started_at = os.time(), delayed_until = Carnival.Db.NULL })
    Carnival.Monitor.log('info', 'attraction', 'session_started', { attractionId = s.attraction_id, actor = actor, details = { colour = s.colour, round = s.round_number, sessionId = s.id } })
    Carnival.Attractions.sessionStarted(s)
    notifyGroup(s.colour, ('Round %d'):format(s.round_number), ('Head to %s.'):format(attractionLabel(s.attraction_id)), 'inform', cfg().audio.roundSound)
end

function Rotation.startRound(n, actor)
    local e = Carnival.Events.active
    if not e then return nil, 'no_event' end
    local m = matrix()
    if n < 1 or n > #m then return nil, 'invalid', 'No such round.' end
    local existing = Carnival.Db.single('SELECT id FROM carnival_rounds WHERE event_id = ? AND round_number = ?', { e.id, n })
    if existing then return nil, 'invalid', 'That round has already started.' end
    local now = os.time()
    local duration = cfg().rotation.roundDurationSeconds
    local roundId = Carnival.Db.insertRow('carnival_rounds', {
        event_id = e.id, round_number = n, state = 'active', duration_seconds = duration,
        started_at = now, ends_at = now + duration,
    })
    if not roundId then return nil, 'database_error', 'Round could not be created.' end
    round = Carnival.Db.single('SELECT * FROM carnival_rounds WHERE id = ?', { roundId })
    sessions = {}
    warningsSent = {}
    Carnival.Db.update('UPDATE carnival_events SET current_round = ?, updated_at = ? WHERE id = ?', { n, now, e.id })
    e.current_round = n

    local behaviour = cfg().rotation.unavailableBehaviour
    local toStart = {}
    for _, colour in ipairs(Carnival.Groups.enabledColours()) do
        local attraction = m[n][C.COLOUR_INDEX[colour]]
        local ready = Carnival.Attractions.readiness(attraction)
        local status, note = SS.ACTIVE, nil
        if not ready.available then
            if behaviour == 'skip' then
                status, note = SS.SKIPPED, 'Attraction unavailable: ' .. (ready.reason or '')
            else
                status, note = SS.PENDING, 'Held: ' .. (ready.reason or 'attraction unavailable')
            end
        end
        local sid = Carnival.Db.insertRow('carnival_attraction_sessions', {
            event_id = e.id, round_id = roundId, round_number = n, colour = colour, attraction_id = attraction,
            status = SS.PENDING, note = note,
        })
        if not sid then
            Carnival.Monitor.log('critical', 'rotation', 'session_create_failed', { details = { round = n, colour = colour, attraction = attraction } })
        else
            local s = Carnival.Db.single('SELECT * FROM carnival_attraction_sessions WHERE id = ?', { sid })
            sessions[colour] = s
            if status == SS.ACTIVE then
                toStart[#toStart + 1] = s
            elseif status == SS.SKIPPED then
                Rotation.completeSession(s.id, actor, note, SS.SKIPPED, true)
            else
                notifyGroup(colour, ('Round %d'):format(n), ('%s is not ready yet. Please wait for staff.'):format(attractionLabel(attraction)), 'warning')
                Carnival.Monitor.log('warning', 'rotation', 'session_held', { attractionId = attraction, details = { colour = colour, reason = note } })
            end
        end
    end

    if e.state == S.BETWEEN then
        Carnival.Events.transition(0, S.RUNNING, ('Round %d started'):format(n), { system = true, actor = actor })
    end
    for _, s in ipairs(toStart) do activate(s, actor) end
    Carnival.Monitor.log('info', 'rotation', 'round_started', { actor = actor, details = { round = n, duration = duration } })
    Carnival.Discord.send('event', ('Round %d started'):format(n), ('Duration %s'):format(U.formatDuration(duration)), 0x1f4fbf)
    pushRotationChanged()
    Rotation.checkRoundComplete(actor)
    return true
end

function Rotation.startEvent(actor)
    if Rotation.isWalkup() then
        Carnival.Monitor.log('info', 'rotation', 'walkup_opened', { actor = actor })
        Carnival.Push.all('notify', { title = Carnival.Config.get().general.eventName, description = 'The carnival is open! Buy a ticket at the booth.', type = 'inform', sound = cfg().audio.roundSound })
        pushRotationChanged()
        return true
    end
    return Rotation.startRound(1, actor)
end

-- Record attraction participation for every active member of the group and award
-- the global participation bonus for completed visits.
local function recordOne(s, p, status)
    if Rotation.hasCompleted(p.id, s.attraction_id) then return end
    local bonus = cfg().scoring.participationBonus
    local id = Carnival.Db.insertRow('carnival_attraction_participation', {
        event_id = s.event_id, participant_id = p.id, attraction_id = s.attraction_id,
        session_id = s.id, status = status, completed_at = os.time(),
    })
    if id and status == SS.COMPLETED then
        completedByPid[p.id] = completedByPid[p.id] or {}
        table.insert(completedByPid[p.id], s.attraction_id)
        if Carnival.Shop then
            local ok, err = pcall(Carnival.Shop.played, p, s.attraction_id, s.id, s.event_id)
            if not ok then Carnival.Monitor.log('error', 'shop', 'play_tickets_failed', { participantId = p.id, details = { error = tostring(err) } }) end
        end
        if bonus > 0 then
            Carnival.Scoring.award({
                participantId = p.id, delta = bonus, key = ('participation:%d:%d'):format(s.id, p.id),
                txType = 'participation', source = 'participation_bonus', reason = 'Completed ' .. attractionLabel(s.attraction_id),
                attractionId = s.attraction_id, sessionId = s.id, roundNumber = s.round_number, skipAttractionCap = true,
                publicReason = 'Participation bonus',
            })
        end
    end
end

local function recordParticipation(s, status)
    for _, p in ipairs(Rotation.sessionMembers(s, false)) do recordOne(s, p, status) end
end

-- Complete (or skip/interrupt) a session. silent suppresses the round check (used
-- while building a round).
function Rotation.completeSession(sessionId, actor, note, status, silent)
    status = status or SS.COMPLETED
    local s = Rotation.sessionById(sessionId)
    if not s then return nil, 'not_found', 'Session is not part of the current round.' end
    if s.status ~= SS.ACTIVE and s.status ~= SS.PENDING then
        return nil, 'invalid', ('Session is already %s.'):format(s.status)
    end
    local wasActive = s.status == SS.ACTIVE
    setSession(s, { status = status, completed_at = os.time(), completed_by = actor and actor.license or nil, note = note or s.note })
    if wasActive then Carnival.Attractions.sessionEnded(s, status) end
    if s.kind == 'walkup' then
        Rotation.closeWalkup(s, status, note)
        return true
    end
    if status == SS.COMPLETED or status == SS.SKIPPED then
        completedByColour[s.colour] = completedByColour[s.colour] or {}
        completedByColour[s.colour][s.attraction_id] = status
        recordParticipation(s, status)
    end
    Carnival.Monitor.log('info', 'rotation', 'session_' .. status, { attractionId = s.attraction_id, actor = actor, details = { colour = s.colour, round = s.round_number, note = note } })
    notifyGroup(s.colour, attractionLabel(s.attraction_id),
        status == SS.COMPLETED and 'Attraction complete. Await the next bell.' or ('Attraction %s. %s'):format(status, note or ''),
        status == SS.COMPLETED and 'success' or 'warning')
    if not silent then Rotation.checkRoundComplete(actor) end
    pushRotationChanged()
    return true
end

function Rotation.checkRoundComplete(actor)
    if not round or round.state ~= 'active' then return end
    for _, s in pairs(sessions) do
        if s.status == SS.ACTIVE or s.status == SS.PENDING then return end
    end
    local now = os.time()
    local e = Carnival.Events.active
    local n = round.round_number
    local last = n >= Rotation.totalRounds()
    local nextAt = (not last and cfg().rotation.autoAdvance) and (now + cfg().rotation.transitionSeconds) or nil
    Carnival.Db.updateRow('carnival_rounds', { state = 'completed', completed_at = now, next_round_at = nextAt or Carnival.Db.NULL }, 'id = ?', { round.id })
    round.state, round.completed_at, round.next_round_at = 'completed', now, nextAt
    Carnival.Monitor.log('info', 'rotation', 'round_completed', { actor = actor, details = { round = n, last = last } })
    if e and e.state == S.RUNNING then
        Carnival.Events.transition(0, S.BETWEEN, ('Round %d complete'):format(n), { system = true, actor = actor or Carnival.Identity.SYSTEM })
    end
    if last then
        Carnival.Push.all('notify', { title = 'The final bell', description = 'All attractions are complete. Results are coming...', type = 'inform', sound = cfg().audio.roundSound })
        if cfg().rotation.autoFinalise and Carnival.Events.state() == S.BETWEEN then
            Carnival.Events.transition(0, S.FINAL, 'All rounds complete', { system = true, actor = Carnival.Identity.SYSTEM })
        end
    elseif nextAt then
        Carnival.Push.all('notify', { title = ('Round %d complete'):format(n), description = ('Next round in %s.'):format(U.formatDuration(nextAt - now)), type = 'inform' })
    end
    pushRotationChanged()
end

---------------------------------------------------------------------------
-- Walk-up mode
---------------------------------------------------------------------------
local function walkupCfg() return cfg().rotation.walkup end

-- The colour's attraction order (its column of the matrix).
function Rotation.sequenceFor(colour)
    local out, idx = {}, C.COLOUR_INDEX[colour]
    if not idx then return out end
    for _, row in ipairs(matrix()) do out[#out + 1] = row[idx] end
    return out
end

-- Next attraction for a walk-up participant. Attractions that are unavailable
-- right now are passed over so nobody is stuck behind one. Returns
-- attractionId | nil, plus the first unavailable attraction still to do.
function Rotation.walkupNext(p)
    if not p.colour then return nil end
    local blocked
    for _, a in ipairs(Rotation.sequenceFor(p.colour)) do
        if not Rotation.hasCompleted(p.id, a) then
            if Carnival.Attractions.readiness(a).available then return a, blocked end
            blocked = blocked or a
        end
    end
    return nil, blocked
end

function Rotation.walkupView(p)
    local nxt = Rotation.walkupNext(p)
    local after
    if nxt and p.colour then
        local seen = false
        for _, a in ipairs(Rotation.sequenceFor(p.colour)) do
            if seen and not Rotation.hasCompleted(p.id, a) then after = a break end
            if a == nxt then seen = true end
        end
    end
    local s = nxt and walkup[nxt]
    return {
        walkup = true,
        completed = Rotation.completedFor(p.id),
        sequence = p.colour and Rotation.sequenceFor(p.colour) or {},
        current = nxt and { attraction = nxt, status = SS.ACTIVE, sessionId = (s and (joined[s.id] or {})[p.id]) and s.id or nil } or nil,
        next = after,
        finished = p.colour ~= nil and #Rotation.completedFor(p.id) >= #Rotation.sequenceFor(p.colour),
    }
end

-- May this participant start playing this attraction now? (eligibility gate)
function Rotation.walkupCheck(p, attractionId)
    if not p.colour then return nil, 'no_colour', 'Your ticket has no colour yet. Visit the ticket booth.' end
    if Rotation.hasCompleted(p.id, attractionId) then
        return nil, 'already_completed', 'You have already completed this attraction.'
    end
    local s = walkup[attractionId]
    if s and (joined[s.id] or {})[p.id] then return true end
    if not Carnival.Attractions.readiness(attractionId).available then
        return nil, 'unavailable', ('%s is closed right now.'):format(attractionLabel(attractionId))
    end
    if walkupCfg().enforceOrder then
        local nxt = Rotation.walkupNext(p)
        if nxt ~= attractionId then
            if not nxt then return nil, 'all_done', 'You have finished every attraction you can play right now.' end
            return nil, 'wrong_attraction', ('Your ticket sends you to %s next.'):format(attractionLabel(nxt))
        end
    end
    return true
end

local function memberRow(s, pid, set)
    Carnival.Db.updateRow('carnival_session_members', set, 'session_id = ? AND participant_id = ?', { s.id, pid })
end

-- Join (or create) the open walk-up session of an attraction.
function Rotation.joinWalkup(p, attractionId)
    return Carnival.withLock('walkup:' .. attractionId, function()
        local s = walkup[attractionId]
        if s and (joined[s.id] or {})[p.id] then
            s.lastActivity = os.time()
            return s
        end
        if s and not Carnival.Attractions.canJoin(s, p) then
            return nil, 'busy', ('%s is in use. Wait for the current players to finish.'):format(attractionLabel(attractionId))
        end
        local now = os.time()
        local created = false
        if not s then
            local e = Carnival.Events.active
            local id = Carnival.Db.insertRow('carnival_attraction_sessions', {
                event_id = e.id, kind = 'walkup', attraction_id = attractionId, status = SS.ACTIVE, started_at = now,
            })
            if not id then return nil, 'database_error', 'The attraction could not be opened. Try again.' end
            s = Carnival.Db.single('SELECT * FROM carnival_attraction_sessions WHERE id = ?', { id })
            s.lastActivity = now
            joined[s.id] = {}
            walkup[attractionId] = s
            created = true
        end
        joined[s.id][p.id] = true
        s.lastActivity = now
        Carnival.Db.insertRow('carnival_session_members', { session_id = s.id, participant_id = p.id, status = 'joined', joined_at = now })
        Carnival.Monitor.log('info', 'attraction', 'walkup_joined', { participantId = p.id, attractionId = attractionId, details = { sessionId = s.id, created = created } })
        if created then Carnival.Attractions.sessionStarted(s) end
        Carnival.Participants.pushOwn(p.id)
        Carnival.Push.invalidate('rotation', 'attractions')
        return s
    end)
end

local function notifyNext(p, label)
    local src = Carnival.Participants.sourceOf(p.id)
    if not src then return end
    local nxt = Rotation.walkupNext(p)
    local text
    if nxt then
        text = ('Next on your ticket: %s.'):format(attractionLabel(nxt))
    elseif p.colour and #Rotation.completedFor(p.id) >= #Rotation.sequenceFor(p.colour) then
        text = 'You have completed every attraction. Check the leaderboard!'
    else
        text = 'Nothing else is open for you right now.'
    end
    Carnival.Push.notify(src, label, text, 'success', cfg().audio.roundSound)
end

-- A participant has finished their own game in a walk-up session (individual
-- attractions: wheel, fortune, shooting). The session closes once empty.
function Rotation.memberFinished(sessionId, pid, note)
    local s = Rotation.sessionById(sessionId)
    if not s or s.kind ~= 'walkup' or not (joined[s.id] or {})[pid] then return end
    local p = Carnival.Participants.get(pid)
    if p then recordOne(s, p, SS.COMPLETED) end
    joined[s.id][pid] = nil
    s.lastActivity = os.time()
    memberRow(s, pid, { status = SS.COMPLETED, left_at = os.time() })
    Carnival.Monitor.log('info', 'attraction', 'walkup_member_finished', { participantId = pid, attractionId = s.attraction_id, details = { sessionId = s.id, note = note } })
    if p then
        notifyNext(p, attractionLabel(s.attraction_id))
        Carnival.Participants.pushOwn(pid)
    end
    if next(joined[s.id] or {}) == nil and not Carnival.Attractions.sessionBusy(s) and s.status == SS.ACTIVE then
        Rotation.completeSession(s.id, Carnival.Identity.SYSTEM, note or 'Every player has finished')
    end
    Carnival.Leaderboard.markDirty()
    Carnival.Push.invalidate('rotation', 'dashboard')
end

-- Closing a walk-up session (called after its status is set). Completed
-- sessions credit everyone still in them; other endings leave the attraction
-- open for those players to try again.
function Rotation.closeWalkup(s, status, note)
    if walkup[s.attraction_id] == s then walkup[s.attraction_id] = nil end
    local members = Rotation.sessionMembers(s, false)
    for _, p in ipairs(members) do
        if status == SS.COMPLETED or status == SS.SKIPPED then recordOne(s, p, status) end
        memberRow(s, p.id, { status = status, left_at = os.time() })
    end
    joined[s.id] = nil
    Carnival.Monitor.log('info', 'rotation', 'session_' .. status, { attractionId = s.attraction_id, details = { sessionId = s.id, kind = 'walkup', players = #members, note = note } })
    for _, p in ipairs(members) do
        if status == SS.COMPLETED then
            notifyNext(p, attractionLabel(s.attraction_id))
        else
            local src = Carnival.Participants.sourceOf(p.id)
            if src then Carnival.Push.notify(src, attractionLabel(s.attraction_id), ('Your visit ended: %s. You can try again.'):format(note or status), 'warning') end
        end
    end
    pushRotationChanged()
end

function Rotation.walkupTick(now, e)
    if e.state ~= S.RUNNING then return end
    local idle = walkupCfg().idleSeconds
    for _, s in pairs(walkup) do
        if now - (s.lastActivity or now) >= idle and not Carnival.Attractions.sessionBusy(s) then
            Rotation.completeSession(s.id, Carnival.Identity.SYSTEM, 'closed after being idle', SS.INTERRUPTED)
        end
    end
end

-- Any activity at an attraction keeps its walk-up visit open.
function Rotation.touch(sessionId)
    local s = Rotation.sessionById(sessionId)
    if s and s.kind == 'walkup' then s.lastActivity = os.time() end
end

---------------------------------------------------------------------------
-- Staff overrides
---------------------------------------------------------------------------
local function audit(actor, action, reason, details)
    Carnival.Audit.record(actor, action, { targetType = 'round', targetId = Rotation.currentRoundNumber(), reason = reason, details = details })
end

function Rotation.extend(actor, seconds, reason)
    if not round or round.state ~= 'active' then return nil, 'invalid', 'No round is running.' end
    local e = Carnival.Events.active
    if e.state == S.PAUSED then
        round.paused_remaining = (round.paused_remaining or 0) + seconds
        Carnival.Db.update('UPDATE carnival_rounds SET paused_remaining = ?, extended_seconds = extended_seconds + ? WHERE id = ?', { round.paused_remaining, seconds, round.id })
    else
        local base = math.max(round.ends_at, os.time())
        round.ends_at = base + seconds
        round.overtime = 0
        Carnival.Db.update('UPDATE carnival_rounds SET ends_at = ?, overtime = 0, extended_seconds = extended_seconds + ? WHERE id = ?', { round.ends_at, seconds, round.id })
    end
    round.extended_seconds = (round.extended_seconds or 0) + seconds
    -- re-arm warnings that are now in the future again
    for w in pairs(warningsSent) do
        if round.ends_at and round.ends_at - os.time() > w then warningsSent[w] = nil end
    end
    audit(actor, 'round_extended', reason, { seconds = seconds })
    Carnival.Push.all('notify', { title = 'Extra time', description = ('The round has been extended by %s.'):format(U.formatDuration(seconds)), type = 'inform' })
    pushRotationChanged()
    return true
end

function Rotation.skip(actor, colour, reason)
    local s = sessions[colour]
    if not s then return nil, 'not_found', 'That group has no session this round.' end
    local ok, code, msg = Rotation.completeSession(s.id, actor, 'Skipped: ' .. reason, SS.SKIPPED)
    if not ok then return nil, code, msg end
    audit(actor, 'session_skipped', reason, { colour = colour, attraction = s.attraction_id })
    return true
end

function Rotation.delay(actor, colour, seconds, reason)
    local s = sessions[colour]
    if not s then return nil, 'not_found', 'That group has no session this round.' end
    if s.status ~= SS.ACTIVE and s.status ~= SS.PENDING then return nil, 'invalid', 'Session already finished.' end
    if s.status == SS.ACTIVE and Carnival.Attractions.sessionBusy(s) then
        return nil, 'invalid', 'The attraction is mid-run; stop it before delaying the group.'
    end
    if s.status == SS.ACTIVE then Carnival.Attractions.sessionEnded(s, 'delayed') end
    setSession(s, { status = SS.PENDING, delayed_until = os.time() + seconds, note = 'Delayed: ' .. reason })
    audit(actor, 'session_delayed', reason, { colour = colour, seconds = seconds, attraction = s.attraction_id })
    notifyGroup(colour, 'Delay', ('Your group is delayed by %s. %s'):format(U.formatDuration(seconds), reason), 'warning')
    pushRotationChanged()
    return true
end

function Rotation.activateSession(actor, colour, reason)
    local s = sessions[colour]
    if not s then return nil, 'not_found', 'That group has no session this round.' end
    if s.status ~= SS.PENDING then return nil, 'invalid', 'Session is not waiting.' end
    activate(s, actor)
    audit(actor, 'session_started_manually', reason, { colour = colour, attraction = s.attraction_id })
    pushRotationChanged()
    return true
end

-- Force-finish the current round (remaining sessions are completed with a note).
function Rotation.advance(actor, reason)
    local e = Carnival.Events.active
    if e and e.state == S.BETWEEN then
        return Rotation.startNextRound(actor, reason)
    end
    if not round or round.state ~= 'active' then return nil, 'invalid', 'No round is running.' end
    for _, s in pairs(sessions) do
        if s.status == SS.ACTIVE or s.status == SS.PENDING then
            Rotation.completeSession(s.id, actor, 'Force-advanced: ' .. reason, SS.COMPLETED, true)
        end
    end
    audit(actor, 'round_force_advanced', reason, { round = round.round_number })
    Rotation.checkRoundComplete(actor)
    return true
end

function Rotation.startNextRound(actor, reason)
    local e = Carnival.Events.active
    if not e or e.state ~= S.BETWEEN then return nil, 'invalid', 'The event is not between rounds.' end
    local n = Rotation.currentRoundNumber() + 1
    if n > Rotation.totalRounds() then return nil, 'invalid', 'All rounds are complete. Move the event to final results.' end
    local ok, code, msg = Rotation.startRound(n, actor)
    if not ok then return nil, code, msg end
    audit(actor, 'round_started_manually', reason, { round = n })
    return true
end

---------------------------------------------------------------------------
-- Event-level hooks
---------------------------------------------------------------------------
function Rotation.pause(actor)
    local now = os.time()
    if round and round.state == 'active' and round.ends_at then
        round.paused_remaining = math.max(0, round.ends_at - now)
        Carnival.Db.update('UPDATE carnival_rounds SET paused_remaining = ? WHERE id = ?', { round.paused_remaining, round.id })
    elseif round and round.next_round_at then
        transitionPausedRemaining = math.max(0, round.next_round_at - now)
        Carnival.Db.update('UPDATE carnival_rounds SET paused_remaining = ? WHERE id = ?', { transitionPausedRemaining, round.id })
    end
    Carnival.Attractions.pauseAll(actor)
    Carnival.Push.all('notify', { title = 'Paused', description = 'The carnival is paused. Stay where you are.', type = 'warning' })
end

function Rotation.resume(actor)
    local now = os.time()
    if round and round.state == 'active' and round.paused_remaining then
        round.ends_at = now + round.paused_remaining
        round.paused_remaining = nil
        Carnival.Db.update('UPDATE carnival_rounds SET ends_at = ?, paused_remaining = NULL WHERE id = ?', { round.ends_at, round.id })
    elseif round and round.state == 'completed' and (transitionPausedRemaining or round.paused_remaining) and round.next_round_at then
        round.next_round_at = now + (transitionPausedRemaining or round.paused_remaining)
        transitionPausedRemaining = nil
        round.paused_remaining = nil
        Carnival.Db.update('UPDATE carnival_rounds SET next_round_at = ?, paused_remaining = NULL WHERE id = ?', { round.next_round_at, round.id })
    end
    Carnival.Attractions.resumeAll(actor)
    Carnival.Push.all('notify', { title = 'Resumed', description = 'The carnival continues!', type = 'success', sound = cfg().audio.roundSound })
end

local function closeOpenSessions(actor, status, note)
    for _, s in pairs(walkup) do
        setSession(s, { status = status, completed_at = os.time(), completed_by = actor and actor.license or nil, note = note })
        Carnival.Attractions.sessionEnded(s, status)
        Rotation.closeWalkup(s, status, note)
    end
    for _, s in pairs(sessions) do
        if s.status == SS.ACTIVE or s.status == SS.PENDING then
            local wasActive = s.status == SS.ACTIVE
            setSession(s, { status = status, completed_at = os.time(), completed_by = actor and actor.license or nil, note = note })
            if wasActive then Carnival.Attractions.sessionEnded(s, status) end
        end
    end
    if round and round.state == 'active' then
        Carnival.Db.update("UPDATE carnival_rounds SET state = 'completed', completed_at = ? WHERE id = ?", { os.time(), round.id })
        round.state = 'completed'
    end
end

function Rotation.finish(actor)
    closeOpenSessions(actor, SS.INTERRUPTED, 'Event moved to final results')
    if round then round.next_round_at = nil end
    Carnival.Attractions.eventEnded('final')
end

function Rotation.cancel(actor, reason)
    closeOpenSessions(actor, SS.INTERRUPTED, 'Event cancelled: ' .. tostring(reason))
    Carnival.Attractions.eventEnded('cancelled')
    reset()
end

---------------------------------------------------------------------------
-- Ticker
---------------------------------------------------------------------------
Carnival.onTick('rotation', function(now)
    local e = Carnival.Events.active
    if e and e.mode == 'walkup' then return Rotation.walkupTick(now, e) end
    if not e or not round then return end
    if e.state == S.RUNNING and round.state == 'active' then
        local remaining = (round.ends_at or now) - now
        for _, w in ipairs(cfg().rotation.warningSeconds) do
            if remaining <= w and remaining > 0 and not warningsSent[w] then
                warningsSent[w] = true
                Carnival.Push.all('notify', { title = 'Round ending', description = ('%s remaining in this round.'):format(U.formatDuration(remaining)), type = 'warning' })
                Carnival.Monitor.log('debug', 'countdown', 'round_warning', { details = { round = round.round_number, remaining = remaining } })
            end
        end
        -- delayed sessions whose delay has elapsed
        for _, s in pairs(sessions) do
            if s.status == SS.PENDING and s.delayed_until and now >= s.delayed_until then
                local ready = Carnival.Attractions.readiness(s.attraction_id)
                if ready.available then activate(s, Carnival.Identity.SYSTEM) pushRotationChanged() end
            end
        end
        if remaining <= 0 and not Carnival.Db.bool(round.overtime) then
            round.overtime = 1
            Carnival.Db.update('UPDATE carnival_rounds SET overtime = 1 WHERE id = ?', { round.id })
            Carnival.Monitor.log('info', 'countdown', 'round_timer_expired', { details = { round = round.round_number } })
            local held = {}
            for _, s in pairs(sessions) do
                if s.status == SS.ACTIVE then
                    local decision = 'hold'
                    if cfg().rotation.autoCompleteOnTimer then
                        decision = Carnival.Attractions.timerExpired(s)
                    end
                    if decision == 'complete' then
                        Rotation.completeSession(s.id, Carnival.Identity.SYSTEM, 'Round timer expired', SS.COMPLETED, true)
                    else
                        held[#held + 1] = s.colour .. ':' .. s.attraction_id
                    end
                end
            end
            if #held > 0 then
                Carnival.Monitor.log('warning', 'rotation', 'round_overtime', { details = { round = round.round_number, waitingOn = held } })
                Carnival.Push.invalidate('rotation')
            end
            Rotation.checkRoundComplete(Carnival.Identity.SYSTEM)
            pushRotationChanged()
        end
    elseif e.state == S.BETWEEN and round.state == 'completed' and round.next_round_at and now >= round.next_round_at then
        round.next_round_at = nil
        local n = round.round_number + 1
        if n <= Rotation.totalRounds() then
            local ok, code, msg = Rotation.startRound(n, Carnival.Identity.SYSTEM)
            if not ok then
                Carnival.Monitor.log('error', 'rotation', 'auto_round_start_failed', { details = { round = n, code = code, message = msg } })
            end
        end
    end
end)

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local Api = Carnival.Api

Api.register('rotation.state', {
    perm = 'panel.admin', rate = 'staff',
    handler = function() return Rotation.staffState() end,
})

local function reasonOf(payload, required)
    return V.reason(payload.reason, required)
end

Api.register('rotation.extend', {
    perm = 'events.operate', rate = 'staff',
    handler = function(ctx, payload)
        local seconds, err = V.int(payload.seconds, 10, 3600)
        if not seconds then return nil, 'invalid', 'seconds ' .. err end
        local reason, rerr = reasonOf(payload, true)
        if not reason then return nil, 'invalid', rerr end
        return Rotation.extend(ctx.actor, seconds, reason)
    end,
})

Api.register('rotation.skip', {
    perm = 'events.operate', rate = 'staff',
    handler = function(ctx, payload)
        local colour = V.colour(payload.colour)
        if not colour then return nil, 'invalid', 'Invalid colour.' end
        local reason, rerr = reasonOf(payload, true)
        if not reason then return nil, 'invalid', rerr end
        return Rotation.skip(ctx.actor, colour, reason)
    end,
})

Api.register('rotation.delay', {
    perm = 'events.operate', rate = 'staff',
    handler = function(ctx, payload)
        local colour = V.colour(payload.colour)
        if not colour then return nil, 'invalid', 'Invalid colour.' end
        local seconds, err = V.int(payload.seconds, 10, 3600)
        if not seconds then return nil, 'invalid', 'seconds ' .. err end
        local reason, rerr = reasonOf(payload, true)
        if not reason then return nil, 'invalid', rerr end
        return Rotation.delay(ctx.actor, colour, seconds, reason)
    end,
})

Api.register('rotation.activate', {
    perm = 'events.operate', rate = 'staff',
    handler = function(ctx, payload)
        local colour = V.colour(payload.colour)
        if not colour then return nil, 'invalid', 'Invalid colour.' end
        local reason = reasonOf(payload, false) or ''
        return Rotation.activateSession(ctx.actor, colour, reason)
    end,
})

Api.register('rotation.completeSession', {
    perm = 'events.operate',
    rate = 'staff',
    handler = function(ctx, payload)
        local s, colour
        if payload.sessionId ~= nil then
            s = Rotation.sessionById(V.id(payload.sessionId))
            colour = s and s.colour
        else
            colour = V.colour(payload.colour)
            if not colour then return nil, 'invalid', 'Invalid colour.' end
            s = sessions[colour]
        end
        if not s then return nil, 'not_found', 'That session is not open.' end
        local reason = reasonOf(payload, false) or ''
        local ok, code, msg = Rotation.completeSession(s.id, ctx.actor, reason ~= '' and reason or 'Completed by staff')
        if not ok then return nil, code, msg end
        Carnival.Audit.record(ctx.actor, 'session_completed', { targetType = 'session', targetId = s.id, reason = reason, details = { colour = colour, attraction = s.attraction_id } })
        return true
    end,
})

Api.register('rotation.advance', {
    perm = 'events.operate', rate = 'staff',
    handler = function(ctx, payload)
        local reason, rerr = reasonOf(payload, true)
        if not reason then return nil, 'invalid', rerr end
        return Rotation.advance(ctx.actor, reason)
    end,
})
