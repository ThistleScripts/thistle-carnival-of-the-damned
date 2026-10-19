-- ox_inventory integration.
--
-- Uses only documented ox_inventory server exports:
--   Items(name?), AddItem, RemoveItem, CanCarryItem, Search, GetItemCount
-- Item definitions are NOT registered dynamically (ox_inventory does not support
-- runtime registration); they must be added to ox_inventory/data/items.lua as
-- described in docs/INSTALLATION.md. Item-use behaviour is provided through the
-- `server.export` hooks declared in items/items.lua (exports defined below).

local C = Carnival.C
local Inv = {}
Carnival.Inventory = Inv

local function res() return Config.Inventory.resource end

function Inv.available()
    return GetResourceState(res()) == 'started'
end

local function call(fn, ...)
    if not Inv.available() then return false, 'inventory_unavailable' end
    local args = table.pack(...)
    local ok, a, b = pcall(function() return exports[res()][fn](exports[res()], table.unpack(args, 1, args.n)) end)
    if not ok then
        Carnival.Monitor.log('error', 'inventory', 'export_failed', { details = { fn = fn, error = tostring(a) } })
        return false, 'inventory_error'
    end
    return true, a, b
end

function Inv.itemExists(name)
    if type(name) ~= 'string' or name == '' then return false end
    local ok, item = call('Items', name)
    return ok and item ~= nil
end

function Inv.itemLabel(name)
    local ok, item = call('Items', name)
    return ok and item and item.label or name
end

function Inv.canCarry(src, item, count, metadata)
    local ok, can = call('CanCarryItem', src, item, count, metadata)
    return ok and can == true
end

-- Returns success, responseOrError
function Inv.addItem(src, item, count, metadata)
    local ok, success, response = call('AddItem', src, item, count, metadata)
    if not ok then return false, success end
    if success then return true, response end
    return false, response or 'add_failed'
end

function Inv.removeItem(src, item, count, metadata)
    local ok, success = call('RemoveItem', src, item, count, metadata)
    return ok and success == true
end

-- All slots of `item` in a player's inventory (with metadata).
function Inv.slots(src, item)
    local ok, slots = call('Search', src, 'slots', item)
    if not ok or type(slots) ~= 'table' then return {} end
    return slots
end

function Inv.count(src, item)
    local ok, n = call('GetItemCount', src, item)
    return ok and (n or 0) or 0
end

-- Check that every item shipped by this resource is registered.
-- Returns { ok, missing = {...}, inventoryRunning }
function Inv.validateDefinitions(raise)
    local result = { ok = true, missing = {}, inventoryRunning = Inv.available(), checked = {} }
    if not result.inventoryRunning then
        result.ok = false
        Carnival.Monitor.log('error', 'inventory', 'inventory_not_running', { details = { resource = res() } })
        return result
    end
    for _, name in ipairs(C.CUSTOM_ITEMS) do
        local exists = Inv.itemExists(name)
        result.checked[#result.checked + 1] = { item = name, registered = exists }
        if not exists then result.missing[#result.missing + 1] = name end
    end
    -- configured reward items
    if Carnival.Config.get() then
        for _, ref in ipairs(Carnival.Config.referencedItems(Carnival.Config.get())) do
            local exists = Inv.itemExists(ref.item)
            result.checked[#result.checked + 1] = { item = ref.item, registered = exists, path = ref.path }
            if not exists then result.missing[#result.missing + 1] = ref.item end
        end
    end
    result.ok = #result.missing == 0
    if not result.ok then
        Carnival.Monitor.log(raise and 'error' or 'warning', 'inventory', 'item_definitions_missing', { details = { missing = result.missing } })
    end
    return result
end

---------------------------------------------------------------------------
-- Item use hooks (referenced from items/items.lua via server.export)
-- ox_inventory calls exports.blacklist_carnival:<name>(event, item, inventory, slot, data)
---------------------------------------------------------------------------

local function sourceOfInventory(inventory)
    if type(inventory) == 'table' then return tonumber(inventory.id) end
    return tonumber(inventory)
end

-- Tickets: inspecting shows the ticket card and validates it against the database.
exports('useTicket', function(event, item, inventory, slot, data)
    if event ~= 'usingItem' then return end
    local src = sourceOfInventory(inventory)
    if not src then return false end
    local slotData = type(inventory) == 'table' and inventory.items and inventory.items[slot] or nil
    local metadata = slotData and slotData.metadata or {}
    Carnival.Tickets.inspect(src, item and item.name, metadata)
    return false -- never consumed; cancel the default use flow
end)

-- Horror keepsake tokens: inspect only. Possession never grants points.
exports('useToken', function(event, item, inventory, slot)
    if event ~= 'usingItem' then return end
    local src = sourceOfInventory(inventory)
    if not src then return false end
    local slotData = type(inventory) == 'table' and inventory.items and inventory.items[slot] or nil
    local md = slotData and slotData.metadata or {}
    Carnival.Push.notify(src, item and item.label or 'Carnival token',
        md.description or 'A keepsake from the House of Horrors. It has no points value.', 'inform')
    return false
end)

-- Trick token: harmless visual trick, consumed.
exports('useTrickToken', function(event, item, inventory)
    local src = sourceOfInventory(inventory)
    if not src then return false end
    if event == 'usingItem' then
        return Carnival.Prizes.canUse(src, 'trick')
    elseif event == 'usedItem' then
        Carnival.Prizes.applyTrick(src)
    end
end)

-- Treat token: restores a little health, consumed.
exports('useTreatToken', function(event, item, inventory)
    local src = sourceOfInventory(inventory)
    if not src then return false end
    if event == 'usingItem' then
        return Carnival.Prizes.canUse(src, 'treat')
    elseif event == 'usedItem' then
        Carnival.Prizes.applyTreat(src)
    end
end)

-- Prize box: opened server-side, contents from the configured weighted table.
exports('usePrizeBox', function(event, item, inventory, slot)
    local src = sourceOfInventory(inventory)
    if not src then return false end
    if event == 'usingItem' then
        return Carnival.Prizes.canOpenBox(src)
    elseif event == 'usedItem' then
        Carnival.Prizes.openBox(src)
    end
end)
