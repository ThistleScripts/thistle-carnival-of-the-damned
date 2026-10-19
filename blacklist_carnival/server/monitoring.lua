-- Operational + security monitoring.
--
-- Monitor.log(severity, category, action, fields)
--   fields = { eventId, attractionId, participantId, actor = identity|license,
--              actorName, result, details = table, noPersist = bool }
--
-- Records are printed to the console (subject to Config.LogLevel), queued and
-- written to carnival_monitor_log in batches, and optionally forwarded to Discord.
-- Secrets must never be placed in `details`.

local C = Carnival.C
local Monitor = {}
Carnival.Monitor = Monitor

local queue = {}
local MAX_QUEUE = 2000
local recent = {}          -- ring buffer for the dashboard (warnings and above)
local RECENT_MAX = 50
local counters = { warning = 0, error = 0, critical = 0 }
local abuse = {}           -- [src] = { count, windowStart }

local function minRank()
    return C.SEVERITY_RANK[Config.LogLevel] or 2
end

local SEVERITY_COLOUR = { debug = '^7', info = '^5', warning = '^3', error = '^1', critical = '^1' }

local function detailsText(details)
    if details == nil then return nil end
    local ok, s = pcall(json.encode, details)
    if not ok then return tostring(details) end
    if #s > 4000 then s = s:sub(1, 4000) end
    return s
end

