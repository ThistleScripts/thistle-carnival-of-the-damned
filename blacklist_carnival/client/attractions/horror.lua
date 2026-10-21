-- House of Horrors client: renders the server's token list as local props with
-- ox_target options, shows the server-driven countdown, plays warning/ambient
-- sounds and scare effects. Collection and escape are requests the server
-- validates (distance, run state, duplicates).

local Horror = {}
Carnival.Horror = Horror

local run = nil   -- { id, tokens = { [id] = { data, entity } }, visibility, visibilityDistance, tokenTypes }

function Horror.inRun()
    return run ~= nil and run.status == 'running' and run.runnerStatus == 'inside'
end

function Horror.enter()
    local res, code, msg = Carnival.api('horror.enter', {})
    if not res then
        return lib.notify({ title = 'House of Horrors', description = msg or code, type = code == 'staff_only' and 'inform' or 'error' })
    end
    if res.running then
        return lib.notify({ title = 'House of Horrors', description = 'Your group is already inside - hurry!', type = 'warning' })
    end
    lib.notify({ title = 'House of Horrors', description = ('The doors open in %ds. Stay close to the entrance...'):format(res.startsIn or 0), type = 'warning' })
end

function Horror.info()
    if run and run.status == 'running' then
        return lib.notify({ title = 'House of Horrors', description = 'Find the tokens and reach the exit before time runs out!', type = 'inform' })
    end
    lib.notify({ title = 'House of Horrors', description = 'Wait at the entrance. The doors open when the keeper is ready...', type = 'inform' })
end

local function deleteProp(t)
    if t.entity and DoesEntityExist(t.entity) then
        exports.ox_target:removeLocalEntity(t.entity)
        DeleteEntity(t.entity)
    end
    t.entity = nil
end

local function removeToken(id)
    local t = run and run.tokens[id]
    if not t then return end
    deleteProp(t)
    if t.zone then exports.ox_target:removeZone(t.zone) end
    run.tokens[id] = nil
end

local function collect(id)
    if not run then return end
    local res, code, msg = Carnival.api('horror.collect', { runId = run.id, tokenId = id })
    if res then
        removeToken(id)
        Carnival.playSound('treat_sparkle', 0.7)
        Carnival.nui('horror', { collected = res.collected, gained = res.points, tokenType = res.type })
    else
        if code == 'collected' or code == 'invalid' then removeToken(id) end
        lib.notify({ title = 'House of Horrors', description = msg or code, type = 'error' })
    end
end

local function targetOptions(id, ttype)
    return { {
        name = 'carnival_token_' .. id, icon = 'fa-solid fa-coins', label = ('Take the %s token'):format(ttype),
        distance = (run.tokenTypes[ttype] and run.tokenTypes[ttype].distance) or 2.0,
        onSelect = function() collect(id) end,
    } }
end

-- Tokens float above their configured position (the coordinate tool captures
-- feet level), bob, spin and glow. Props are created only while the player is
-- close enough for the area to be streamed in, and dropped again when far away.
local SPAWN_DISTANCE, DESPAWN_DISTANCE, DRAW_DISTANCE = 60.0, 80.0, 45.0
local FALLBACK_COLOURS = { bronze = '#cd7f32', silver = '#c8d2e6', gold = '#ffc83c' }

local function hexToRgb(hex)
    local r, g, b = tostring(hex or ''):match('^#(%x%x)(%x%x)(%x%x)$')
    if not r then return 255, 255, 255 end
    return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local function typeCfg(ttype)
    local c = run.tokenTypes[ttype] or {}
    local r, g, b = hexToRgb(c.glowColour or FALLBACK_COLOURS[ttype])
    return {
        model = (c.model and c.model ~= '') and c.model or nil,
        float = c.floatHeight or 0.9, bob = c.bobHeight or 0.12, spin = c.spinSpeed or 90,
        r = r, g = g, b = b, range = c.glowRange or 2.5, intensity = c.glowIntensity or 6.0,
    }
end

