-- Live individual leaderboard, tie-breaks, frozen final results and prize tiers.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Leaderboard = {}
Carnival.Leaderboard = Leaderboard

local dirty = true
local ranking = {}       -- ordered list of entries
local rankById = {}
local lastPush = 0
local lastRanks = {}     -- [pid] = rank last pushed

function Leaderboard.markDirty() dirty = true end

local TIE_BREAKS = {
    attractions_completed = function(a, b) return a.completed > b.completed, a.completed == b.completed end,
    earliest_to_score = function(a, b)
        local x, y = a.lastScoreAt or math.huge, b.lastScoreAt or math.huge
        return x < y, x == y
    end,
    highest_single_attraction = function(a, b) return a.highestAttraction > b.highestAttraction, a.highestAttraction == b.highestAttraction end,
    fewest_deductions = function(a, b) return a.deductions < b.deductions, a.deductions == b.deductions end,
    most_gold_tokens = function(a, b) return a.goldTokens > b.goldTokens, a.goldTokens == b.goldTokens end,
    registration_order = function(a, b) return a.registeredAt < b.registeredAt, a.registeredAt == b.registeredAt end,
}

-- Returns ordering (bool a before b) and equality across the tie-break chain.
local function compare(a, b, chain)
    if a.total ~= b.total then return a.total > b.total, false end
    for _, key in ipairs(chain) do
        local fn = TIE_BREAKS[key]
        if fn then
            local before, equal = fn(a, b)
            if not equal then return before, false end
        end
    end
    return a.id < b.id, true
end

function Leaderboard.compute()
    local cfg = Carnival.Config.get()
    local chain = cfg and cfg.scoring.tieBreak or {}
    local entries = {}
    for _, p in pairs(Carnival.Participants.byId) do
        if p.status == 'active' then
            local st = Carnival.Scoring.stats(p.id)
            entries[#entries + 1] = {
                id = p.id, name = p.display_name, colour = p.colour, total = p.total_score or 0,
                breakdown = Carnival.Scoring.breakdown(p.id),
                completed = #Carnival.Rotation.completedFor(p.id),
                lastScoreAt = p.last_score_at, registeredAt = p.registered_at or 0,
                deductions = st.deductions, goldTokens = st.goldTokens, highestAttraction = st.highestAttraction,
            }
        end
    end
    table.sort(entries, function(a, b) return (compare(a, b, chain)) end)
    rankById = {}
    for i, e in ipairs(entries) do
        if i > 1 then
            local _, tied = compare(entries[i - 1], e, chain)
            e.rank = tied and entries[i - 1].rank or i
            e.tied = tied
            if tied then entries[i - 1].tied = true end
        else
            e.rank = 1
        end
        rankById[e.id] = e.rank
    end
    ranking = entries
    dirty = false
    return entries
end

function Leaderboard.ranking()
    if dirty then Leaderboard.compute() end
    return ranking
end

function Leaderboard.rankOf(pid)
    if dirty then Leaderboard.compute() end
    return rankById[pid]
end

local function publicEntry(e, cfg, idx)
    local lb = cfg.leaderboard
    return {
        rank = e.rank,
        tied = e.tied or false,
        name = lb.anonymise and ('Contestant #' .. idx) or e.name,
        total = e.total,
        colour = lb.showColours and e.colour or nil,
        breakdown = lb.showBreakdown and e.breakdown or nil,
        completed = lb.showCompleted and e.completed or nil,
    }
end

