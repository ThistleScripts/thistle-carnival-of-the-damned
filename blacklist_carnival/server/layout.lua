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
        add('attractions.horror.entry', 'Horrors entry', 'entry', h.entry, { radius = Carnival.C.HORROR_DOOR_RADIUS })
        add('attractions.horror.exit', 'Horrors exit', 'exit', h.exit, { radius = h.exitRadius })
        add('attractions.horror.boundaryCentre', 'Horrors boundary', 'boundary', h.boundaryCentre, { radius = h.boundaryRadius })
        local eh = h.escapeHatches
        add('attractions.horror.escapeHatches.returnTo', 'Escape hatch drop-off', 'return', eh.returnTo)
        for _, hp in ipairs(eh.points) do
            add('hatch:' .. hp.id, 'Escape hatch ' .. hp.id, 'hatch', hp.coords, { id = hp.id, radius = eh.radius })
        end
        for _, t in ipairs(h.tokens) do
            add('token:' .. t.id, ('%s coin %s'):format(t.type:gsub('^%l', string.upper), t.id), 'token', t.coords,
                { id = t.id, type = t.type, model = h.tokenTypes[t.type] and h.tokenTypes[t.type].model })
        end
    end
    local d = cfg.attractions.deception
    if d.enabled then
        add('attractions.deception.start', 'Hall of Deception start', 'mazeStart', d.start)
        add('attractions.deception.finish', 'Hall of Deception way out', 'mazeFinish', d.finish, { radius = d.finishRadius })
        add('attractions.deception.exitTo', 'Hall of Deception drop-off', 'return', d.exitTo)
        local labels = {}
        for _, door in ipairs(d.doors) do labels[door.id] = door.label end
        for _, door in ipairs(d.doors) do
            add('door:' .. door.id, ('%s (%s)'):format(door.label, door.id), 'door', door.coords,
                { id = door.id, to = door.to, toLabel = door.to == 'start' and 'the start' or labels[door.to] })
        end
        for _, t in ipairs(d.traps) do
            add('trap:' .. t.id, 'Trap ' .. t.id, 'trap', t.coords, { id = t.id, radius = d.trapRadius })
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
    if path == 'attractions.horror.entry' or path == 'attractions.horror.escapeHatches.returnTo' then return { heading = true } end
    if path == 'attractions.horror.exit' then return { heading = true, radius = 'attractions.horror.exitRadius' } end
    if path == 'attractions.horror.boundaryCentre' then return { radius = 'attractions.horror.boundaryRadius' } end
    if path == 'attractions.deception.start' or path == 'attractions.deception.exitTo' then return { heading = true } end
    if path == 'attractions.deception.finish' then return { heading = true, radius = 'attractions.deception.finishRadius' } end
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
            if m.radius and radius then setPath(doc, m.radius, U.round(radius, 1)) end
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

Api.register('layout.hatch', {
    perm = PERM, rate = 'admin',
    handler = function(ctx, payload)
        local op = V.oneOf(payload.op, { 'add', 'move', 'remove' })
        if not op then return nil, 'invalid', 'op must be add, move or remove' end
        local coords, err
        if op ~= 'remove' then
            coords, err = V.vec3(payload.coords)
            if not coords then return nil, 'invalid', 'coords ' .. err end
        end
        local id = type(payload.id) == 'string' and payload.id:sub(1, 32) or nil
        local newId
        return save(ctx.source, 'Layout: escape hatch ' .. op, function(doc)
            local list = doc.attractions.horror.escapeHatches.points
            if op == 'add' then
                if #list >= 20 then return nil, 'invalid', 'The maze already has 20 escape hatches.' end
                newId = newId or nextTokenId(list, 'hatch')
                list[#list + 1] = { id = newId, coords = coords }
                return true
            end
            for i, hp in ipairs(list) do
                if hp.id == id then
                    if op == 'remove' then table.remove(list, i) else hp.coords = coords end
                    return true
                end
            end
            return nil, 'not_found', 'That escape hatch no longer exists.'
        end)
    end,
})

-- Hall of Deception doors: add, move, remove, and choose where one leads.
Api.register('layout.door', {
    perm = PERM, rate = 'admin',
    handler = function(ctx, payload)
        local op = V.oneOf(payload.op, { 'add', 'move', 'remove', 'link' })
        if not op then return nil, 'invalid', 'op must be add, move, remove or link' end
        local coords, err
        if op == 'add' or op == 'move' then
            coords, err = V.vec4(payload.coords)
            if not coords then return nil, 'invalid', 'coords ' .. err end
        end
        local id = type(payload.id) == 'string' and payload.id:sub(1, 32) or nil
        local to = type(payload.to) == 'string' and payload.to:sub(1, 32) or nil
        local newId
        return save(ctx.source, 'Layout: door ' .. op, function(doc)
            local doors = doc.attractions.deception.doors
            if op == 'add' then
                if #doors >= 60 then return nil, 'invalid', 'The hall already has 60 doors.' end
                newId = newId or nextTokenId(doors, 'door')
                doors[#doors + 1] = { id = newId, label = 'Door ' .. newId:sub(2), coords = coords, to = 'start' }
                return true
            end
            for i, d in ipairs(doors) do
                if d.id == id then
                    if op == 'remove' then
                        table.remove(doors, i)
                        -- anything that led here now leads back to the start
                        for _, other in ipairs(doors) do if other.to == id then other.to = 'start' end end
                    elseif op == 'move' then
                        d.coords = coords
                    else
                        if not to then return nil, 'invalid', 'Choose a door or "start".' end
                        d.to = to
                    end
                    return true
                end
            end
            return nil, 'not_found', 'That door no longer exists.'
        end)
    end,
})

Api.register('layout.trap', {
    perm = PERM, rate = 'admin',
    handler = function(ctx, payload)
        local op = V.oneOf(payload.op, { 'add', 'move', 'remove' })
        if not op then return nil, 'invalid', 'op must be add, move or remove' end
        local coords, err
        if op ~= 'remove' then
            coords, err = V.vec3(payload.coords)
            if not coords then return nil, 'invalid', 'coords ' .. err end
        end
        local id = type(payload.id) == 'string' and payload.id:sub(1, 32) or nil
        local newId
        return save(ctx.source, 'Layout: trap ' .. op, function(doc)
            local traps = doc.attractions.deception.traps
            if op == 'add' then
                if #traps >= 60 then return nil, 'invalid', 'The hall already has 60 traps.' end
                newId = newId or nextTokenId(traps, 'trap')
                traps[#traps + 1] = { id = newId, coords = coords }
                return true
            end
            for i, t in ipairs(traps) do
                if t.id == id then
                    if op == 'remove' then table.remove(traps, i) else t.coords = coords end
                    return true
                end
            end
            return nil, 'not_found', 'That trap no longer exists.'
        end)
    end,
})
