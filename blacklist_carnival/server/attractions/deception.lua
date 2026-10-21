-- Attraction: The Hall of Deception.
-- Runs by itself: the mystery starts when players arrive, clues unlock over
-- time, and every accusation is marked automatically. Players read each
-- suspect's testimony and pick the liars. The answer key stays on the server
-- until the reveal.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api
local ID = 'deception'

local current = nil  -- { row fields..., mystery, key = set }
local finishSelf, everyoneSubmitted

local function cfg() return Carnival.Config.get().attractions.deception end

local function mysteryById(id)
    for _, m in ipairs(cfg().mysteries) do if m.id == id then return m end end
    return nil
end

local function publicMystery(m)
    return {
        id = m.id, title = m.title, description = m.description, rules = m.rules, liarCount = m.liarCount,
        -- testimony is what each performer says aloud; whether they lie stays secret
        performers = U.map(m.performers, function(p) return { id = p.id, name = p.name, profile = p.profile, statements = p.statements } end),
    }
end

local function releasedClues(roundId)
    return Carnival.Db.query('SELECT clue_id, clue_text, released_at FROM carnival_deception_clues WHERE round_id = ? ORDER BY id', { roundId }) or {}
end

local function submissionCount(roundId, pid)
    return Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_deception_submissions WHERE round_id = ? AND participant_id = ?', { roundId, pid }) or 0
end

