-- First-run setup checklist for the admin Overview: everything the carnival
-- still needs from a human before it can run on its own. Each entry says what
-- is missing and where to fix it; the card disappears once every entry is done.

local C, U = Carnival.C, Carnival.U
local Setup = {}
Carnival.Setup = Setup

local function samePlace(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    return U.dist3(a, b) < 1.0
end

local function entry(list, id, ok, label, detail, where)
    list[#list + 1] = { id = id, ok = ok, label = label, detail = detail, where = where }
end

function Setup.checklist()
    local cfg, D = Carnival.Config.get(), Carnival.Defaults
    local items = {}

    local inv = Carnival.Inventory.available()
    local target = GetResourceState('ox_target') == 'started'
    entry(items, 'dependencies', inv and target, 'ox_inventory and ox_target are running',
        (not inv and 'ox_inventory is not started. ' or '') .. (not target and 'ox_target is not started.' or ''), 'server.cfg')

    local missing = {}
    if inv then
        for _, name in ipairs(C.CUSTOM_ITEMS) do
            if not Carnival.Inventory.itemExists(name) then missing[#missing + 1] = name end
        end
    end
    entry(items, 'items', inv and #missing == 0, 'Carnival items are added to ox_inventory',
        #missing > 0 and ('Missing: ' .. table.concat(missing, ', ') .. '. Paste ox_inventory_additions/data/carnival_items.lua into ox_inventory/data/items.lua and copy the images.') or nil,
        'docs/INSTALLATION.md')

    -- places still at the factory placeholder (Del Perro pier)
    local places = {}
    if samePlace(cfg.registration.entrance, D.registration.entrance) then places[#places + 1] = 'ticket booth' end
    if cfg.shop.enabled and samePlace(cfg.shop.location, D.shop.location) then places[#places + 1] = 'prize counter' end
    for _, id in ipairs(C.ATTRACTIONS) do
        local a = cfg.attractions[id]
        if a.enabled and samePlace(a.location, D.attractions[id].location) then places[#places + 1] = a.label end
    end
    entry(items, 'locations', #places == 0, 'Ticket booth, prize counter and attractions are placed',
        #places > 0 and ('Still at the placeholder pier position: ' .. table.concat(places, ', ') .. '. Type /carnivallayout and move each one where it belongs.') or nil,
        'Settings -> Carnival / Attractions / Scoring & prizes -> Prize counter')

    local h, dh = cfg.attractions.horror, D.attractions.horror
    if h.enabled then
        local maze = {}
        if samePlace(h.entry, dh.entry) then maze[#maze + 1] = 'entry' end
        if samePlace(h.exit, dh.exit) then maze[#maze + 1] = 'exit' end
        if samePlace(h.boundaryCentre, dh.boundaryCentre) then maze[#maze + 1] = 'boundary centre' end
        local defaultTokens = 0
        for _, t in ipairs(h.tokens or {}) do
            for _, dt in ipairs(dh.tokens or {}) do
                if samePlace(t.coords, dt.coords) then defaultTokens = defaultTokens + 1 break end
            end
        end
        if defaultTokens > 0 then maze[#maze + 1] = ('%d coin position(s)'):format(defaultTokens) end
        entry(items, 'horror', #maze == 0, 'House of Horrors maze is set up',
            #maze > 0 and ('Still at the placeholder: ' .. table.concat(maze, ', ') .. '.') or nil, 'Settings -> Attractions -> House of Horrors')
    end

    local hd, dd = cfg.attractions.deception, D.attractions.deception
    if hd.enabled then
        local left = {}
        if samePlace(hd.start, dd.start) then left[#left + 1] = 'start' end
        if samePlace(hd.finish, dd.finish) then left[#left + 1] = 'way out' end
        local defaultDoors = 0
        for _, d in ipairs(hd.doors or {}) do
            for _, dflt in ipairs(dd.doors or {}) do
                if samePlace(d.coords, dflt.coords) then defaultDoors = defaultDoors + 1 break end
            end
        end
        if defaultDoors > 0 then left[#left + 1] = ('%d door(s)'):format(defaultDoors) end
        entry(items, 'deception', #left == 0, 'Hall of Deception doors are set up',
            #left > 0 and ('Still at the placeholder: ' .. table.concat(left, ', ') .. '. Walk the hall with /carnivallayout.') or nil, 'Settings -> Attractions -> Hall of Deception')
    end

    if cfg.ambience.enabled then
        local zones = 0
        for _, z in ipairs(cfg.ambience.zones or {}) do
            for _, dz in ipairs(D.ambience.zones or {}) do
                if z.enabled and samePlace(z.coords, dz.coords) then zones = zones + 1 break end
            end
        end
        entry(items, 'ambience', zones == 0, 'Ambient sound zones are placed',
            zones > 0 and ('%d zone(s) still at the placeholder position.'):format(zones) or nil, 'Settings -> Carnival -> Ambient sound')
    end

    local wk = cfg.rotation.walkup
    if cfg.general.mode == 'walkup' then
        entry(items, 'schedule', wk.endNight ~= 'manual', 'Nights end by themselves',
            wk.endNight == 'manual' and 'Nights only end when an admin presses End the night. Choose daily or after_hours to run with no staff.' or nil,
            'Settings -> Carnival -> Rotation -> Walk-up mode')
    else
        entry(items, 'schedule', false, 'The carnival runs itself (walk-up mode)',
            'Timed-round mode needs an admin to create and run each night. Switch General -> Carnival mode to walkup to run with no staff.',
            'Settings -> Carnival -> General')
    end

    local done = true
    for _, e in ipairs(items) do if not e.ok then done = false end end
    return { done = done, items = items }
end

Carnival.Api.register('setup.checklist', {
    perm = 'panel.admin', rate = 'admin',
    handler = function() return Setup.checklist() end,
})
