-- Central permission service.
--
-- A player's role is the highest-ranked of:
--   1. Config.Security.Allowlist (license -> role)
--   2. ACE `carnival.role.<role>`
--   3. active in-game staff assignment (carnival_staff_assignments), capped at
--      Config.Security.MaxGrantableRank
-- Extra individual permissions: ACE `carnival.perm.<permission>`.
-- Attraction scoping: ACE `carnival.attraction.<id>` or an assignment with attraction_id.
--
-- Every privileged API handler, command and export calls Perms.has() on the server.

local C = Carnival.C
local Perms = {}
Carnival.Perms = Perms

local cache = {}         -- [src] = { at, role, perms = set, assigned = set }
local assignments = {}   -- [license] = list of active assignment rows

local function roleRank(role)
    local r = role and Config.Security.Roles[role]
    return r and r.rank or 0
end
Perms.roleRank = roleRank

function Perms.loadAssignments()
    assignments = {}
    local rows = Carnival.Db.query('SELECT * FROM carnival_staff_assignments WHERE revoked_at IS NULL') or {}
    local activeEvent = Carnival.Events and Carnival.Events.activeId() or nil
    for _, r in ipairs(rows) do
        if r.event_id == nil or r.event_id == activeEvent then
            assignments[r.license] = assignments[r.license] or {}
            table.insert(assignments[r.license], r)
        end
    end
    Perms.invalidate()
end

local function ace(src, name)
    return IsPlayerAceAllowed(tostring(src), Config.Security.AcePrefix .. '.' .. name)
end

