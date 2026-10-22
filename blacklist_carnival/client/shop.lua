-- Prize counter: opens the shop screen. Prices, balances and purchases are all
-- decided by the server (shop.open / shop.buy).

local Shop = {}
Carnival.Shop = Shop

function Shop.open()
    local data = Carnival.apiNotify('shop.open')
    if not data then return end
    Carnival.openView('shop', data)
end

Carnival.onPush('wallet', function(data)
    if (data.delta or 0) > 0 and not Carnival.isViewOpen('shop') then
        -- quiet reminder; the NUI toast shows the amount
        Carnival.playSound('carnival_chime', 0.25)
    end
end)

RegisterCommand('prizepoints', function()
    local w = Carnival.api('shop.wallet')
    if not w then return end
    lib.notify({ title = 'Prize counter', description = ('You have %d %s.'):format(w.balance or 0, w.currency or 'points'), type = 'inform' })
end, false)

TriggerEvent('chat:addSuggestion', '/prizepoints', 'Show how many prize points you have to spend at the carnival prize counter')
