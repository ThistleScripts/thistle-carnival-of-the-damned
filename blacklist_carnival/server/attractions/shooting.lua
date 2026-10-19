-- Attraction: The Shooting Gallery (self-service mouse-aim mini-game).
--
-- A player targets the gallery ped and the NUI opens a shooting game: targets
-- slide across lanes and the player aims with the mouse and clicks to shoot.
--
-- The server owns the game:
--   * it generates the target schedule (spawn time, lane, direction, kind) and
--     sends it to the client to render
--   * every click is reported; a hit only counts if that target exists, was on
--     screen at that moment by the SERVER clock (with a latency allowance), has
--     not been hit before, and the click rate is plausible
--   * points, accuracy and the final award are calculated on the server and the
--     award is written once per game
-- Remaining limitation: a modified client could auto-click targets perfectly
-- (an aimbot for a 2D game); scores are still bounded by the schedule and caps.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api
local ID = 'shooting'
local OP = 'attractions.operate.shooting'

local COUNTDOWN_MS = 3000      -- "3, 2, 1" before targets appear
local LATENCY_MS = 1500        -- allowance for a click reaching the server late
local EARLY_MS = 250           -- allowance for clocks drifting the other way

local games = {}   -- [participantId] = game

local function cfg() return Carnival.Config.get().attractions.shooting end
local function nowMs() return GetGameTimer() end

local function gamesPlayed(sessionId, pid)
    return Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_shooting_results WHERE session_id = ? AND participant_id = ?', { sessionId, pid }) or 0
end

local function liveCount()
    local n = 0
    for _, g in pairs(games) do if not g.finished then n = n + 1 end end
    return n
end

-- Elapsed game time by the server clock (negative during the countdown).
local function elapsed(g)
    local now = g.pausedAtMs or nowMs()
    return now - g.startMs - COUNTDOWN_MS
end

