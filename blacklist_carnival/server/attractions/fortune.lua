-- Attraction: The Fortune Teller's Curse.
-- Each reading asks server-selected questions; answers are marked on the server
-- (correct answers never leave the server). Each question can be scored once per
-- participant, readings are limited and pending questions survive dialogue
-- resets so retrying cannot farm points.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api
local ID = 'fortune'

local visits = {}   -- [pid] = { id, questionIds, answered = set, startedAt, askedAt, sessionId }

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
    -- walk-up: a finished reading completes this player's visit
    if (status == nil or status == 'finished') and v.sessionId then
        CreateThread(function() Carnival.Rotation.memberFinished(v.sessionId, pid, 'Reading finished') end)
    end
end

local function startVisit(p, session, questionIds, fortune)
    local e = Carnival.Events.active
    local n = (Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_fortune_visits WHERE event_id = ? AND participant_id = ?', { e.id, p.id }) or 0) + 1
    local id = Carnival.Db.insertRow('carnival_fortune_visits', {
        event_id = e.id, participant_id = p.id, session_id = session and session.id or nil, visit_number = n, mode = 'automated',
        fortune = fortune, question_ids = json.encode(questionIds), status = 'active', started_at = os.time(),
    })
    if not id then return nil end
    local v = { id = id, questionIds = questionIds, answered = {}, startedAt = os.time(), askedAt = os.time(), sessionId = session and session.id }
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
        -- readings closed before they finished (visit closed, player walked off) do not count
        local used = Carnival.Db.scalar("SELECT COUNT(*) FROM carnival_fortune_visits WHERE event_id = ? AND participant_id = ? AND mode = 'automated' AND status <> 'closed'", { e.id, p.id }) or 0
        if used >= c.maxVisits then return nil, 'no_visits', 'The fortune teller has nothing more to tell you tonight.' end
        local lastFinish = Carnival.Db.scalar("SELECT MAX(finished_at) FROM carnival_fortune_visits WHERE event_id = ? AND participant_id = ? AND status <> 'closed'", { e.id, p.id })
        if lastFinish and os.time() - lastFinish < c.cooldownSeconds then
            return nil, 'cooldown', 'The cards must rest. Come back shortly.'
        end
        local qids = pickQuestions(e, p, c.questionsPerVisit)
        local fortune = randomFortune()
        v = startVisit(p, session, qids, fortune)
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
    -- Re-run eligibility for distance / ticket / session.
    local ok, code, msg = Carnival.Attractions.eligibility(src, ID)
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
            local session = Carnival.Rotation.participantSession(p, ID)
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
            local mine = v.sessionId == session.id or (session.kind ~= 'walkup' and p ~= nil and p.colour == session.colour)
            if mine then
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
                startedAt = r.started_at, askedAt = os.time(), sessionId = r.session_id }
        end
    end,
    staffSummary = function()
        return { activeVisits = U.count(visits) }
    end,
})

Api.register('fortune.begin', { rate = 'action', handler = function(ctx) return begin(ctx.source) end })
Api.register('fortune.answer', { rate = 'action', handler = function(ctx, payload) return answer(ctx.source, payload) end })
