-- Attraction: The Hall of Deception - a maze of doors.
-- A player talks to the doorman and appears at the start. Every door sends
-- them to another door (or straight back to the start), hidden traps send them
-- back to the start, and stepping into the finish circle ends the run and pays
-- the finish points. Runs out of time: no points, out you go.
-- Where each door leads stays on the server; the server checks the player is
-- at the door, trap or finish before it answers, and tells the client where to
-- teleport.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api
local ID = 'deception'

local runs = {}   -- [pid] = { id, pid, sessionId, eventId, endsAt, doors, resets, maze (settings snapshot) }

local function cfg() return Carnival.Config.get().attractions.deception end

local function liveCount()
    local n = 0
    for _ in pairs(runs) do n = n + 1 end
    return n
end

local function v4(c) return { x = c.x, y = c.y, z = c.z, w = c.w or 0.0 } end

local function doorById(maze, id)
    for _, d in ipairs(maze.doors) do if d.id == id then return d end end
    return nil
end

-- What the player's client needs: positions only, never where a door leads.
local function publicRun(r)
    local m = r.maze
    return {
        runId = r.id, endsAt = r.endsAt, serverTime = os.time(), start = v4(m.start),
        finish = v4(m.finish), finishRadius = m.finishRadius, doorDistance = m.doorDistance,
        trapRadius = m.trapRadius, showTraps = m.showTraps,
        doors = U.map(m.doors, function(d) return { id = d.id, label = d.label, coords = v4(d.coords) } end),
        traps = U.map(m.traps, function(t) return { id = t.id, coords = t.coords } end),
        resets = r.resets, doorsUsed = r.doors,
    }
end

local function runsPlayed(sessionId, pid)
    return Carnival.Db.scalar("SELECT COUNT(*) FROM carnival_deception_runs WHERE session_id = ? AND participant_id = ? AND status = 'ended'", { sessionId, pid }) or 0
end

local function maybeCompleteSession(sessionId)
    local session = Carnival.Rotation.sessionById(sessionId)
    if not session or session.status ~= C.SESSION_STATUS.ACTIVE then return end
    local members = Carnival.Rotation.sessionMembers(session, true)
    if #members == 0 then return end
    for _, p in ipairs(members) do
        if runsPlayed(sessionId, p.id) < 1 then return end
    end
    for _, r in pairs(runs) do if r.sessionId == sessionId then return end end
    Carnival.Rotation.completeSession(sessionId, Carnival.Identity.SYSTEM, 'Every member of the group has been through the hall')
end

-- reason: 'finished' | 'time' | 'session_ended' | 'event_ended'
local function endRun(r, reason)
    if runs[r.pid] ~= r then return nil end
    runs[r.pid] = nil
    local points = 0
    if reason == 'finished' and r.maze.finishPoints > 0 then
        local session = Carnival.Rotation.sessionById(r.sessionId)
        local ok, tx = Carnival.Scoring.award({
            participantId = r.pid, delta = r.maze.finishPoints, key = ('deception:run:%d'):format(r.id), txType = 'award',
            source = 'deception_finish', reason = ('Found the way out (%d doors, %d resets, %ds)'):format(r.doors, r.resets, os.time() - r.startedAt),
            attractionId = ID, sessionId = r.sessionId, roundNumber = session and session.round_number or nil, publicReason = 'Escaped the Hall of Deception',
        })
        if ok then points = tx.delta end
    end
    Carnival.Db.update("UPDATE carnival_deception_runs SET status = 'ended', ended_at = ?, end_reason = ?, doors_used = ?, resets = ?, points = ? WHERE id = ?",
        { os.time(), reason, r.doors, r.resets, points, r.id })
    Carnival.Monitor.log('info', 'attraction', 'deception_run_ended', { participantId = r.pid, attractionId = ID, result = reason,
        details = { runId = r.id, doors = r.doors, resets = r.resets, points = points } })
    Carnival.Push.invalidate('deception')
    local result = { action = 'end', reason = reason, points = points, doors = r.doors, resets = r.resets,
        seconds = os.time() - r.startedAt, exitTo = v4(r.maze.exitTo) }
    if reason ~= 'finished' then
        local src = Carnival.Participants.sourceOf(r.pid)
        if src then Carnival.Push.send(src, 'deception', result) end
    end
    CreateThread(function()
        Carnival.Rotation.memberFinished(r.sessionId, r.pid, reason == 'finished' and 'Found the way out' or 'Lost in the Hall of Deception')
        maybeCompleteSession(r.sessionId)
        local busy = false
        for _, other in pairs(runs) do if other.sessionId == r.sessionId then busy = true end end
        if not busy then Carnival.Rotation.completeIfOvertime(r.sessionId, 'Last player left the hall after the round timer') end
    end)
    return result