local function buildPlan(c)
    local duration = c.durationSeconds * 1000
    local plan, byId = {}, {}
    local span = math.max(1, duration - c.targetLifetimeMs)
    for i = 1, c.targetCount do
        local roll = math.random(100)
        local kind = 'normal'
        if roll <= c.specialChance then
            kind = 'special'
        elseif roll <= c.specialChance + c.decoyChance then
            kind = 'decoy'
        end
        local life = kind == 'special' and math.floor(c.targetLifetimeMs * 0.65) or c.targetLifetimeMs
        local base = math.floor((i - 1) * span / c.targetCount)
        local jitter = math.random(0, math.max(1, math.floor(span / c.targetCount)))
        local t = {
            id = i, t = math.max(0, math.min(base + jitter, duration - life)), life = life, kind = kind,
            lane = math.random(c.lanes), dir = math.random(2) == 1 and 1 or -1,
        }
        plan[#plan + 1] = t
        byId[i] = t
    end
    return plan, byId
end

local function publicGame(g)
    return {
        gameId = g.id, duration = g.duration, lanes = g.lanes, countdownMs = COUNTDOWN_MS,
        elapsedMs = elapsed(g), plan = g.plan, total = g.points, hits = g.hits, shots = g.shots,
        hitIds = U.keys(g.hit), label = cfg().label,
    }
end

---------------------------------------------------------------------------
-- Finishing a game
---------------------------------------------------------------------------
local function maybeCompleteSession(sessionId)
    local session = Carnival.Rotation.sessionById(sessionId)
    if not session or session.status ~= C.SESSION_STATUS.ACTIVE then return end
    local members = Carnival.Participants.members(session.colour, true)
    if #members == 0 then return end
    for _, p in ipairs(members) do
        if gamesPlayed(sessionId, p.id) < 1 then return end
    end
    for _, g in pairs(games) do if g.sessionId == sessionId and not g.finished then return end end
    Carnival.Rotation.completeSession(sessionId, Carnival.Identity.SYSTEM, 'Every member of the group has played')
end

local function finishGame(g, reason)
    if g.finished then return g.result end
    g.finished = true
    local c = cfg()
    local accuracy = g.shots > 0 and (g.hits / g.shots) or 0
    local accBonus = (c.accuracyScoring and g.hits > 0) and math.floor(c.accuracyBonusMax * accuracy) or 0
    local penalty = math.max(0, g.shots - g.hits - g.decoys) * c.missPenalty
    local total = g.points + accBonus - penalty
    Carnival.Db.update("UPDATE carnival_shooting_heats SET status = 'ended', ended_at = ?, end_reason = ? WHERE id = ?", { os.time(), reason, g.id })
    local rid = Carnival.Db.insertRow('carnival_shooting_results', {
        event_id = g.eventId, heat_id = g.id, session_id = g.sessionId, participant_id = g.pid,
        hits = g.hits, shots = g.shots, bullseyes = g.bullseyes, specials = g.specials, target_points = g.points,
        accuracy_bonus = accBonus, miss_penalty = penalty, points = total, rejected_hits = g.rejected, created_at = os.time(),
    })
    local applied = 0
    if rid and total ~= 0 then
        local session = Carnival.Rotation.sessionById(g.sessionId)
        local ok, tx = Carnival.Scoring.award({
            participantId = g.pid, delta = total, key = ('shooting:%d:%d'):format(g.id, g.pid), txType = total > 0 and 'award' or 'penalty',
            source = 'shooting_game', reason = ('%d hits / %d shots, %d bullseyes, %d golden, %d lanterns'):format(g.hits, g.shots, g.bullseyes, g.specials, g.decoys),
            attractionId = ID, sessionId = g.sessionId, roundNumber = session and session.round_number or nil, publicReason = 'Shooting Gallery',
        })
        if ok then applied = tx.delta end
    end
    g.result = {
        gameId = g.id, points = applied, targetPoints = g.points, hits = g.hits, shots = g.shots, bullseyes = g.bullseyes,
        specials = g.specials, decoys = g.decoys, accuracy = math.floor(accuracy * 100), accuracyBonus = accBonus, penalty = penalty,
    }
    Carnival.Monitor.log('info', 'attraction', 'shooting_game_finished', { participantId = g.pid, attractionId = ID, result = reason, details = g.result })
    if games[g.pid] == g then games[g.pid] = nil end
    Carnival.Push.invalidate('shooting')
    local src = Carnival.Participants.sourceOf(g.pid)
    if src then Carnival.Push.send(src, 'shooting', { action = 'result', result = g.result }) end
    CreateThread(function()
        maybeCompleteSession(g.sessionId)
        local busy = false
        for _, other in pairs(games) do if other.sessionId == g.sessionId and not other.finished then busy = true end end
        if not busy then Carnival.Rotation.completeIfOvertime(g.sessionId, 'Last game finished after the round timer') end
    end)
    return g.result
end

---------------------------------------------------------------------------
-- Player actions
---------------------------------------------------------------------------
local function start(src)
    local p, session, msg = Carnival.Attractions.eligibility(src, ID)
    if not p then return nil, session, msg end
    if Carnival.Events.state() ~= C.STATES.RUNNING then return nil, 'paused', 'The carnival is paused.' end
    local c = cfg()
    return Carnival.withLock('shooting:' .. p.id, function()
        local g = games[p.id]
        if g and not g.finished then return publicGame(g) end -- resume after closing the screen
        if gamesPlayed(session.id, p.id) >= c.playsPerVisit then
            return nil, 'already_shot', 'You have already had your turn at the gallery.'
        end
        if liveCount() >= c.maxPlayers then return nil, 'busy', 'Every stall is taken. Try again in a moment.' end
        local id = Carnival.Db.insertRow('carnival_shooting_heats', {
            event_id = p.event_id, session_id = session.id, status = 'running', duration_seconds = c.durationSeconds,
            started_by = Carnival.Identity.license(src), started_at = os.time(),
        })
        if not id then return nil, 'database_error', 'The gallery is jammed. Try again.' end
        local plan, byId = buildPlan(c)
        g = {
            id = id, pid = p.id, eventId = p.event_id, sessionId = session.id, startMs = nowMs(), duration = c.durationSeconds * 1000,
            lanes = c.lanes, plan = plan, byId = byId, hit = {}, shots = 0, hits = 0, bullseyes = 0, specials = 0, decoys = 0,
            points = 0, rejected = 0, lastShotMs = nil,
        }
        games[p.id] = g
        Carnival.Monitor.log('info', 'attraction', 'shooting_game_started', { participantId = p.id, attractionId = ID, details = { gameId = id, targets = #plan } })
        Carnival.Push.invalidate('shooting')
        return publicGame(g)
    end)
end

local function reject(g, pid, why)
    g.rejected = g.rejected + 1
    local sev = (why == 'already_hit' or why == 'off_screen') and 'debug' or 'warning'
    Carnival.Monitor.log(sev, sev == 'warning' and 'security' or 'attraction', 'shooting_shot_rejected', { participantId = pid, attractionId = ID, result = why })
    return nil, why
end

local function shot(src, payload)
    local pid = Carnival.Participants.idOfSource(src)
    local g = pid and games[pid]
    if not g or g.finished or V.id(payload.gameId) ~= g.id then return nil, 'stale', 'That game has ended.' end
    if Carnival.Events.state() ~= C.STATES.RUNNING then return nil, 'paused', 'The carnival is paused.' end
    local c = cfg()
    local at = elapsed(g)
    if at < -EARLY_MS then return reject(g, pid, 'before_start') end
    if at > g.duration + LATENCY_MS then return nil, 'time_up', 'Time is up.' end
    local ms = nowMs()
    if g.lastShotMs and ms - g.lastShotMs < c.minClickIntervalMs then return reject(g, pid, 'too_fast') end
    g.lastShotMs = ms
    if g.shots >= c.targetCount * 4 then return reject(g, pid, 'shot_cap') end
    g.shots = g.shots + 1

    local tid = payload.targetId ~= nil and V.int(payload.targetId, 1, c.targetCount) or nil
    if not tid then return { hit = false, total = g.points, shots = g.shots, hits = g.hits } end -- a miss
    local t = g.byId[tid]
    if not t then return reject(g, pid, 'unknown_target') end
    if g.hit[tid] then return reject(g, pid, 'already_hit') end
    if at < t.t - EARLY_MS or at > t.t + t.life + LATENCY_MS then return reject(g, pid, 'off_screen') end
    g.hit[tid] = true
    local points
    if t.kind == 'decoy' then
        points = -c.decoyPenalty
        g.decoys = g.decoys + 1
    elseif t.kind == 'special' then
        points = c.specialPoints
        g.specials = g.specials + 1
        g.hits = g.hits + 1
    else
        local bull = payload.ring == 'inner'
        points = c.targetPoints + (bull and c.bullseyeBonus or 0)
        if bull then g.bullseyes = g.bullseyes + 1 end
        g.hits = g.hits + 1
    end
    g.points = g.points + points
    return { hit = true, targetId = tid, kind = t.kind, points = points, total = g.points, shots = g.shots, hits = g.hits }
end

---------------------------------------------------------------------------
-- Ticker & lifecycle
---------------------------------------------------------------------------
Carnival.onTick('shooting', function()
    if Carnival.Events.state() ~= C.STATES.RUNNING then return end
    for _, g in pairs(games) do
        if not g.finished and elapsed(g) > g.duration + LATENCY_MS then finishGame(g, 'time') end
    end
end)

local function finishAll(reason, sessionId)
    for _, g in pairs(games) do
        if not g.finished and (not sessionId or g.sessionId == sessionId) then finishGame(g, reason) end
    end
end

Carnival.Attractions.register({
    id = ID,
    isBusy = function() return liveCount() > 0 end,
    onTimerExpired = function(session)
        -- games in progress finish first; the last one completes the visit
        for _, g in pairs(games) do if g.sessionId == session.id and not g.finished then return 'hold' end end
        return 'complete'
    end,
    onSessionEnd = function(session) finishAll('session_ended', session.id) end,
    onPause = function()
        for _, g in pairs(games) do g.pausedAtMs = nowMs() end
    end,
    onResume = function()
        for _, g in pairs(games) do
            if g.pausedAtMs then
                g.startMs = g.startMs + (nowMs() - g.pausedAtMs)
                g.pausedAtMs = nil
            end
            local src = Carnival.Participants.sourceOf(g.pid)
            if src then Carnival.Push.send(src, 'shooting', { action = 'sync', elapsedMs = elapsed(g) }) end
        end
    end,
    onEventEnd = function()
        finishAll('event_ended')
        games = {}
    end,
    recover = function(e)
        games = {}
        local n = Carnival.Db.update("UPDATE carnival_shooting_heats SET status = 'interrupted', ended_at = ?, end_reason = 'server_restart' WHERE event_id = ? AND status = 'running'", { os.time(), e.id })
        if n and n > 0 then Carnival.Monitor.log('warning', 'recovery', 'shooting_game_interrupted', { attractionId = ID, details = { games = n } }) end
    end,
    staffSummary = function() return { playing = liveCount() } end,
})

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
Api.register('shooting.start', { rate = 'action', handler = function(ctx) return start(ctx.source) end })
Api.register('shooting.shot', { rate = 'shooting', handler = function(ctx, payload) return shot(ctx.source, payload) end })
Api.register('shooting.finish', {
    rate = 'action',
    handler = function(ctx, payload)
        local pid = Carnival.Participants.idOfSource(ctx.source)
        local g = pid and games[pid]
        if not g or V.id(payload.gameId) ~= g.id then return nil, 'stale', 'That game has ended.' end
        -- the client may only finish once the server clock agrees the time is up
        if elapsed(g) < g.duration then return nil, 'too_early', 'The game is still running.' end
        return finishGame(g, 'time')
    end,
})

Api.register('shooting.staff.state', {
    perm = OP, rate = 'staff',
    handler = function()
        local session = Carnival.Rotation.sessionFor(ID)
        local live = {}
        for _, g in pairs(games) do
            local p = Carnival.Participants.get(g.pid)
            live[#live + 1] = { id = g.pid, name = p and p.display_name or '?', points = g.points, hits = g.hits, shots = g.shots,
                rejected = g.rejected, remaining = math.max(0, math.floor((g.duration - elapsed(g)) / 1000)) }
        end
        local members = {}
        if session then
            for _, p in ipairs(Carnival.Participants.members(session.colour, false)) do
                members[#members + 1] = { id = p.id, name = p.display_name, online = Carnival.Participants.sourceOf(p.id) ~= nil,
                    played = gamesPlayed(session.id, p.id), points = Carnival.Scoring.attractionPoints(p.id, ID) }
            end
        end
        local recent = Carnival.Events.activeId() and (Carnival.Db.query([[SELECT r.*, p.display_name FROM carnival_shooting_results r JOIN carnival_participants p ON p.id = r.participant_id
            WHERE r.event_id = ? ORDER BY r.id DESC LIMIT 30]], { Carnival.Events.activeId() }) or {}) or {}
        return { session = session, live = live, members = members, recent = recent, playsPerVisit = cfg().playsPerVisit }
    end,
})

-- Staff can give a player another go (e.g. after a disconnect); audited.
Api.register('shooting.allowReplay', {
    perm = OP, rate = 'staff',
    handler = function(ctx, payload)
        local pid = V.id(payload.participantId)
        if not pid then return nil, 'invalid', 'Choose a participant.' end
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        local session = Carnival.Rotation.sessionFor(ID)
        if not session then return nil, 'no_session', 'No group is at the gallery.' end
        local n = Carnival.Db.update('UPDATE carnival_shooting_results SET session_id = NULL WHERE session_id = ? AND participant_id = ?', { session.id, pid })
        Carnival.Audit.record(ctx.actor, 'shooting_replay_allowed', { targetType = 'participant', targetId = pid, reason = reason, details = { cleared = n } })
        Carnival.Push.invalidate('shooting')
        return { cleared = n }
    end,
})
