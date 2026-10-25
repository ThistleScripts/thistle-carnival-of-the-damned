-- In-world layout: admins walk the carnival and move the NPCs, the maze entry,
-- exit and boundary, and the House of Horrors coins where they stand (client
-- /carnivallayout). Every change is validated and saved as a normal config
-- version, so it shows in the history and can be rolled back.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Api = Carnival.Api
local Cfg = Carnival.Config

local Layout = {}
Carnival.Layout = Layout

local PERM = { 'panel.admin', 'config.edit' }
local MAX_TOKENS = 200

-- Every point that can be moved: config path, what it is and how it looks.
local function points(cfg)
    local out = {}
    local function add(path, label, kind, coords, extra)
        local p = { path = path, label = label, kind = kind, coords = coords }
        for k, v in pairs(extra or {}) do p[k] = v end
        out[#out + 1] = p
    end
    add('registration.entrance', 'Ticket booth', 'ped', cfg.registration.entrance, { model = cfg.registration.npcModel })
    for _, id in ipairs(C.ATTRACTIONS) do
        local a = cfg.attractions[id]
        if a.enabled then add('attractions.' .. id .. '.location', a.label, 'ped', a.location, { model = a.npcModel }) end
    end
    if cfg.shop.enabled then add('shop.location', cfg.shop.label, 'ped', cfg.shop.location, { model = cfg.shop.npcModel }) end
    local h = cfg.attractions.horror
    if h.enabled then
        add('attractions.horror.entry', 'Maze entry', 'entry', h.entry, { radius = Carnival.C.HORROR_DOOR_RADIUS })
        add('attractions.horror.exit', 'Maze exit', 'exit', h.exit, { radius = h.exitRadius })
        add('attractions.horror.boundaryCentre', 'Maze boundary', 'boundary', h.boundaryCentre, { radius = h.boundaryRadius })
        for _, t in ipairs(h.tokens) do
            add('token:' .. t.id, ('%s coin %s'):format(t.type:gsub('^%l', string.upper), t.id), 'token', t.coords,
                { id = t.id, type = t.type, model = h.tokenTypes[t.type] and h.tokenTypes[t.type].model })
        end
    end
    return out
end

function Layout.points() return points(Cfg.get()) end

-- path -> { vec4?, radiusKey? }
local function movable(path)
    if path == 'registration.entrance' or path == 'shop.location' then return { heading = true } end
    local id = path:match('^attractions%.([%w_]+)%.location$')
    if id and Cfg.get().attractions[id] then return { heading = true } end
    if path == 'attractions.horror.entry' then return { heading = true } end
    if path == 'attractions.horror.exit' then return { heading = true, radius = 'exitRadius' } end
    if path == 'attractions.horror.boundaryCentre' then return { radius = 'boundaryRadius' } end
    return nil
end

local function setPath(doc, path, value)
    local node = doc
    local parts = {}
    for part in path:gmatch('[^.]+') do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do node = node[parts[i]] end
    node[parts[#parts]] = value
end

-- Apply `mutate` to the saved settings (and to tonight's override, if there is
-- one, so the change is visible straight away) and save.
local function save(src, note, mutate)
    local scopes = { 'global' }
    if Cfg.versionInfo().source == 'event' then scopes[#scopes + 1] = 'event' end
    for _, scope in ipairs(scopes) do
        local doc = Cfg.document(scope)
        local ok, code, msg = mutate(doc)
        if not ok then return nil, code, msg end
        local res, err, info = Cfg.save(src, scope, doc, note, true)
        if err == 'invalid' and type(info) == 'table' then
            local first = info.errors and info.errors[1]
            return nil, 'invalid', first and ('%s: %s'):format(first.path, first.message) or 'That position is not valid.'
        end
        if err and err ~= 'no_changes' then return nil, err, info end
        if res and res.needsConfirm then return nil, 'invalid', 'The change could not be confirmed.' end
    end
    return { points = Layout.points() }
end

local function nextTokenId(tokens, ttype)
    local prefix = ttype:sub(1, 1)
    local used, n = {}, 0
    for _, t in ipairs(tokens) do used[t.id] = true end
    repeat n = n + 1 until not used[prefix .. n]
    return prefix .. n
end

Api.register('layout.get', {
    perm = PERM, rate = 'admin',
    handler = function() return { points = Layout.points() } end,
})

Api.register('layout.set', {
    perm = PERM, rate = 'admin',
    handler = function(ctx, payload)
        local path = type(payload.path) == 'string' and payload.path or ''
        local m = movable(path)
        if not m then return nil, 'invalid', 'That point cannot be moved here.' end
        local coords, err = (m.heading and V.vec4 or V.vec3)(payload.coords)
        if not coords then return nil, 'invalid', 'coords ' .. err end
        local radius = payload.radius ~= nil and V.number(payload.radius, 0.5, 500) or nil
        return save(ctx.source, 'Layout: moved ' .. path, function(doc)
            setPath(doc, path, coords)
            if m.radius and radius then doc.attractions.horror[m.radius] = U.round(radius, 1) end
            return true
        end)
    end,
})

Api.register('layout.token', {
    perm = PERM, rate = 'admin',
    handler = function(ctx, payload)
        local op = V.oneOf(payload.op, { 'add', 'move', 'remove', 'retype' })
        if not op then return nil, 'invalid', 'op must be add, move, remove or retype' end
        local coords, err
        if op == 'add' or op == 'move' then
            coords, err = V.vec3(payload.coords)
            if not coords then return nil, 'invalid', 'coords ' .. err end
        end
        local ttype = payload.type ~= nil and V.oneOf(payload.type, C.TOKEN_TYPES) or nil
        if (op == 'add' or op == 'retype') and not ttype then return nil, 'invalid', 'type must be bronze, silver or gold' end
        local id = type(payload.id) == 'string' and payload.id:sub(1, 32) or nil
        local label
        return save(ctx.source, 'Layout: coin ' .. op, function(doc)
            local tokens = doc.attractions.horror.tokens
            if op == 'add' then
                if #tokens >= MAX_TOKENS then return nil, 'invalid', ('The maze already has %d coin spots.'):format(MAX_TOKENS) end
                label = label or nextTokenId(tokens, ttype)
                tokens[#tokens + 1] = { id = label, type = ttype, coords = coords }
                return true
            end
            for i, t in ipairs(tokens) do
                if t.id == id then
                    if op == 'remove' then table.remove(tokens, i)
                    elseif op == 'move' then t.coords = coords
                    else t.type = ttype end
                    return true
                end
            end
            return nil, 'not_found', 'That coin spot no longer exists.'
        end)
    end,
})
