-- World props placed with the admin prop placer.
--
-- Props are stored in carnival_props and survive restarts. They are not tied to
-- an event: the whole list goes to every player in the bootstrap push, and each
-- change is pushed to everyone (`props` channel), so every client spawns the
-- same props locally. Removing a prop keeps its row (deleted_at) for history.

local V = Carnival.Validate
local Props = {}
Carnival.Props = Props

local MAX_PROPS = 1000
local active = {}   -- [id] = public prop

local function public(row)
    return {
        id = row.id, model = row.model, label = row.label,
        x = row.x, y = row.y, z = row.z,
        rx = row.rot_x, ry = row.rot_y, rz = row.rot_z,
        collision = Carnival.Db.bool(row.collision),
        createdBy = row.created_by_name, createdAt = row.created_at, updatedAt = row.updated_at,
    }
end

function Props.load()
    active = {}
    for _, r in ipairs(Carnival.Db.query('SELECT * FROM carnival_props WHERE deleted_at IS NULL ORDER BY id') or {}) do
        active[r.id] = public(r)
    end
    Carnival.Monitor.log('info', 'props', 'props_loaded', { details = { count = Carnival.U.count(active) } })
end

-- Every placed prop, ordered by id (what clients spawn).
function Props.all()
    local out = {}
    for _, p in pairs(active) do out[#out + 1] = p end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Props.get(id) return active[id] end

local function number(v, min, max, name)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil, name .. ' must be a number' end
    if v < min or v > max then return nil, ('%s must be between %s and %s'):format(name, min, max) end
    return v
end

-- payload: { model, label?, x, y, z, rx?, ry?, rz?, collision? }
local function fields(payload, partial)
    local out = {}
    if payload.model ~= nil or not partial then
        local model, err = V.string(payload.model, 64)
        if not model then return nil, 'model ' .. err end
        if not model:match('^[%w_]+$') then return nil, 'model names may only contain letters, numbers and underscores' end
        out.model = model
    end
    if payload.label ~= nil then
        local label = V.string(payload.label, 64, true)
        if not label then return nil, 'label is too long' end
        out.label = label ~= '' and label or Carnival.Db.NULL
    end
    for _, k in ipairs({ 'x', 'y' }) do
        if payload[k] ~= nil or not partial then
            local v, err = number(payload[k], -10000, 10000, k)
            if not v then return nil, err end
            out[k] = v
        end
    end
    if payload.z ~= nil or not partial then
        local v, err = number(payload.z, -500, 3000, 'z')
        if not v then return nil, err end
        out.z = v
    end
    for k, col in pairs({ rx = 'rot_x', ry = 'rot_y', rz = 'rot_z' }) do
        if payload[k] ~= nil then
            local v, err = number(payload[k], -360, 360, k)
            if not v then return nil, err end
            out[col] = v
        end
    end
    if payload.collision ~= nil then out.collision = payload.collision == true and 1 or 0 end
    return out
end

local function refresh(id)
    local row = Carnival.Db.single('SELECT * FROM carnival_props WHERE id = ?', { id })
    if not row then return nil end
    if row.deleted_at then
        active[id] = nil
        return nil
    end
    active[id] = public(row)
    return active[id]
end

function Props.create(src, payload)
    if Carnival.U.count(active) >= MAX_PROPS then return nil, 'limit', ('There are already %d props placed.'):format(MAX_PROPS) end
    local f, err = fields(payload, false)
    if not f then return nil, 'invalid', err end
    local actor = Carnival.Identity.actor(src)
    f.created_by, f.created_by_name, f.created_at = actor.license, actor.name, os.time()
    if f.collision == nil then f.collision = 1 end
    if f.label == Carnival.Db.NULL then f.label = nil end
    local id = Carnival.Db.insertRow('carnival_props', f)
    if not id then return nil, 'database_error', 'The prop could not be saved.' end
    local prop = refresh(id)
    Carnival.Audit.record(actor, 'prop_placed', { targetType = 'prop', targetId = id, details = { model = prop.model, label = prop.label, x = prop.x, y = prop.y, z = prop.z } })
    Carnival.Push.all('props', { action = 'upsert', prop = prop })
    Carnival.Push.invalidate('props')
    return prop
end

function Props.update(src, id, payload)
    if not active[id] then return nil, 'not_found', 'That prop no longer exists.' end
    local f, err = fields(payload, true)
    if not f then return nil, 'invalid', err end
    if next(f) == nil then return nil, 'invalid', 'Nothing to change.' end
    local actor = Carnival.Identity.actor(src)
    f.updated_by, f.updated_at = actor.license, os.time()
    Carnival.Db.updateRow('carnival_props', f, 'id = ? AND deleted_at IS NULL', { id })
    local before = active[id]
    local prop = refresh(id)
    if not prop then return nil, 'database_error', 'The prop could not be saved.' end
    Carnival.Audit.record(actor, 'prop_updated', { targetType = 'prop', targetId = id, details = {
        model = prop.model, from = { x = before.x, y = before.y, z = before.z }, to = { x = prop.x, y = prop.y, z = prop.z } } })
    Carnival.Push.all('props', { action = 'upsert', prop = prop })
    Carnival.Push.invalidate('props')
    return prop
end

function Props.remove(src, id)
    local prop = active[id]
    if not prop then return nil, 'not_found', 'That prop no longer exists.' end
    local actor = Carnival.Identity.actor(src)
    local n = Carnival.Db.update('UPDATE carnival_props SET deleted_at = ?, deleted_by = ? WHERE id = ? AND deleted_at IS NULL', { os.time(), actor.license, id })
    if not n or n < 1 then return nil, 'database_error', 'The prop could not be removed.' end
    active[id] = nil
    Carnival.Audit.record(actor, 'prop_removed', { targetType = 'prop', targetId = id, details = { model = prop.model, label = prop.label } })
    Carnival.Push.all('props', { action = 'remove', id = id })
    Carnival.Push.invalidate('props')
    return true
end

Carnival.onReady(function() Props.load() end)

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local Api = Carnival.Api

Api.register('props.list', {
    perm = 'props.manage', rate = 'admin',
    handler = function()
        local models = {}
        for _, r in ipairs(Carnival.Db.query('SELECT model, COUNT(*) AS n FROM carnival_props GROUP BY model ORDER BY n DESC LIMIT 50') or {}) do
            models[#models + 1] = r.model
        end
        return { props = Props.all(), models = models, max = MAX_PROPS }
    end,
})

Api.register('props.create', {
    perm = 'props.manage', rate = 'admin',
    handler = function(ctx, payload) return Props.create(ctx.source, payload) end,
})

Api.register('props.update', {
    perm = 'props.manage', rate = 'admin',
    handler = function(ctx, payload)
        local id, err = V.id(payload.id)
        if not id then return nil, 'invalid', 'id ' .. err end
        return Props.update(ctx.source, id, payload)
    end,
})

Api.register('props.delete', {
    perm = 'props.manage', rate = 'admin',
    handler = function(ctx, payload)
        local id, err = V.id(payload.id)
        if not id then return nil, 'invalid', 'id ' .. err end
        return Props.remove(ctx.source, id)
    end,
})
