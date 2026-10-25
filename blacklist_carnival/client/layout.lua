-- Layout mode (/carnivallayout): admins walk the carnival and see every NPC
-- spot, the maze entry, exit and boundary, and every coin spot as markers in the
-- world. Aim at one and press E to pick it up, put it down where you look, add
-- or remove coins - each change is saved by the server straight away (a normal
-- config version, so it can be rolled back from the panel).

local Layout = {}
Carnival.Layout = Layout

local active = false
local points = {}
local carrying = nil   -- { point, ghost, heading, radius }
local busy = false

local DRAW_DISTANCE = 150.0
local TYPE_KEYS = { { key = 157, type = 'bronze' }, { key = 158, type = 'silver' }, { key = 160, type = 'gold' }, { key = 164, type = 'hatch' } }
local TYPES = { 'bronze', 'silver', 'gold' }
local COLOURS = {
    ped = { 170, 90, 255 }, entry = { 150, 60, 220 }, exit = { 60, 220, 110 }, boundary = { 255, 120, 40 },
    hatch = { 255, 140, 30 }, ['return'] = { 255, 140, 30 },
    bronze = { 205, 127, 50 }, silver = { 200, 210, 230 }, gold = { 255, 200, 60 },
}
local BLOCKED = { 24, 25, 37, 44, 45, 47, 73, 140, 141, 142, 157, 158, 160, 164, 257, 263 }
local BLOCKED_CARRY = { 14, 15, 16, 17, 172, 173, 191, 194, 199, 200, 177 }

local HELP = table.concat({
    '**Carnival layout**',
    'Aim at a marker · E: pick it up',
    '1 / 2 / 3: add a bronze / silver / gold coin',
    '4: add an escape hatch',
    'G: change coin colour · X: remove coin or hatch',
    'Backspace: leave layout mode',
}, '  \n')

local HELP_CARRY = table.concat({
    '**Moving %s**',
    'Look where it should go',
    'Scroll: turn · Arrow up/down: resize',
    'Enter / left click: put it here',
    'Right click: cancel',
}, '  \n')

local function colourOf(p) return COLOURS[p.type] or COLOURS[p.kind] or { 255, 255, 255 } end

local function text3d(x, y, z, label, scale)
    SetTextScale(0.0, scale or 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 235)
    SetTextOutline()
    SetTextCentre(true)
    SetDrawOrigin(x, y, z, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function aim()
    local hit, _, coords = lib.raycast.cam(1 | 16, 4, 40.0)
    if hit then return coords end
    return nil
end

local function vec(c) return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0) end

local function drawPoint(p, highlight, at, heading, radius)
    local c = at or vec(p.coords)
    local r, g, b = table.unpack(colourOf(p))
    local a = highlight and 230 or 150
    if p.kind == 'ped' or p.kind == 'return' then
        DrawMarker(1, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.9, 0.9, 1.9, r, g, b, highlight and 120 or 60, false, false, 2, false, nil, nil, false)
        -- facing arrow
        DrawMarker(2, c.x, c.y, c.z + 2.2, 0.0, 0.0, 0.0, 90.0, 0.0, (heading or p.coords.w or 0.0) + 90.0, 0.4, 0.4, 0.4, r, g, b, a, false, false, 2, false, nil, nil, false)
    elseif p.kind == 'token' then
        DrawMarker(6, c.x, c.y, c.z + 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, r, g, b, a, false, false, 2, true, nil, nil, false)
        DrawMarker(25, c.x, c.y, c.z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.7, 0.7, 0.7, r, g, b, a, false, false, 2, false, nil, nil, false)
    else
        local d = (radius or p.radius or 1.5) * 2.0
        if p.kind == 'boundary' then
            DrawMarker(1, c.x, c.y, c.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, d, d, 3.0, r, g, b, highlight and 45 or 22, false, false, 2, false, nil, nil, false)
            DrawMarker(28, c.x, c.y, c.z + 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, r, g, b, a, false, false, 2, false, nil, nil, false)
        else
            DrawMarker(25, c.x, c.y, c.z + 0.04, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, d, d, d, r, g, b, a, false, false, 2, false, nil, nil, false)
            DrawMarker(1, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, d, d, 1.0, r, g, b, highlight and 90 or 45, false, false, 2, false, nil, nil, false)
        end
    end
    local label = p.label
    if highlight and not carrying then
        label = label .. (p.kind == 'token' and '~n~E: move · G: colour · X: remove' or p.kind == 'hatch' and '~n~E: move · X: remove' or '~n~E: move')
    end
    text3d(c.x, c.y, c.z + (p.kind == 'token' and 1.4 or 2.6), label, highlight and 0.36 or 0.3)
