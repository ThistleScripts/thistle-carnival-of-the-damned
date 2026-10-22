-- Ambient sound zones. Each zone loops a bundled sound that fades in as the
-- player walks towards its centre (full volume at the centre, silent at the
-- radius). Mixing happens in the NUI; this loop only sends target volumes.
-- Players can mute the ambience for themselves with /carnivalambience.

local KVP = 'blacklist_carnival:ambienceMuted'
local muted = GetResourceKvpInt(KVP) == 1
local sent = {}   -- [zoneId] = last volume sent
local force = true -- resend everything on the next tick (settings changed)

local function masterVolume()
    local s = Carnival.Client.settings
    return s and s.audio and s.audio.masterVolume or 0.6
end

local function send(levels)
    Carnival.nui('ambient', { levels = levels })
end

local function silenceAll()
    if next(sent) == nil and not force then return end
    sent, force = {}, false
    send({})
end

CreateThread(function()
    while true do
        Wait(400)
        local s = Carnival.Client.settings
        local amb = s and s.ambience
        if muted or not amb or not amb.enabled or not Carnival.Client.nuiReady then
            silenceAll()
        else
            local pos = GetEntityCoords(PlayerPedId())
            local levels, changed = {}, false
            local seen = {}
            for _, z in ipairs(amb.zones or {}) do
                if z.enabled and z.coords and z.radius and z.radius > 0 then
                    local d = #(pos - vector3(z.coords.x + 0.0, z.coords.y + 0.0, z.coords.z + 0.0))
                    if d < z.radius then
                        local t = 1.0 - d / z.radius
                        local vol = (t * t * (3 - 2 * t)) * (z.volume or 1) * (amb.volume or 1) * masterVolume()
                        vol = math.floor(vol * 100 + 0.5) / 100
                        if vol > 0 then
                            levels[#levels + 1] = { id = z.id, sound = z.sound, volume = vol }
                            seen[z.id] = true
                            if sent[z.id] == nil or math.abs(sent[z.id] - vol) >= 0.02 then changed = true end
                            sent[z.id] = vol
                        end
                    end
                end
            end
            for id in pairs(sent) do
                if not seen[id] then sent[id] = nil changed = true end
            end
            if changed or force then
                force = false
                send(levels)
            end
        end
    end
end)

Carnival.onPush('settings', function() force = true end)
Carnival.onPush('bootstrap', function() force = true end)

RegisterCommand('carnivalambience', function()
    muted = not muted
    SetResourceKvpInt(KVP, muted and 1 or 0)
    if muted then silenceAll() end
    lib.notify({ title = 'Carnival', description = muted and 'Carnival ambience muted.' or 'Carnival ambience on.', type = 'inform' })
end, false)

TriggerEvent('chat:addSuggestion', '/carnivalambience', 'Turn the carnival ambient sounds on or off (just for you)')

Carnival.onCleanup(function() send({}) end)