function Monitor.log(severity, category, action, fields)
    fields = fields or {}
    local rank = C.SEVERITY_RANK[severity] or 2
    local actor, actorName = fields.actor, fields.actorName
    if type(actor) == 'table' then
        actorName = actorName or actor.name
        actor = actor.license
    end
    local eventId = fields.eventId
    if eventId == nil and Carnival.Events and Carnival.Events.activeId then
        eventId = Carnival.Events.activeId()
    end
    local rec = {
        severity = severity,
        category = category,
        event_id = eventId,
        attraction_id = fields.attractionId,
        participant_id = fields.participantId,
        actor = actor,
        actor_name = actorName,
        action = action,
        result = fields.result,
        details = detailsText(fields.details),
        created_at = os.time(),
    }

    if rank >= minRank() then
        print(('%s[carnival:%s] %s/%s%s%s^0'):format(
            SEVERITY_COLOUR[severity] or '', severity, category, action,
            rec.result and (' -> ' .. rec.result) or '',
            rec.details and (' ' .. rec.details) or ''))
        if not fields.noPersist then
            if #queue >= MAX_QUEUE then table.remove(queue, 1) end
            queue[#queue + 1] = rec
        end
    end

    if rank >= C.SEVERITY_RANK.warning then
        counters[severity] = (counters[severity] or 0) + 1
        table.insert(recent, 1, rec)
        if #recent > RECENT_MAX then recent[#recent] = nil end
        if Carnival.Discord then
            local channel = (category == 'security' or category == 'permission' or category == 'invalid_request') and 'security' or 'error'
            if rank >= C.SEVERITY_RANK.error or channel == 'security' then
                Carnival.Discord.send(channel, ('%s: %s/%s'):format(severity:upper(), category, action), rec.details or '', rank >= 4 and 0xb3122a or 0xd8b21c)
            end
        end
    end
    return rec
end

-- Security event helper. Tracks repeated rejected requests per player and raises
-- a single elevated warning when the abuse threshold is crossed. Never bans.
function Monitor.security(src, action, details, category)
    local ident = Carnival.Identity and Carnival.Identity.actor(src) or nil
    Monitor.log('warning', category or 'security', action, { actor = ident, details = details, result = 'rejected' })
    if not src or src <= 0 then return end
    local now = os.time()
    local a = abuse[src]
    if not a or now - a.windowStart > 60 then
        a = { count = 0, windowStart = now, flagged = false }
        abuse[src] = a
    end
    a.count = a.count + 1
    if not a.flagged and a.count >= (Config.RateLimits.abuseThreshold or 30) then
        a.flagged = true
        Monitor.log('error', 'security', 'repeated_invalid_requests', {
            actor = ident, details = { count = a.count, windowSeconds = 60, last = action },
        })
    end
end

function Monitor.recent(limit)
    local out = {}
    for i = 1, math.min(limit or 20, #recent) do out[i] = recent[i] end
    return out
end

function Monitor.counters()
    return counters
end

function Monitor.flush()
    if #queue == 0 or not Carnival.Db then return end
    local batch = queue
    queue = {}
    -- Multi-row insert. NULL columns are emitted as literal NULL so the parameter
    -- array never contains nil holes.
    local rowsSql, params = {}, {}
    for _, r in ipairs(batch) do
        local v = { r.severity, r.category, r.event_id, r.attraction_id, r.participant_id, r.actor, r.actor_name, r.action, r.result, r.details, r.created_at }
        local ph = {}
        for i = 1, 11 do
            if v[i] == nil then
                ph[i] = 'NULL'
            else
                ph[i] = '?'
                params[#params + 1] = v[i]
            end
        end
        rowsSql[#rowsSql + 1] = '(' .. table.concat(ph, ', ') .. ')'
    end
    local sql = 'INSERT INTO carnival_monitor_log (severity, category, event_id, attraction_id, participant_id, actor, actor_name, action, result, details, created_at) VALUES ' .. table.concat(rowsSql, ', ')
    local ok, err = pcall(MySQL.insert.await, sql, params)
    if not ok then
        print(('^1[blacklist_carnival] could not persist %d monitoring records: %s^0'):format(#batch, tostring(err)))
        Carnival.Db.healthy = false
        Carnival.Db.lastError = tostring(err)
        Carnival.Db.lastErrorAt = os.time()
        -- re-queue (bounded) so a short outage does not lose records
        for i = #batch, 1, -1 do
            if #queue < MAX_QUEUE then table.insert(queue, 1, batch[i]) end
        end
    end
end

-- Paginated search used by the monitoring centre.
-- filters: { from, to, eventId, participantId, actor, attractionId, severity, minSeverity, category, search }
function Monitor.query(filters, page, pageSize)
    local where, params = {}, {}
    local function add(cond, ...)
        where[#where + 1] = cond
        for _, v in ipairs({ ... }) do params[#params + 1] = v end
    end
    if filters.from then add('created_at >= ?', filters.from) end
    if filters.to then add('created_at <= ?', filters.to) end
    if filters.eventId then add('event_id = ?', filters.eventId) end
    if filters.participantId then add('participant_id = ?', filters.participantId) end
    if filters.actor then add('(actor = ? OR actor_name LIKE ?)', filters.actor, '%' .. filters.actor .. '%') end
    if filters.attractionId then add('attraction_id = ?', filters.attractionId) end
    if filters.category then add('category = ?', filters.category) end
    if filters.severity then add('severity = ?', filters.severity) end
    if filters.minSeverity then
        local list = {}
        for _, s in ipairs(C.SEVERITIES) do
            if C.SEVERITY_RANK[s] >= (C.SEVERITY_RANK[filters.minSeverity] or 1) then list[#list + 1] = s end
        end
        local ph = {}
        for _, s in ipairs(list) do ph[#ph + 1] = '?' params[#params + 1] = s end
        where[#where + 1] = 'severity IN (' .. table.concat(ph, ',') .. ')'
    end
    if filters.search then add('(action LIKE ? OR details LIKE ?)', '%' .. filters.search .. '%', '%' .. filters.search .. '%') end
    if filters.categories then
        local ph = {}
        for _, c in ipairs(filters.categories) do ph[#ph + 1] = '?' params[#params + 1] = c end
        where[#where + 1] = 'category IN (' .. table.concat(ph, ',') .. ')'
    end

    local whereSql = #where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or ''
    local total = Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_monitor_log' .. whereSql, params) or 0
    local lp = {}
    for i, v in ipairs(params) do lp[i] = v end
    lp[#lp + 1] = pageSize
    lp[#lp + 1] = (page - 1) * pageSize
    local rows = Carnival.Db.query('SELECT * FROM carnival_monitor_log' .. whereSql .. ' ORDER BY id DESC LIMIT ? OFFSET ?', lp) or {}
    return rows, total
end

-- Background flush + retention pruning.
CreateThread(function()
    local lastPrune = 0
    while true do
        Wait(2000)
        Monitor.flush()
        local now = os.time()
        if Carnival.ready and now - lastPrune > 3600 then
            lastPrune = now
            for severity, days in pairs(Config.Retention or {}) do
                Carnival.Db.update('DELETE FROM carnival_monitor_log WHERE severity = ? AND created_at < ? LIMIT 5000', { severity, now - days * 86400 })
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    abuse[source] = nil
end)
