-- Attraction: The Fortune Teller's Curse.
-- Automated visits ask server-selected questions; answers are marked on the server
-- (correct answers never leave the server for participants). Each question can be
-- scored once per participant, visits are limited and pending questions survive
-- dialogue resets so retrying cannot farm points. Staff can also lead visits.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api
local ID = 'fortune'

local visits = {}   -- [pid] = { id, questionIds, answered = set, staff, startedAt, askedAt }

local function cfg() return Carnival.Config.get().attractions.fortune end

local function questionById(id)
    for _, q in ipairs(cfg().questions) do if q.id == id then return q end end
    return nil
end

local function publicQuestion(q, index, total)
    return {
        id = q.id, kind = q.kind, prompt = q.prompt, category = q.category,
        choices = q.kind == 'choice' and q.choices or nil, index = index, total = total,
        timeout = cfg().answerTimeoutSeconds,
    }
end

local function answeredIds(eventId, pid)
    local set = {}
    for _, r in ipairs(Carnival.Db.query('SELECT question_id FROM carnival_fortune_answers WHERE event_id = ? AND participant_id = ?', { eventId, pid }) or {}) do
        set[r.question_id] = true
    end
    return set
end

local function currentQuestion(v)
    for i, qid in ipairs(v.questionIds) do
        if not v.answered[qid] then return questionById(qid), i end
    end
    return nil
end

local function finishVisit(v, pid, status)
    Carnival.Db.update('UPDATE carnival_fortune_visits SET status = ?, finished_at = ? WHERE id = ?', { status or 'finished', os.time(), v.id })
    visits[pid] = nil
end