end

local function refresh(list)
    if list then points = list return end
    local res, code, msg = Carnival.api('layout.get', {})
    if not res then
        lib.notify({ title = 'Layout', description = msg or code, type = 'error' })
        return false
    end
    points = res.points or {}
    return true
end

local function send(name, payload, done)
    if busy then return end
    busy = true
    CreateThread(function()
        local res, code, msg = Carnival.api(name, payload)
        busy = false
        if res then
            refresh(res.points)
            lib.notify({ title = 'Layout', description = done, type = 'success' })
        else
            lib.notify({ title = 'Layout', description = msg or code, type = 'error' })
        end
    end)
end

-- The marker the admin is looking at (or standing on).
local function targeted(pos)
    local hit = aim()
    local best, bestD
    for _, p in ipairs(points) do
        local c = vec(p.coords)
        local d = math.min(hit and #(hit - c) or 99.0, #(pos - vector3(0.0, 0.0, 1.0) - c))
        local reach = p.kind == 'token' and 1.2 or (p.kind == 'ped' and 1.5 or math.max(1.5, math.min(p.radius or 1.5, 3.0)))
        if d <= reach and (not bestD or d < bestD) then best, bestD = p, d end
    end
    return best
end

local function deleteGhost()
    if carrying and carrying.ghost and DoesEntityExist(carrying.ghost) then DeleteEntity(carrying.ghost) end
end

local function pickUp(p)
    carrying = { point = p, heading = p.coords.w or GetEntityHeading(PlayerPedId()), radius = p.radius }
    if p.kind == 'ped' and p.model and p.model ~= '' and IsModelValid(joaat(p.model)) and pcall(lib.requestModel, p.model, 5000) then
        local ped = CreatePed(4, joaat(p.model), p.coords.x, p.coords.y, p.coords.z, carrying.heading, false, false)
        SetModelAsNoLongerNeeded(joaat(p.model))
        if ped and ped ~= 0 then
            SetEntityAlpha(ped, 160, false)
            SetEntityCollision(ped, false, false)
            FreezeEntityPosition(ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            carrying.ghost = ped
        end
    end
    lib.showTextUI(HELP_CARRY:format(p.label), { position = 'left-center' })
end

local function putDown(ok, at)
    local c = carrying
    deleteGhost()
    carrying = nil
    lib.showTextUI(HELP, { position = 'left-center' })
    if not ok or not at then return end
    local p = c.point
    if p.kind == 'token' then
        send('layout.token', { op = 'move', id = p.id, coords = { x = at.x, y = at.y, z = at.z } }, p.label .. ' moved.')
    elseif p.kind == 'hatch' then
        send('layout.hatch', { op = 'move', id = p.id, coords = { x = at.x, y = at.y, z = at.z } }, p.label .. ' moved.')
    else
        send('layout.set', { path = p.path, coords = { x = at.x, y = at.y, z = at.z, w = c.heading }, radius = c.radius },
            p.label .. ' moved. Everyone sees it now.')
    end
end

local function carryFrame()
    local c = carrying
    for _, k in ipairs(BLOCKED_CARRY) do DisableControlAction(0, k, true) end
    local fine = IsControlPressed(0, 21)
    if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then c.heading = c.heading + (fine and 1 or 10) end
    if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then c.heading = c.heading - (fine and 1 or 10) end
    c.heading = (c.heading + 360.0) % 360.0
    if c.radius then
        if IsDisabledControlPressed(0, 172) then c.radius = math.min(500.0, c.radius + (c.point.kind == 'boundary' and 0.5 or 0.05)) end
        if IsDisabledControlPressed(0, 173) then c.radius = math.max(c.point.kind == 'boundary' and 5.0 or 0.5, c.radius - (c.point.kind == 'boundary' and 0.5 or 0.05)) end
    end
    local at = aim()
    if at then
        if c.ghost then
            SetEntityCoordsNoOffset(c.ghost, at.x, at.y, at.z + 1.0, false, false, false)
            SetEntityHeading(c.ghost, c.heading)
        end
        drawPoint(c.point, true, at, c.heading, c.radius)
    end
    if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 24) then
        if at then putDown(true, at) else lib.notify({ title = 'Layout', description = 'Look at the ground where it should go.', type = 'error' }) end
    elseif IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) then
        putDown(false)
    end
