-- Central, server-authoritative scoring ledger.
--
-- Every point change is a row in carnival_score_transactions with a unique
-- (event_id, idempotency_key). The ledger row, the per-attraction summary and the
-- participant total are written in ONE database transaction. Callers must
-- supply a deterministic idempotency key derived from the thing being scored
-- (spin id, token id, performance id...), so retries and replays can never
-- award twice. There is no client-facing endpoint that awards points.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local S = C.STATES
local Scoring = {}
Carnival.Scoring = Scoring

local summaries = {}   -- [pid][attractionKey] = { points, positive, negative, tx_count }
local stats = {}       -- [pid] = { deductions, goldTokens }

local GENERAL = 'general'

function Scoring.loadForEvent(eventId)
    summaries, stats = {}, {}
    if not eventId then return end
    for _, r in ipairs(Carnival.Db.query('SELECT * FROM carnival_score_summaries WHERE event_id = ?', { eventId }) or {}) do
        summaries[r.participant_id] = summaries[r.participant_id] or {}
        summaries[r.participant_id][r.attraction_id] = { points = r.points, positive = r.positive, negative = r.negative, tx_count = r.tx_count }
    end
    for _, r in ipairs(Carnival.Db.query([[SELECT participant_id,
            SUM(CASE WHEN delta < 0 THEN 1 ELSE 0 END) AS deductions,
            SUM(CASE WHEN source = 'horror_token_gold' THEN 1 ELSE 0 END) AS gold
        FROM carnival_score_transactions WHERE event_id = ? GROUP BY participant_id]], { eventId }) or {}) do
        stats[r.participant_id] = { deductions = tonumber(r.deductions) or 0, goldTokens = tonumber(r.gold) or 0 }
    end
end

function Scoring.ensureParticipant(pid)
    summaries[pid] = summaries[pid] or {}
    stats[pid] = stats[pid] or { deductions = 0, goldTokens = 0 }
end

function Scoring.breakdown(pid)
    local out = {}
    for k, v in pairs(summaries[pid] or {}) do out[k] = v.points end
    return out
end

function Scoring.attractionPoints(pid, attractionId)
    local s = summaries[pid] and summaries[pid][attractionId or GENERAL]
    return s and s.points or 0
end

function Scoring.stats(pid)
    local st = stats[pid] or { deductions = 0, goldTokens = 0 }
    local maxA = 0
    for k, v in pairs(summaries[pid] or {}) do
        if k ~= GENERAL and v.points > maxA then maxA = v.points end
    end
    return { deductions = st.deductions, goldTokens = st.goldTokens, highestAttraction = maxA }
end

local STAFF_TYPES = { adjustment = true, correction = true, reversal = true }