local function startVisit(p, session, questionIds, mode, staffActor, fortune)
    local e = Carnival.Events.active
    local n = (Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_fortune_visits WHERE event_id = ? AND participant_id = ?', { e.id, p.id }) or 0) + 1
    local id = Carnival.Db.insertRow('carnival_fortune_visits', {
        event_id = e.id, participant_id = p.id, session_id = session and session.id or nil, visit_number = n, mode = mode,
        fortune = fortune, question_ids = json.encode(questionIds), status = 'active',
        staff_license = staffActor and staffActor.license or nil, started_at = os.time(),
    })
    if not id then return nil end
    local v = { id = id, questionIds = questionIds, answered = {}, staff = staffActor ~= nil, startedAt = os.time(), askedAt = os.time(), sessionId = session and session.id }
    visits[p.id] = v
    return v
end

local function pickQuestions(e, p, count)
    local done = answeredIds(e.id, p.id)
    local pool = {}
    for _, q in ipairs(cfg().questions) do
        if not done[q.id] then pool[#pool + 1] = q.id end
    end
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local out = {}
    for i = 1, math.min(count, #pool) do out[i] = pool[i] end
    return out
end

local function randomFortune()
    local list = cfg().fortunes
    if #list == 0 then return nil end
    return list[math.random(#list)]
end

---------------------------------------------------------------------------
-- Participant flow
---------------------------------------------------------------------------
local function begin(src)
    local c = cfg()
    if c.mode == 'staff' then return nil, 'staff_only', 'The fortune teller only reads for those the staff bring forward.' end
    local p, session, msg = Carnival.Attractions.eligibility(src, ID)
    if not p then return nil, session, msg end
    return Carnival.withLock('fortune:' .. p.id, function()
        local e = Carnival.Events.active
        local v = visits[p.id]
        if v then
            -- resume the pending question; never regenerate a visit
            local q, idx = currentQuestion(v)
            if q then
                return { visitId = v.id, greeting = c.greeting, resumed = true, question = publicQuestion(q, idx, #v.questionIds) }
            end
            finishVisit(v, p.id)
        end
        local used = Carnival.Db.scalar("SELECT COUNT(*) FROM carnival_fortune_visits WHERE event_id = ? AND participant_id = ? AND mode = 'automated'", { e.id, p.id }) or 0
        if used >= c.maxVisits then return nil, 'no_visits', 'The fortune teller has nothing more to tell you tonight.' end
        local lastFinish = Carnival.Db.scalar('SELECT MAX(finished_at) FROM carnival_fortune_visits WHERE event_id = ? AND participant_id = ?', { e.id, p.id })
        if lastFinish and os.time() - lastFinish < c.cooldownSeconds then
            return nil, 'cooldown', 'The cards must rest. Come back shortly.'
        end
        local qids = pickQuestions(e, p, c.questionsPerVisit)
        local fortune = randomFortune()
        v = startVisit(p, session, qids, 'automated', nil, fortune)
        if not v then return nil, 'database_error', 'The fortune teller is indisposed. Try again.' end
        Carnival.Monitor.log('info', 'attraction', 'fortune_visit_started', { participantId = p.id, attractionId = ID, details = { visitId = v.id, questions = #qids } })
        if c.scoreFortunes and c.fortunePoints > 0 and fortune then
            Carnival.Scoring.award({
                participantId = p.id, delta = c.fortunePoints, key = 'fortune:reading:' .. v.id, txType = 'award', source = 'fortune_reading',
                reason = 'Fortune reading', attractionId = ID, sessionId = session.id, roundNumber = session.round_number, publicReason = 'Fortune reading',
            })
        end
        if #qids == 0 then
            finishVisit(v, p.id)
            return { visitId = v.id, greeting = c.greeting, fortune = fortune, finished = true, farewell = c.farewell }
        end
        local q = questionById(qids[1])
        return { visitId = v.id, greeting = c.greeting, fortune = fortune, question = publicQuestion(q, 1, #qids) }
    end)
end

local function answer(src, payload)
    local visitId = V.id(payload.visitId)
    local qid = type(payload.questionId) == 'string' and payload.questionId:sub(1, 32) or nil
    if not visitId or not qid then return nil, 'invalid', 'Invalid answer.' end
    local p = Carnival.Participants.getBySource(src)
    if not p then return nil, 'not_registered', 'You are not registered.' end
    local v = visits[p.id]
    if not v or v.id ~= visitId then
        Carnival.Monitor.log('info', 'duplicate', 'fortune_answer_without_visit', { participantId = p.id, attractionId = ID })
        return nil, 'no_visit', 'The fortune teller is not expecting an answer.'
    end
    -- Re-run eligibility for distance / ticket / session. Staff-led visits may run
    -- even if the group is not scheduled here (staff chose to present it).
    local ok, code, msg = Carnival.Attractions.eligibility(src, ID, { requireSession = not v.staff })
    if not ok then return nil, code, msg end

    return Carnival.withLock('fortune:' .. p.id, function()
        local q, idx = currentQuestion(v)
        if not q or q.id ~= qid then
            Carnival.Monitor.log('info', 'duplicate', 'fortune_stale_answer', { participantId = p.id, attractionId = ID, details = { questionId = qid } })
            return nil, 'stale', 'That question has already been answered.'
        end
        local c = cfg()
        local timedOut = os.time() - v.askedAt > c.answerTimeoutSeconds + 5
        local given, correct
        if q.kind == 'choice' then
            local choice = V.int(payload.choice, 1, #q.choices)
            if not choice and not timedOut then return nil, 'invalid', 'Pick one of the answers.' end
            given = choice and q.choices[choice] or nil
            correct = (not timedOut) and choice == q.correctIndex
        else
            local text = type(payload.text) == 'string' and U.sanitizeText(payload.text, 120) or ''
            given = text
            correct = false
            if not timedOut then
                local norm = U.normaliseAnswer(text)
                for _, a in ipairs(q.acceptedAnswers) do
                    if norm ~= '' and norm == U.normaliseAnswer(a) then correct = true end
                end
            end
        end
        local e = Carnival.Events.active
        local points = correct and q.points or (q.wrongPoints or 0)
        local answerId = Carnival.Db.insertRow('carnival_fortune_answers', {
            event_id = e.id, participant_id = p.id, visit_id = v.id, question_id = q.id,
            question_snapshot = json.encode({ prompt = q.prompt, kind = q.kind, choices = q.choices, correctIndex = q.correctIndex, acceptedAnswers = q.acceptedAnswers, points = q.points }),
            answer = given, correct = correct and 1 or 0, timed_out = timedOut and 1 or 0, points = points, created_at = os.time(),
        })
        if not answerId then return nil, 'stale', 'That question has already been answered.' end
        v.answered[q.id] = true
        v.askedAt = os.time()
        local applied = 0
        if points ~= 0 then
            local session = Carnival.Rotation.sessionForColour(p.colour)
            local aok, tx = Carnival.Scoring.award({
                participantId = p.id, delta = points, key = 'fortune:answer:' .. answerId, txType = points > 0 and 'award' or 'penalty',
                source = correct and 'fortune_correct' or 'fortune_wrong', reason = 'Fortune question ' .. q.id, attractionId = ID,
                sessionId = session and session.id or v.sessionId, roundNumber = session and session.round_number or nil,
                publicReason = correct and 'Correct answer' or 'Wrong answer',
            })
            if aok then applied = tx.delta end
        end
        Carnival.Monitor.log('info', 'attraction', 'fortune_answer', { participantId = p.id, attractionId = ID, result = correct and 'correct' or (timedOut and 'timeout' or 'wrong'), details = { question = q.id } })
        local result = { correct = correct, timedOut = timedOut, points = applied, text = correct and q.successText or q.failureText }
        local nextQ, nextIdx = currentQuestion(v)
        if nextQ then
            result.question = publicQuestion(nextQ, nextIdx, #v.questionIds)
        else
            finishVisit(v, p.id)
            result.finished = true
            result.farewell = c.farewell
        end
        Carnival.Push.invalidate('fortune')
        return result
    end)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
Carnival.Attractions.register({
    id = ID,
    onTimerExpired = function() return 'complete' end,
    onSessionEnd = function(session)
        for pid, v in pairs(visits) do
            local p = Carnival.Participants.get(pid)
            if p and p.colour == session.colour then
                finishVisit(v, pid, 'closed')
                local s = Carnival.Participants.sourceOf(pid)
                if s then Carnival.Push.send(s, 'fortune', { action = 'close' }) end
            end
        end
    end,
    onEventEnd = function()
        for pid, v in pairs(visits) do finishVisit(v, pid, 'closed') end
    end,
    recover = function(e)
        visits = {}
        for _, r in ipairs(Carnival.Db.query("SELECT * FROM carnival_fortune_visits WHERE event_id = ? AND status = 'active'", { e.id }) or {}) do
            local answered = {}
            for _, a in ipairs(Carnival.Db.query('SELECT question_id FROM carnival_fortune_answers WHERE visit_id = ?', { r.id }) or {}) do answered[a.question_id] = true end
            visits[r.participant_id] = { id = r.id, questionIds = Carnival.Db.decode(r.question_ids, {}), answered = answered,
                staff = r.mode == 'staff', startedAt = r.started_at, askedAt = os.time(), sessionId = r.session_id }
        end
    end,
    staffSummary = function()
        return { activeVisits = U.count(visits) }
    end,
})

Api.register('fortune.begin', { rate = 'action', handler = function(ctx) return begin(ctx.source) end })
Api.register('fortune.answer', { rate = 'action', handler = function(ctx, payload) return answer(ctx.source, payload) end })

---------------------------------------------------------------------------
-- Staff controls
---------------------------------------------------------------------------
local function staffTarget(payload)
    local pid = V.id(payload.participantId)
    if not pid then return nil, 'invalid', 'Choose a participant.' end
    local p = Carnival.Participants.get(pid)
    if not p or p.status ~= 'active' then return nil, 'not_found', 'Participant not found.' end
    local s = Carnival.Participants.sourceOf(pid)
    if not s then return nil, 'offline', 'That participant is offline.' end
    return p, s
end

Api.register('fortune.staff.state', {
    perm = 'attractions.operate.fortune', rate = 'staff',
    handler = function()
        local e = Carnival.Events.active
        local session = Carnival.Rotation.sessionFor(ID)
        local members = {}
        if e and session then
            for _, p in ipairs(Carnival.Participants.members(session.colour, false)) do
                local stats = Carnival.Db.single('SELECT COUNT(*) AS answered, COALESCE(SUM(correct), 0) AS correct, COALESCE(SUM(points), 0) AS points FROM carnival_fortune_answers WHERE event_id = ? AND participant_id = ?', { e.id, p.id })
                members[#members + 1] = { id = p.id, name = p.display_name, online = Carnival.Participants.sourceOf(p.id) ~= nil,
                    answered = stats and tonumber(stats.answered) or 0, correct = stats and tonumber(stats.correct) or 0,
                    points = Carnival.Scoring.attractionPoints(p.id, ID), inVisit = visits[p.id] ~= nil }
            end
        end
        local c = cfg()
        local recent = e and (Carnival.Db.query([[SELECT a.id, p.display_name, a.question_id, a.answer, a.correct, a.timed_out, a.points, a.created_at
            FROM carnival_fortune_answers a JOIN carnival_participants p ON p.id = a.participant_id WHERE a.event_id = ? ORDER BY a.id DESC LIMIT 30]], { e.id }) or {}) or {}
        return {
            session = session, members = members, mode = c.mode, roleplayMaxPoints = c.roleplayMaxPoints,
            questions = U.map(c.questions, function(q)
                return { id = q.id, prompt = q.prompt, kind = q.kind, category = q.category, choices = q.choices,
                    answer = q.kind == 'choice' and q.choices[q.correctIndex] or table.concat(q.acceptedAnswers, ' / '), points = q.points }
            end),
            fortunes = c.fortunes, recent = recent,
        }
    end,
})

Api.register('fortune.staff.present', {
    perm = 'attractions.operate.fortune', rate = 'staff',
    handler = function(ctx, payload)
        local p, s, m = staffTarget(payload)
        if not p then return nil, s, m end
        local qid = type(payload.questionId) == 'string' and payload.questionId or nil
        local q = qid and questionById(qid)
        if not q then return nil, 'invalid', 'Unknown question.' end
        local e = Carnival.Events.active
        if not e or not C.LIVE_STATES[e.state] then return nil, 'not_live', 'The event is not running.' end
        return Carnival.withLock('fortune:' .. p.id, function()
            if answeredIds(e.id, p.id)[q.id] then return nil, 'invalid', 'They have already answered that question.' end
            if visits[p.id] then return nil, 'invalid', 'They are already mid-reading.' end
            local v = startVisit(p, Carnival.Rotation.sessionForColour(p.colour), { q.id }, 'staff', ctx.actor, nil)
            if not v then return nil, 'database_error' end
            Carnival.Push.send(s, 'fortune', { action = 'question', visitId = v.id, staffLed = true, question = publicQuestion(q, 1, 1), greeting = cfg().greeting })
            Carnival.Audit.record(ctx.actor, 'fortune_question_presented', { targetType = 'participant', targetId = p.id, details = { question = q.id } })
            return { visitId = v.id }
        end)
    end,
})

Api.register('fortune.staff.reveal', {
    perm = 'attractions.operate.fortune', rate = 'staff',
    handler = function(ctx, payload)
        local ids = type(payload.participantIds) == 'table' and payload.participantIds or {}
        if #ids == 0 or #ids > 24 then return nil, 'invalid', 'Choose up to 24 participants.' end
        local text
        if payload.text and payload.text ~= '' then
            text = V.text(payload.text, 300)
        else
            local idx = V.int(payload.fortuneIndex, 1, #cfg().fortunes)
            text = idx and cfg().fortunes[idx]
        end
        if not text then return nil, 'invalid', 'Choose a fortune.' end
        local sent = 0
        for _, raw in ipairs(ids) do
            local pid = V.id(raw)
            local s = pid and Carnival.Participants.sourceOf(pid)
            if s then
                Carnival.Push.send(s, 'fortune', { action = 'fortune', text = text })
                sent = sent + 1
            end
        end
        Carnival.Monitor.log('info', 'attraction', 'fortune_revealed', { attractionId = ID, actor = ctx.actor, details = { recipients = sent } })
        return { sent = sent }
    end,
})

Api.register('fortune.staff.award', {
    perm = 'attractions.operate.fortune', rate = 'staff',
    handler = function(ctx, payload)
        local p, s, m = staffTarget(payload)
        if not p then return nil, s, m end
        local max = cfg().roleplayMaxPoints
        local points, perr = V.int(payload.points, 1, math.max(1, max))
        if not points or max <= 0 then return nil, 'invalid', 'points ' .. (perr or 'not allowed') end
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        local requestId, qerr = V.requestId(payload.requestId)
        if not requestId then return nil, 'invalid', qerr end
        local session = Carnival.Rotation.sessionForColour(p.colour)
        if not session or session.attraction_id ~= ID or session.status ~= C.SESSION_STATUS.ACTIVE then
            return nil, 'invalid', 'That participant\'s group is not at the fortune teller.'
        end
        local ok, tx, msg = Carnival.Scoring.award({
            participantId = p.id, delta = points, key = 'fortune:rp:' .. requestId, txType = 'award', source = 'fortune_roleplay',
            reason = reason, attractionId = ID, sessionId = session.id, roundNumber = session.round_number, actor = ctx.actor,
            publicReason = 'The fortune teller is pleased',
        })
        if not ok then return nil, tx, msg end
        if not tx.duplicate then
            Carnival.Audit.record(ctx.actor, 'fortune_roleplay_award', { targetType = 'participant', targetId = p.id, reason = reason, details = { points = tx.delta } })
        end
        return tx
    end,
})