end

function Layout.stop()
    if not active then return end
    active = false
    if carrying then deleteGhost() carrying = nil end
    lib.hideTextUI()
    lib.notify({ title = 'Layout', description = 'Layout mode off.', type = 'inform' })
end

function Layout.start()
    if active then return Layout.stop() end
    if not (Carnival.has('panel.admin') and Carnival.has('config.edit')) then
        return lib.notify({ title = 'Layout', description = 'Only carnival admins who can edit settings can change the layout.', type = 'error' })
    end
    if not refresh() then return end
    active = true
    lib.showTextUI(HELP, { position = 'left-center' })
    lib.notify({ title = 'Layout', description = 'Walk around and aim at a marker to move it. Changes save as you go.', type = 'inform' })
    CreateThread(function()
        while active do
            for _, k in ipairs(BLOCKED) do DisableControlAction(0, k, true) end
            local pos = GetEntityCoords(PlayerPedId())
            if carrying then
                for _, p in ipairs(points) do
                    if p ~= carrying.point and #(pos - vec(p.coords)) < DRAW_DISTANCE then drawPoint(p, false) end
                end
                carryFrame()
            else
                local t = targeted(pos)
                for _, p in ipairs(points) do
                    if #(pos - vec(p.coords)) < DRAW_DISTANCE then drawPoint(p, p == t) end
                end
                if IsControlJustPressed(0, 38) and t then
                    pickUp(t)
                elseif IsDisabledControlJustPressed(0, 73) and t and (t.kind == 'token' or t.kind == 'hatch') then
                    send(t.kind == 'hatch' and 'layout.hatch' or 'layout.token', { op = 'remove', id = t.id }, t.label .. ' removed.')
                elseif IsDisabledControlJustPressed(0, 47) and t and t.kind == 'token' then
                    local nextType = TYPES[1]
                    for i, ty in ipairs(TYPES) do if ty == t.type then nextType = TYPES[i % #TYPES + 1] end end
                    send('layout.token', { op = 'retype', id = t.id, type = nextType }, ('Coin %s is now %s.'):format(t.id, nextType))
                elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194) then
                    Layout.stop()
                    break
                else
                    for _, k in ipairs(TYPE_KEYS) do
                        if IsDisabledControlJustPressed(0, k.key) then
                            local at = aim()
                            if at and k.type == 'hatch' then
                                send('layout.hatch', { op = 'add', coords = { x = at.x, y = at.y, z = at.z } }, 'Escape hatch added.')
                            elseif at then
                                send('layout.token', { op = 'add', type = k.type, coords = { x = at.x, y = at.y, z = at.z } }, ('%s coin added.'):format(k.type:gsub('^%l', string.upper)))
                            else
                                lib.notify({ title = 'Layout', description = 'Look at the ground where the coin should go.', type = 'error' })
                            end
                        end
                    end
                end
            end
            Wait(0)
        end
    end)
end

-- From the admin panel ("Lay out in the world").
RegisterNUICallback('layoutMode', function(_, cb)
    cb({ ok = true })
    Carnival.closeView('admin')
    CreateThread(Layout.start)
end)

RegisterCommand('carnivallayout', function() Layout.start() end, false)
TriggerEvent('chat:addSuggestion', '/carnivallayout', 'Move the carnival NPCs, maze doors and coins in the world (admins)')

Carnival.onCleanup(function()
    if active then
        active = false
        if carrying then deleteGhost() carrying = nil end
        lib.hideTextUI()
    end
end)
