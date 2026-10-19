-- Attraction: The Puppet Master's Theatre (staff-led improvisation).
-- The Puppet Master builds a performance (scenario + performers + roles), shows
-- the cards, runs the timer and judges. Awards are individual, previewed before
-- commit, and committed exactly once per performance (guarded status change +
-- per-performer idempotency keys).

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api
local ID = 'puppets'

local current = nil   -- active performance (not committed / cancelled)

local function cfg() return Carnival.Config.get().attractions.puppets end

local function scenarioById(id)
    for _, s in ipairs(cfg().scenarios) do if s.id == id then return s end end
    return nil
end

local function persist(perf, set)
    Carnival.Db.updateRow('carnival_theatre_performances', set, 'id = ?', { perf.id })
    for k, v in pairs(set) do perf[k] = v ~= Carnival.Db.NULL and v or nil end
end

local function performerIds(perf)
    return U.map(perf.performers, function(x) return x.participantId end)
end

local function audienceSources(perf)
    local out = {}
    local session = Carnival.Rotation.sessionById(perf.session_id)
    if session then
        for _, p in ipairs(Carnival.Participants.members(session.colour, true)) do
            out[#out + 1] = Carnival.Participants.sourceOf(p.id)
        end
    end
    return out
end

local function cardFor(perf, pid)
    local role
    for _, x in ipairs(perf.performers) do if x.participantId == pid then role = x.role end end
    return {
        action = 'card', performanceId = perf.id, status = perf.status,
        scenario = { title = perf.scenario.title, description = perf.scenario.description, difficulty = perf.scenario.difficulty, category = perf.scenario.category },
        role = role, performer = role ~= nil,
        performers = U.map(perf.performers, function(x)
            local p = Carnival.Participants.get(x.participantId)
            return { name = p and p.display_name or '?', role = x.role }
        end),
        duration = perf.duration_seconds, endsAt = perf.ends_at, remaining = perf.paused_remaining, serverTime = os.time(),
    }
end

local function pushCards(perf)
    local performerSet = U.toSet(performerIds(perf))
    for _, s in ipairs(audienceSources(perf)) do
        local pid = Carnival.Participants.idOfSource(s)
        local card = cardFor(perf, pid)
        if not performerSet[pid] then card.role = nil card.performer = false end
        Carnival.Push.send(s, 'theatre', card)
    end
    -- performers transferred from another group still receive their card
    for _, pid in ipairs(performerIds(perf)) do
        local s = Carnival.Participants.sourceOf(pid)
        if s then Carnival.Push.send(s, 'theatre', cardFor(perf, pid)) end
    end
end

local function closeCards(perf, text)
    for _, s in ipairs(audienceSources(perf)) do Carnival.Push.send(s, 'theatre', { action = 'close', text = text }) end
    for _, pid in ipairs(performerIds(perf)) do
        local s = Carnival.Participants.sourceOf(pid)
        if s then Carnival.Push.send(s, 'theatre', { action = 'close', text = text }) end
    end
end

local function publicPerformance(perf)
    if not perf then return nil end
    return {
        id = perf.id, status = perf.status, scenario = perf.scenario, isCustom = Carnival.Db.bool(perf.is_custom),
        performers = U.map(perf.performers, function(x)
            local p = Carnival.Participants.get(x.participantId)
            return { participantId = x.participantId, name = p and p.display_name or '?', role = x.role, online = Carnival.Participants.sourceOf(x.participantId) ~= nil }
        end),
        duration = perf.duration_seconds, startedAt = perf.started_at, endsAt = perf.ends_at, remaining = perf.paused_remaining,
        serverTime = os.time(),
    }
end

local function loadPerformance(row)
    local perfs = Carnival.Db.query('SELECT participant_id, role_name FROM carnival_theatre_performers WHERE performance_id = ? ORDER BY id', { row.id }) or {}
    row.scenario = Carnival.Db.decode(row.scenario_snapshot, {})
    row.performers = U.map(perfs, function(x) return { participantId = x.participant_id, role = x.role_name } end)
    return row
end

---------------------------------------------------------------------------
-- Operator actions
---------------------------------------------------------------------------
local function requireSession(ctx)
    local s, code, msg = Carnival.Attractions.requireOperator(ctx, ID)
    if s == nil then return nil, code, msg end
    if not s then return nil, 'no_session', 'No group is at the theatre right now.' end
    return s
end

local function create(ctx, payload)
    local session, code, msg = requireSession(ctx)
    if not session then return nil, code, msg end
    if current and current.status ~= 'committed' and current.status ~= 'cancelled' then
        return nil, 'invalid', 'Finish, commit or cancel the current performance first.'
    end
    local c = cfg()
    local scenario, isCustom
    if payload.custom then
        if not ctx:has('theatre.custom') then return nil, 'forbidden', 'You may not create custom scenarios.' end
        local cu = payload.custom
        local title, terr = V.string(cu.title, 96)
        if not title then return nil, 'invalid', 'title ' .. terr end
        local desc, derr = V.text(cu.description, 1000)
        if not desc then return nil, 'invalid', 'description ' .. derr end
        local maxP = V.int(cu.maxPoints or c.maxPointsPerAward, 0, c.maxPointsPerAward) or c.maxPointsPerAward
        scenario = { id = 'custom', title = title, description = desc, category = 'custom', difficulty = V.oneOf(cu.difficulty, { 'easy', 'medium', 'hard', 'absurd' }) or 'medium',
            minPlayers = 1, maxPlayers = 12, timeLimit = c.defaultDurationSeconds, minPoints = 0, maxPoints = maxP, roles = {} }
        isCustom = true
    else
        local sc = type(payload.scenarioId) == 'string' and scenarioById(payload.scenarioId)
        if not sc then return nil, 'invalid', 'Choose a scenario.' end
        scenario = U.deepCopy(sc)
    end

    local list = type(payload.performers) == 'table' and payload.performers or {}
    if #list < 1 or #list > 12 then return nil, 'invalid', 'Choose between 1 and 12 performers.' end
    if not isCustom and (#list < scenario.minPlayers or #list > scenario.maxPlayers) then
        return nil, 'invalid', ('This scenario needs %d-%d performers.'):format(scenario.minPlayers, scenario.maxPlayers)
    end
    local seen, performers = {}, {}
    for _, x in ipairs(list) do
        local pid = V.id(x.participantId)
        local p = pid and Carnival.Participants.get(pid)
        if not p or p.status ~= 'active' or p.colour ~= session.colour then
            return nil, 'invalid', 'Performers must be active members of the group at the theatre.'
        end
        if seen[pid] then return nil, 'invalid', 'A performer is listed twice.' end
        seen[pid] = true
        local role = x.role and V.string(x.role, 64, true) or ''
        performers[#performers + 1] = { participantId = pid, role = role ~= '' and role or nil }
    end
    local duration = V.int(payload.duration or scenario.timeLimit or c.defaultDurationSeconds, 15, 1800) or c.defaultDurationSeconds

    local e = Carnival.Events.active
    local id = Carnival.Db.insertRow('carnival_theatre_performances', {
        event_id = e.id, session_id = session.id, scenario_id = scenario.id, scenario_snapshot = json.encode(scenario),
        is_custom = isCustom and 1 or 0, status = 'draft', duration_seconds = duration,
        operator_license = ctx.actor.license, operator_name = ctx.actor.name, created_at = os.time(),
    })
    if not id then return nil, 'database_error' end
    for _, x in ipairs(performers) do
        Carnival.Db.insertRow('carnival_theatre_performers', { performance_id = id, participant_id = x.participantId, role_name = x.role })
    end
    current = loadPerformance(Carnival.Db.single('SELECT * FROM carnival_theatre_performances WHERE id = ?', { id }))
    Carnival.Audit.record(ctx.actor, 'theatre_performance_created', { targetType = 'performance', targetId = id,
        details = { scenario = scenario.id, custom = isCustom, performers = #performers, duration = duration } })
    Carnival.Push.invalidate('theatre')
    return publicPerformance(current)
end

local function requireCurrent(statuses)
    if not current then return nil, 'invalid', 'There is no performance.' end
    if statuses and not U.toSet(statuses)[current.status] then
        return nil, 'invalid', ('The performance is %s.'):format(current.status)
    end
    return current
end

local function control(ctx, action)
    local s, code, msg = Carnival.Attractions.requireOperator(ctx, ID)
    if s == nil then return nil, code, msg end
    local now = os.time()
    if action == 'display' then
        local perf, c2, m2 = requireCurrent({ 'draft', 'displayed' })
        if not perf then return nil, c2, m2 end
        persist(perf, { status = 'displayed' })
        pushCards(perf)
    elseif action == 'start' then
        local perf, c2, m2 = requireCurrent({ 'draft', 'displayed' })
        if not perf then return nil, c2, m2 end
        local e = Carnival.Events.active
        if not e or not C.LIVE_STATES[e.state] then return nil, 'not_live', 'The event is paused or not running.' end
        persist(perf, { status = 'running', started_at = now, ends_at = now + perf.duration_seconds })
        pushCards(perf)
    elseif action == 'pause' then
        local perf, c2, m2 = requireCurrent({ 'running' })
        if not perf then return nil, c2, m2 end
        persist(perf, { status = 'paused', paused_remaining = math.max(0, perf.ends_at - now) })
        pushCards(perf)
    elseif action == 'resume' then
        local perf, c2, m2 = requireCurrent({ 'paused' })
        if not perf then return nil, c2, m2 end
        persist(perf, { status = 'running', ends_at = now + (perf.paused_remaining or 0), paused_remaining = Carnival.Db.NULL })
        pushCards(perf)
    elseif action == 'end' then
        local perf, c2, m2 = requireCurrent({ 'running', 'paused', 'displayed' })
        if not perf then return nil, c2, m2 end
        persist(perf, { status = 'ended', ended_at = now })
        closeCards(perf, 'The curtain falls. The Puppet Master is judging...')
    else
        return nil, 'invalid', 'Unknown action.'
    end
    Carnival.Monitor.log('info', 'attraction', 'theatre_' .. action, { attractionId = ID, actor = ctx.actor, details = { performanceId = current.id } })
    Carnival.Push.invalidate('theatre')
    return publicPerformance(current)
end

-- Build the award lines (clamped) for preview / commit.
local function buildAwards(perf, payload)
    local c = cfg()
    local maxPoints = math.min(perf.scenario.maxPoints or c.maxPointsPerAward, c.maxPointsPerAward)
    local performerSet = U.toSet(performerIds(perf))
    local lines, warnings, seen = {}, {}, {}
    for _, a in ipairs(type(payload.awards) == 'table' and payload.awards or {}) do
        local pid = V.id(a.participantId)
        if not pid or not performerSet[pid] then return nil, 'Awards may only go to this performance\'s performers.' end
        if seen[pid] then return nil, 'A performer appears twice in the awards.' end
        seen[pid] = true
        local requested = V.int(a.points or 0, 0, 100000) or 0
        local points = U.clamp(requested, 0, maxPoints)
        if points ~= requested then warnings[#warnings + 1] = ('Award for #%d clamped to %d.'):format(pid, points) end
        local winner = a.winner == true
        if winner and points < (perf.scenario.minPoints or 0) then
            warnings[#warnings + 1] = ('Winner #%d receives less than the scenario minimum (%d).'):format(pid, perf.scenario.minPoints)
        end
        local cap = Carnival.Config.get().attractions.puppets.maxScore
        local already = Carnival.Scoring.attractionPoints(pid, ID)
        local p = Carnival.Participants.get(pid)
        lines[#lines + 1] = {
            participantId = pid, name = p and p.display_name or '?', points = points, winner = winner,
            bonus = payload.participationBonus == true and c.participationBonus or 0,
            capNote = (cap > 0 and already + points > cap) and ('attraction cap will limit this to %d'):format(math.max(0, cap - already)) or nil,
        }
    end
    for pid in pairs(performerSet) do
        if not seen[pid] then
            local p = Carnival.Participants.get(pid)
            lines[#lines + 1] = { participantId = pid, name = p and p.display_name or '?', points = 0, winner = false,
                bonus = payload.participationBonus == true and c.participationBonus or 0 }
        end
    end
    return lines, warnings
end

local function preview(ctx, payload)
    local s, code, msg = Carnival.Attractions.requireOperator(ctx, ID)
    if s == nil then return nil, code, msg end
    local perf, c2, m2 = requireCurrent({ 'ended' })
    if not perf then return nil, c2, m2 end
    local lines, warnings = buildAwards(perf, payload)
    if not lines then return nil, 'invalid', warnings end
    return { lines = lines, warnings = warnings, performanceId = perf.id }
end

local function commit(ctx, payload)
    local s, code, msg = Carnival.Attractions.requireOperator(ctx, ID)
    if s == nil then return nil, code, msg end
    local perfId = V.id(payload.performanceId)
    return Carnival.withLock('theatre:commit', function()
        local perf = current
        if not perf or perf.id ~= perfId then
            local row = perfId and Carnival.Db.single('SELECT status FROM carnival_theatre_performances WHERE id = ?', { perfId })
            if row and row.status == 'committed' then
                Carnival.Monitor.log('info', 'duplicate', 'theatre_duplicate_commit', { attractionId = ID, actor = ctx.actor, details = { performanceId = perfId } })
                return { alreadyCommitted = true }
            end
            return nil, 'invalid', 'That performance is not awaiting judgement.'
        end
        if perf.status ~= 'ended' then return nil, 'invalid', ('The performance is %s.'):format(perf.status) end
        local lines, warnings = buildAwards(perf, payload)
        if not lines then return nil, 'invalid', warnings end
        local note = V.text(payload.note or '', 1000, true) or ''
        -- mark committed first so a concurrent/retried commit cannot re-enter
        local n = Carnival.Db.update("UPDATE carnival_theatre_performances SET status = 'committed', committed_at = ?, judging_note = ? WHERE id = ? AND status = 'ended'", { os.time(), note, perf.id })
        if not n or n < 1 then return { alreadyCommitted = true } end
        perf.status = 'committed'
        local session = Carnival.Rotation.sessionById(perf.session_id)
        local results = {}
        for _, l in ipairs(lines) do
            local applied, bonusApplied = 0, 0
            if l.points > 0 then
                local ok, tx = Carnival.Scoring.award({
                    participantId = l.participantId, delta = l.points, key = ('theatre:%d:%d'):format(perf.id, l.participantId),
                    txType = 'award', source = l.winner and 'theatre_winner' or 'theatre_award', reason = ('%s — %s'):format(perf.scenario.title, note ~= '' and note or 'judged'),
                    attractionId = ID, sessionId = perf.session_id, roundNumber = session and session.round_number or nil, actor = ctx.actor,
                    publicReason = l.winner and 'Theatre winner!' or 'Theatre performance',
                })
                if ok then applied = tx.delta end
            end
            if l.bonus > 0 then
                local ok, tx = Carnival.Scoring.award({
                    participantId = l.participantId, delta = l.bonus, key = ('theatre:%d:%d:bonus'):format(perf.id, l.participantId),
                    txType = 'participation', source = 'theatre_participation', reason = perf.scenario.title .. ' participation',
                    attractionId = ID, sessionId = perf.session_id, roundNumber = session and session.round_number or nil, actor = ctx.actor,
                    publicReason = 'Took the stage',
                })
                if ok then bonusApplied = tx.delta end
            end
            Carnival.Db.update('UPDATE carnival_theatre_performers SET is_winner = ?, points = ?, participation_bonus = ? WHERE performance_id = ? AND participant_id = ?',
                { l.winner and 1 or 0, applied, bonusApplied, perf.id, l.participantId })
            results[#results + 1] = { participantId = l.participantId, name = l.name, points = applied, bonus = bonusApplied, winner = l.winner }
        end
        Carnival.Audit.record(ctx.actor, 'theatre_results_committed', { targetType = 'performance', targetId = perf.id, reason = note,
            details = { results = results } })
        for _, r in ipairs(results) do
            local src = Carnival.Participants.sourceOf(r.participantId)
            if src and r.winner then Carnival.Push.notify(src, 'Bravo!', 'The Puppet Master chose you as a winner.', 'success', 'treat_sparkle') end
        end
        current = nil
        Carnival.Push.invalidate('theatre')
        return { results = results, warnings = warnings }
    end)
end

local function cancel(ctx, payload)
    local s, code, msg = Carnival.Attractions.requireOperator(ctx, ID)
    if s == nil then return nil, code, msg end
    local perf, c2, m2 = requireCurrent({ 'draft', 'displayed', 'running', 'paused', 'ended' })
    if not perf then return nil, c2, m2 end
    local reason, rerr = V.reason(payload.reason, true)
    if not reason then return nil, 'invalid', rerr end
    persist(perf, { status = 'cancelled', ended_at = os.time(), judging_note = reason })
    closeCards(perf, 'The performance was cancelled.')
    Carnival.Audit.record(ctx.actor, 'theatre_performance_cancelled', { targetType = 'performance', targetId = perf.id, reason = reason })
    current = nil
    Carnival.Push.invalidate('theatre')
    return true
end

local function randomScenario(payload)
    local candidates = {}
    for _, sc in ipairs(cfg().scenarios) do
        local ok = true
        if payload.category and payload.category ~= '' and sc.category ~= payload.category then ok = false end
        if payload.difficulty and payload.difficulty ~= '' and sc.difficulty ~= payload.difficulty then ok = false end
        local players = tonumber(payload.players)
        if players and (players < sc.minPlayers or players > sc.maxPlayers) then ok = false end
        if ok then candidates[#candidates + 1] = sc end
    end
    if #candidates == 0 then return nil, 'not_found', 'No scenario matches those filters.' end
    return candidates[math.random(#candidates)]
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
Carnival.Attractions.register({
    id = ID,
    isBusy = function() return current ~= nil and (current.status == 'running' or current.status == 'paused') end,
    onSessionEnd = function(session)
        if current and current.session_id == session.id and current.status ~= 'ended' then
            persist(current, { status = 'cancelled', ended_at = os.time(), judging_note = 'Session ended before judging' })
            closeCards(current, 'The theatre is closing.')
            current = nil
        end
    end,
    onPause = function()
        if current and current.status == 'running' then
            persist(current, { status = 'paused', paused_remaining = math.max(0, current.ends_at - os.time()) })
            pushCards(current)
        end
    end,
    onEventEnd = function()
        if current and current.status ~= 'ended' then
            persist(current, { status = 'cancelled', ended_at = os.time(), judging_note = 'Event ended' })
            current = nil
        end
    end,
    recover = function(e)
        current = nil
        local row = Carnival.Db.single("SELECT * FROM carnival_theatre_performances WHERE event_id = ? AND status IN ('draft', 'displayed', 'running', 'paused', 'ended') ORDER BY id DESC LIMIT 1", { e.id })
        if row then
            if row.status == 'running' or row.status == 'paused' then
                Carnival.Db.update("UPDATE carnival_theatre_performances SET status = 'ended', ended_at = ? WHERE id = ?", { os.time(), row.id })
                row.status = 'ended'
                Carnival.Monitor.log('warning', 'recovery', 'theatre_performance_interrupted', { attractionId = ID, details = { performanceId = row.id } })
            end
            current = loadPerformance(row)
        end
    end,
    staffSummary = function() return current and { performance = current.status, title = current.scenario.title } or nil end,
})

Carnival.onTick('theatre', function(now)
    if current and current.status == 'running' and current.ends_at and now >= current.ends_at then
        persist(current, { status = 'ended', ended_at = now })
        closeCards(current, 'Time! The Puppet Master is judging...')
        Carnival.Monitor.log('info', 'countdown', 'theatre_time_up', { attractionId = ID, details = { performanceId = current.id } })
        Carnival.Push.invalidate('theatre')
    end
end)

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local OP = 'attractions.operate.puppets'

Api.register('theatre.state', {
    perm = OP, rate = 'staff',
    handler = function()
        local e = Carnival.Events.active
        local session = Carnival.Rotation.sessionFor(ID)
        local eligible = {}
        if session then
            for _, p in ipairs(Carnival.Participants.members(session.colour, false)) do
                eligible[#eligible + 1] = { id = p.id, name = p.display_name, online = Carnival.Participants.sourceOf(p.id) ~= nil,
                    points = Carnival.Scoring.attractionPoints(p.id, ID) }
            end
        end
        local history = {}
        if e then
            for _, r in ipairs(Carnival.Db.query("SELECT * FROM carnival_theatre_performances WHERE event_id = ? AND status IN ('committed', 'cancelled') ORDER BY id DESC LIMIT 20", { e.id }) or {}) do
                local perfs = Carnival.Db.query('SELECT tp.*, p.display_name FROM carnival_theatre_performers tp JOIN carnival_participants p ON p.id = tp.participant_id WHERE tp.performance_id = ?', { r.id }) or {}
                history[#history + 1] = { id = r.id, status = r.status, scenario = Carnival.Db.decode(r.scenario_snapshot, {}).title, operator = r.operator_name,
                    note = r.judging_note, committedAt = r.committed_at, performers = perfs }
            end
        end
        return { session = session, eligible = eligible, scenarios = cfg().scenarios, current = publicPerformance(current), history = history,
            defaultDuration = cfg().defaultDurationSeconds, maxPointsPerAward = cfg().maxPointsPerAward, participationBonus = cfg().participationBonus }
    end,
})

Api.register('theatre.random', {
    perm = OP, rate = 'staff',
    handler = function(ctx, payload) return randomScenario(payload) end,
})
Api.register('theatre.create', { perm = OP, rate = 'staff', handler = create })
for _, action in ipairs({ 'display', 'start', 'pause', 'resume', 'end' }) do
    Api.register('theatre.' .. action, { perm = OP, rate = 'staff', handler = function(ctx) return control(ctx, action) end })
end
Api.register('theatre.preview', { perm = OP, rate = 'staff', handler = preview })
Api.register('theatre.commit', { perm = OP, rate = 'staff', handler = commit })
Api.register('theatre.cancel', { perm = OP, rate = 'staff', handler = cancel })