local function spawnProp(entry)
    local cfg = entry.cfg
    local c = entry.data.coords
    local model = joaat(cfg.model)
    if not IsModelInCdimage(model) or not pcall(lib.requestModel, cfg.model, 5000) then
        entry.propFailed = true
        return
    end
    local obj = CreateObjectNoOffset(model, c.x, c.y, c.z + cfg.float, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not obj or obj == 0 then entry.propFailed = true return end
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    SetEntityInvincible(obj, true)
    entry.entity = obj
    exports.ox_target:addLocalEntity(obj, targetOptions(entry.data.id, entry.data.type))
end

local function spawnToken(t)
    if run.tokens[t.id] then return end
    local entry = { data = t, cfg = typeCfg(t.type), phase = math.random() * 6.28 }
    run.tokens[t.id] = entry
    if not entry.cfg.model then
        -- no prop: a target zone where the glowing ring floats
        local c = t.coords
        entry.zone = exports.ox_target:addSphereZone({ coords = vector3(c.x, c.y, c.z + entry.cfg.float), radius = 0.8, options = targetOptions(t.id, t.type) })
    end
end

local function clearRun()
    if not run then return end
    for id in pairs(run.tokens) do removeToken(id) end
    run = nil
    Carnival.nui('horror', { active = false })
end

local function renderLoop()
    CreateThread(function()
        while run do
            local pos = GetEntityCoords(PlayerPedId())
            local now = GetGameTimer() / 1000.0
            for _, t in pairs(run.tokens) do
                local cfg, c = t.cfg, t.data.coords
                local d = #(pos - vector3(c.x, c.y, c.z))
                local visible = run.visibility ~= 'proximity' or d <= run.visibilityDistance
                if cfg.model and not t.entity and not t.propFailed and d <= SPAWN_DISTANCE then
                    spawnProp(t)
                    if t.propFailed then
                        -- model missing from the game files: fall back to the glowing ring
                        t.zone = exports.ox_target:addSphereZone({ coords = vector3(c.x, c.y, c.z + cfg.float), radius = 0.8, options = targetOptions(t.data.id, t.data.type) })
                    end
                elseif t.entity and d > DESPAWN_DISTANCE then
                    deleteProp(t)
                end
                if t.entity then SetEntityVisible(t.entity, visible, false) end
                if visible and d < DRAW_DISTANCE then
                    local z = c.z + cfg.float + math.sin(now * 2.2 + t.phase) * cfg.bob
                    local heading = (now * cfg.spin + t.phase * 57.3) % 360.0
                    if t.entity then
                        SetEntityCoordsNoOffset(t.entity, c.x, c.y, z, false, false, false)
                        SetEntityHeading(t.entity, heading)
                    else
                        -- a spinning upright ring reads as a coin from any angle
                        DrawMarker(6, c.x, c.y, z, 0.0, 0.0, 0.0, 0.0, 0.0, heading, 0.45, 0.45, 0.45, cfg.r, cfg.g, cfg.b, 220, false, false, 2, false, nil, nil, false)
                    end
                    if cfg.range > 0 and cfg.intensity > 0 then
                        DrawLightWithRange(c.x, c.y, z, cfg.r, cfg.g, cfg.b, cfg.range, cfg.intensity)
                    end
                    -- soft halo on the floor beneath the token
                    DrawMarker(25, c.x, c.y, c.z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.7, 0.7, 0.7, cfg.r, cfg.g, cfg.b, 70, false, false, 2, false, nil, nil, false)
                end
            end
            Wait(0)
        end
    end)
end

local function applyState(data)
    local fresh = not run or run.id ~= data.runId
    if fresh then
        clearRun()
        run = { id = data.runId, tokens = {} }
        renderLoop()
    end
    run.status = data.status
    run.runnerStatus = data.runner and data.runner.status or 'inside'
    run.visibility = data.visibility
    run.visibilityDistance = data.visibilityDistance or 25.0
    run.tokenTypes = data.tokenTypes or {}
    local keep = {}
    for _, t in ipairs(data.tokens or {}) do
        keep[t.id] = true
        spawnToken(t)
    end
    for id in pairs(run.tokens) do if not keep[id] then removeToken(id) end end
    Carnival.nui('horror', {
        active = true, status = data.status, endsAt = data.endsAt, remaining = data.remaining, serverTime = data.serverTime,
        collected = data.runner and data.runner.collected or 0, points = data.runner and data.runner.points or 0,
        runnerStatus = run.runnerStatus,
    })
end

local function flash()
    AnimpostfxPlay('FocusOut', 800, false)
end

Carnival.onPush('horror', function(data)
    if data.action == 'state' then
        applyState(data)
    elseif data.action == 'audio' then
        Carnival.playSound(data.sound, data.volume, data.loop)
    elseif data.action == 'audio_stop' then
        Carnival.stopSound(data.sound)
    elseif data.action == 'warning' then
        Carnival.playSound(data.sound, data.volume)
        Carnival.nui('horror', { warning = data.remaining, warningText = data.text })
    elseif data.action == 'paused' then
        if run then run.status = 'paused' end
        Carnival.nui('horror', { status = 'paused', remaining = data.remaining })
    elseif data.action == 'token_removed' then
        removeToken(data.tokenId)
    elseif data.action == 'token_added' and run then
        spawnToken(data.token)
    elseif data.action == 'boundary_warning' then
        lib.notify({ title = 'House of Horrors', description = 'Get back inside the maze or lose points!', type = 'error' })
    elseif data.action == 'scare' then
        Carnival.playSound(data.sound, data.volume)
        if data.effect == 'shake' or data.effect == 'shake_flash' then ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.35) end
        if data.effect == 'flash' or data.effect == 'shake_flash' then flash() end
    elseif data.action == 'end' then
        if data.sound then Carnival.playSound(data.sound, data.volume) end
        clearRun()
    elseif data.action == 'result' then
        Carnival.openView('horrorResult', data, { focus = false })
        SetTimeout(10000, function() Carnival.closeView('horrorResult') end)
    end
end)

function Horror.escape()
    if not run then return end
    local res, code, msg = Carnival.api('horror.exit', { runId = run.id })
    if res then
        run.runnerStatus = 'escaped'
        for id in pairs(run.tokens) do removeToken(id) end
        Carnival.nui('horror', { runnerStatus = 'escaped', points = res.points, collected = res.collected })
        lib.notify({ title = 'You escaped!', description = ('Bonus: %d points'):format(res.bonus or 0), type = 'success' })
    else
        lib.notify({ title = 'House of Horrors', description = msg or code, type = 'error' })
    end
end

-- Recover the run view after the resource restarts on the client.
Carnival.onPush('bootstrap', function()
    CreateThread(function()
        local st = Carnival.api('horror.state', {})
        if st and st.active then applyState(st) end
    end)
end)

Carnival.onCleanup(clearRun)
