-- Shooting Gallery client: spawns local target props for the player's heat,
-- detects impacts and REPORTS them. The server validates every hit and keeps the
-- score; this client never decides points.

local Shooting = {}
Carnival.Shooting = Shooting

local heat = nil       -- { id, endsAt, props = { [targetId] = entity }, down = { [targetId] = ms }, shots, special }
local fallbackMarkers = {}

local function settings() return Carnival.Client.settings.attractions.shooting end

function Shooting.join()
    local res, code, msg = Carnival.api('shooting.join', {})
    if res then
        lib.notify({ title = 'Shooting Gallery', description = ('You are number %d in line.'):format(res.position), type = 'success' })
    else
        lib.notify({ title = 'Shooting Gallery', description = msg or code, type = 'error' })
    end
end

local function spawnTarget(t)
    local model = joaat(t.model)
    if not IsModelValid(model) or not pcall(lib.requestModel, t.model, 5000) then
        fallbackMarkers[t.id] = t
        return nil
    end
    local obj = CreateObjectNoOffset(model, t.coords.x, t.coords.y, t.coords.z, false, false, false)
    SetEntityHeading(obj, t.heading or 0.0)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, true, true)
    SetModelAsNoLongerNeeded(model)
    if t.kind == 'special' then SetEntityVisible(obj, false, false) end
    return obj
end

local function clear()
    if not heat then return end
    for _, obj in pairs(heat.props) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    heat = nil
    fallbackMarkers = {}
    Carnival.nui('shooting', { active = false })
end

local function isUp(t)
    if (heat.down[t.id] or 0) > GetGameTimer() then return false end
    if t.kind == 'special' then return heat.special == t.id end
    return true
end

local function nearestTarget(impact)
    local best, bestDist
    for _, t in ipairs(settings().targets) do
        if isUp(t) then
            local d = #(impact - vector3(t.coords.x, t.coords.y, t.coords.z))
            if d <= (t.radius + 0.25) and (not bestDist or d < bestDist) then best, bestDist = t, d end
        end
    end
    return best
end

local function setTargetVisible(id, visible)
    local obj = heat and heat.props[id]
    if obj and DoesEntityExist(obj) then SetEntityVisible(obj, visible, false) end
end

local function report(t, impact)
    CreateThread(function()
        local res = Carnival.api('shooting.hit', {
            heatId = heat and heat.id, targetId = t.id,
            impact = { x = impact.x, y = impact.y, z = impact.z }, shots = heat and heat.shots or 0,
        })
        if not heat then return end
        if res then
            heat.down[t.id] = GetGameTimer() + (res.downMs or 2000)
            setTargetVisible(t.id, false)
            SetTimeout(res.downMs or 2000, function()
                if heat and (t.kind ~= 'special' or heat.special == t.id) then setTargetVisible(t.id, true) end
            end)
            Carnival.playSound(res.bullseye and 'shooting_bullseye' or 'shooting_hit', 0.8)
            Carnival.nui('shooting', { active = true, hit = { points = res.points, bullseye = res.bullseye, special = res.special }, total = res.total, hits = res.hits })
        end
    end)
end

local function run()
    CreateThread(function()
        local lastShotsSent, lastSend = 0, GetGameTimer()
        while heat do
            local ped = PlayerPedId()
            if IsPedShooting(ped) then
                heat.shots = heat.shots + 1
                local ok, impact = GetPedLastWeaponImpactCoord(ped)
                if ok then
                    local t = nearestTarget(impact)
                    if t then report(t, impact) end
                end
                Carnival.nui('shooting', { active = true, shots = heat.shots })
            end
            for _, t in pairs(fallbackMarkers) do
                if isUp(t) then
                    DrawMarker(28, t.coords.x, t.coords.y, t.coords.z, 0, 0, 0, 0, 0, 0, t.radius * 2, t.radius * 2, t.radius * 2,
                        t.kind == 'special' and 216 or 179, t.kind == 'special' and 178 or 18, 42, 160, false, false, 2, false, nil, nil, false)
                end
            end
            if GetGameTimer() - lastSend > 2000 and heat.shots ~= lastShotsSent then
                lastSend, lastShotsSent = GetGameTimer(), heat.shots
                local id, shots = heat.id, heat.shots
                CreateThread(function() Carnival.api('shooting.shots', { heatId = id, shots = shots }) end)
            end
            Wait(0)
        end
    end)
end

Carnival.onPush('shooting', function(data)
    if data.action == 'start' then
        if heat and heat.id == data.heatId then
            heat.endsAt = data.endsAt
        else
            clear()
            heat = { id = data.heatId, endsAt = data.endsAt, props = {}, down = {}, shots = 0 }
            for _, t in ipairs(settings().targets) do
                local obj = spawnTarget(t)
                if obj then heat.props[t.id] = obj end
            end
            run()
            lib.notify({ title = 'Shooting Gallery', description = 'Fire at will!', type = 'success' })
        end
        Carnival.nui('shooting', { active = true, endsAt = data.endsAt, serverTime = data.serverTime, paused = false, shots = heat.shots })
    elseif data.action == 'paused' then
        Carnival.nui('shooting', { active = true, paused = true, remaining = data.remaining })
    elseif data.action == 'special' and heat then
        heat.special = data.targetId
        setTargetVisible(data.targetId, true)
        Carnival.playSound('carnival_chime', 0.6)
        Carnival.nui('shooting', { active = true, special = true })
    elseif data.action == 'special_end' and heat then
        if heat.special == data.targetId then heat.special = nil end
        setTargetVisible(data.targetId, false)
        Carnival.nui('shooting', { active = true, special = false })
    elseif data.action == 'end' then
        clear()
    elseif data.action == 'result' then
        Carnival.openView('shootingResult', data, { focus = false })
        SetTimeout(8000, function() Carnival.closeView('shootingResult') end)
    end
end)

Carnival.onCleanup(clear)