-- Latest frozen results of the most recently finished event (shown when idle).
local function latestFrozenPublic(src)
    local row = Carnival.Db.single([[SELECT r.*, e.name AS event_name FROM carnival_event_results r JOIN carnival_events e ON e.id = r.event_id
        WHERE e.state = 'completed' ORDER BY r.event_id DESC, r.version DESC LIMIT 1]])
    if not row then return { active = false, entries = {} } end
    local data = Carnival.Db.decode(row.data, {})
    local entries = {}
    for i, e in ipairs(data.entries or {}) do
        if i > 25 then break end
        entries[#entries + 1] = { rank = e.rank, tied = e.tied, name = e.name, total = e.total, colour = e.colour, prize = e.prize }
    end
    return { active = false, frozen = true, eventId = row.event_id, eventName = row.event_name, version = row.version, entries = entries, frozenAt = row.frozen_at }
end

function Leaderboard.publicView(src)
    local e = Carnival.Events.active
    if not e then return latestFrozenPublic(src) end
    local cfg = Carnival.Config.get()
    local list = Leaderboard.ranking()
    local entries = {}
    for i = 1, math.min(cfg.leaderboard.publicSize, #list) do
        entries[i] = publicEntry(list[i], cfg, i)
    end
    local you
    local p = src and Carnival.Participants.getBySource(src)
    if p then you = { rank = rankById[p.id], total = p.total_score } end
    return {
        active = true, eventId = e.id, eventName = e.name, state = e.state,
        frozen = e.state == C.STATES.FINAL,
        entries = entries, you = you, count = #list, updatedAt = os.time(),
    }
end

function Leaderboard.staffView()
    local list = Leaderboard.ranking()
    local out = {}
    for i, e in ipairs(list) do
        out[i] = {
            rank = e.rank, tied = e.tied or false, id = e.id, name = e.name, colour = e.colour, total = e.total,
            breakdown = e.breakdown, completed = e.completed, deductions = e.deductions, goldTokens = e.goldTokens,
            online = Carnival.Participants.sourceOf(e.id) ~= nil,
        }
    end
    return out
end

---------------------------------------------------------------------------
-- Frozen results
---------------------------------------------------------------------------
local function tierFor(rank, tiers)
    for i, t in ipairs(tiers) do
        if rank >= t.fromRank and rank <= t.toRank then return t, i end
    end
    return nil
end

function Leaderboard.freeze(actor, reason)
    local e = Carnival.Events.active
    if not e then return false, 'no_event' end
    local cfg = Carnival.Config.get()
    local list = Leaderboard.compute()
    local version = (Carnival.Db.scalar('SELECT MAX(version) FROM carnival_event_results WHERE event_id = ?', { e.id }) or 0) + 1
    local entries = {}
    for i, x in ipairs(list) do
        local tier = tierFor(x.rank, cfg.prizes.tiers)
        entries[i] = {
            rank = x.rank, tied = x.tied or false, participantId = x.id, name = x.name, colour = x.colour, total = x.total,
            breakdown = x.breakdown, completed = x.completed, prize = tier and tier.label or nil,
        }
    end
    local data = {
        eventId = e.id, eventName = e.name, version = version, frozenAt = os.time(),
        tieBreak = cfg.scoring.tieBreak, prizeTiers = cfg.prizes.tiers, entries = entries,
        configVersion = Carnival.Config.versionInfo(),
    }
    local resultId = Carnival.Db.insertRow('carnival_event_results', {
        event_id = e.id, version = version, reason = reason, tie_break = json.encode(cfg.scoring.tieBreak),
        data = json.encode(data), frozen_by = actor and actor.license or nil, frozen_at = os.time(),
    })
    if not resultId then return false, 'database_error' end
    for _, x in ipairs(entries) do
        Carnival.Db.insertRow('carnival_event_result_rows', {
            result_id = resultId, rank_position = x.rank, participant_id = x.participantId, display_name = x.name,
            colour = x.colour, total = x.total, breakdown = json.encode(x.breakdown or {}), prize_tier = x.prize,
        })
    end
    Carnival.Audit.record(actor, 'results_frozen', { eventId = e.id, targetType = 'event', targetId = e.id, reason = reason,
        details = { version = version, entries = #entries } })
    local top = {}
    for i = 1, math.min(3, #entries) do top[i] = ('%d. %s (%d)'):format(entries[i].rank, entries[i].name, entries[i].total) end
    Carnival.Discord.send('event', ('Results v%d frozen'):format(version), table.concat(top, '\n'), 0xb08d3c)

    if cfg.prizes.autoDeliver then
        CreateThread(function() Leaderboard.deliverPrizes(entries, cfg.prizes.tiers) end)
    end
    Carnival.Push.all('results', { eventId = e.id, version = version, top = U.map({ table.unpack(entries, 1, math.min(10, #entries)) }, function(x)
        return { rank = x.rank, name = cfg.leaderboard.anonymise and nil or x.name, total = x.total, colour = x.colour, prize = x.prize }
    end) })
    Carnival.Push.invalidate('results', 'dashboard')
    return true, version
end

-- Prize keys depend only on participant + tier + item, so re-freezing after a
-- correction never duplicates a prize already granted.
function Leaderboard.deliverPrizes(entries, tiers)
    for _, x in ipairs(entries) do
        local tier = tierFor(x.rank, tiers)
        if tier then
            for j, it in ipairs(tier.items or {}) do
                local r = Carnival.Rewards.create({
                    participantId = x.participantId, source = 'prize_tier', item = it.item, count = it.count,
                    key = ('prize:%d:%s:%d:%s'):format(x.participantId, tier.label, j, it.item),
                    note = ('Prize tier %s (rank %d)'):format(tier.label, x.rank),
                })
                if r and r.status == 'pending' then Carnival.Rewards.deliver(r.id, Carnival.Identity.SYSTEM) end
            end
        end
    end
end

-- Corrections during final results produce a new results version.
function Leaderboard.onCorrection(actor, reason)
    local e = Carnival.Events.active
    if e and e.state == C.STATES.FINAL then
        Leaderboard.freeze(actor, 'Correction: ' .. (reason or ''))
    end
end

function Leaderboard.resultVersions(eventId)
    return Carnival.Db.query('SELECT id, version, reason, frozen_by, frozen_at FROM carnival_event_results WHERE event_id = ? ORDER BY version DESC', { eventId }) or {}
end

function Leaderboard.results(eventId, version)
    local row
    if version then
        row = Carnival.Db.single('SELECT * FROM carnival_event_results WHERE event_id = ? AND version = ?', { eventId, version })
    else
        row = Carnival.Db.single('SELECT * FROM carnival_event_results WHERE event_id = ? ORDER BY version DESC LIMIT 1', { eventId })
    end
    if not row then return nil end
    return Carnival.Db.decode(row.data, {})
end

-- Throttled live push to subscribers + rank-change pushes to participants.
Carnival.onTick('leaderboard', function(now)
    if not dirty and now - lastPush < 30 then return end
    local cfg = Carnival.Config.get()
    if not cfg or (now - lastPush) * 1000 < cfg.leaderboard.pushIntervalMs then return end
    if not Carnival.Events.active then return end
    lastPush = now
    Leaderboard.compute()
    for _, s in ipairs(Carnival.Push.subscribers('leaderboard')) do
        Carnival.Push.send(s, 'leaderboard', Leaderboard.publicView(s))
    end
    for pid, rank in pairs(rankById) do
        if lastRanks[pid] ~= rank then
            lastRanks[pid] = rank
            local s = Carnival.Participants.sourceOf(pid)
            if s then Carnival.Push.send(s, 'rank', { rank = rank, total = Carnival.Participants.get(pid).total_score }) end
        end
    end
end)

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local Api = Carnival.Api

Api.register('leaderboard.public', {
    rate = 'participant',
    handler = function(ctx) return Leaderboard.publicView(ctx.source) end,
})

Api.register('leaderboard.staff', {
    perm = 'leaderboard.staff', rate = 'staff',
    handler = function()
        return { entries = Leaderboard.staffView(), tieBreak = Carnival.Config.get().scoring.tieBreak }
    end,
})

Api.register('results.get', {
    perm = 'events.history', rate = 'admin',
    handler = function(ctx, payload)
        local id, err = V.id(payload.eventId)
        if not id then return nil, 'invalid', 'eventId ' .. err end
        local version = payload.version and V.int(payload.version, 1, 10000) or nil
        return { results = Leaderboard.results(id, version), versions = Leaderboard.resultVersions(id) }
    end,
})

Api.register('results.export', {
    perm = 'export.history', rate = 'admin',
    handler = function(ctx, payload)
        local id, err = V.id(payload.eventId)
        if not id then return nil, 'invalid', 'eventId ' .. err end
        local data = Leaderboard.results(id)
        if not data then return nil, 'not_found', 'This event has no frozen results.' end
        local lines = { 'rank,name,colour,total,completed,prize' }
        for _, x in ipairs(data.entries or {}) do
            local name = tostring(x.name):gsub('"', '""')
            lines[#lines + 1] = ('%d,"%s",%s,%d,%s,"%s"'):format(x.rank, name, x.colour or '', x.total, tostring(x.completed or ''), x.prize or '')
        end
        Carnival.Audit.record(ctx.actor, 'results_exported', { eventId = id, targetType = 'event', targetId = id, details = { version = data.version } })
        return { csv = table.concat(lines, '\n'), json = json.encode(data), version = data.version }
    end,
})

Api.register('results.refreeze', {
    perm = { 'panel.admin', 'events.manage' }, rate = 'admin',
    handler = function(ctx, payload)
        local e = Carnival.Events.active
        if not e or e.state ~= C.STATES.FINAL then return nil, 'invalid', 'Results can only be re-frozen during final results.' end
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        local ok, v = Leaderboard.freeze(ctx.actor, reason)
        if not ok then return nil, v end
        return { version = v }
    end,
})