local function resolve(src)
    local licenses = Carnival.Identity.licenses(src)
    local role, rank = nil, 0
    local function consider(r, cap)
        local rr = roleRank(r)
        if cap and rr > cap then return end
        if rr > rank then role, rank = r, rr end
    end

    for _, l in ipairs(licenses) do
        local r = Config.Security.Allowlist[l]
        if r then consider(r) end
    end
    for name in pairs(Config.Security.Roles) do
        if ace(src, 'role.' .. name) then consider(name) end
    end
    local assigned = {}
    if Config.Security.AllowDatabaseGrants then
        for _, l in ipairs(licenses) do
            for _, a in ipairs(assignments[l] or {}) do
                consider(a.role, Config.Security.MaxGrantableRank)
                if a.attraction_id then assigned[a.attraction_id] = true end
            end
        end
    end
    for _, a in ipairs(C.ATTRACTIONS) do
        if ace(src, 'attraction.' .. a) then assigned[a] = true end
    end

    local perms = {}
    local function grant(p)
        if p == '*' then
            for _, x in ipairs(C.PERMISSIONS) do perms[x] = true end
        elseif p == 'attractions.operate.@assigned' then
            for a in pairs(assigned) do perms['attractions.operate.' .. a] = true end
        elseif p:sub(-1) == '*' then
            local prefix = p:sub(1, -2)
            for _, x in ipairs(C.PERMISSIONS) do
                if x:sub(1, #prefix) == prefix then perms[x] = true end
            end
        else
            perms[p] = true
        end
    end
    if role then
        for _, p in ipairs(Config.Security.Roles[role].permissions) do grant(p) end
    end
    for _, p in ipairs(C.PERMISSIONS) do
        if not perms[p] and ace(src, 'perm.' .. p) then perms[p] = true end
    end

    -- Separate allowlist for horror controls.
    if perms['horror.control'] and Config.Security.RequireHorrorAllowlist
        and not (role and Config.Security.HorrorAllowlistBypassRoles[role]) then
        local listed = false
        local set = Carnival.U.toSet(Config.Security.HorrorControllers)
        for _, l in ipairs(licenses) do
            if set[l] then listed = true end
        end
        if not listed then perms['horror.control'] = nil end
    end

    return { at = os.time(), role = role, rank = rank, perms = perms, assigned = assigned }
end

local function get(src)
    if not src or src <= 0 then return nil end
    local c = cache[src]
    if not c or os.time() - c.at > (Config.Security.PermissionCacheSeconds or 30) then
        c = resolve(src)
        cache[src] = c
    end
    return c
end

function Perms.has(src, perm)
    if src == 0 then return true end -- server console
    local c = get(src)
    return c ~= nil and c.perms[perm] == true
end

function Perms.hasAny(src, list)
    for _, p in ipairs(list) do
        if Perms.has(src, p) then return true end
    end
    return false
end

function Perms.role(src)
    if src == 0 then return 'owner' end
    local c = get(src)
    return c and c.role or nil
end

function Perms.rank(src)
    if src == 0 then return 1000 end
    local c = get(src)
    return c and c.rank or 0
end

function Perms.list(src)
    local c = get(src)
    local out = {}
    if c then for p in pairs(c.perms) do out[#out + 1] = p end end
    table.sort(out)
    return out
end

function Perms.isStaff(src)
    return Perms.has(src, 'panel.staff') or Perms.has(src, 'panel.admin')
end

function Perms.canOperate(src, attractionId)
    return Perms.has(src, 'attractions.operate.' .. attractionId)
end

-- Drop cached permissions (one player or everyone) and push fresh permission
-- lists to affected clients so open panels update immediately.
function Perms.invalidate(src)
    if src then
        cache[src] = nil
        if Carnival.Push then Carnival.Push.permissions(src) end
    else
        local srcs = {}
        for s in pairs(cache) do srcs[#srcs + 1] = s end
        cache = {}
        if Carnival.Push then
            for _, s in ipairs(srcs) do Carnival.Push.permissions(s) end
        end
    end
end

-- Staff assignments ------------------------------------------------------------

function Perms.grantableRoles(src)
    local out = {}
    local maxRank = math.min(Config.Security.MaxGrantableRank, Perms.rank(src) - 1)
    for name, r in pairs(Config.Security.Roles) do
        if r.rank <= maxRank then out[#out + 1] = { id = name, label = r.label, rank = r.rank } end
    end
    table.sort(out, function(a, b) return a.rank > b.rank end)
    return out
end

function Perms.grant(actorSrc, license, displayName, role, attractionId, eventScoped, reason)
    if not Config.Security.AllowDatabaseGrants then return false, 'grants_disabled' end
    local r = Config.Security.Roles[role]
    if not r then return false, 'unknown_role' end
    if r.rank > Config.Security.MaxGrantableRank then return false, 'role_not_grantable' end
    if r.rank >= Perms.rank(actorSrc) then return false, 'cannot_grant_equal_or_higher_role' end
    if attractionId and not C.ATTRACTION_INDEX[attractionId] then return false, 'invalid_attraction' end
    local actor = Carnival.Identity.actor(actorSrc)
    local id = Carnival.Db.insertRow('carnival_staff_assignments', {
        license = license, display_name = displayName, role = role, attraction_id = attractionId,
        event_id = eventScoped and Carnival.Events.activeId() or nil,
        granted_by = actor.license, reason = reason, created_at = os.time(),
    })
    if not id then return false, 'database_error' end
    Carnival.Audit.record(actor, 'staff_role_granted', { targetType = 'staff', targetId = license, reason = reason,
        details = { role = role, attraction = attractionId, assignmentId = id, eventScoped = eventScoped } })
    Perms.loadAssignments()
    return true, id
end

function Perms.revoke(actorSrc, assignmentId, reason)
    local row = Carnival.Db.single('SELECT * FROM carnival_staff_assignments WHERE id = ? AND revoked_at IS NULL', { assignmentId })
    if not row then return false, 'not_found' end
    if roleRank(row.role) >= Perms.rank(actorSrc) then return false, 'cannot_revoke_equal_or_higher_role' end
    local actor = Carnival.Identity.actor(actorSrc)
    local n = Carnival.Db.update('UPDATE carnival_staff_assignments SET revoked_at = ?, revoked_by = ?, revoke_reason = ? WHERE id = ? AND revoked_at IS NULL',
        { os.time(), actor.license, reason, assignmentId })
    if not n or n < 1 then return false, 'database_error' end
    Carnival.Audit.record(actor, 'staff_role_revoked', { targetType = 'staff', targetId = row.license, reason = reason,
        details = { role = row.role, attraction = row.attraction_id, assignmentId = assignmentId } })
    Perms.loadAssignments()
    return true
end

function Perms.listAssignments()
    return Carnival.Db.query('SELECT * FROM carnival_staff_assignments ORDER BY revoked_at IS NULL DESC, id DESC LIMIT 300') or {}
end

-- Online staff (for performer assignment / readiness).
function Perms.onlineStaff()
    local out = {}
    for _, s in ipairs(Carnival.Identity.online()) do
        if Perms.isStaff(s) then
            local c = get(s)
            out[#out + 1] = { source = s, name = Carnival.Identity.characterName(s), role = c and c.role, assigned = c and Carnival.U.keys(c.assigned) or {} }
        end
    end
    return out
end

AddEventHandler('playerDropped', function()
    cache[source] = nil
end)

Carnival.onReady(function()
    Perms.loadAssignments()
end)
