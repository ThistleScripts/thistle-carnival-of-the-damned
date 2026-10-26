-- Hall of Deception client: the maze of doors. Doors are ox_target spots with a
-- faint glow and a name; the server decides where each one leads and the
-- client only teleports where it is told. Traps are checked by walking over
-- them, the golden finish circle by stepping in.

local Deception = {}
Carnival.Deception = Deception

local run = nil   -- { id, endsAt, doors, traps, finish, ..., zones = {} }
local busy = false

local DRAW_DISTANCE = 40.0

local function nuiState(extra)
    if not run then return Carnival.nui('maze', { active = false }) end
    local data = { active = true, endsAt = run.endsAt, serverTime = run.serverTime, doorsUsed = run.doorsUsed or 0, resets = run.resets or 0 }
    for k, v in pairs(extra or {}) do data[k] = v end
    Carnival.nui('maze', data)
end

local function teleport(to, flash)
    if not to then return end
    DoScreenFadeOut(250)
    local t = GetGameTimer()
    while not IsScreenFadedOut() and GetGameTimer() - t < 1500 do Wait(0) end
    local ped = PlayerPedId()
    SetEntityCoords(ped, to.x + 0.0, to.y + 0.0, to.z + 0.0, false, false, false, false)
    SetEntityHeading(ped, (to.w or 0.0) + 0.0)
    Wait(250)
    DoScreenFadeIn(400)
    if flash then AnimpostfxPlay('FocusOut', 700, false) end
end

local function clearZones()
    if not run then return end
    for _, z in ipairs(run.zones or {}) do exports.ox_target:removeZone(z) end
    run.zones = {}
end

local function stop()
    clearZones()
    run = nil
    nuiState()
end

local function useDoor(door)
    if not run or busy then return end
    busy = true
    local res, code, msg = Carnival.api('deception.door', { runId = run.id, doorId = door.id })
    busy = false
    if not res then
        return lib.notify({ title = 'Hall of Deception', description = msg or code, type = 'error' })
    end
    Carnival.playSound(res.back and 'horror_warning' or 'carnival_chime', 0.5)
    teleport(res.to, res.back)
    if not run then return end
    run.doorsUsed, run.resets = res.doorsUsed, res.resets
    nuiState()
    if res.back then
        lib.notify({ title = 'Hall of Deception', description = 'That door was a lie. Back to the start!', type = 'warning' })
    end
end

local function addDoorZones()
    clearZones()
    for _, d in ipairs(run.doors) do
        run.zones[#run.zones + 1] = exports.ox_target:addSphereZone({
            coords = vector3(d.coords.x, d.coords.y, d.coords.z + 1.0), radius = 0.9, debug = false,
            options = { {
                name = 'carnival_maze_door_' .. d.id, icon = 'fa-solid fa-door-closed', label = ('Open the %s'):format(d.label),
                distance = run.doorDistance or 2.0,
                onSelect = function() CreateThread(function() useDoor(d) end) end,
            } },
        })
    end
end