-- opts: participantId, delta, key, txType, source, reason, attractionId, sessionId,
--       roundNumber, actor, reversesTx, skipAttractionCap
-- Returns true, tx  |  false, code, message
function Scoring.award(opts)
    local e = Carnival.Events.active
    if not e then return false, 'no_event', 'There is no active event.' end
    local p = Carnival.Participants.get(opts.participantId)
    if not p then return false, 'not_found', 'Participant not found.' end
    if p.event_id ~= e.id then return false, 'stale_event', 'Participant belongs to another event.' end
    local txType = opts.txType or 'award'
    local isStaff = STAFF_TYPES[txType] == true
    if p.status ~= 'active' and not isStaff then return false, 'participant_inactive', 'Participant is not active.' end

    if e.state == S.COMPLETED or e.state == S.CANCELLED then
        return false, 'event_closed', 'The event is closed; results are frozen.'
    end
    if not isStaff and not C.LIVE_STATES[e.state] then
        return false, 'event_not_live', 'Scoring is not open right now.'
    end
    if e.state == S.FINAL and not isStaff then
        return false, 'event_final', 'Final results are being prepared.'
    end

    local key = opts.key
    if type(key) ~= 'string' or key == '' or #key > 128 then return false, 'bad_key', 'Missing idempotency key.' end
    local requested = math.tointeger(opts.delta) or math.floor(tonumber(opts.delta) or 0)
    local actor = opts.actor

    return Carnival.withLock('score:' .. p.id, function()
        local existing = Carnival.Db.single('SELECT id, delta, previous_total, resulting_total FROM carnival_score_transactions WHERE event_id = ? AND idempotency_key = ?', { e.id, key })
        if existing then
            Carnival.Monitor.log('info', 'duplicate', 'duplicate_score_prevented', { participantId = p.id, attractionId = opts.attractionId, details = { key = key } })
            return true, { id = existing.id, delta = existing.delta, previous = existing.previous_total, total = existing.resulting_total, duplicate = true }
        end

        local cfg = Carnival.Config.get()
        local attrKey = opts.attractionId or GENERAL
        Scoring.ensureParticipant(p.id)
        local sum = summaries[p.id][attrKey] or { points = 0, positive = 0, negative = 0, tx_count = 0 }
        local total = p.total_score or 0
        local delta = requested
        local clampNote

        if delta > 0 and opts.attractionId and not opts.skipAttractionCap and not isStaff then
            local cap = cfg.attractions[opts.attractionId] and cfg.attractions[opts.attractionId].maxScore or 0
            if cap > 0 and sum.points + delta > cap then
                delta = math.max(0, cap - sum.points)
                clampNote = 'attraction_cap'
            end
        end
        if delta > 0 and cfg.scoring.maxTotal > 0 and total + delta > cfg.scoring.maxTotal then
            delta = math.max(0, cfg.scoring.maxTotal - total)
            clampNote = 'event_cap'
        end
        if delta < 0 and not cfg.scoring.allowNegativeTotal and total + delta < 0 then
            delta = -math.max(0, total)
            clampNote = 'no_negative_total'
        end

        local now = os.time()
        local resulting = total + delta
        local reason = opts.reason and U.sanitizeText(opts.reason, 500) or nil
        if clampNote then reason = ((reason or '') .. ' [clamped: ' .. clampNote .. ']') end

        local insSql, insParams = Carnival.Db.buildInsert('carnival_score_transactions', {
            event_id = e.id, participant_id = p.id, citizenid = p.citizenid,
            attraction_id = opts.attractionId, round_number = opts.roundNumber, session_id = opts.sessionId,
            requested_delta = requested, delta = delta, previous_total = total, resulting_total = resulting,
            tx_type = txType, source = opts.source or txType, reason = reason,
            staff_license = actor and actor.license ~= 'system' and actor.license or nil,
            staff_name = actor and actor.license ~= 'system' and actor.name or nil,
            reverses_tx = opts.reversesTx, idempotency_key = key, created_at = now,
        })
        local queries = {
            { query = insSql, values = insParams },
            { query = [[INSERT INTO carnival_score_summaries (event_id, participant_id, attraction_id, points, positive, negative, tx_count, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, 1, ?)
                ON DUPLICATE KEY UPDATE points = points + VALUES(points), positive = positive + VALUES(positive),
                    negative = negative + VALUES(negative), tx_count = tx_count + 1, updated_at = VALUES(updated_at)]],
              values = { e.id, p.id, attrKey, delta, math.max(delta, 0), math.min(delta, 0), now } },
            { query = 'UPDATE carnival_participants SET total_score = total_score + ?, last_score_at = ?, first_score_at = COALESCE(first_score_at, ?) WHERE id = ?',
              values = { delta, now, now, p.id } },
        }
        local ok = Carnival.Db.transaction(queries)
        if not ok then
            local dup = Carnival.Db.single('SELECT id, delta, previous_total, resulting_total FROM carnival_score_transactions WHERE event_id = ? AND idempotency_key = ?', { e.id, key })
            if dup then
                return true, { id = dup.id, delta = dup.delta, previous = dup.previous_total, total = dup.resulting_total, duplicate = true }
            end
            Carnival.Monitor.log('error', 'score', 'score_write_failed', { participantId = p.id, attractionId = opts.attractionId, details = { key = key, delta = requested } })
            return false, 'database_error', 'The score could not be saved.'
        end
        local txId = Carnival.Db.scalar('SELECT id FROM carnival_score_transactions WHERE event_id = ? AND idempotency_key = ?', { e.id, key })

        -- caches
        sum.points = sum.points + delta
        sum.positive = sum.positive + math.max(delta, 0)
        sum.negative = sum.negative + math.min(delta, 0)
        sum.tx_count = sum.tx_count + 1
        summaries[p.id][attrKey] = sum
        p.total_score = resulting
        p.last_score_at = now
        p.first_score_at = p.first_score_at or now
        if delta < 0 then stats[p.id].deductions = stats[p.id].deductions + 1 end
        if opts.source == 'horror_token_gold' then stats[p.id].goldTokens = stats[p.id].goldTokens + 1 end

        Carnival.Monitor.log('info', 'score', delta >= 0 and 'points_awarded' or 'points_deducted', {
            participantId = p.id, attractionId = opts.attractionId, actor = actor, result = clampNote or 'ok',
            details = { delta = delta, requested = requested, total = resulting, type = txType, source = opts.source, key = key },
        })
        local s = Carnival.Participants.sourceOf(p.id)
        if s then
            Carnival.Push.send(s, 'score', {
                delta = delta, total = resulting, attraction = opts.attractionId, reason = opts.publicReason or opts.source, type = txType,
            })
        end
        Carnival.Leaderboard.markDirty()
        Carnival.Push.invalidate('scores')
        -- prize tickets for the prize counter (game scores only, never staff changes)
        if delta > 0 and not isStaff and txId and Carnival.Shop then
            local cok, cerr = pcall(Carnival.Shop.credit, p, { id = txId, delta = delta, attractionId = opts.attractionId, txType = txType }, e.id)
            if not cok then Carnival.Monitor.log('error', 'shop', 'prize_credit_failed', { participantId = p.id, details = { error = tostring(cerr), txId = txId } }) end
        end
        return true, { id = txId, delta = delta, requested = requested, previous = total, total = resulting, clamped = clampNote, duplicate = false }
    end)
