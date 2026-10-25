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
        and e.state ~= 'completed' and e.state ~= 'cancelled' and e.state ~= 'final_results'
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
-- Wheel effects (Trick! / Treat! segments) and the prize box reveal
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

-- A prize box was opened: show what was inside (no mouse focus, closes by itself).
Carnival.onPush('prize', function(data)
    if data.kind ~= 'box' then return end
    Carnival.playSound('treat_sparkle', 0.9)
    local images = {}
    for _, c in ipairs(data.contents or {}) do
        images[#images + 1] = Carnival.Shop and Carnival.Shop.itemImage(c.item) or nil
    end
    Carnival.openView('prizeReveal', { contents = data.contents or {}, images = images }, { focus = false })
end)

Carnival.onPush('results', function(data)
    Carnival.openView('results', data, { focus = false })
    Carnival.playSound('round_bell', 0.8)
end)

Carnival.onCleanup(function()
    AnimpostfxStop('DrugsMichaelAliensFight')
    StopGameplayCamShaking(true)
end)