end

local function runFor(src, payload)
    local pid = Carnival.Participants.idOfSource(src)
    local r = pid and runs[pid]
    if not r or V.id(payload.runId) ~= r.id then return nil, 'stale', 'You are not in the hall.' end
    if Carnival.Events.state() ~= C.STATES.RUNNING then return nil, 'paused', 'The carnival is paused.' end
    return r
end

---------------------------------------------------------------------------
-- Player actions
---------------------------------------------------------------------------
local function enter(src)
    local p, session, msg = Carnival.Attractions.eligibility(src, ID)
    if not p then return nil, session, msg end
    if Carnival.Events.state() ~= C.STATES.RUNNING then return nil, 'paused', 'The carnival is paused.' end
    local c = cfg()
    return Carnival.withLock('deception:' .. p.id, function()
        local r = runs[p.id]
        if r then return publicRun(r) end -- already inside: send them back to the start
        if runsPlayed(session.id, p.id) > 0 then return nil, 'already_played', 'You have already been through the hall.' end
        if #c.doors == 0 then return nil, 'misconfigured', 'The hall has no doors yet.' end
        if liveCount() >= c.maxPlayers then return nil, 'busy', 'The hall is full. Try again in a moment.' end
        local now = os.time()
        local id = Carnival.Db.insertRow('carnival_deception_runs', {
            event_id = p.event_id, session_id = session.id, participant_id = p.id, status = 'running',
            started_at = now, ends_at = now + c.durationSeconds,
        })
        if not id then return nil, 'database_error', 'The doors are stuck. Try again.' end
        r = { id = id, pid = p.id, eventId = p.event_id, sessionId = session.id, startedAt = now, endsAt = now + c.durationSeconds,
            doors = 0, resets = 0, maze = U.deepCopy(c) }
        runs[p.id] = r
        Carnival.Monitor.log('info', 'attraction', 'deception_run_started', { participantId = p.id, attractionId = ID, details = { runId = id } })
        Carnival.Push.invalidate('deception')
        return publicRun(r)
    end)
end

local function useDoor(src, payload)
    local r, code, msg = runFor(src, payload)
    if not r then return nil, code, msg end
    local door = type(payload.doorId) == 'string' and doorById(r.maze, payload.doorId) or nil
    if not door then return nil, 'invalid', 'There is no door here.' end
    if not Carnival.Identity.within(src, door.coords, r.maze.doorDistance + 2.0) then return nil, 'too_far', 'Get closer to the door.' end
    r.doors = r.doors + 1
    if door.to == 'start' then
        r.resets = r.resets + 1
        return { to = v4(r.maze.start), back = true, resets = r.resets, doorsUsed = r.doors }
    end
    local target = doorById(r.maze, door.to)
    if not target then
        -- a door pointing nowhere (settings changed mid-run): be kind, back to the start
        r.resets = r.resets + 1
        return { to = v4(r.maze.start), back = true, resets = r.resets, doorsUsed = r.doors }
    end
    -- come out a step in front of the other door, facing the way it points
    local h = math.rad(target.coords.w or 0.0)
    local out = { x = target.coords.x - math.sin(h) * 1.2, y = target.coords.y + math.cos(h) * 1.2, z = target.coords.z, w = target.coords.w or 0.0 }
    return { to = out, door = target.label, back = false, resets = r.resets, doorsUsed = r.doors }
