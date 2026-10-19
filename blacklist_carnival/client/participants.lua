-- Participant notifications, score feedback, HUD and prize item effects.

local C = Carnival.C

local function notifyType(t)
    if t == 'success' or t == 'error' or t == 'warning' then return t end
    return 'inform'
end

Carnival.onPush('notify', function(data)
    lib.notify({ title = data.title or 'Carnival', description = data.description, type = notifyType(data.type), duration = 6000 })
    local sound = data.sound
    if not sound and Carnival.Client.settings then sound = Carnival.Client.settings.audio.notificationSound end
    if sound then Carnival.playSound(sound, 0.5) end
end)

-- Score feedback is rendered by the NUI HUD (it receives the push automatically).

-- HUD visibility: shown while registered for a live event.
local function updateHud()
    local s = Carnival.Client.settings
    local p = Carnival.Client.participant
    local e = Carnival.Client.event
    local show = s and s.general.hudEnabled and p and p.registered and e and e.active
        and e.state ~= 'completed' and e.state ~= 'cancelled'
    Carnival.nui('hud', { visible = show and true or false })
end
Carnival.onPush('participant', updateHud)
Carnival.onPush('event', updateHud)
Carnival.onPush('bootstrap', updateHud)

RegisterCommand('carnivalhud', function()
    Carnival.nui('hud', { toggle = true })
end, false)

-- Set a waypoint to the player's current attraction.
RegisterCommand('carnivalwhere', function()
    local p = Carnival.Client.participant
    local s = Carnival.Client.settings
    if not p or not p.registered or not p.current then
        return lib.notify({ title = 'Carnival', description = 'You have no attraction right now.', type = 'inform' })
    end
    local loc = s.attractions[p.current.attraction].location
    SetNewWaypoint(loc.x + 0.0, loc.y + 0.0)
    lib.notify({ title = 'Carnival', description = 'Waypoint set: ' .. s.attractions[p.current.attraction].label, type = 'inform' })
end, false)

---------------------------------------------------------------------------
-- Prize item effects (server consumed the item and decided the effect)
---------------------------------------------------------------------------
Carnival.effects = Carnival.effects or {}

function Carnival.effects.trick(data)
    local seconds = (data and data.seconds) or (Carnival.Client.settings and Carnival.Client.settings.rewards.trickEffectSeconds) or 10
    Carnival.playSound('trick_laugh', 0.9)
    AnimpostfxPlay('DrugsMichaelAliensFight', 0, true)
    ShakeGameplayCam('DRUNK_SHAKE', 0.6)
    SetTimeout(seconds * 1000, function()
        AnimpostfxStop('DrugsMichaelAliensFight')
        StopGameplayCamShaking(true)
    end)
end

function Carnival.effects.treat(data)
    Carnival.playSound('treat_sparkle', 0.9)
    AnimpostfxPlay('SuccessNeutral', 1500, false)
end

Carnival.onPush('prize', function(data)
    if data.kind == 'trick' then
        Carnival.effects.trick(data)
        lib.notify({ title = 'Trick!', description = 'The token cackles and the world spins...', type = 'warning' })
    elseif data.kind == 'treat' then
        local ped = PlayerPedId()
        local heal = tonumber(data.heal) or 0
        if heal > 0 then
            SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + heal))
        end
        Carnival.effects.treat(data)
        lib.notify({ title = 'Treat!', description = 'Sweet relief.', type = 'success' })
    elseif data.kind == 'box' then
        Carnival.playSound('treat_sparkle', 0.9)
        lib.notify({ title = 'Prize box', description = ('Inside: %dx %s'):format(data.count or 1, data.label or data.item), type = 'success' })
    end
end)

Carnival.onPush('results', function(data)
    Carnival.openView('results', data, { focus = false })
    Carnival.playSound('round_bell', 0.8)
end)

Carnival.onCleanup(function()
    AnimpostfxStop('DrugsMichaelAliensFight')
    StopGameplayCamShaking(true)
end)
