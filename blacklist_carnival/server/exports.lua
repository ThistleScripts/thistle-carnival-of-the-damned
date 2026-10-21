-- Server exports for trusted server-side integrations.
-- Exports are callable only by other server resources (never by clients). Where an
-- export changes state on behalf of a player, pass that player's source as
-- `actorSource`: the same permission checks as the panel are applied. Passing 0
-- means "system" and is reserved for automated server-side integrations.
-- See docs/EXPORTS.md for argument and return documentation.

local C = Carnival.C

local function denied(actorSource, perm)
    if actorSource == 0 then return false end
    if not Carnival.Perms.has(actorSource, perm) then
        Carnival.Monitor.security(actorSource, 'permission_denied', { export = true, permission = perm }, 'permission')
        return true
    end
    return false
end

-- getCurrentEvent() -> table|nil
exports('getCurrentEvent', function()
    local st = Carnival.Events.publicState()
    if not st.active then return nil end
    return st
end)

-- isEligible(source, attractionId?) -> boolean, reasonCode
exports('isEligible', function(source, attractionId)
    if attractionId then
        local p, code = Carnival.Attractions.eligibility(source, attractionId, { skipDistance = true })
        return p ~= nil, p and nil or code
    end
    local p = Carnival.Participants.getBySource(source)
    if not p then return false, 'not_registered' end
    if p.status ~= 'active' then return false, 'inactive' end
    return true
end)

-- getParticipant(source) -> { id, name, colour, status, total, rank } | nil
exports('getParticipant', function(source)
    local p = Carnival.Participants.getBySource(source)
    if not p then return nil end
    return { id = p.id, name = p.display_name, colour = p.colour, status = p.status, total = p.total_score, rank = Carnival.Leaderboard.rankOf(p.id) }
end)

-- getScore(source) -> number|nil, breakdown table
exports('getScore', function(source)
    local p = Carnival.Participants.getBySource(source)
    if not p then return nil end
    return p.total_score, Carnival.Scoring.breakdown(p.id)
end)

-- awardPoints(targetSource, delta, reason, idempotencyKey, actorSource?, attractionId?)
-- -> ok, txOrErrorCode
-- Requires actorSource == 0 (system) or `scores.adjust`. idempotencyKey must be unique
-- per award; repeating a key returns the original transaction.
exports('awardPoints', function(targetSource, delta, reason, idempotencyKey, actorSource, attractionId)
    actorSource = actorSource or 0
    if denied(actorSource, 'scores.adjust') then return false, 'forbidden' end
    local p = Carnival.Participants.getBySource(targetSource)
    if not p then return false, 'not_registered' end
    if type(idempotencyKey) ~= 'string' or #idempotencyKey < 4 or #idempotencyKey > 100 then return false, 'bad_key' end
    if attractionId and not C.ATTRACTION_INDEX[attractionId] then return false, 'invalid_attraction' end
    local res = GetInvokingResource() or 'unknown'
    local actor = actorSource == 0 and { license = 'resource:' .. res, name = res } or Carnival.Identity.actor(actorSource)
    local ok, tx, msg = Carnival.Scoring.award({
        participantId = p.id, delta = math.tointeger(delta) or 0, key = ('export:%s:%s'):format(res, idempotencyKey),
        txType = 'adjustment', source = 'export:' .. res, reason = tostring(reason or 'External award'), attractionId = attractionId, actor = actor,
    })
    if ok and not tx.duplicate then
        Carnival.Audit.record(actor, 'score_awarded_by_export', { targetType = 'participant', targetId = p.id, reason = reason, details = { delta = tx.delta, resource = res } })
    end
    return ok, ok and tx or tx
end)

-- getAttractionState(attractionId) -> { id, readiness, session, summary } | nil
exports('getAttractionState', function(attractionId)
    for _, a in ipairs(Carnival.Attractions.overview()) do
        if a.id == attractionId then return a end
    end
    return nil
end)

-- registerExternalResult(targetSource, attractionId, points, resultKey, actorSource?)
-- Records a result for one of the six attractions from another resource (for
-- example a custom mini-game). The participant must be eligible for that
-- attraction right now (correct group, active session, valid ticket).
exports('registerExternalResult', function(targetSource, attractionId, points, resultKey, actorSource)
    actorSource = actorSource or 0
    if not C.ATTRACTION_INDEX[attractionId] then return false, 'invalid_attraction' end
    if denied(actorSource, 'scores.adjust') then return false, 'forbidden' end
    local p, session = Carnival.Attractions.eligibility(targetSource, attractionId, { skipDistance = true })
    if not p then return false, session end
    if type(resultKey) ~= 'string' or #resultKey < 4 or #resultKey > 100 then return false, 'bad_key' end
    local res = GetInvokingResource() or 'unknown'
    local ok, tx = Carnival.Scoring.award({
        participantId = p.id, delta = math.tointeger(points) or 0, key = ('external:%s:%s'):format(res, resultKey),
        txType = 'award', source = 'external:' .. res, reason = 'External result', attractionId = attractionId,
        sessionId = session.id, roundNumber = session.round_number,
        actor = actorSource == 0 and { license = 'resource:' .. res, name = res } or Carnival.Identity.actor(actorSource),
    })
    return ok, tx
end)
