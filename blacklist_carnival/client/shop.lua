-- Prize counter: opens the shop screen. Prices, balances and purchases are all
-- decided by the server (shop.open / shop.buy).

local Shop = {}
Carnival.Shop = Shop

-- Item pictures come from ox_inventory, resolved the same way ox_inventory
-- does it: an item's own `client.image` (a file name in the image folder or a
-- full URL), otherwise <inventory:imagepath>/<item>.png.
function Shop.imagePath()
    return GetConvar('inventory:imagepath', 'nui://ox_inventory/web/images')
end

function Shop.itemImage(name)
    local base = Shop.imagePath()
    local ok, item = pcall(function() return exports.ox_inventory:Items(name) end)
    local img = ok and type(item) == 'table' and item.client and item.client.image
    if type(img) == 'string' and img ~= '' then
        if img:find('://', 1, true) then return img end
        return ('%s/%s'):format(base, img)
    end
    return ('%s/%s.png'):format(base, name)
end

function Shop.open()
    local data = Carnival.apiNotify('shop.open')
    if not data then return end
    for _, it in ipairs(data.items or {}) do it.image = Shop.itemImage(it.item) end
    Carnival.openView('shop', data)
end

Carnival.onPush('wallet', function(data)
    if (data.delta or 0) > 0 and not Carnival.isViewOpen('shop') then
        -- quiet reminder; the NUI toast shows the amount
        Carnival.playSound('carnival_chime', 0.25)
    end
end)

local function showTickets()
    local w = Carnival.api('shop.wallet')
    if not w then return end
    lib.notify({ title = 'Prize counter', description = ('You have %d %s.'):format(w.balance or 0, w.currency or 'tickets'), type = 'inform' })
end
RegisterCommand('prizetickets', showTickets, false)
RegisterCommand('prizepoints', showTickets, false) -- old name

TriggerEvent('chat:addSuggestion', '/prizetickets', 'Show how many prize tickets you have to spend at the carnival prize counter')