end

local function hitTrap(src, payload)
    local r, code, msg = runFor(src, payload)
    if not r then return nil, code, msg end
    local trap
    for _, t in ipairs(r.maze.traps) do if t.id == payload.trapId then trap = t end end
    if not trap then return nil, 'invalid', 'There is no trap here.' end
    if not Carnival.Identity.within(src, trap.coords, r.maze.trapRadius + 2.0) then return nil, 'too_far', 'Nothing happened.' end
    r.resets = r.resets + 1
    return { to = v4(r.maze.start), resets = r.resets }
end

local function finish(src, payload)
    local r, code, msg = runFor(src, payload)
    if not r then return nil, code, msg end
    if not Carnival.Identity.within(src, r.maze.finish, r.maze.finishRadius + 1.5) then return nil, 'too_far', 'This is not the way out.' end
    return endRun(r, 'finished')
end

---------------------------------------------------------------------------
-- Timer and lifecycle
---------------------------------------------------------------------------
Carnival.onTick('deception', function(now)
    if Carnival.Events.state() ~= C.STATES.RUNNING then return end
    for _, r in pairs(runs) do
        if now >= r.endsAt then endRun(r, 'time') end
    end
end)

local function endAll(reason, sessionId)
    for _, r in pairs(runs) do
        if not sessionId or r.sessionId == sessionId then endRun(r, reason) end
    end
end

Carnival.Attractions.register({
    id = ID,
    isBusy = function() return liveCount() > 0 end,
    canJoin = function() return true end,
    onTimerExpired = function(session)
        for _, r in pairs(runs) do if r.sessionId == session.id then return 'hold' end end
        return 'complete'
    end,
    onSessionEnd = function(session) endAll('session_ended', session.id) end,
    onPause = function()
        local now = os.time()
        for _, r in pairs(runs) do r.pausedLeft = math.max(0, r.endsAt - now) end
    end,
    onResume = function()
        local now = os.time()
        for _, r in pairs(runs) do
            if r.pausedLeft then
                r.endsAt = now + r.pausedLeft
                r.pausedLeft = nil
                local src = Carnival.Participants.sourceOf(r.pid)
                if src then Carnival.Push.send(src, 'deception', { action = 'sync', endsAt = r.endsAt, serverTime = now }) end
            end
        end
    end,
    onEventEnd = function()
        endAll('event_ended')
        runs = {}
    end,
    recover = function(e)
        runs = {}
        local n = Carnival.Db.update("UPDATE carnival_deception_runs SET status = 'interrupted', ended_at = ?, end_reason = 'server_restart' WHERE event_id = ? AND status = 'running'", { os.time(), e.id })
        if n and n > 0 then Carnival.Monitor.log('warning', 'recovery', 'deception_run_interrupted', { attractionId = ID, details = { runs = n } }) end
    end,
    onPlayerLoaded = function(src, p)
        local r = runs[p.id]
        if r then Carnival.Push.send(src, 'deception', { action = 'resume', run = publicRun(r) }) end
    end,
    staffSummary = function() return { inside = liveCount() } end,
})

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
Api.register('deception.enter', { rate = 'action', handler = function(ctx) return enter(ctx.source) end })
Api.register('deception.door', { rate = 'action', handler = function(ctx, payload) return useDoor(ctx.source, payload) end })
Api.register('deception.trap', { rate = 'action', handler = function(ctx, payload) return hitTrap(ctx.source, payload) end })
Api.register('deception.finish', { rate = 'action', handler = function(ctx, payload) return finish(ctx.source, payload) end })
Api.register('deception.state', {
    rate = 'participant',
    handler = function(ctx)
        local pid = Carnival.Participants.idOfSource(ctx.source)
        local r = pid and runs[pid]
        if not r then return { active = false } end
        local st = publicRun(r)
        st.active = true
        return st
    end,
})
