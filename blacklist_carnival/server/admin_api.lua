-- Admin dashboard, monitoring centre, audit viewer, role management and health.
-- Every endpoint is permission-gated by the API router.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api

local function health()
    local inv = Carnival.Inventory.available()
    return {
        resourceVersion = C.VERSION,
        uptime = os.time() - Carnival.startedAt,
        ready = Carnival.ready,
        database = Carnival.Db.status(),
        schemaVersion = Carnival.Db.schemaVersion(),
        inventoryRunning = inv,
        targetRunning = GetResourceState('ox_target') == 'started',
        qbxRunning = GetResourceState('qbx_core') == 'started',
        discordEnabled = Config.Discord.Enabled,
        counters = Carnival.Monitor.counters(),
        config = Carnival.Config.versionInfo(),
        onlinePlayers = #Carnival.Identity.online(),
    }
end

local function dashboard(ctx, full)
    local e = Carnival.Events.active
    local counts = e and Carnival.Groups.counts() or nil
    local out = {
        serverTime = os.time(),
        event = Carnival.Events.publicState(),
        eventRow = e,
        rotation = e and Carnival.Rotation.staffState() or nil,
        groups = e and Carnival.Groups.overview() or nil,
        attractions = e and Carnival.Attractions.overview() or nil,
        participants = e and { total = counts.total, online = Carnival.Participants.onlineCount(), unassigned = counts.unassigned } or nil,
        leaderboard = (e and ctx:has('leaderboard.staff')) and U.map({ table.unpack(Carnival.Leaderboard.staffView(), 1, 10) }, function(x) return x end) or nil,
        role = Carnival.Perms.role(ctx.source),
        permissions = Carnival.Perms.list(ctx.source),
    }
    if full then
        out.health = health()
        out.recentTransactions = e and (Carnival.Db.query([[SELECT t.id, p.display_name, t.attraction_id, t.delta, t.resulting_total, t.tx_type, t.source, t.staff_name, t.created_at
            FROM carnival_score_transactions t JOIN carnival_participants p ON p.id = t.participant_id WHERE t.event_id = ? ORDER BY t.id DESC LIMIT 15]], { e.id }) or {}) or {}
        out.outstandingRewards = Carnival.Rewards.outstandingCount(e and e.id)
        out.setup = Carnival.Setup and Carnival.Setup.checklist() or nil
        out.recentStaffActions = Carnival.Db.query('SELECT id, actor_name, action, target_type, target_id, reason, created_at FROM carnival_audit_log ORDER BY id DESC LIMIT 15') or {}
        out.recentProblems = Carnival.Monitor.recent(15)
        out.countdowns = {}
        for _, a in ipairs(out.attractions or {}) do
            if a.summary and a.summary.remaining then out.countdowns[#out.countdowns + 1] = { attraction = a.id, remaining = a.summary.remaining } end
        end
    end
    return out
end

Api.register('admin.dashboard', {
    perm = 'panel.admin', rate = 'admin',
    handler = function(ctx) return dashboard(ctx, true) end,
})

Api.register('system.health', {
    perm = 'panel.admin', rate = 'admin',
    handler = function() return health() end,
})

Api.register('items.validate', {
    perm = 'panel.admin', rate = 'admin',
    handler = function() return Carnival.Inventory.validateDefinitions(false) end,
})

---------------------------------------------------------------------------
-- Monitoring centre / audit
---------------------------------------------------------------------------
local function dateFilter(v)
    if v == nil or v == '' or v == 0 then return nil end
    return V.int(v, 0, 4102444800)
end

Api.register('monitoring.query', {
    perm = 'monitoring.view', rate = 'admin',
    handler = function(ctx, payload)
        local f = {
            from = dateFilter(payload.from), to = dateFilter(payload.to),
            eventId = payload.eventId and V.id(payload.eventId) or nil,
            participantId = payload.participantId and V.id(payload.participantId) or nil,
            actor = payload.actor and payload.actor ~= '' and V.string(payload.actor, 80) or nil,
            attractionId = payload.attractionId and V.attraction(payload.attractionId) or nil,
            category = payload.category and V.oneOf(payload.category, C.MONITOR_CATEGORIES) or nil,
            severity = payload.severity and V.oneOf(payload.severity, C.SEVERITIES) or nil,
            minSeverity = payload.minSeverity and V.oneOf(payload.minSeverity, C.SEVERITIES) or nil,
            search = payload.search and payload.search ~= '' and V.string(payload.search, 64) or nil,
        }
        local page = V.int(payload.page or 1, 1, 100000) or 1
        local pageSize = V.int(payload.pageSize or 50, 10, 200) or 50
        Carnival.Monitor.flush()
        local rows, total = Carnival.Monitor.query(f, page, pageSize)
        return { rows = rows, total = total, page = page, pageSize = pageSize, categories = C.MONITOR_CATEGORIES, severities = C.SEVERITIES }
    end,
})

Api.register('audit.query', {
    perm = 'audit.view', rate = 'admin',
    handler = function(ctx, payload)
        local f = {
            from = dateFilter(payload.from), to = dateFilter(payload.to),
            eventId = payload.eventId and V.id(payload.eventId) or nil,
            actor = payload.actor and payload.actor ~= '' and V.string(payload.actor, 80) or nil,
            action = payload.action and payload.action ~= '' and V.string(payload.action, 64) or nil,
            targetType = payload.targetType and payload.targetType ~= '' and V.string(payload.targetType, 32) or nil,
            targetId = payload.targetId and payload.targetId ~= '' and V.string(tostring(payload.targetId), 64) or nil,
        }
        local page = V.int(payload.page or 1, 1, 100000) or 1
        local rows, total = Carnival.Audit.query(f, page, 50)
        return { rows = rows, total = total, page = page, pageSize = 50 }
    end,
})

---------------------------------------------------------------------------
-- Staff role management
---------------------------------------------------------------------------
Api.register('staff.list', {
    perm = 'staff.manage', rate = 'admin',
    handler = function(ctx)
        local online = {}
        for _, s in ipairs(Carnival.Identity.online()) do
            online[#online + 1] = { source = s, name = Carnival.Identity.characterName(s), license = Carnival.Identity.license(s), role = Carnival.Perms.role(s) }
        end
        table.sort(online, function(a, b) return a.name < b.name end)
        local roles = {}
        for name, r in pairs(Config.Security.Roles) do roles[#roles + 1] = { id = name, label = r.label, rank = r.rank } end
        table.sort(roles, function(a, b) return a.rank > b.rank end)
        return {
            assignments = Carnival.Perms.listAssignments(), online = online, roles = roles,
            grantable = Carnival.Perms.grantableRoles(ctx.source), allowGrants = Config.Security.AllowDatabaseGrants,
        }
    end,
})

Api.register('staff.grant', {
    perm = 'staff.manage', rate = 'admin',
    handler = function(ctx, payload)
        local target = V.int(payload.source, 1, 65535)
        local license, name
        if target and GetPlayerName(target) then
            license, name = Carnival.Identity.license(target), Carnival.Identity.characterName(target)
        elseif type(payload.license) == 'string' and payload.license:match('^license2?:%x+$') then
            license, name = payload.license, payload.name and V.string(payload.name, 96, true) or nil
        else
            return nil, 'invalid', 'Choose an online player or enter a license identifier.'
        end
        local role = type(payload.role) == 'string' and payload.role or ''
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        local ok, res = Carnival.Perms.grant(ctx.source, license, name, role, payload.eventScoped == true, reason)
        if not ok then return nil, res, 'The role could not be granted (' .. tostring(res) .. ').' end
        if target then Carnival.Perms.invalidate(target) end
        return { id = res }
    end,
})

Api.register('staff.revoke', {
    perm = 'staff.manage', rate = 'admin',
    handler = function(ctx, payload)
        local id, err = V.id(payload.id)
        if not id then return nil, 'invalid', 'id ' .. err end
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        local ok, res = Carnival.Perms.revoke(ctx.source, id, reason)
        if not ok then return nil, res, 'The role could not be revoked (' .. tostring(res) .. ').' end
        return true
    end,
})