local function solution()
    local out = {}
    for _, p in ipairs(current.mystery.performers) do
        if current.key[p.id] then out[#out + 1] = { id = p.id, name = p.name } end
    end
    return out
end

-- What a participant may see.
local function participantState(pid)
    if not current then return { active = false } end
    local st = {
        active = true, roundId = current.id, status = current.status, mystery = publicMystery(current.mystery),
        clues = U.map(releasedClues(current.id), function(c) return { id = c.clue_id, text = c.clue_text, releasedAt = c.released_at } end),
        endsAt = current.questioning_ends_at, serverTime = os.time(),
        maxSubmissions = cfg().maxSubmissions,
        submissionsUsed = pid and submissionCount(current.id, pid) or 0,
    }
    if current.status == 'revealed' or current.status == 'committed' then st.solution = solution() end
    return st
end

local function pushGroup(action)
    if not current then return end
    local session = Carnival.Rotation.sessionById(current.session_id)
    if not session then return end
    for _, p in ipairs(Carnival.Rotation.sessionMembers(session, true)) do
        local s = Carnival.Participants.sourceOf(p.id)
        local st = participantState(p.id)
        st.action = action
        Carnival.Push.send(s, 'deception', st)
    end
end

local function persist(set)
    Carnival.Db.updateRow('carnival_deception_rounds', set, 'id = ?', { current.id })
    for k, v in pairs(set) do current[k] = v ~= Carnival.Db.NULL and v or nil end
end

local function loadRound(row)
    row.mystery = Carnival.Db.decode(row.mystery_snapshot, {})
    row.key = U.toSet(Carnival.Db.decode(row.answer_key, {}))
    return row
end

---------------------------------------------------------------------------
-- Marking
---------------------------------------------------------------------------
local function latestSubmissions(roundId)
    local rows = Carnival.Db.query([[SELECT s.*, p.display_name FROM carnival_deception_submissions s
        JOIN carnival_participants p ON p.id = s.participant_id WHERE s.round_id = ? ORDER BY s.participant_id, s.submission_number]], { roundId }) or {}
    local latest, all = {}, {}
    for _, r in ipairs(rows) do
        r.selections = Carnival.Db.decode(r.selections, {})
        latest[r.participant_id] = r
        all[#all + 1] = r
    end
    return latest, all
end

local function mark(selections)
    local correct, incorrect = 0, 0
    for _, id in ipairs(selections) do
        if current.key[id] then correct = correct + 1 else incorrect = incorrect + 1 end
    end
    return correct, incorrect
end

local function computeResults()
    local m = current.mystery
    local latest = latestSubmissions(current.id)
    local perfectEarliest
    local lines = {}
    for pid, sub in pairs(latest) do
        local correct, incorrect = mark(sub.selections)
        local perfect = correct == m.liarCount and incorrect == 0
        local auto
        if m.partialCredit then
            auto = correct * m.pointsPerCorrect - incorrect * m.penaltyPerIncorrect
        else
            auto = perfect and (m.liarCount * m.pointsPerCorrect) or -(incorrect * m.penaltyPerIncorrect)
        end
        if perfect then
            auto = auto + m.perfectBonus
            if not perfectEarliest or sub.created_at < perfectEarliest.created_at or (sub.created_at == perfectEarliest.created_at and sub.id < perfectEarliest.id) then
                perfectEarliest = sub
            end
        end
        lines[pid] = { participantId = pid, name = sub.display_name, submissionId = sub.id, selections = sub.selections, explanation = sub.explanation,
            correct = correct, incorrect = incorrect, perfect = perfect, auto = auto, tieBreak = 0 }
    end
    if m.tieBreak == 'earliest_submission' and perfectEarliest and (m.tieBreakBonus or 0) > 0 then
        local l = lines[perfectEarliest.participant_id]
        l.tieBreak = m.tieBreakBonus
        l.auto = l.auto + m.tieBreakBonus
    end
    local out = {}
    for _, l in pairs(lines) do
        l.total = l.auto
        out[#out + 1] = l
    end
    table.sort(out, function(a, b) return a.total > b.total end)
    return out
end

---------------------------------------------------------------------------
-- Participant endpoints
---------------------------------------------------------------------------
Api.register('deception.public', {
    rate = 'participant',
    handler = function(ctx)
        local p, session, msg = Carnival.Attractions.eligibility(ctx.source, ID, { skipTicket = true })
        if not p then return nil, session, msg end
        if not current or current.session_id ~= session.id then return { active = false } end
        return participantState(p.id)
    end,
})

Api.register('deception.submit', {
    rate = 'action',
    handler = function(ctx, payload)
        local p, session, msg = Carnival.Attractions.eligibility(ctx.source, ID)
        if not p then return nil, session, msg end
        if not current or current.session_id ~= session.id then return nil, 'invalid', 'There is no mystery running for your group.' end
        if V.id(payload.roundId) ~= current.id then return nil, 'stale', 'That mystery has ended.' end
        if current.status ~= 'questioning' then return nil, 'closed', 'Submissions are closed.' end
        return Carnival.withLock('deception:' .. p.id, function()
            local used = submissionCount(current.id, p.id)
            if used >= cfg().maxSubmissions then return nil, 'limit', 'You have no submissions left.' end
            local valid = U.toSet(U.map(current.mystery.performers, function(x) return x.id end))
            local sel, seen = {}, {}
            for _, id in ipairs(type(payload.selections) == 'table' and payload.selections or {}) do
                if type(id) ~= 'string' or not valid[id] or seen[id] then
                    Carnival.Monitor.log('warning', 'invalid_request', 'deception_bad_selection', { participantId = p.id, attractionId = ID })
                    return nil, 'invalid', 'Invalid selection.'
                end
                seen[id] = true
                sel[#sel + 1] = id
            end
            if #sel ~= current.mystery.liarCount then
                return nil, 'invalid', ('Choose exactly %d performers.'):format(current.mystery.liarCount)
            end
            local explanation = payload.explanation and V.text(payload.explanation, 1000, true) or nil
            local id = Carnival.Db.insertRow('carnival_deception_submissions', {
                round_id = current.id, participant_id = p.id, submission_number = used + 1,
                selections = json.encode(sel), explanation = explanation ~= '' and explanation or nil, created_at = os.time(),
            })
            if not id then return nil, 'duplicate', 'That submission was already recorded.' end
            Carnival.Monitor.log('info', 'attraction', 'deception_submission', { participantId = p.id, attractionId = ID, details = { roundId = current.id, number = used + 1 } })
            Carnival.Push.invalidate('deception')
            if everyoneSubmitted() then
                local sessionId = current.session_id
                CreateThread(function()
                    Wait(5000)
                    if current and current.session_id == sessionId and current.status == 'questioning' then
                        finishSelf('Every investigator has accused')
                        local s = Carnival.Rotation.sessionById(sessionId)
                        if s and s.status == C.SESSION_STATUS.ACTIVE then Carnival.Rotation.completeSession(s.id, Carnival.Identity.SYSTEM, 'Mystery solved') end
                    end
                end)
            end
            return { submissionNumber = used + 1, remaining = cfg().maxSubmissions - used - 1 }
        end)
    end,
})

---------------------------------------------------------------------------
-- Running a mystery
---------------------------------------------------------------------------
local function setupRound(session, m)
    local key = {}
    for _, p in ipairs(m.performers) do if p.isLiar then key[#key + 1] = p.id end end
    local e = Carnival.Events.active
    local id = Carnival.Db.insertRow('carnival_deception_rounds', {
        event_id = e.id, session_id = session.id, mystery_id = m.id, mystery_snapshot = json.encode(m),
        answer_key = json.encode(key), performer_assignments = '{}', status = 'setup',
        operator_license = 'system', created_at = os.time(),
    })
    if not id then return nil end
    current = loadRound(Carnival.Db.single('SELECT * FROM carnival_deception_rounds WHERE id = ?', { id }))
    Carnival.Push.invalidate('deception')
    return current
end

-- Score the current round exactly once (closed or revealed). Returns lines or nil.
local function commitRound(note, actor)
    do
        local n = Carnival.Db.update("UPDATE carnival_deception_rounds SET status = 'committed', committed_at = ?, judging_note = ? WHERE id = ? AND status IN ('closed', 'revealed')",
            { os.time(), note, current.id })
        if not n or n < 1 then return nil end
        local wasRevealed = current.status == 'revealed'
        current.status = 'committed'
        local lines = computeResults()
        local session = Carnival.Rotation.sessionById(current.session_id)
        for _, l in ipairs(lines) do
            if l.auto ~= 0 then
                Carnival.Scoring.award({
                    participantId = l.participantId, delta = l.auto, key = ('deception:%d:%d:auto'):format(current.id, l.participantId),
                    txType = l.auto > 0 and 'award' or 'penalty', source = 'deception_answer',
                    reason = ('%s: %d correct, %d wrong'):format(current.mystery.title, l.correct, l.incorrect),
                    attractionId = ID, sessionId = current.session_id, roundNumber = session and session.round_number or nil, actor = actor,
                    publicReason = ('%d liar(s) unmasked'):format(l.correct),
                })
            end
            Carnival.Db.update('UPDATE carnival_deception_submissions SET correct_count = ?, incorrect_count = ?, auto_points = ?, judged_by = ? WHERE id = ?',
                { l.correct, l.incorrect, l.auto, actor.license, l.submissionId })
        end
        Carnival.Audit.record(actor, 'deception_results_committed', { targetType = 'deception_round', targetId = current.id, reason = note,
            details = { lines = #lines } })
        if not wasRevealed then
            current.status = 'revealed'
            pushGroup('revealed')
            current.status = 'committed'
        end
        Carnival.Push.invalidate('deception')
        -- walk-up: the mystery is over, so is the visit for every investigator
        if Carnival.Rotation.isWalkup() then
            local sessionId = current.session_id
            CreateThread(function() Carnival.Rotation.runFinished(sessionId, 'Mystery solved') end)
        end
        return lines
    end
end

---------------------------------------------------------------------------
-- Self-service: start on arrival, timed clues, automatic marking
---------------------------------------------------------------------------
local function startQuestioning()
    local now = os.time()
    persist({ status = 'questioning', questioning_started_at = now, questioning_ends_at = now + cfg().durationSeconds })
    pushGroup('open')
end

-- Close, mark, reveal and complete the group's visit (self-service only).
finishSelf = function(reason)
    if not current or current.status == 'committed' then return end
    if current.status == 'questioning' or current.status == 'setup' then
        persist({ status = 'closed', questioning_ended_at = os.time() })
    end
    Carnival.withLock('deception:commit', function()
        if current and current.status ~= 'committed' then commitRound(reason, Carnival.Identity.SYSTEM) end
    end)
    Carnival.Monitor.log('info', 'attraction', 'deception_self_finished', { attractionId = ID, details = { reason = reason } })
end

local function releaseDueClues(now)
    if not current or current.status ~= 'questioning' or not current.questioning_started_at then return end
    local interval = cfg().clueIntervalSeconds
    local due = math.floor((now - current.questioning_started_at) / interval)
    local released = U.toSet(U.map(releasedClues(current.id), function(c) return c.clue_id end))
    local n = U.count(released)
    for _, clue in ipairs(current.mystery.clues or {}) do
        if n >= due then break end
        if not released[clue.id] then
            Carnival.Db.insertRow('carnival_deception_clues', { round_id = current.id, clue_id = clue.id, clue_text = clue.text, released_by = 'system', released_at = now })
            n = n + 1
            pushGroup('clue')
        end
    end
end

everyoneSubmitted = function()
    local session = current and Carnival.Rotation.sessionById(current.session_id)
    if not session then return false end
    local members = Carnival.Rotation.sessionMembers(session, true)
    if #members == 0 then return false end
    for _, p in ipairs(members) do
        if submissionCount(current.id, p.id) == 0 then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
Carnival.Attractions.register({
    id = ID,
    isBusy = function() return current ~= nil and current.status == 'questioning' end,
    -- walk-up: investigators may join until accusations close
    canJoin = function(session)
        if not current or current.session_id ~= session.id then return true end
        return current.status == 'questioning' or current.status == 'setup'
    end,
    onSessionStart = function(session)
        -- The previous group's committed round is no longer current.
        if current and current.status == 'committed' then current = nil end
        if not current then
            local m = mysteryById(cfg().defaultMystery) or cfg().mysteries[1]
            if m and setupRound(session, U.deepCopy(m)) then startQuestioning() end
        end
    end,
    onTimerExpired = function()
        if current and current.status ~= 'committed' then finishSelf('Round timer expired') end
        return 'complete'
    end,
    onSessionEnd = function(session)
        if current and current.session_id == session.id and current.status ~= 'committed' then
            finishSelf('Group moved on')
        end
    end,
    onPause = function()
        if current and current.status == 'questioning' then
            current.paused_remaining = math.max(0, (current.questioning_ends_at or os.time()) - os.time())
        end
    end,
    onResume = function()
        if current and current.status == 'questioning' and current.paused_remaining then
            persist({ questioning_ends_at = os.time() + current.paused_remaining })
            current.paused_remaining = nil
            pushGroup('open')
        end
    end,
    recover = function(e)
        current = nil
        local row = Carnival.Db.single("SELECT * FROM carnival_deception_rounds WHERE event_id = ? AND status <> 'committed' ORDER BY id DESC LIMIT 1", { e.id })
        if row then
            current = loadRound(row)
            if current.status == 'questioning' then
                current.paused_remaining = math.max(0, (current.questioning_ends_at or os.time()) - os.time())
            end
        end
    end,
    staffSummary = function()
        return current and { status = current.status, mystery = current.mystery.title } or nil
    end,
})

Carnival.onTick('deception', function(now)
    if Carnival.Events.state() == C.STATES.PAUSED then return end
    releaseDueClues(now)
    if current and current.status == 'questioning' and current.questioning_ends_at and now >= current.questioning_ends_at then
        local sessionId = current.session_id
        finishSelf('Questioning time is up')
        local s = Carnival.Rotation.sessionById(sessionId)
        if s and s.status == C.SESSION_STATUS.ACTIVE then Carnival.Rotation.completeSession(s.id, Carnival.Identity.SYSTEM, 'Mystery solved (time up)') end
    end
end)

