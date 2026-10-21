-- World props: every player spawns the server's prop list locally while near,
-- and admins (props.manage) place, move and remove props with an in-world
-- placement mode. The server stores and validates every change.

local Props = {}
Carnival.Props = Props

local SPAWN_DISTANCE, DESPAWN_DISTANCE = 150.0, 180.0
local placed = {}      -- [id] = { data, entity, failed }
local placing = nil    -- active placement (one at a time)

local function canManage() return Carnival.has('props.manage') end

local function deleteEntity(p)
    if p.entity and DoesEntityExist(p.entity) then
        exports.ox_target:removeLocalEntity(p.entity)
        DeleteEntity(p.entity)
    end
    p.entity = nil
end

local function loadModel(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    if not pcall(lib.requestModel, model, 5000) then return nil end
    return hash
end

local function targetOptions(id)
    return {
        { name = 'carnival_prop_move_' .. id, icon = 'fa-solid fa-up-down-left-right', label = 'Admin: move prop',
            canInteract = canManage, onSelect = function() Props.place({ id = id }) end },
        { name = 'carnival_prop_remove_' .. id, icon = 'fa-solid fa-trash', label = 'Admin: remove prop',
            canInteract = canManage, onSelect = function() Props.confirmRemove(id) end },
    }
end

local function spawn(p)
    local d = p.data
    local hash = loadModel(d.model)
    if not hash then
        p.failed = true
        print(('^3[blacklist_carnival] prop #%d: model "%s" is not streamed^0'):format(d.id, d.model))
        return
    end
    local obj = CreateObjectNoOffset(hash, d.x + 0.0, d.y + 0.0, d.z + 0.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 then p.failed = true return end
    SetEntityRotation(obj, (d.rx or 0) + 0.0, (d.ry or 0) + 0.0, (d.rz or 0) + 0.0, 2, false)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, d.collision ~= false, d.collision ~= false)
    SetEntityInvincible(obj, true)
    p.entity = obj
    exports.ox_target:addLocalEntity(obj, targetOptions(d.id))
end

local function upsert(data)
    local p = placed[data.id]
    if p then deleteEntity(p) end
    placed[data.id] = { data = data }
end

local function remove(id)
    local p = placed[id]
    if not p then return end
    deleteEntity(p)
    placed[id] = nil
end

local function clearAll()
    for id in pairs(placed) do remove(id) end
end

Carnival.onPush('bootstrap', function(data)
    clearAll()
    for _, prop in ipairs(data.props or {}) do upsert(prop) end
end)

Carnival.onPush('props', function(data)
    if data.action == 'upsert' and data.prop then upsert(data.prop)
    elseif data.action == 'remove' then remove(data.id) end
end)

-- Stream props in and out around the player.
CreateThread(function()
    while true do
        Wait(1000)
        local pos = GetEntityCoords(PlayerPedId())
        for _, p in pairs(placed) do
            local d = p.data
            local dist = #(pos - vector3(d.x, d.y, d.z))
            if not p.entity and not p.failed and not p.hidden and dist <= SPAWN_DISTANCE then
                spawn(p)
            elseif p.entity and dist > DESPAWN_DISTANCE then
                deleteEntity(p)
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Placement mode
---------------------------------------------------------------------------
local HELP = table.concat({
    '**Placing %s**',
    'Look to move it',
    'Scroll: rotate (Shift: fine)',
    'Arrow up/down: raise/lower (Shift: faster)',
    'Arrow left/right: tilt',
    'G: drop onto the ground · X: reset',
    'Enter / left click: place',
    'Backspace / right click: cancel',
}, '  \n')

local BLOCKED = { 14, 15, 16, 17, 24, 25, 37, 44, 45, 47, 73, 140, 141, 142, 172, 173, 174, 175, 177, 191, 194, 199, 200, 257, 263 }

local function finish(ok)
    local pl = placing
    if not pl then return end
    placing = nil
    lib.hideTextUI()
    local coords, rot = GetEntityCoords(pl.ghost), GetEntityRotation(pl.ghost, 2)
    DeleteEntity(pl.ghost)
    SetModelAsNoLongerNeeded(pl.hash)
    local existing = pl.id and placed[pl.id]
    if existing then existing.hidden = nil end
    if not ok then
        if existing then deleteEntity(existing) end -- respawned by the streaming loop
        return lib.notify({ title = 'Props', description = 'Placement cancelled.', type = 'inform' })
    end
    local payload = {
        id = pl.id, model = pl.model, label = pl.label, collision = pl.collision,
        x = coords.x, y = coords.y, z = coords.z, rx = rot.x, ry = rot.y, rz = rot.z,
    }
    local res, code, msg = Carnival.api(pl.id and 'props.update' or 'props.create', payload)
    if res then
        lib.notify({ title = 'Props', description = (pl.id and 'Prop moved.' or 'Prop placed.') .. ' Everyone can see it now.', type = 'success' })
    else
        if existing then deleteEntity(existing) end
        lib.notify({ title = 'Props', description = msg or code, type = 'error' })
    end
end

-- opts: { id? (move an existing prop), model?, label?, collision? }
function Props.place(opts)
    if placing then return lib.notify({ title = 'Props', description = 'You are already placing a prop.', type = 'error' }) end
    if not canManage() then return lib.notify({ title = 'Props', description = 'You cannot place props.', type = 'error' }) end
    local existing = opts.id and placed[opts.id]
    if opts.id and not existing then return lib.notify({ title = 'Props', description = 'That prop no longer exists.', type = 'error' }) end
    local src = existing and existing.data or {}
    local model = opts.model or src.model
    local hash = model and loadModel(model)
    if not hash then
        return lib.notify({ title = 'Props', description = ('"%s" is not a streamed model. Check the file names in stream/props.'):format(tostring(model)), type = 'error' })
    end
    local pos = GetEntityCoords(PlayerPedId())
    local ghost = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
    SetEntityAlpha(ghost, 190, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    if existing then
        existing.hidden = true
        deleteEntity(existing)
    end
    placing = {
        id = opts.id, model = model, hash = hash, ghost = ghost,
        label = opts.label or src.label, collision = opts.collision ~= nil and opts.collision or src.collision ~= false,
        heading = src.rz or GetEntityHeading(PlayerPedId()), tilt = src.ry or 0.0, height = 0.0,
    }
    lib.showTextUI(HELP:format(src.label or model), { position = 'left-center' })
    CreateThread(function()
        while placing and placing.ghost == ghost do
            for _, c in ipairs(BLOCKED) do DisableControlAction(0, c, true) end
            local pl = placing
            local fine = IsControlPressed(0, 21)
            if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then pl.heading = pl.heading + (fine and 1 or 7.5) end
            if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then pl.heading = pl.heading - (fine and 1 or 7.5) end
            if IsDisabledControlPressed(0, 172) then pl.height = pl.height + (fine and 0.05 or 0.01) end
            if IsDisabledControlPressed(0, 173) then pl.height = pl.height - (fine and 0.05 or 0.01) end
            if IsDisabledControlJustPressed(0, 174) then pl.tilt = pl.tilt - 5.0 end
            if IsDisabledControlJustPressed(0, 175) then pl.tilt = pl.tilt + 5.0 end
            if IsDisabledControlJustPressed(0, 73) then pl.heading, pl.tilt, pl.height = GetEntityHeading(PlayerPedId()), 0.0, 0.0 end
            pl.heading = (pl.heading + 360.0) % 360.0

            local hit, _, coords = lib.raycast.cam(1 | 16, 4, 25.0)
            if not hit then
                local cam, dir = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2)
                local rx, rz = math.rad(dir.x), math.rad(dir.z)
                coords = cam + vector3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx)) * 6.0
            end
            SetEntityCoordsNoOffset(ghost, coords.x, coords.y, coords.z + pl.height, false, false, false)
            SetEntityRotation(ghost, 0.0, pl.tilt + 0.0, pl.heading + 0.0, 2, false)
            if IsDisabledControlJustPressed(0, 47) then
                PlaceObjectOnGroundProperly(ghost)
                pl.height, pl.tilt = GetEntityCoords(ghost).z - coords.z, 0.0
            end

            if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 24) then finish(true) break end
            if IsDisabledControlJustPressed(0, 194) or IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 25) then finish(false) break end
            Wait(0)
        end
    end)