local function text3d(x, y, z, label, r, g, b)
    SetTextScale(0.0, 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(r, g, b, 230)
    SetTextOutline()
    SetTextCentre(true)
    SetDrawOrigin(x, y, z, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function finish()
    if not run or busy then return end
    busy = true
    local res, code, msg = Carnival.api('deception.finish', { runId = run.id })
    busy = false
    if not res then
        return lib.notify({ title = 'Hall of Deception', description = msg or code, type = 'error' })
    end
    stop()
    Carnival.playSound('carnival_chime', 0.8)
    teleport(res.exitTo)
    Carnival.openView('mazeResult', res, { focus = false })
    SetTimeout(10000, function() Carnival.closeView('mazeResult') end)
end

local function trap(t)
    if not run or busy then return end
    busy = true
    local res, code = Carnival.api('deception.trap', { runId = run.id, trapId = t.id })
    busy = false
    if not res then
        if code ~= 'too_far' then lib.notify({ title = 'Hall of Deception', description = code, type = 'error' }) end
        return
    end
    Carnival.playSound('horror_warning', 0.6)
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.2)
    teleport(res.to, true)
    if not run then return end
    run.resets = res.resets
    nuiState()
    lib.notify({ title = 'Hall of Deception', description = 'The floor gave way. Back to the start!', type = 'warning' })
end

local function loop()
    CreateThread(function()
        local inTrap, inFinish = {}, false
        while run do
            local pos = GetEntityCoords(PlayerPedId())
            local feet = pos - vector3(0.0, 0.0, 1.0)
            local now = GetGameTimer()
            -- doors: a faint glowing frame and their name
            for _, d in ipairs(run.doors) do
                local c = d.coords
                if #(pos - vector3(c.x, c.y, c.z)) < DRAW_DISTANCE then
                    DrawMarker(1, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.9, 0.9, 2.2, 150, 60, 220, 45, false, false, 2, false, nil, nil, false)
                    text3d(c.x, c.y, c.z + 2.4, d.label, 210, 170, 255)
                end
            end
            -- traps: invisible unless the admin chose to show them
            for _, t in ipairs(run.traps) do
                local c = t.coords
                local d2 = #(vector2(feet.x, feet.y) - vector2(c.x, c.y))
                if run.showTraps and d2 < DRAW_DISTANCE then
                    local s = run.trapRadius * 2.0
                    DrawMarker(25, c.x, c.y, c.z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, s, s, s, 200, 40, 40, 60, false, false, 2, false, nil, nil, false)
                end
                local on = d2 <= run.trapRadius and math.abs(feet.z - c.z) < 2.0
                if on and not inTrap[t.id] then CreateThread(function() trap(t) end) end
                inTrap[t.id] = on
            end
            -- the way out
            local f = run.finish
            if #(pos - vector3(f.x, f.y, f.z)) < DRAW_DISTANCE + 20.0 then
                local pulse = 0.75 + math.sin(now / 300.0) * 0.25
                local s = run.finishRadius * 2.0
                DrawMarker(25, f.x, f.y, f.z + 0.04, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, s, s, s, 255, 200, 60, math.floor(180 * pulse), false, false, 2, false, nil, nil, false)
                DrawMarker(1, f.x, f.y, f.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, s, s, 4.0, 255, 200, 60, 40, false, false, 2, false, nil, nil, false)
                text3d(f.x, f.y, f.z + 2.4, 'THE WAY OUT', 255, 210, 90)
                local on = #(vector2(feet.x, feet.y) - vector2(f.x, f.y)) <= run.finishRadius and math.abs(feet.z - f.z) < 2.5
                if on and not inFinish then CreateThread(finish) end
                inFinish = on
            end
            Wait(0)
        end
    end)
end

local function begin(data, fresh)
    if run then clearZones() end
    local first = not run
    run = data
    run.id = data.runId
    run.zones = {}
    addDoorZones()
    nuiState()
    if first then loop() end
    if fresh then teleport(data.start) end
end

-- Talking to the doorman.
function Deception.open()
    local res, code, msg = Carnival.api('deception.enter', {})
    if not res then
        return lib.notify({ title = 'Hall of Deception', description = msg or code, type = 'error' })
    end
    begin(res, true)
    lib.notify({ title = 'Hall of Deception', description = 'Every door leads somewhere else. Some lead nowhere at all. Find the golden circle before time runs out.', type = 'inform', duration = 9000 })
end

Carnival.onPush('deception', function(data)
    if data.action == 'end' then
        local to = data.exitTo
        stop()
        CreateThread(function() teleport(to) end)
        Carnival.openView('mazeResult', data, { focus = false })
        SetTimeout(10000, function() Carnival.closeView('mazeResult') end)
    elseif data.action == 'sync' and run then
        run.endsAt, run.serverTime = data.endsAt, data.serverTime
        nuiState()
    elseif data.action == 'resume' and data.run then
        begin(data.run, false)
    end
end)

-- Recover after the resource restarts on the client.
Carnival.onPush('bootstrap', function()
    CreateThread(function()
        local st = Carnival.api('deception.state', {})
        if st and st.active then begin(st, false) end
    end)
end)

Carnival.onCleanup(function()
    clearZones()
    run = nil
end)
