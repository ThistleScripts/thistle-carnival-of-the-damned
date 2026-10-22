-- World setup: NPCs, ox_target interactions and blips, rebuilt from the public
-- settings whenever an administrator changes them. NPCs are local (non-networked)
-- and only spawned while the player is nearby.

local C = Carnival.C
local Interactions = {}
Carnival.Interactions = Interactions

local points = {}   -- lib.points
local peds = {}     -- [key] = ped
local zones = {}    -- ox_target zone ids
local blips = {}

local SPAWN_DISTANCE = 80.0

local function vec(v) return vector3(v.x + 0.0, v.y + 0.0, v.z + 0.0) end

local function deletePed(key)
    if peds[key] and DoesEntityExist(peds[key]) then
        exports.ox_target:removeLocalEntity(peds[key])
        DeleteEntity(peds[key])
    end
    peds[key] = nil
end

local function spawnPed(key, model, loc, options)
    if peds[key] then return end
    if not model or model == '' or not IsModelValid(joaat(model)) then return end
    local ok = pcall(lib.requestModel, model, 5000)
    if not ok then return end
    local ped = CreatePed(4, joaat(model), loc.x, loc.y, loc.z, loc.w or 0.0, false, false)
    SetModelAsNoLongerNeeded(joaat(model))
    if not DoesEntityExist(ped) then return end
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    peds[key] = ped
    exports.ox_target:addLocalEntity(ped, options)
end

local function addZone(loc, radius, options)
    local id = exports.ox_target:addSphereZone({ coords = vec(loc), radius = radius, debug = false, options = options })
    zones[#zones + 1] = id
end

-- NPC when a model is configured, otherwise a sphere zone at the location.
local function place(key, loc, model, distance, options)
    for _, o in ipairs(options) do o.distance = o.distance or distance end
    if model and model ~= '' and IsModelValid(joaat(model)) then
        local p = lib.points.new({ coords = vec(loc), distance = SPAWN_DISTANCE })
        function p:onEnter() spawnPed(key, model, loc, options) end
        function p:onExit() deletePed(key) end
        points[#points + 1] = p
    else
        -- no (valid) model configured: a plain interaction zone
        addZone(loc, 1.2, options)
    end
end

local function addBlip(loc, blip, label)
    if not blip or not blip.enabled then return end
    local b = AddBlipForCoord(loc.x, loc.y, loc.z)
    SetBlipSprite(b, blip.sprite)
    SetBlipColour(b, blip.colour)
    SetBlipScale(b, 0.75)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(b)
    blips[#blips + 1] = b
end

function Interactions.clear()
    for _, p in ipairs(points) do p:remove() end
    points = {}
    for key in pairs(peds) do deletePed(key) end
    for _, id in ipairs(zones) do exports.ox_target:removeZone(id) end
    zones = {}
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
end

local function registered()
    local p = Carnival.Client.participant
    return p and p.registered and p.status == 'active'
end

-- Admins can open any game screen with demo data (artwork / layout check).
local function previewOption(attractionId)
    return {
        name = 'carnival_preview_' .. attractionId, icon = 'fa-solid fa-eye', label = 'Admin: preview game screen',
        canInteract = function() return Carnival.has('panel.admin') end,
        onSelect = function() Carnival.Preview.open(attractionId) end,
    }
end

local function merge(a, b)
    for _, x in ipairs(b) do a[#a + 1] = x end
    return a
end

local ATTRACTION_OPTIONS = {
    shooting = function()
        return {
            { name = 'carnival_shoot_play', icon = 'fa-solid fa-crosshairs', label = 'Play the Shooting Gallery',
                onSelect = function() Carnival.Shooting.play() end },
        }
    end,
    wheel = function()
        return { { name = 'carnival_wheel', icon = 'fa-solid fa-dharmachakra', label = 'Spin the Wheel of Misfortune',
            onSelect = function() Carnival.Wheel.open() end } }
    end,
    fortune = function()
        return { { name = 'carnival_fortune', icon = 'fa-solid fa-hat-wizard', label = 'Consult the Fortune Teller',
            onSelect = function() Carnival.Fortune.begin() end } }
    end,
    puppets = function()
        return { { name = 'carnival_theatre', icon = 'fa-solid fa-masks-theater', label = 'Take the stage',
            onSelect = function() Carnival.Theatre.play() end } }
    end,
    deception = function()
        return { { name = 'carnival_deception', icon = 'fa-solid fa-user-secret', label = 'Use the accusation terminal',
            onSelect = function() Carnival.Deception.open() end } }
    end,
    horror = function()
        return { { name = 'carnival_horror', icon = 'fa-solid fa-skull', label = 'Enter the House of Horrors',
            onSelect = function() Carnival.Horror.enter() end } }
    end,
}

function Interactions.build()
    Interactions.clear()
    local s = Carnival.Client.settings
    if not s then return end

    local reg = s.registration
    place('entrance', reg.entrance, reg.npcModel, reg.interactDistance, {
        { name = 'carnival_register', icon = 'fa-solid fa-ticket', label = 'Buy a ticket (register)',
            canInteract = function()
                local p = Carnival.Client.participant
                return not (p and p.registered)
            end,
            onSelect = function() Carnival.Tickets.register() end },
        { name = 'carnival_ticket_view', icon = 'fa-solid fa-id-card', label = 'Show my ticket', canInteract = registered,
            onSelect = function() Carnival.Tickets.show() end },
        { name = 'carnival_ticket_replace', icon = 'fa-solid fa-rotate', label = 'Replace or collect my ticket', canInteract = registered,
            onSelect = function() Carnival.Tickets.replace() end },
        { name = 'carnival_board', icon = 'fa-solid fa-ranking-star', label = 'View the leaderboard',
            onSelect = function() Carnival.openLeaderboard() end },
    })
    addBlip(reg.entrance, reg.blip, s.general.blipLabel)

    for _, id in ipairs(C.ATTRACTIONS) do
        local a = s.attractions[id]
        if a.enabled then
            local opts = merge(ATTRACTION_OPTIONS[id](), { previewOption(id) })
            place('attraction_' .. id, a.location, a.npcModel, a.interactDistance, opts)
            addBlip(a.location, a.blip, a.label)
        end
    end

    -- Prize counter (anyone may browse; points come from playing the games).
    local shop = s.shop
    if shop and shop.enabled then
        place('shop', shop.location, shop.npcModel, shop.interactDistance, {
            { name = 'carnival_shop', icon = 'fa-solid fa-gift', label = ('Browse %s'):format(shop.label),
                onSelect = function() Carnival.Shop.open() end },
        })
        addBlip(shop.location, shop.blip, shop.label)
    end

    -- House of Horrors exit point (escape is validated by the server).
    local h = s.attractions.horror
    if h.enabled then
        addZone(h.exit, math.max(1.0, h.exitRadius), { {
            name = 'carnival_horror_exit', icon = 'fa-solid fa-door-open', label = 'ESCAPE!', distance = h.exitRadius + 1.0,
            canInteract = function() return Carnival.Horror and Carnival.Horror.inRun() end,
            onSelect = function() Carnival.Horror.escape() end,
        } })
    end
end

Carnival.onPush('bootstrap', function() Interactions.build() end)
Carnival.onPush('settings', function() Interactions.build() end)
Carnival.onCleanup(function() Interactions.clear() end)