end

function Props.confirmRemove(id)
    local p = placed[id]
    if not p then return end
    local ok = lib.alertDialog({
        header = 'Remove prop?', content = ('Remove %s for everyone?'):format(p.data.label or p.data.model),
        centered = true, cancel = true,
    })
    if ok ~= 'confirm' then return end
    local res, code, msg = Carnival.api('props.delete', { id = id })
    lib.notify({ title = 'Props', description = res and 'Prop removed.' or (msg or code), type = res and 'success' or 'error' })
end

-- From the admin panel (Settings → Props).
RegisterNUICallback('propPlace', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' then return end
    CreateThread(function()
        Props.place({ id = tonumber(data.id), model = data.model, label = data.label, collision = data.collision })
    end)
end)

RegisterCommand('carnivalprop', function(_, args)
    if not args[1] then
        return lib.notify({ title = 'Props', description = 'Usage: /carnivalprop <model> [label]', type = 'inform' })
    end
    Props.place({ model = args[1], label = args[2] and table.concat(args, ' ', 2) or nil })
end, false)

TriggerEvent('chat:addSuggestion', '/carnivalprop', 'Place a carnival prop (admins)', {
    { name = 'model', help = 'Streamed model name, e.g. carnivalcoingold' },
    { name = 'label', help = 'Optional name shown in the admin panel' },
})

Carnival.onCleanup(function()
    if placing then
        lib.hideTextUI()
        DeleteEntity(placing.ghost)
        placing = nil
    end
    clearAll()
end)
