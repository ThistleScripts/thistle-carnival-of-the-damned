-- Attraction: The Shooting Gallery.
--
-- GTA/FiveM gives the server no authoritative record of where a bullet landed on
-- a client-side prop, so clients REPORT potential hits (target id + impact point)
-- and the server decides whether to accept them:
--   * heat running, shooter registered in the heat, event running
--   * shooter standing at the firing stand (server-side ped position)
--   * an allowed weapon is selected (server-side GetSelectedPedWeapon)
--   * impact point within the configured target radius (bullseye radius for bonus)
--   * target is up for that shooter (per-target reset timer), special targets
--     only while the server has them active
--   * minimum time between accepted hits, hit count bounded by ammo
-- Points are accumulated server-side and awarded once per shooter per heat.
-- Remaining limitation: a modified client could fabricate plausible impact
-- coordinates while standing at the stand holding the right weapon; the caps
-- above bound the damage and every hit is logged for review.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api
local ID = 'shooting'
local OP = 'attractions.operate.shooting'

local heat = nil
local queue = {}   -- ordered list of participant ids waiting at the stand

local function cfg() return Carnival.Config.get().attractions.shooting end

local function targetById(id)
    for _, t in ipairs(cfg().targets) do if t.id == id then return t end end
    return nil
end

local function nowMs() return GetGameTimer() end

