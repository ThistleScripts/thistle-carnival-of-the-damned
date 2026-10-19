-- Attraction: The Hall of Deception.
-- Participants question performers and submit which of them are lying. The answer
-- key, performer statements and private briefs are kept server-side and only sent
-- to staff with `deception.secrets` (full key) or to the performer assigned to a
-- profile (their own brief). Participants receive the solution only on reveal.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api
local ID = 'deception'
local OP = 'attractions.operate.deception'

local current = nil  -- { row fields..., mystery, key = set, assignments = { [profileId] = { license, name } } }
local setupRound, commitRound
local selfMode, finishSelf, everyoneSubmitted

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
    for _, p in ipairs(Carnival.Participants.members(session.colour, true)) do
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
    row.assignments = Carnival.Db.decode(row.performer_assignments, {}) or {}
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

-- adjustments: { [pid] = { judgePoints, note } }
local function computeResults(adjustments)
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
        local adj = adjustments[pid] or {}
        local judge = U.clamp(math.tointeger(adj.judgePoints or 0) or 0, 0, m.reasoningMaxPoints or 0)
        lines[pid] = { participantId = pid, name = sub.display_name, submissionId = sub.id, selections = sub.selections, explanation = sub.explanation,
            correct = correct, incorrect = incorrect, perfect = perfect, auto = auto, judge = judge, tieBreak = 0, note = adj.note }
    end
    if m.tieBreak == 'earliest_submission' and perfectEarliest and (m.tieBreakBonus or 0) > 0 then
        local l = lines[perfectEarliest.participant_id]
        l.tieBreak = m.tieBreakBonus
        l.auto = l.auto + m.tieBreakBonus
    end
    local out = {}
    for _, l in pairs(lines) do
        l.total = l.auto + l.judge
        out[#out + 1] = l
    end
    table.sort(out, function(a, b) return a.total > b.total end)
    return out
end

local function parseAdjustments(payload)
    local out = {}
    for _, a in ipairs(type(payload.adjustments) == 'table' and payload.adjustments or {}) do
        local pid = V.id(a.participantId)
        if pid then out[pid] = { judgePoints = V.int(a.judgePoints or 0, 0, 100000) or 0, note = a.note and V.text(a.note, 500, true) or nil } end
    end
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
            if selfMode() and everyoneSubmitted() then
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
-- Staff endpoints
---------------------------------------------------------------------------
local function staffSession(ctx)
    local s, code, msg = Carnival.Attractions.requireOperator(ctx, ID)
    if s == nil then return nil, code, msg end
    return s
end

local function staffState(ctx)
    local secrets = ctx:has('deception.secrets')
    local session = Carnival.Rotation.sessionFor(ID)
    local out = {
        session = session, canSeeSecrets = secrets,
        mysteries = U.map(cfg().mysteries, function(m) return { id = m.id, title = m.title, liarCount = m.liarCount, performers = #m.performers } end),
        defaultMystery = cfg().defaultMystery, maxSubmissions = cfg().maxSubmissions,
        staff = Carnival.Perms.onlineStaff(), serverTime = os.time(),
    }
    if not current then return out end
    local m = current.mystery
    local r = {
        id = current.id, status = current.status, endsAt = current.questioning_ends_at,
        mystery = publicMystery(m), clues = U.map(m.clues or {}, function(c) return { id = c.id, text = c.text } end),
        released = U.map(releasedClues(current.id), function(c) return c.clue_id end),
        assignments = current.assignments,
    }
    if secrets then
        r.answerKey = solution()
        r.performers = m.performers
    end
    local _, all = latestSubmissions(current.id)
    r.submissions = U.map(all, function(s)
        local row = { id = s.id, participantId = s.participant_id, name = s.display_name, number = s.submission_number,
            selections = s.selections, explanation = s.explanation, createdAt = s.created_at, recordedBy = s.recorded_by }
        if secrets then row.correct, row.incorrect = mark(s.selections) end
        return row
    end)
    if session then
        r.members = U.map(Carnival.Participants.members(session.colour, false), function(p)
            return { id = p.id, name = p.display_name, online = Carnival.Participants.sourceOf(p.id) ~= nil, used = submissionCount(current.id, p.id) }
        end)
    end
    out.round = r
    return out
end

-- Brief for the performer(s) assigned to the caller.
local function myBrief(ctx)
    if not current then return { assigned = {} } end
    local license = ctx.actor.license
    local out = {}
    for profileId, a in pairs(current.assignments) do
        if a.license == license then
            for _, p in ipairs(current.mystery.performers) do
                if p.id == profileId then
                    out[#out + 1] = { id = p.id, name = p.name, profile = p.profile, statements = p.statements, isLiar = p.isLiar, brief = p.brief }
                end
            end
        end
    end
    return { assigned = out, mystery = { title = current.mystery.title, rules = current.mystery.rules }, status = current.status }
end

setupRound = function(session, m, actor, custom)
    local key = {}
    for _, p in ipairs(m.performers) do if p.isLiar then key[#key + 1] = p.id end end
    local e = Carnival.Events.active
    local id = Carnival.Db.insertRow('carnival_deception_rounds', {
        event_id = e.id, session_id = session.id, mystery_id = m.id, mystery_snapshot = json.encode(m),
        answer_key = json.encode(key), performer_assignments = '{}', status = 'setup',
        operator_license = actor.license, created_at = os.time(),
    })
    if not id then return nil end
    current = loadRound(Carnival.Db.single('SELECT * FROM carnival_deception_rounds WHERE id = ?', { id }))
    Carnival.Audit.record(actor, 'deception_round_setup', { targetType = 'deception_round', targetId = id, details = { mystery = m.id, custom = custom } })
    Carnival.Push.invalidate('deception')
    return current
end

local function setup(ctx, payload)
    local session, code, msg = staffSession(ctx)
    if not session then return nil, code or 'no_session', msg or 'No group is at the hall right now.' end
    if current and current.status ~= 'committed' and current.session_id == session.id then
        return nil, 'invalid', 'A mystery is already set up for this group.'
    end
    local m
    if payload.custom then
        if not ctx:has('deception.secrets') then return nil, 'forbidden', 'Creating a mystery requires access to secret answers.' end
        local tree = U.deepCopy(Carnival.Config.get())
        tree.attractions.deception.mysteries = { payload.custom }
        tree.attractions.deception.defaultMystery = type(payload.custom) == 'table' and payload.custom.id or ''
        local normalised, errors = Carnival.Validate.config(tree)
        if #errors > 0 then return nil, 'invalid', errors[1].path .. ': ' .. errors[1].message end
        m = normalised.attractions.deception.mysteries[1]
    else
        local found = type(payload.mysteryId) == 'string' and mysteryById(payload.mysteryId)
        if not found then return nil, 'invalid', 'Choose a mystery.' end
        m = U.deepCopy(found)
    end
    if not setupRound(session, m, ctx.actor, payload.custom ~= nil) then return nil, 'database_error' end
    return staffState(ctx)
end

local function requireRound(statuses)
    if not current then return nil, 'invalid', 'No mystery is set up.' end
    if statuses and not U.toSet(statuses)[current.status] then return nil, 'invalid', ('The mystery is %s.'):format(current.status) end
    return current
end

local function assign(ctx, payload)
    local s, code, msg = staffSession(ctx)
    if s == nil then return nil, code, msg end
    local r, c2, m2 = requireRound({ 'setup', 'questioning', 'closed' })
    if not r then return nil, c2, m2 end
    local profileId = type(payload.profileId) == 'string' and payload.profileId or nil
    local profile = profileId and U.find(current.mystery.performers, function(p) return p.id == profileId end)
    if not profile then return nil, 'invalid', 'Unknown performer profile.' end
    local prev = current.assignments[profileId]
    if payload.source == nil or payload.source == false then
        current.assignments[profileId] = nil
    else
        local target = V.int(payload.source, 1, 65535)
        if not target or not GetPlayerName(target) then return nil, 'invalid', 'That staff member is not online.' end
        if not Carnival.Perms.has(target, OP) then return nil, 'invalid', 'That player is not a Hall of Deception performer/operator.' end
        current.assignments[profileId] = { license = Carnival.Identity.license(target), name = Carnival.Identity.characterName(target) }
        Carnival.Push.send(target, 'deception', { action = 'brief_assigned', profile = profile.name })
    end
    persist({ performer_assignments = json.encode(current.assignments) })
    Carnival.Audit.record(ctx.actor, 'deception_performer_assigned', { targetType = 'deception_round', targetId = current.id,
        details = { profile = profileId, to = current.assignments[profileId] and current.assignments[profileId].name or nil, from = prev and prev.name or nil } })
    Carnival.Push.invalidate('deception')
    return true
end

local function control(ctx, action, payload)
    local s, code, msg = staffSession(ctx)
    if s == nil then return nil, code, msg end
    local now = os.time()
    if action == 'start' then
        local r, c2, m2 = requireRound({ 'setup' })
        if not r then return nil, c2, m2 end
        local e = Carnival.Events.active
        if not e or not C.LIVE_STATES[e.state] then return nil, 'not_live', 'The event is not running.' end
        persist({ status = 'questioning', questioning_started_at = now, questioning_ends_at = now + cfg().durationSeconds })
        pushGroup('open')
    elseif action == 'end' then
        local r, c2, m2 = requireRound({ 'questioning' })
        if not r then return nil, c2, m2 end
        persist({ status = 'closed', questioning_ended_at = now })
        pushGroup('closed')
    elseif action == 'clue' then
        local r, c2, m2 = requireRound({ 'setup', 'questioning', 'closed' })
        if not r then return nil, c2, m2 end
        local clue = U.find(current.mystery.clues or {}, function(c) return c.id == payload.clueId end)
        if not clue then return nil, 'invalid', 'Unknown clue.' end
        local id = Carnival.Db.insertRow('carnival_deception_clues', { round_id = current.id, clue_id = clue.id, clue_text = clue.text, released_by = ctx.actor.license, released_at = now })
        if not id then return nil, 'invalid', 'That clue was already released.' end
        pushGroup('clue')
    elseif action == 'reveal' then
        local r, c2, m2 = requireRound({ 'closed', 'questioning' })
        if not r then return nil, c2, m2 end
        if current.status == 'questioning' then persist({ questioning_ended_at = now }) end
        persist({ status = 'revealed', revealed_at = now })
        pushGroup('revealed')
    else
        return nil, 'invalid', 'Unknown action.'
    end
    Carnival.Audit.record(ctx.actor, 'deception_' .. action, { targetType = 'deception_round', targetId = current.id, details = { clue = payload and payload.clueId } })
    Carnival.Push.invalidate('deception')
    return true
end

local function record(ctx, payload)
    local s, code, msg = staffSession(ctx)
    if s == nil then return nil, code, msg end
    local r, c2, m2 = requireRound({ 'questioning', 'closed' })
    if not r then return nil, c2, m2 end
    local pid = V.id(payload.participantId)
    local p = pid and Carnival.Participants.get(pid)
    local session = Carnival.Rotation.sessionById(current.session_id)
    if not p or not session or p.colour ~= session.colour or p.status ~= 'active' then return nil, 'invalid', 'Participant is not in this group.' end
    local used = submissionCount(current.id, pid)
    if used >= cfg().maxSubmissions then return nil, 'limit', 'That participant has no submissions left.' end
    local valid = U.toSet(U.map(current.mystery.performers, function(x) return x.id end))
    local sel, seen = {}, {}
    for _, id in ipairs(type(payload.selections) == 'table' and payload.selections or {}) do
        if not valid[id] or seen[id] then return nil, 'invalid', 'Invalid selection.' end
        seen[id] = true
        sel[#sel + 1] = id
    end
    if #sel ~= current.mystery.liarCount then return nil, 'invalid', ('Choose exactly %d performers.'):format(current.mystery.liarCount) end
    local id = Carnival.Db.insertRow('carnival_deception_submissions', {
        round_id = current.id, participant_id = pid, submission_number = used + 1, selections = json.encode(sel),
        explanation = payload.explanation and V.text(payload.explanation, 1000, true) or nil, recorded_by = ctx.actor.license, created_at = os.time(),
    })
    if not id then return nil, 'duplicate' end
    Carnival.Audit.record(ctx.actor, 'deception_answer_recorded', { targetType = 'participant', targetId = pid, details = { roundId = current.id } })
    Carnival.Push.invalidate('deception')
    return { submissionNumber = used + 1 }
end

local function preview(ctx, payload)
    local s, code, msg = staffSession(ctx)
    if s == nil then return nil, code, msg end
    local r, c2, m2 = requireRound({ 'closed', 'revealed' })
    if not r then return nil, c2, m2 end
    return { lines = computeResults(parseAdjustments(payload)), solution = solution() }
end

local function commit(ctx, payload)
    local s, code, msg = staffSession(ctx)
    if s == nil then return nil, code, msg end
    return Carnival.withLock('deception:commit', function()
        if not current or current.id ~= V.id(payload.roundId) then
            local row = V.id(payload.roundId) and Carnival.Db.single('SELECT status FROM carnival_deception_rounds WHERE id = ?', { V.id(payload.roundId) })
            if row and row.status == 'committed' then return { alreadyCommitted = true } end
            return nil, 'invalid', 'That mystery is not awaiting judgement.'
        end
        if current.status == 'committed' then return { alreadyCommitted = true } end
        if current.status ~= 'closed' and current.status ~= 'revealed' then return nil, 'invalid', 'End questioning first.' end
        local note = payload.note and V.text(payload.note, 1000, true) or ''
        local lines = commitRound(parseAdjustments(payload), note, ctx.actor)
        if not lines then return { alreadyCommitted = true } end
        return { lines = lines }
    end)
end

-- Score the current round exactly once (closed or revealed). Returns lines or nil.
commitRound = function(adjustments, note, actor)
    do
        local n = Carnival.Db.update("UPDATE carnival_deception_rounds SET status = 'committed', committed_at = ?, judging_note = ? WHERE id = ? AND status IN ('closed', 'revealed')",
            { os.time(), note, current.id })
        if not n or n < 1 then return nil end
        local wasRevealed = current.status == 'revealed'
        current.status = 'committed'
        local lines = computeResults(adjustments)
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
            if l.judge > 0 then
                Carnival.Scoring.award({
                    participantId = l.participantId, delta = l.judge, key = ('deception:%d:%d:judge'):format(current.id, l.participantId),
                    txType = 'bonus', source = 'deception_reasoning', reason = l.note or 'Reasoning judged by staff',
                    attractionId = ID, sessionId = current.session_id, roundNumber = session and session.round_number or nil, actor = actor,
                    publicReason = 'Sharp reasoning',
                })
            end
            Carnival.Db.update('UPDATE carnival_deception_submissions SET correct_count = ?, incorrect_count = ?, auto_points = ?, judge_points = ?, judge_note = ?, judged_by = ? WHERE id = ?',
                { l.correct, l.incorrect, l.auto, l.judge, l.note, actor.license, l.submissionId })
        end
        Carnival.Audit.record(actor, 'deception_results_committed', { targetType = 'deception_round', targetId = current.id, reason = note,
            details = { lines = #lines } })
        if not wasRevealed then
            current.status = 'revealed'
            pushGroup('revealed')
            current.status = 'committed'
        end
        Carnival.Push.invalidate('deception')
        return lines
    end
end

---------------------------------------------------------------------------
-- Self-service: start on arrival, timed clues, automatic marking
---------------------------------------------------------------------------
selfMode = function() return cfg().mode == 'self' end

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
        if current and current.status ~= 'committed' then commitRound({}, reason, Carnival.Identity.SYSTEM) end
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
    local members = Carnival.Participants.members(session.colour, true)
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
    onSessionStart = function(session)
        -- The previous group's committed round is no longer current.
        if current and current.status == 'committed' then current = nil end
        if selfMode() and not current then
            local m = mysteryById(cfg().defaultMystery) or cfg().mysteries[1]
            if m and setupRound(session, U.deepCopy(m), Carnival.Identity.SYSTEM, false) then startQuestioning() end
        end
    end,
    onTimerExpired = function()
        if selfMode() and current and current.status ~= 'committed' then finishSelf('Round timer expired') end
        return 'complete'
    end,
    onSessionEnd = function(session)
        if selfMode() and current and current.session_id == session.id and current.status ~= 'committed' then
            finishSelf('Group moved on')
            return
        end
        if current and current.session_id == session.id then
            if current.status == 'questioning' then persist({ status = 'closed', questioning_ended_at = os.time() }) end
            pushGroup('closed')
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
    if selfMode() then releaseDueClues(now) end
    if current and current.status == 'questioning' and current.questioning_ends_at and now >= current.questioning_ends_at then
        if selfMode() then
            local sessionId = current.session_id
            finishSelf('Questioning time is up')
            local s = Carnival.Rotation.sessionById(sessionId)
            if s and s.status == C.SESSION_STATUS.ACTIVE then Carnival.Rotation.completeSession(s.id, Carnival.Identity.SYSTEM, 'Mystery solved (time up)') end
            return
        end
        persist({ status = 'closed', questioning_ended_at = now })
        pushGroup('closed')
        Carnival.Monitor.log('info', 'countdown', 'deception_questioning_closed', { attractionId = ID })
        Carnival.Push.invalidate('deception')
    end
end)

Api.register('deception.staff.state', { perm = OP, rate = 'staff', handler = function(ctx) return staffState(ctx) end })
Api.register('deception.myBrief', { perm = OP, rate = 'staff', handler = myBrief })
Api.register('deception.setup', { perm = OP, rate = 'staff', handler = setup })
Api.register('deception.assign', { perm = OP, rate = 'staff', handler = assign })
for _, action in ipairs({ 'start', 'end', 'clue', 'reveal' }) do
    Api.register('deception.' .. action, { perm = OP, rate = 'staff', handler = function(ctx, payload) return control(ctx, action, payload) end })
end
Api.register('deception.record', { perm = OP, rate = 'staff', handler = record })
Api.register('deception.preview', { perm = { OP, 'deception.secrets' }, rate = 'staff', handler = preview })
Api.register('deception.commit', { perm = { OP, 'deception.secrets' }, rate = 'staff', handler = commit })
