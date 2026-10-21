-- Attraction: The Wheel of Misfortune.
-- The server chooses every outcome (weighted, server-side RNG) and persists the
-- spin before any points or items are granted. The client only animates the
-- wheel to the segment the server returns.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api
local ID = 'wheel'

local Wheel = {}

local function cfg() return Carnival.Config.get().attractions.wheel end

local function spinsUsed(eventId, pid)
    return Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_wheel_spins WHERE event_id = ? AND participant_id = ?', { eventId, pid }) or 0
end

local function lastSpinAt(eventId, pid)
    return Carnival.Db.scalar('SELECT MAX(created_at) FROM carnival_wheel_spins WHERE event_id = ? AND participant_id = ?', { eventId, pid })
end

-- Weighted choice. Returns outcome, index, roll, totalWeight.
function Wheel.choose(outcomes)
    local total = 0
    for _, o in ipairs(outcomes) do total = total + math.max(0, o.weight or 0) end
    if total <= 0 then return nil end
    local roll = math.random() * total
    local acc = 0
    for i, o in ipairs(outcomes) do
        acc = acc + math.max(0, o.weight or 0)
        if roll < acc then return o, i, roll, total end
    end
    return outcomes[#outcomes], #outcomes, roll, total
end

local function publicOutcomes()
    return U.map(cfg().outcomes, function(o) return { id = o.id, label = o.label, type = o.type, colour = o.colour } end)
end

local function maybeCompleteSession(session)
    if not session or not cfg().autoCompleteWhenAllSpun then return end
    local members = Carnival.Rotation.sessionMembers(session, false)
    if #members == 0 then return end
    local max = cfg().maxSpins
    for _, p in ipairs(members) do
        if spinsUsed(session.event_id, p.id) < max then return end
    end
    Carnival.Rotation.completeSession(session.id, Carnival.Identity.SYSTEM, 'Every member of the group has spun the wheel')
end

function Wheel.spin(src)
    local p, session, msg = Carnival.Attractions.eligibility(src, ID)
    if not p then return nil, session, msg end
    local c = cfg()
    if not c.enabled then return nil, 'disabled', 'The wheel is closed.' end

    return Carnival.withLock('wheel:' .. p.id, function()
        local e = Carnival.Events.active
        local used = spinsUsed(e.id, p.id)
        if used >= c.maxSpins then return nil, 'no_spins', 'You have used all of your spins.' end
        local last = lastSpinAt(e.id, p.id)
        if last and os.time() - last < c.cooldownSeconds then
            return nil, 'cooldown', ('The wheel needs %ds to settle.'):format(c.cooldownSeconds - (os.time() - last))
        end
        local outcome, index, roll, total = Wheel.choose(c.outcomes)
        if not outcome then return nil, 'misconfigured', 'The wheel is jammed. Staff have been notified.' end

        local spinNumber = used + 1
        local spinId = Carnival.Db.insertRow('carnival_wheel_spins', {
            event_id = e.id, participant_id = p.id, session_id = session.id, spin_number = spinNumber,
            outcome_id = outcome.id, outcome_label = outcome.label, outcome_type = outcome.type,
            points = outcome.points or 0, item = (outcome.item ~= '' and outcome.item) or nil, item_count = outcome.count or 0,
            roll = roll, total_weight = total, created_at = os.time(),
        })
        if not spinId then
            Carnival.Monitor.log('warning', 'duplicate', 'wheel_spin_rejected', { participantId = p.id, attractionId = ID, details = { spinNumber = spinNumber } })
            return nil, 'duplicate', 'That spin was already recorded.'
        end
        Carnival.Monitor.log('info', 'attraction', 'wheel_spin', { participantId = p.id, attractionId = ID, details = { spinId = spinId, outcome = outcome.id, roll = U.round(roll, 3), total = total } })

        if spinNumber == 1 and c.participationBonus > 0 then
            Carnival.Scoring.award({
                participantId = p.id, delta = c.participationBonus, key = 'wheel:participation:' .. p.id, txType = 'participation',
                source = 'wheel_participation', reason = 'First spin of the Wheel of Misfortune', attractionId = ID,
                sessionId = session.id, roundNumber = session.round_number, publicReason = 'Wheel participation',
            })
        end

        local applied = 0
        if (outcome.points or 0) ~= 0 then
            local ok, tx = Carnival.Scoring.award({
                participantId = p.id, delta = outcome.points, key = 'wheel:spin:' .. spinId,
                txType = outcome.points > 0 and 'award' or 'penalty', source = 'wheel_' .. outcome.type,
                reason = 'Wheel: ' .. outcome.label, attractionId = ID, sessionId = session.id, roundNumber = session.round_number,
                publicReason = outcome.label,
            })
            if ok then applied = tx.delta end
        end

        local reward
        if outcome.item and outcome.item ~= '' and (outcome.count or 0) > 0 then
            local r, rcode = Carnival.Rewards.create({
                participantId = p.id, source = 'wheel', item = outcome.item, count = outcome.count,
                key = 'wheel:reward:' .. spinId,
                note = 'Wheel outcome ' .. outcome.label,
            })
            if r then
                Carnival.Db.update('UPDATE carnival_wheel_spins SET reward_id = ? WHERE id = ?', { r.id, spinId })
                local status = r.status
                if status == 'pending' then status = Carnival.Rewards.deliver(r.id, Carnival.Identity.SYSTEM) end
                reward = { item = outcome.item, label = Carnival.Inventory.itemLabel(outcome.item), count = outcome.count, status = status }
                if status == 'awaiting_approval' then Carnival.Push.invalidate('wheel', 'rewards') end
            else
                reward = { item = outcome.item, count = outcome.count, status = 'failed', error = rcode }
            end
        end

        Carnival.Push.invalidate('wheel')
        CreateThread(function()
            Wait(c.spinAnimationMs + 500)
            -- walk-up: the visit is over for this player once their spins are used
            if spinNumber >= c.maxSpins then Carnival.Rotation.memberFinished(session.id, p.id, 'Spun the wheel') end
            maybeCompleteSession(Carnival.Rotation.sessionById(session.id))
        end)
        return {
            index = index, outcome = { id = outcome.id, label = outcome.label, type = outcome.type },
            points = applied, reward = reward, spinsUsed = spinNumber, maxSpins = c.maxSpins,
            animationMs = c.spinAnimationMs, cooldownSeconds = c.cooldownSeconds,
        }
    end)
end

Carnival.Attractions.register({
    id = ID,
    onTimerExpired = function() return 'complete' end,
    staffSummary = function()
        local e = Carnival.Events.active
        if not e then return nil end
        return Carnival.Db.single([[SELECT COUNT(*) AS spins,
            (SELECT COUNT(*) FROM carnival_rewards WHERE event_id = ? AND source = 'wheel' AND status = 'awaiting_approval') AS awaitingApproval
            FROM carnival_wheel_spins WHERE event_id = ?]], { e.id, e.id })
    end,
})

Api.register('wheel.open', {
    rate = 'participant',
    handler = function(ctx)
        local p, session, msg = Carnival.Attractions.eligibility(ctx.source, ID)
        if not p then return nil, session, msg end
        local c = cfg()
        local e = Carnival.Events.active
        local last = lastSpinAt(e.id, p.id)
        return {
            outcomes = publicOutcomes(), spinsUsed = spinsUsed(e.id, p.id), maxSpins = c.maxSpins,
            cooldownRemaining = last and math.max(0, c.cooldownSeconds - (os.time() - last)) or 0,
            animationMs = c.spinAnimationMs, label = c.label,
        }
    end,
})

Api.register('wheel.spin', {
    rate = 'action',
    handler = function(ctx) return Wheel.spin(ctx.source) end,
})

Carnival.WheelAttraction = Wheel