local function heatSources()
    local out = {}
    if not heat then return out end
    for pid in pairs(heat.shooters) do
        local s = Carnival.Participants.sourceOf(pid)
        if s then out[#out + 1] = s end
    end
    return out
end

local function push(data)
    for _, s in ipairs(heatSources()) do Carnival.Push.send(s, 'shooting', data) end
end

local function alreadyShot(sessionId, pid)
    return (Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_shooting_results WHERE session_id = ? AND participant_id = ?', { sessionId, pid }) or 0) > 0
end

local function removeFromQueue(pid)
    for i = #queue, 1, -1 do if queue[i] == pid then table.remove(queue, i) end end
end

local function weaponHashes()
    local set = {}
    for _, w in ipairs(cfg().weapons) do set[GetHashKey(w)] = true end
    return set
end

local function provideWeapons(pid)
    local c = cfg()
    if not c.provideWeapon then return end
    local s = Carnival.Participants.sourceOf(pid)
    if not s then return end
    local ok = Carnival.Inventory.addItem(s, c.weaponItem, 1, { carnivalHeat = heat.id, serial = 'CARNIVAL' })
    if ok and c.ammoItem ~= '' then Carnival.Inventory.addItem(s, c.ammoItem, c.ammoCount) end
    heat.shooters[pid].provided = ok
end

local function reclaimWeapons(pid)
    local c = cfg()
    local sh = heat and heat.shooters[pid]
    if not sh or not sh.provided then return end
    local s = Carnival.Participants.sourceOf(pid)
    if not s then return end
    Carnival.Inventory.removeItem(s, c.weaponItem, 1, { carnivalHeat = heat.id })
    if c.ammoItem ~= '' then
        local have = Carnival.Inventory.count(s, c.ammoItem)
        local take = math.min(have, c.ammoCount)
        if take > 0 then Carnival.Inventory.removeItem(s, c.ammoItem, take) end
    end
    sh.provided = false
end

local function publicHeat()
    if not heat then return nil end
    local shooters = {}
    for pid, sh in pairs(heat.shooters) do
        local p = Carnival.Participants.get(pid)
        shooters[#shooters + 1] = { id = pid, name = p and p.display_name or '?', hits = sh.hits, shots = sh.shots, bullseyes = sh.bullseyes,
            specials = sh.specials, points = sh.targetPoints, rejected = sh.rejected, online = Carnival.Participants.sourceOf(pid) ~= nil }
    end
    table.sort(shooters, function(a, b) return a.points > b.points end)
    return { id = heat.id, status = heat.status, endsAt = heat.endsAt, remaining = heat.pausedRemaining, shooters = shooters, serverTime = os.time() }
end

---------------------------------------------------------------------------
-- Heat lifecycle
---------------------------------------------------------------------------
local function startHeat(actor, pids)
    local session = Carnival.Rotation.activeSessionFor(ID)
    if not session then return nil, 'no_session', 'No group is at the Shooting Gallery.' end
    if heat and (heat.status == 'running' or heat.status == 'paused') then return nil, 'invalid', 'A heat is already running.' end
    local e = Carnival.Events.active
    if not e or e.state ~= C.STATES.RUNNING then return nil, 'not_live', 'The event must be running.' end
    local c = cfg()
    if not pids or #pids == 0 then
        pids = {}
        for i = 1, math.min(c.maxPlayers, #queue) do pids[i] = queue[i] end
    end
    if #pids == 0 then return nil, 'invalid', 'Nobody is waiting at the stand.' end
    if #pids > c.maxPlayers then return nil, 'invalid', ('At most %d shooters per heat.'):format(c.maxPlayers) end
    for _, pid in ipairs(pids) do
        local p = Carnival.Participants.get(pid)
        if not p or p.status ~= 'active' or p.colour ~= session.colour then return nil, 'invalid', 'Shooters must be members of the group at the gallery.' end
        if not Carnival.Participants.sourceOf(pid) then return nil, 'invalid', (p.display_name .. ' is offline.') end
        if alreadyShot(session.id, pid) then return nil, 'invalid', (p.display_name .. ' has already shot this round.') end
    end
    local now = os.time()
    local id = Carnival.Db.insertRow('carnival_shooting_heats', {
        event_id = e.id, session_id = session.id, status = 'running', duration_seconds = c.durationSeconds,
        started_by = actor.license, started_at = now,
    })
    if not id then return nil, 'database_error' end
    heat = { id = id, sessionId = session.id, status = 'running', startedAt = now, endsAt = now + c.durationSeconds, shooters = {},
        special = nil, nextSpecialAt = now + c.specialIntervalSeconds }
    for _, pid in ipairs(pids) do
        heat.shooters[pid] = { hits = 0, shots = 0, bullseyes = 0, specials = 0, targetPoints = 0, rejected = 0, lastHitMs = nil, down = {} }
        removeFromQueue(pid)
        provideWeapons(pid)
    end
    push({ action = 'start', heatId = id, endsAt = heat.endsAt, serverTime = now, duration = c.durationSeconds })
    Carnival.Monitor.log('info', 'attraction', 'shooting_heat_started', { attractionId = ID, actor = actor, details = { heatId = id, shooters = #pids } })
    Carnival.Push.invalidate('shooting')
    return publicHeat()
end

local function finishHeat(actor, reason)
    if not heat or (heat.status ~= 'running' and heat.status ~= 'paused') then return nil, 'invalid', 'No heat is running.' end
    local c = cfg()
    heat.status = 'ended'
    Carnival.Db.update("UPDATE carnival_shooting_heats SET status = 'ended', ended_at = ?, end_reason = ? WHERE id = ?", { os.time(), reason, heat.id })
    local session = Carnival.Rotation.sessionById(heat.sessionId)
    local results = {}
    for pid, sh in pairs(heat.shooters) do
        local shots = math.max(sh.shots, sh.hits)
        if c.provideWeapon then shots = math.min(shots, c.ammoCount) end
        local accuracy = shots > 0 and (sh.hits / shots) or 0
        local accBonus = (c.accuracyScoring and sh.hits > 0) and math.floor(c.accuracyBonusMax * accuracy) or 0
        local penalty = math.max(0, shots - sh.hits) * c.missPenalty
        local total = sh.targetPoints + accBonus - penalty
        local rid = Carnival.Db.insertRow('carnival_shooting_results', {
            event_id = Carnival.Events.activeId(), heat_id = heat.id, session_id = heat.sessionId, participant_id = pid,
            hits = sh.hits, shots = shots, bullseyes = sh.bullseyes, specials = sh.specials, target_points = sh.targetPoints,
            accuracy_bonus = accBonus, miss_penalty = penalty, points = total, rejected_hits = sh.rejected, created_at = os.time(),
        })
        local applied = 0
        if rid and total ~= 0 then
            local ok, tx = Carnival.Scoring.award({
                participantId = pid, delta = total, key = ('shooting:%d:%d'):format(heat.id, pid), txType = total > 0 and 'award' or 'penalty',
                source = 'shooting_heat', reason = ('%d hits / %d shots, %d bullseyes, %d specials'):format(sh.hits, shots, sh.bullseyes, sh.specials),
                attractionId = ID, sessionId = heat.sessionId, roundNumber = session and session.round_number or nil, publicReason = 'Shooting Gallery',
            })
            if ok then applied = tx.delta end
        end
        reclaimWeapons(pid)
        local s = Carnival.Participants.sourceOf(pid)
        if s then
            Carnival.Push.send(s, 'shooting', { action = 'result', hits = sh.hits, shots = shots, bullseyes = sh.bullseyes, specials = sh.specials,
                accuracy = math.floor(accuracy * 100), accuracyBonus = accBonus, penalty = penalty, points = applied })
        end
        results[#results + 1] = { participantId = pid, points = applied }
    end
    push({ action = 'end', reason = reason })
    Carnival.Monitor.log('info', 'attraction', 'shooting_heat_finished', { attractionId = ID, actor = actor, result = reason, details = { heatId = heat.id, results = results } })
    Carnival.Push.invalidate('shooting')
    return { results = results }
end

local function resetHeat(actor, reason)
    if not heat then return nil, 'invalid', 'No heat to reset.' end
    for pid in pairs(heat.shooters) do reclaimWeapons(pid) end
    Carnival.Db.update("UPDATE carnival_shooting_heats SET status = 'reset', ended_at = ?, end_reason = ? WHERE id = ?", { os.time(), 'reset: ' .. reason, heat.id })
    push({ action = 'end', reason = 'reset' })
    Carnival.Audit.record(actor, 'shooting_heat_reset', { targetType = 'shooting_heat', targetId = heat.id, reason = reason })
    heat = nil
    Carnival.Push.invalidate('shooting')
    return true
end

---------------------------------------------------------------------------
-- Hit validation
---------------------------------------------------------------------------
local function reject(src, sh, pid, why, details)
    if sh then sh.rejected = sh.rejected + 1 end
    Carnival.Monitor.log(why == 'target_down' and 'debug' or 'warning', why == 'target_down' and 'attraction' or 'security', 'shooting_hit_rejected', {
        participantId = pid, attractionId = ID, actor = Carnival.Identity.actor(src), result = why, details = details,
    })
    return nil, why
end

local function hit(src, payload)
    if not heat or heat.status ~= 'running' or V.id(payload.heatId) ~= heat.id then return nil, 'stale' end
    if Carnival.Events.state() ~= C.STATES.RUNNING then return nil, 'paused' end
    local pid = Carnival.Participants.idOfSource(src)
    local sh = pid and heat.shooters[pid]
    if not sh then return reject(src, nil, pid, 'not_in_heat') end
    local c = cfg()
    local t = type(payload.targetId) == 'string' and targetById(payload.targetId)
    if not t then return reject(src, sh, pid, 'unknown_target') end
    local impact = V.vec3(payload.impact)
    if not impact then return reject(src, sh, pid, 'bad_impact') end
    if type(payload.shots) == 'number' then
        sh.shots = math.max(sh.shots, math.min(math.floor(payload.shots), 500))
    end

    local stand = c.stand
    local near, d = Carnival.Identity.within(src, stand, c.maxDistanceFromStand + 1.0)
    if not near then return reject(src, sh, pid, 'not_at_stand', { distance = d and U.round(d, 1) }) end
    local ped = GetPlayerPed(src)
    local weapon = GetSelectedPedWeapon(ped)
    if not weaponHashes()[weapon] then return reject(src, sh, pid, 'wrong_weapon') end

    local ms = nowMs()
    if sh.lastHitMs and ms - sh.lastHitMs < c.minHitIntervalMs then return reject(src, sh, pid, 'too_fast') end
    if (sh.down[t.id] or 0) > ms then return reject(src, sh, pid, 'target_down') end
    if t.kind == 'special' and not (heat.special and heat.special.id == t.id and os.time() <= heat.special['until']) then
        return reject(src, sh, pid, 'special_not_active')
    end
    local dist = U.dist3(impact, t.coords)
    if dist > t.radius + 0.15 then return reject(src, sh, pid, 'missed_target', { distance = U.round(dist, 2) }) end
    local shooterPos = Carnival.Identity.pedCoords(src)
    if shooterPos and U.dist3(shooterPos, impact) > 80 then return reject(src, sh, pid, 'implausible_impact') end
    local maxHits = c.provideWeapon and c.ammoCount or (c.durationSeconds * 5)
    if sh.hits >= maxHits then return reject(src, sh, pid, 'hit_cap') end

    sh.lastHitMs = ms
    sh.down[t.id] = ms + c.targetRespawnMs
    sh.hits = sh.hits + 1
    local points = t.points
    local bullseye = dist <= c.bullseyeRadius
    if bullseye then
        points = points + c.bullseyeBonus
        sh.bullseyes = sh.bullseyes + 1
    end
    if t.kind == 'special' then
        points = points + c.specialBonus
        sh.specials = sh.specials + 1
        heat.special = nil
        push({ action = 'special_end', targetId = t.id })
    end
    sh.targetPoints = sh.targetPoints + points
    Carnival.Push.invalidate('shooting')
    return { targetId = t.id, points = points, bullseye = bullseye, special = t.kind == 'special', total = sh.targetPoints, hits = sh.hits, downMs = c.targetRespawnMs }
end

---------------------------------------------------------------------------
-- Ticker
---------------------------------------------------------------------------
Carnival.onTick('shooting', function(now)
    if not heat or heat.status ~= 'running' or Carnival.Events.state() ~= C.STATES.RUNNING then return end
    local c = cfg()
    if heat.special and now > heat.special['until'] then
        push({ action = 'special_end', targetId = heat.special.id })
        heat.special = nil
    end
    if not heat.special and now >= heat.nextSpecialAt then
        local specials = U.filter(c.targets, function(t) return t.kind == 'special' end)
        if #specials > 0 then
            local t = specials[math.random(#specials)]
            heat.special = { id = t.id, ['until'] = now + c.specialWindowSeconds }
            push({ action = 'special', targetId = t.id, ['until'] = heat.special['until'], serverTime = now })
        end
        heat.nextSpecialAt = now + c.specialIntervalSeconds
    end
    if now >= heat.endsAt then finishHeat(nil, 'time') end
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
Carnival.Attractions.register({
    id = ID,
    isBusy = function() return heat ~= nil and (heat.status == 'running' or heat.status == 'paused') end,
    onTimerExpired = function()
        if heat and (heat.status == 'running' or heat.status == 'paused') then return 'hold' end
        return 'complete'
    end,
    onSessionStart = function() queue = {} if heat and heat.status == 'ended' then heat = nil end end,
    onSessionEnd = function(session)
        if heat and heat.sessionId == session.id and (heat.status == 'running' or heat.status == 'paused') then
            finishHeat(nil, 'session_ended')
        end
        queue = {}
    end,
    onPause = function()
        if heat and heat.status == 'running' then
            heat.status = 'paused'
            heat.pausedRemaining = math.max(0, heat.endsAt - os.time())
            push({ action = 'paused', remaining = heat.pausedRemaining })
        end
    end,
    onResume = function()
        if heat and heat.status == 'paused' then
            heat.status = 'running'
            heat.endsAt = os.time() + (heat.pausedRemaining or 0)
            heat.pausedRemaining = nil
            push({ action = 'start', heatId = heat.id, endsAt = heat.endsAt, serverTime = os.time(), duration = cfg().durationSeconds })
        end
    end,
    onEventEnd = function()
        if heat and (heat.status == 'running' or heat.status == 'paused') then resetHeat(Carnival.Identity.SYSTEM, 'event ended') end
        heat, queue = nil, {}
    end,
    onPlayerDropped = function(src, p)
        removeFromQueue(p.id)
    end,
    recover = function(e)
        heat, queue = nil, {}
        local n = Carnival.Db.update("UPDATE carnival_shooting_heats SET status = 'interrupted', ended_at = ?, end_reason = 'server_restart' WHERE event_id = ? AND status = 'running'", { os.time(), e.id })
        if n and n > 0 then Carnival.Monitor.log('warning', 'recovery', 'shooting_heat_interrupted', { attractionId = ID, details = { heats = n } }) end
    end,
    staffSummary = function()
        return { queue = #queue, heat = heat and heat.status or nil }
    end,
})

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
Api.register('shooting.join', {
    rate = 'action',
    handler = function(ctx)
        local c = cfg()
        local p, session, msg = Carnival.Attractions.eligibility(ctx.source, ID, { point = c.stand, distance = c.validationDistance })
        if not p then return nil, session, msg end
        if alreadyShot(session.id, p.id) then return nil, 'already_shot', 'You have already taken your turn.' end
        if heat and heat.shooters[p.id] and heat.status ~= 'ended' then return nil, 'invalid', 'You are already shooting.' end
        for i, q in ipairs(queue) do if q == p.id then return { position = i } end end
        queue[#queue + 1] = p.id
        Carnival.Push.invalidate('shooting')
        if c.autoStart and #queue >= c.maxPlayers and not (heat and (heat.status == 'running' or heat.status == 'paused')) then
            CreateThread(function() startHeat(Carnival.Identity.SYSTEM, nil) end)
        end
        return { position = #queue }
    end,
})

Api.register('shooting.leave', {
    rate = 'action',
    handler = function(ctx)
        local pid = Carnival.Participants.idOfSource(ctx.source)
        if pid then removeFromQueue(pid) Carnival.Push.invalidate('shooting') end
        return true
    end,
})

Api.register('shooting.hit', { rate = 'shooting', handler = function(ctx, payload) return hit(ctx.source, payload) end })

Api.register('shooting.shots', {
    rate = 'shooting',
    handler = function(ctx, payload)
        if not heat or V.id(payload.heatId) ~= heat.id then return nil, 'stale' end
        local pid = Carnival.Participants.idOfSource(ctx.source)
        local sh = pid and heat.shooters[pid]
        if not sh then return nil, 'not_in_heat' end
        local n = V.int(payload.shots, 0, 500)
        if n then sh.shots = math.max(sh.shots, n) end
        return true
    end,
})

Api.register('shooting.staff.state', {
    perm = OP, rate = 'staff',
    handler = function()
        local session = Carnival.Rotation.sessionFor(ID)
        local q = U.map(queue, function(pid)
            local p = Carnival.Participants.get(pid)
            return { id = pid, name = p and p.display_name or '?' }
        end)
        local members = {}
        if session then
            for _, p in ipairs(Carnival.Participants.members(session.colour, false)) do
                members[#members + 1] = { id = p.id, name = p.display_name, online = Carnival.Participants.sourceOf(p.id) ~= nil,
                    shot = alreadyShot(session.id, p.id), points = Carnival.Scoring.attractionPoints(p.id, ID) }
            end
        end
        local recent = Carnival.Events.activeId() and (Carnival.Db.query([[SELECT r.*, p.display_name FROM carnival_shooting_results r JOIN carnival_participants p ON p.id = r.participant_id
            WHERE r.event_id = ? ORDER BY r.id DESC LIMIT 30]], { Carnival.Events.activeId() }) or {}) or {}
        return { session = session, queue = q, members = members, heat = publicHeat(), recent = recent, maxPlayers = cfg().maxPlayers }
    end,
})

Api.register('shooting.startHeat', {
    perm = OP, rate = 'staff',
    handler = function(ctx, payload)
        local pids
        if type(payload.participantIds) == 'table' and #payload.participantIds > 0 then
            pids = {}
            for _, x in ipairs(payload.participantIds) do
                local id = V.id(x)
                if not id then return nil, 'invalid', 'Invalid participant.' end
                pids[#pids + 1] = id
            end
        end
        return startHeat(ctx.actor, pids)
    end,
})

Api.register('shooting.pause', {
    perm = OP, rate = 'staff',
    handler = function(ctx)
        if not heat or heat.status ~= 'running' then return nil, 'invalid', 'No heat is running.' end
        heat.status = 'paused'
        heat.pausedRemaining = math.max(0, heat.endsAt - os.time())
        push({ action = 'paused', remaining = heat.pausedRemaining })
        Carnival.Monitor.log('info', 'attraction', 'shooting_paused', { attractionId = ID, actor = ctx.actor })
        Carnival.Push.invalidate('shooting')
        return publicHeat()
    end,
})

Api.register('shooting.resume', {
    perm = OP, rate = 'staff',
    handler = function(ctx)
        if not heat or heat.status ~= 'paused' then return nil, 'invalid', 'The heat is not paused.' end
        if Carnival.Events.state() ~= C.STATES.RUNNING then return nil, 'invalid', 'Resume the event first.' end
        heat.status = 'running'
        heat.endsAt = os.time() + (heat.pausedRemaining or 0)
        heat.pausedRemaining = nil
        push({ action = 'start', heatId = heat.id, endsAt = heat.endsAt, serverTime = os.time(), duration = cfg().durationSeconds })
        Carnival.Push.invalidate('shooting')
        return publicHeat()
    end,
})

Api.register('shooting.finish', { perm = OP, rate = 'staff', handler = function(ctx) return finishHeat(ctx.actor, 'staff') end })

Api.register('shooting.reset', {
    perm = OP, rate = 'staff',
    handler = function(ctx, payload)
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        return resetHeat(ctx.actor, reason)
    end,
})
