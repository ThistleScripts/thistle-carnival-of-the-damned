-- Attraction: The House of Horrors.
-- A timed maze run with server-tracked bronze/silver/gold tokens. The timer,
-- warnings, token state, collection, boundary checks, escape and scoring all run
-- on the server. Clients only render tokens, play sounds and request actions.
-- A player at the entrance opens the doors; the run starts by itself after a
-- short gathering countdown. Inventory possession of a keepsake token never
-- grants points.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api
local ID = 'horror'

local run = nil
local lobby = nil   -- self-service: { sessionId, at } before the doors open

local function cfg() return Carnival.Config.get().attractions.horror end

local function runnerSources()
    local out = {}
    if not run then return out end
    for pid in pairs(run.runners) do
        local s = Carnival.Participants.sourceOf(pid)
        if s then out[#out + 1] = s end
    end
    return out
end

local function tokenVisibleTo(t, pid)
    if t.respawnAt then return false end
    if run.settings.collectionRule == 'once_global' then return t.collectedBy.global == nil end
    return not t.collectedBy[pid]
end

local function tokensFor(pid)
    local out = {}
    for _, t in pairs(run.tokens) do
        if tokenVisibleTo(t, pid) then
            out[#out + 1] = { id = t.id, type = t.type, coords = t.coords }
        end
    end
    return out
end

local function remaining(now)
    if not run then return 0 end
    if run.status == 'paused' or Carnival.Events.state() == C.STATES.PAUSED then
        return run.pausedRemaining or math.max(0, run.endsAt - (now or os.time()))
    end
    return math.max(0, run.endsAt - (now or os.time()))
end

local function stateFor(pid)
    local r = run.runners[pid]
    return {
        action = 'state', runId = run.id, status = run.status, endsAt = run.endsAt, remaining = remaining(), serverTime = os.time(),
        tokens = tokensFor(pid), runner = r and { status = r.status, collected = r.collected, points = r.points } or nil,
        exit = run.settings.exit, exitRadius = run.settings.exitRadius,
        boundary = { centre = run.settings.boundaryCentre, radius = run.settings.boundaryRadius },
        sounds = { ambient = run.settings.ambientSound, volume = run.settings.volume },
        visibility = run.settings.visibility, visibilityDistance = run.settings.visibilityDistance,
        tokenTypes = run.settings.tokenTypes,
    }
end

local function pushRunners(data)
    for _, s in ipairs(runnerSources()) do Carnival.Push.send(s, 'horror', data) end
end

local function pushStateAll()
    for pid in pairs(run.runners) do
        local s = Carnival.Participants.sourceOf(pid)
        if s then Carnival.Push.send(s, 'horror', stateFor(pid)) end
    end
end

local function persistRun(set)
    Carnival.Db.updateRow('carnival_horror_runs', set, 'id = ?', { run.id })
end

local function award(pid, delta, keySuffix, txType, source, reason, publicReason)
    local session = Carnival.Rotation.sessionById(run.sessionId)
    return Carnival.Scoring.award({
        participantId = pid, delta = delta, key = ('horror:%d:%s'):format(run.id, keySuffix), txType = txType,
        source = source, reason = reason, attractionId = ID, sessionId = run.sessionId,
        roundNumber = session and session.round_number or nil, publicReason = publicReason,
    })
end

---------------------------------------------------------------------------
-- Run lifecycle
---------------------------------------------------------------------------
local function startRun(actor)
    local session = Carnival.Rotation.activeSessionFor(ID)
    if not session then return nil, 'no_session', 'No group is scheduled at the House of Horrors.' end
    if run and (run.status == 'running' or run.status == 'paused') then return nil, 'invalid', 'A run is already in progress.' end
    local e = Carnival.Events.active
    if not e or e.state ~= C.STATES.RUNNING then return nil, 'not_live', 'The event must be running to start a run.' end
    local c = U.deepCopy(cfg())
    local members = Carnival.Rotation.sessionMembers(session, false)
    if #members == 0 then return nil, 'invalid', 'This group has no active participants.' end

    local now = os.time()
    local runId = Carnival.Db.insertRow('carnival_horror_runs', {
        event_id = e.id, session_id = session.id, status = 'running', duration_seconds = c.durationSeconds,
        settings_snapshot = json.encode(c), started_by = actor.license, started_at = now, ends_at = now + c.durationSeconds,
    })
    if not runId then return nil, 'database_error' end
    run = { id = runId, sessionId = session.id, colour = session.colour, status = 'running', startedAt = now, endsAt = now + c.durationSeconds,
        settings = c, tokens = {}, runners = {}, warningsSent = {}, lastBoundaryCheck = 0 }

    -- choose token positions per type
    local byType = {}
    for _, t in ipairs(c.tokens) do
        byType[t.type] = byType[t.type] or {}
        table.insert(byType[t.type], t)
    end
    for _, ttype in ipairs(C.TOKEN_TYPES) do
        local list = byType[ttype] or {}
        for i = #list, 2, -1 do local j = math.random(i) list[i], list[j] = list[j], list[i] end
        local qty = c.tokenTypes[ttype].quantity
        local n = (qty == 0 or qty > #list) and #list or qty
        for i = 1, n do
            local t = list[i]
            local points = c.tokenTypes[ttype].points
            local tid = Carnival.Db.insertRow('carnival_horror_tokens', { run_id = runId, token_key = t.id, token_type = ttype, x = t.coords.x, y = t.coords.y, z = t.coords.z, points = points })
            if tid then
                run.tokens[tid] = { id = tid, key = t.id, type = ttype, coords = t.coords, points = points, collectedBy = {} }
            end
        end
    end
    for _, p in ipairs(members) do
        Carnival.Db.insertRow('carnival_horror_runners', { run_id = runId, participant_id = p.id, status = 'inside' })
        run.runners[p.id] = { status = 'inside', collected = 0, points = 0 }
    end
    Carnival.Audit.record(actor, 'horror_run_started', { targetType = 'horror_run', targetId = runId, details = { colour = session.colour, runners = #members, tokens = U.count(run.tokens), duration = c.durationSeconds } })
    Carnival.Monitor.log('info', 'countdown', 'horror_run_started', { attractionId = ID, actor = actor, details = { runId = runId, duration = c.durationSeconds } })
    pushStateAll()
    pushRunners({ action = 'audio', sound = c.ambientSound, volume = c.volume, loop = true })
    Carnival.Push.invalidate('horror')
    return { runId = runId }
end

local function endRun(reason, actor)
    if not run or (run.status ~= 'running' and run.status ~= 'paused') then return nil, 'invalid', 'No run in progress.' end
    local now = os.time()
    run.status = 'ended'
    -- Tell the players first: whatever happens below, nobody is left staring at
    -- a finished countdown.
    local trapped = {}
    for pid, r in pairs(run.runners) do
        if r.status == 'inside' then
            r.status = 'trapped'
            trapped[#trapped + 1] = pid
        end
    end
    pushRunners({ action = 'audio_stop', sound = run.settings.ambientSound })
    pushRunners({ action = 'end', reason = reason, sound = run.settings.endSound, volume = run.settings.volume })
    for pid, r in pairs(run.runners) do
        local s = Carnival.Participants.sourceOf(pid)
        if s then Carnival.Push.send(s, 'horror', { action = 'result', status = r.status, collected = r.collected, points = r.points }) end
    end
    local ok, err = pcall(function()
        persistRun({ status = 'ended', ended_at = now, end_reason = reason, paused_remaining = Carnival.Db.NULL })
        local penalty = run.settings.penalties.notEscaped
        for _, pid in ipairs(trapped) do
            Carnival.Db.update("UPDATE carnival_horror_runners SET status = 'trapped' WHERE run_id = ? AND participant_id = ?", { run.id, pid })
            if reason == 'expired' and penalty > 0 then
                award(pid, -penalty, pid .. ':not_escaped', 'penalty', 'horror_not_escaped', 'Did not escape the House of Horrors', 'Trapped inside!')
            end
        end
    end)
    if not ok then Carnival.Monitor.log('error', 'attraction', 'horror_end_failed', { attractionId = ID, details = { runId = run.id, error = tostring(err) } }) end
    Carnival.Monitor.log('info', 'countdown', 'horror_run_ended', { attractionId = ID, actor = actor, result = reason, details = { runId = run.id } })
    if actor then Carnival.Audit.record(actor, 'horror_run_ended', { targetType = 'horror_run', targetId = run.id, reason = reason }) end
    Carnival.Push.invalidate('horror')
    if (run.settings.autoCompleteSession or Carnival.Rotation.isWalkup()) and (reason == 'expired' or reason == 'all_escaped' or reason == 'stopped') then
        local session = Carnival.Rotation.sessionById(run.sessionId)
        if session and session.status == C.SESSION_STATUS.ACTIVE then
            Carnival.Rotation.completeSession(session.id, actor or Carnival.Identity.SYSTEM, 'House of Horrors run ' .. reason)
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Participant actions
---------------------------------------------------------------------------
local function runnerCheck(src, payload)
    if not run or V.id(payload.runId) ~= run.id then return nil, 'stale', 'That run is over.' end
    if run.status ~= 'running' or Carnival.Events.state() ~= C.STATES.RUNNING then return nil, 'paused', 'The run is paused.' end
    local p, session, msg = Carnival.Attractions.eligibility(src, ID, { skipDistance = true })
    if not p then return nil, session, msg end
    local r = run.runners[p.id]
    if not r then return nil, 'not_runner', 'You are not part of this run.' end
    if r.status ~= 'inside' then return nil, 'escaped', 'You have already left the maze.' end
    return p, r
end

local function collect(src, payload)
    local p, r, msg = runnerCheck(src, payload)
    if not p then return nil, r, msg end
    local tid = V.id(payload.tokenId)
    local t = tid and run.tokens[tid]
    if not t then
        Carnival.Monitor.security(src, 'horror_invalid_token', { tokenId = tostring(payload.tokenId):sub(1, 16) }, 'token')
        return nil, 'invalid', 'There is nothing here.'
    end
    local typeCfg = run.settings.tokenTypes[t.type]
    local near, d = Carnival.Identity.within(src, t.coords, typeCfg.distance + 1.5)
    if not near then
        Carnival.Monitor.log('warning', 'security', 'horror_collect_out_of_range', { participantId = p.id, attractionId = ID, details = { distance = d and U.round(d, 1), token = t.key } })
        return nil, 'too_far', 'Get closer.'
    end
    local inside = Carnival.Identity.within(src, run.settings.boundaryCentre, run.settings.boundaryRadius + 2)
    if not inside then return nil, 'outside', 'You are outside the maze.' end

    return Carnival.withLock('horror:token:' .. tid, function()
        local global = run.settings.collectionRule == 'once_global'
        if t.respawnAt or (global and t.collectedBy.global) or t.collectedBy[p.id] then
            Carnival.Monitor.log('info', 'duplicate', 'horror_token_already_collected', { participantId = p.id, attractionId = ID, details = { token = t.key } })
            return nil, 'collected', 'Someone got here first.'
        end
        local cid = Carnival.Db.insertRow('carnival_horror_collections', {
            run_id = run.id, token_id = tid, participant_id = p.id, token_type = t.type, points = t.points, created_at = os.time(),
        })
        if not cid then return nil, 'collected', 'Already collected.' end
        t.collectedBy[p.id] = true
        if global then
            t.collectedBy.global = p.id
            if (typeCfg.respawnSeconds or 0) > 0 then t.respawnAt = os.time() + typeCfg.respawnSeconds end
        end
        local ok, tx = award(p.id, t.points, ('%d:%d'):format(tid, p.id), 'award', 'horror_token_' .. t.type,
            ('%s token %s'):format(t.type, t.key), ('%s token'):format(t.type:gsub('^%l', string.upper)))
        local applied = ok and tx.delta or 0
        r.collected = r.collected + 1
        r.points = r.points + applied
        if run.settings.physicalTokens then
            local rw = Carnival.Rewards.create({ participantId = p.id, source = 'horror_keepsake', item = C.TOKEN_ITEMS[t.type], count = 1,
                key = ('horror:keepsake:%d:%d:%d'):format(run.id, tid, p.id), metadata = { description = 'Found in the House of Horrors. Keepsake only.' } })
            if rw and rw.status == 'pending' then Carnival.Rewards.deliver(rw.id, Carnival.Identity.SYSTEM) end
        end
        Carnival.Monitor.log('info', 'token', 'horror_token_collected', { participantId = p.id, attractionId = ID, details = { token = t.key, type = t.type, points = applied } })
        if global then pushRunners({ action = 'token_removed', tokenId = tid }) end
        Carnival.Push.invalidate('horror')
        return { tokenId = tid, type = t.type, points = applied, collected = r.collected }
    end)
end

local function escape(src, payload)
    local p, r, msg = runnerCheck(src, payload)
    if not p then return nil, r, msg end
    local near = Carnival.Identity.within(src, run.settings.exit, run.settings.exitRadius + 1.5)
    if not near then return nil, 'too_far', 'This is not the way out.' end
    return Carnival.withLock('horror:runner:' .. p.id, function()
        if r.status ~= 'inside' then return nil, 'escaped', 'You already escaped.' end
        local left = remaining()
        r.status = 'escaped'
        Carnival.Db.update("UPDATE carnival_horror_runners SET status = 'escaped', exited_at = ?, seconds_remaining = ? WHERE run_id = ? AND participant_id = ?",
            { os.time(), left, run.id, p.id })
        local total = 0
        local bonus = run.settings.completionBonus
        if bonus > 0 then
            local ok, tx = award(p.id, bonus, p.id .. ':complete', 'bonus', 'horror_escape', 'Escaped the House of Horrors', 'Escaped!')
            if ok then total = total + tx.delta end
        end
        local tb = run.settings.timeBonus
        if tb.enabled and tb.pointsPerTenSeconds > 0 then
            local tbonus = math.min(tb.max, (left // 10) * tb.pointsPerTenSeconds)
            if tbonus > 0 then
                local ok, tx = award(p.id, tbonus, p.id .. ':time', 'bonus', 'horror_time_bonus', ('Escaped with %ds remaining'):format(left), 'Time bonus')
                if ok then total = total + tx.delta end
            end
        end
        r.points = r.points + total
        Carnival.Monitor.log('info', 'attraction', 'horror_escaped', { participantId = p.id, attractionId = ID, details = { remaining = left, bonus = total } })
        Carnival.Push.send(src, 'horror', { action = 'audio_stop', sound = run.settings.ambientSound })
        Carnival.Push.invalidate('horror')
        local allOut = true
        for _, rr in pairs(run.runners) do if rr.status == 'inside' then allOut = false end end
        if allOut then CreateThread(function() endRun('all_escaped', nil) end) end
        return { escaped = true, bonus = total, remaining = left, collected = r.collected, points = r.points }
    end)
end

-- Escape hatch: the player gives up, is taken back to the return point and
-- forfeits a share of the points they won in this run.
local function bailOut(src, payload)
    local p, r, msg = runnerCheck(src, payload)
    if not p then return nil, r, msg end
    local eh = run.settings.escapeHatches
    if not eh or not eh.enabled then return nil, 'disabled', 'The escape hatches are sealed.' end
    local hatch
    for _, hp in ipairs(eh.points or {}) do
        if hp.id == payload.hatchId then hatch = hp end
    end
    if not hatch then return nil, 'invalid', 'There is no hatch here.' end
    if not Carnival.Identity.within(src, hatch.coords, eh.radius + 1.5) then return nil, 'too_far', 'Get closer to the hatch.' end
    return Carnival.withLock('horror:runner:' .. p.id, function()
        if r.status ~= 'inside' then return nil, 'escaped', 'You already left the maze.' end
        r.status = 'bailed'
        Carnival.Db.update("UPDATE carnival_horror_runners SET status = 'bailed', exited_at = ?, seconds_remaining = ? WHERE run_id = ? AND participant_id = ?",
            { os.time(), remaining(), run.id, p.id })
        local forfeit = math.floor(math.max(0, r.points) * eh.forfeitPercent / 100 + 0.5)
        local lost = 0
        if forfeit > 0 then
            local ok, tx = award(p.id, -forfeit, p.id .. ':bailout', 'penalty', 'horror_bailout',
                ('Used escape hatch %s (%d%% of %d run points)'):format(hatch.id, eh.forfeitPercent, r.points), 'Escape hatch')
            if ok then lost = -tx.delta end
        end
        r.points = r.points - lost
        Carnival.Monitor.log('info', 'attraction', 'horror_bailout', { participantId = p.id, attractionId = ID, details = { hatch = hatch.id, lost = lost } })
        Carnival.Push.send(src, 'horror', { action = 'audio_stop', sound = run.settings.ambientSound })
        Carnival.Push.invalidate('horror')
        local allOut = true
        for _, rr in pairs(run.runners) do if rr.status == 'inside' then allOut = false end end
        if allOut then CreateThread(function() endRun('all_escaped', nil) end) end
        return { bailed = true, lost = lost, points = r.points, collected = r.collected, returnTo = eh.returnTo }
    end)
end

---------------------------------------------------------------------------
-- Ticker: timer, warnings, respawns, boundary
---------------------------------------------------------------------------
Carnival.onTick('horror', function(now)
    if lobby and now >= lobby.at and Carnival.Events.state() == C.STATES.RUNNING then
        local l = lobby
        lobby = nil
        local session = Carnival.Rotation.activeSessionFor(ID)
        if session and session.id == l.sessionId then
            local ok, code, msg = startRun(Carnival.Identity.SYSTEM)
            if not ok then Carnival.Monitor.log('warning', 'attraction', 'horror_autostart_failed', { attractionId = ID, details = { code = code, message = msg } }) end
        end
    end
    if not run or run.status ~= 'running' or Carnival.Events.state() ~= C.STATES.RUNNING then return end
    local left = run.endsAt - now
    if left <= 0 then return endRun('expired', nil) end
    local warnings = U.deepCopy(run.settings.warnings)
    table.sort(warnings, function(a, b) return a > b end)
    for _, w in ipairs(warnings) do
        if left <= w and left > 0 and not run.warningsSent[w] then
            run.warningsSent[w] = true
            local sound = w <= 10 and run.settings.finalWarningSound or run.settings.warningSound
            pushRunners({ action = 'warning', remaining = left, sound = sound, volume = run.settings.volume })
            Carnival.Monitor.log('debug', 'countdown', 'horror_warning', { attractionId = ID, details = { remaining = left } })
        end
    end
    for _, t in pairs(run.tokens) do
        if t.respawnAt and now >= t.respawnAt then
            t.respawnAt = nil
            t.collectedBy.global = nil
            for pid in pairs(run.runners) do
                local s = Carnival.Participants.sourceOf(pid)
                if s and not t.collectedBy[pid] then Carnival.Push.send(s, 'horror', { action = 'token_added', token = { id = t.id, type = t.type, coords = t.coords } }) end
            end
        end
    end
    if now - run.lastBoundaryCheck >= 2 then
        run.lastBoundaryCheck = now
        local penalty = run.settings.penalties.leftBoundary
        for pid, r in pairs(run.runners) do
            local s = Carnival.Participants.sourceOf(pid)
            if s and r.status == 'inside' then
                local inside = Carnival.Identity.within(s, run.settings.boundaryCentre, run.settings.boundaryRadius)
                if not inside then
                    if not r.outsideSince then
                        r.outsideSince = now
                        Carnival.Push.send(s, 'horror', { action = 'boundary_warning' })
                    elseif now - r.outsideSince >= 10 and penalty > 0 and not r.boundaryPenalised then
                        r.boundaryPenalised = true
                        Carnival.Db.update('UPDATE carnival_horror_runners SET boundary_penalised = 1 WHERE run_id = ? AND participant_id = ?', { run.id, pid })
                        award(pid, -penalty, pid .. ':boundary', 'penalty', 'horror_left_boundary', 'Left the maze during a run', 'Left the maze!')
                    end
                else
                    r.outsideSince = nil
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Lifecycle hooks
---------------------------------------------------------------------------
Carnival.Attractions.register({
    id = ID,
    isBusy = function() return run ~= nil and (run.status == 'running' or run.status == 'paused') end,
    -- walk-up: players may join while the doors are still open (the lobby)
    canJoin = function(session)
        return not (run and run.sessionId == session.id and (run.status == 'running' or run.status == 'paused'))
    end,
    onTimerExpired = function()
        -- An unfinished run keeps its own timer; the group is completed when it ends.
        if run and (run.status == 'running' or run.status == 'paused') then return 'hold' end
        return 'complete'
    end,
    onSessionStart = function()
        if run and run.status ~= 'running' and run.status ~= 'paused' then run = nil end
    end,
    onSessionEnd = function(session)
        if lobby and lobby.sessionId == session.id then lobby = nil end
        if run and run.sessionId == session.id and (run.status == 'running' or run.status == 'paused') then
            endRun('session_ended', nil)
        end
    end,
    onPause = function()
        if run and run.status == 'running' then
            run.pausedRemaining = math.max(0, run.endsAt - os.time())
            persistRun({ paused_remaining = run.pausedRemaining })
            pushRunners({ action = 'paused', remaining = run.pausedRemaining })
        end
    end,
    onResume = function()
        if run and run.status == 'running' and run.pausedRemaining then
            run.endsAt = os.time() + run.pausedRemaining
            run.pausedRemaining = nil
            persistRun({ ends_at = run.endsAt, paused_remaining = Carnival.Db.NULL })
            pushStateAll()
        end
    end,
    onEventEnd = function()
        lobby = nil
        if run and (run.status == 'running' or run.status == 'paused') then endRun('event_ended', nil) end
        run = nil
    end,
    recover = function(e)
        run = nil
        -- Never restart a countdown automatically after a restart.
        local n = Carnival.Db.update("UPDATE carnival_horror_runs SET status = 'interrupted', ended_at = ?, end_reason = 'server_restart' WHERE event_id = ? AND status IN ('running', 'paused')", { os.time(), e.id })
        if n and n > 0 then
            Carnival.Monitor.log('warning', 'recovery', 'horror_run_interrupted', { attractionId = ID, details = { runs = n } })
        end
    end,
    onPlayerLoaded = function(src, p)
        if run and run.runners[p.id] and (run.status == 'running' or run.status == 'paused') then
            Carnival.Push.send(src, 'horror', stateFor(p.id))
            if run.runners[p.id].status == 'inside' then
                Carnival.Push.send(src, 'horror', { action = 'audio', sound = run.settings.ambientSound, volume = run.settings.volume, loop = true })
            end
        end
    end,
    staffSummary = function()
        if not run then return nil end
        local inside, escaped = 0, 0
        for _, r in pairs(run.runners) do
            if r.status == 'inside' then inside = inside + 1 elseif r.status == 'escaped' then escaped = escaped + 1 end
        end
        return { status = run.status, remaining = remaining(), inside = inside, escaped = escaped }
    end,
})

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
Api.register('horror.collect', { rate = 'action', handler = function(ctx, payload) return collect(ctx.source, payload) end })
Api.register('horror.exit', { rate = 'action', handler = function(ctx, payload) return escape(ctx.source, payload) end })
Api.register('horror.bailout', { rate = 'action', handler = function(ctx, payload) return bailOut(ctx.source, payload) end })
Api.register('horror.state', {
    rate = 'participant',
    handler = function(ctx)
        local p = Carnival.Participants.getBySource(ctx.source)
        if not p or not run or not run.runners[p.id] then return { active = false } end
        local st = stateFor(p.id)
        st.active = true
        return st
    end,
})

-- A player at the entrance opens the doors for everyone gathered after a short
-- countdown. One run per visit.
Api.register('horror.enter', {
    rate = 'action',
    handler = function(ctx)
        local c = cfg()
        local p, session, msg = Carnival.Attractions.eligibility(ctx.source, ID, { point = c.entry, distance = c.validationDistance })
        if not p then return nil, session, msg end
        if run and run.sessionId == session.id and (run.status == 'running' or run.status == 'paused') then
            if run.runners[p.id] then Carnival.Push.send(ctx.source, 'horror', stateFor(p.id)) end
            return { running = true, runId = run.id }
        end
        local done = Carnival.Db.scalar("SELECT COUNT(*) FROM carnival_horror_runs WHERE session_id = ? AND status = 'ended'", { session.id }) or 0
        if done > 0 then return nil, 'done', 'Your group has already braved the House of Horrors.' end
        if Carnival.Events.state() ~= C.STATES.RUNNING then return nil, 'paused', 'The carnival is paused.' end
        if not lobby or lobby.sessionId ~= session.id then
            lobby = { sessionId = session.id, at = os.time() + c.lobbySeconds }
            Carnival.Rotation.pushSession(session, 'notify', {
                title = 'House of Horrors',
                description = ('%s is opening the doors! The run starts in %ds - gather at the entrance.'):format(p.display_name, c.lobbySeconds),
                type = 'warning', sound = c.warningSound,
            })
            Carnival.Monitor.log('info', 'attraction', 'horror_lobby_opened', { attractionId = ID, participantId = p.id })
        end
        return { startsIn = math.max(0, lobby.at - os.time()) }
    end,
})