end

-- Manual staff adjustment. requestId makes UI retries idempotent.
function Scoring.adjust(src, pid, delta, reason, requestId, attractionId)
    local cfg = Carnival.Config.get()
    if delta == 0 then return nil, 'invalid', 'Adjustment cannot be zero.' end
    if math.abs(delta) > cfg.scoring.maxManualAdjustment then
        return nil, 'invalid', ('Adjustments are limited to ±%d.'):format(cfg.scoring.maxManualAdjustment)
    end
    local actor = Carnival.Identity.actor(src)
    local ok, tx, msg = Scoring.award({
        participantId = pid, delta = delta, key = 'adjust:' .. requestId, txType = 'adjustment',
        source = 'manual', reason = reason, attractionId = attractionId, actor = actor,
    })
    if not ok then return nil, tx, msg end
    if not tx.duplicate then
        Carnival.Audit.record(actor, 'score_adjusted', { targetType = 'participant', targetId = pid, reason = reason,
            details = { delta = tx.delta, requested = delta, total = tx.total, txId = tx.id, attraction = attractionId } })
        Carnival.Leaderboard.onCorrection(actor, reason)
    end
    return tx
end

-- Reverse a transaction with a correction entry (the original row stays in the ledger).
function Scoring.reverse(src, txId, reason)
    local tx = Carnival.Db.single('SELECT * FROM carnival_score_transactions WHERE id = ?', { txId })
    if not tx then return nil, 'not_found', 'Transaction not found.' end
    if tx.event_id ~= Carnival.Events.activeId() then return nil, 'invalid', 'Only transactions of the active event can be corrected.' end
    if tx.delta == 0 then return nil, 'invalid', 'Nothing to reverse.' end
    if tx.reverses_tx then return nil, 'invalid', 'Corrections cannot be reversed; adjust instead.' end
    local actor = Carnival.Identity.actor(src)
    local ok, res, msg = Scoring.award({
        participantId = tx.participant_id, delta = -tx.delta, key = 'reverse:' .. tx.id, txType = 'correction',
        source = 'correction', reason = reason, attractionId = tx.attraction_id, actor = actor, reversesTx = tx.id,
    })
    if not ok then return nil, res, msg end
    if not res.duplicate then
        Carnival.Audit.record(actor, 'score_corrected', { targetType = 'score_transaction', targetId = tx.id, reason = reason,
            details = { participant = tx.participant_id, reversedDelta = tx.delta, appliedDelta = res.delta, txId = res.id } })
        Carnival.Leaderboard.onCorrection(actor, reason)
    end
    return res
end

-- Verify cached totals against the ledger. Returns a report.
function Scoring.verify(eventId)
    local report = { ok = true, totals = {}, summaries = {}, chains = {} }
    for _, r in ipairs(Carnival.Db.query([[SELECT p.id, p.total_score, COALESCE(SUM(t.delta), 0) AS ledger
        FROM carnival_participants p LEFT JOIN carnival_score_transactions t ON t.participant_id = p.id
        WHERE p.event_id = ? GROUP BY p.id, p.total_score HAVING p.total_score <> ledger]], { eventId }) or {}) do
        report.ok = false
        report.totals[#report.totals + 1] = { participantId = r.id, cached = r.total_score, ledger = tonumber(r.ledger) }
    end
    for _, r in ipairs(Carnival.Db.query([[SELECT s.participant_id, s.attraction_id, s.points,
            (SELECT COALESCE(SUM(t.delta), 0) FROM carnival_score_transactions t
             WHERE t.participant_id = s.participant_id AND COALESCE(t.attraction_id, 'general') = s.attraction_id) AS ledger
        FROM carnival_score_summaries s WHERE s.event_id = ?]], { eventId }) or {}) do
        if tonumber(r.ledger) ~= r.points then
            report.ok = false
            report.summaries[#report.summaries + 1] = { participantId = r.participant_id, attraction = r.attraction_id, cached = r.points, ledger = tonumber(r.ledger) }
        end
    end
    -- previous_total of each row must equal resulting_total of the row before it
    local rows = Carnival.Db.query('SELECT id, participant_id, previous_total, resulting_total, delta FROM carnival_score_transactions WHERE event_id = ? ORDER BY participant_id, id', { eventId }) or {}
    local last = {}
    for _, r in ipairs(rows) do
        local expectPrev = last[r.participant_id] or 0
        if r.previous_total ~= expectPrev or r.previous_total + r.delta ~= r.resulting_total then
            report.ok = false
            report.chains[#report.chains + 1] = { txId = r.id, participantId = r.participant_id }
        end
        last[r.participant_id] = r.resulting_total
    end
    report.transactions = #rows
    if not report.ok then
        Carnival.Monitor.log('critical', 'score', 'ledger_mismatch', { eventId = eventId, details = { totals = #report.totals, summaries = #report.summaries, chains = #report.chains } })
    end
    return report
end

function Scoring.transactions(filters, page, pageSize)
    local where, params = { 't.event_id = ?' }, { filters.eventId }
    if filters.participantId then where[#where + 1] = 't.participant_id = ?' params[#params + 1] = filters.participantId end
    if filters.attractionId then where[#where + 1] = 't.attraction_id = ?' params[#params + 1] = filters.attractionId end
    if filters.txType then where[#where + 1] = 't.tx_type = ?' params[#params + 1] = filters.txType end
    local whereSql = ' WHERE ' .. table.concat(where, ' AND ')
    local total = Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_score_transactions t' .. whereSql, params) or 0
    local lp = { table.unpack(params) }
    lp[#lp + 1] = pageSize
    lp[#lp + 1] = (page - 1) * pageSize
    local rows = Carnival.Db.query([[SELECT t.id, t.participant_id, p.display_name, t.attraction_id, t.round_number, t.requested_delta, t.delta,
            t.previous_total, t.resulting_total, t.tx_type, t.source, t.reason, t.staff_name, t.reverses_tx, t.created_at
        FROM carnival_score_transactions t JOIN carnival_participants p ON p.id = t.participant_id]] .. whereSql .. ' ORDER BY t.id DESC LIMIT ? OFFSET ?', lp) or {}
    return rows, total
end

---------------------------------------------------------------------------
-- API (staff only — there is deliberately no participant scoring endpoint)
---------------------------------------------------------------------------
local Api = Carnival.Api

Api.register('scores.adjust', {
    perm = 'scores.adjust', rate = 'staff',
    handler = function(ctx, payload)
        local v, code, msg = Api.validate(payload, {
            participantId = V.id,
            delta = function(x) return V.int(x, -1000000, 1000000) end,
            reason = function(x) return V.reason(x, true) end,
            requestId = V.requestId,
            attractionId = Api.optional(V.attraction),
        })
        if not v then return nil, code, msg end
        return Scoring.adjust(ctx.source, v.participantId, v.delta, v.reason, v.requestId, v.attractionId)
    end,
})

Api.register('scores.reverse', {
    perm = 'scores.adjust', rate = 'staff',
    handler = function(ctx, payload)
        local id, err = V.id(payload.txId)
        if not id then return nil, 'invalid', 'txId ' .. err end
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        return Scoring.reverse(ctx.source, id, reason)
    end,
})

Api.register('scores.transactions', {
    perm = 'scores.view', rate = 'staff',
    handler = function(ctx, payload)
        local eventId = payload.eventId and V.id(payload.eventId) or Carnival.Events.activeId()
        if not eventId then return { rows = {}, total = 0, page = 1, pageSize = 25 } end
        if eventId ~= Carnival.Events.activeId() and not ctx:has('events.history') then return nil, 'forbidden' end
        local page = V.int(payload.page or 1, 1, 100000) or 1
        local rows, total = Scoring.transactions({
            eventId = eventId,
            participantId = payload.participantId and V.id(payload.participantId) or nil,
            attractionId = payload.attractionId and V.attraction(payload.attractionId) or nil,
            txType = payload.txType and V.oneOf(payload.txType, { 'award', 'deduction', 'participation', 'bonus', 'penalty', 'adjustment', 'correction' }) or nil,
        }, page, 25)
        return { rows = rows, total = total, page = page, pageSize = 25 }
    end,
})

Api.register('scores.verify', {
    perm = { 'panel.admin', 'scores.adjust' }, rate = 'admin',
    handler = function(ctx, payload)
        local eventId = payload.eventId and V.id(payload.eventId) or Carnival.Events.activeId()
        if not eventId then return nil, 'invalid', 'No event selected.' end
        local report = Scoring.verify(eventId)
        Carnival.Audit.record(ctx.actor, 'score_ledger_verified', { eventId = eventId, targetType = 'event', targetId = eventId, details = { ok = report.ok, transactions = report.transactions } })
        return report
    end,
})
