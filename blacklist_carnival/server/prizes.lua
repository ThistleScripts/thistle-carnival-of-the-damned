-- Behaviour of the carnival prize items (trick token, treat token, prize box).
-- Called from the ox_inventory item hooks in server/inventory.lua. These items work
-- outside of events too: they are keepsakes players may keep after the carnival.

local Prizes = {}
Carnival.Prizes = Prizes

local lastUse = {}

function Prizes.canUse(src, kind)
    local key = src .. ':' .. kind
    if lastUse[key] and os.time() - lastUse[key] < 3 then return false end
    lastUse[key] = os.time()
    return true
end

function Prizes.applyTrick(src)
    local cfg = Carnival.Config.get().rewards
    Carnival.Push.send(src, 'prize', { kind = 'trick', seconds = cfg.trickEffectSeconds })
    Carnival.Monitor.log('debug', 'inventory', 'trick_token_used', { actor = Carnival.Identity.actor(src) })
end

function Prizes.applyTreat(src)
    local cfg = Carnival.Config.get().rewards
    Carnival.Push.send(src, 'prize', { kind = 'treat', heal = cfg.treatHeal })
    Carnival.Monitor.log('debug', 'inventory', 'treat_token_used', { actor = Carnival.Identity.actor(src) })
end

local function pick(contents)
    local total = 0
    for _, c in ipairs(contents) do total = total + c.weight end
    if total <= 0 then return nil end
    local roll = math.random() * total
    local acc = 0
    for _, c in ipairs(contents) do
        acc = acc + c.weight
        if roll < acc then return c end
    end
    return contents[#contents]
end

local pendingBox = {}

function Prizes.canOpenBox(src)
    local contents = Carnival.Config.get().rewards.prizeBox
    if #contents == 0 then
        Carnival.Push.notify(src, 'Prize box', 'The box is sealed shut.', 'error')
        return false
    end
    local choice = pick(contents)
    if not choice or not Carnival.Inventory.itemExists(choice.item) then
        Carnival.Monitor.log('error', 'inventory', 'prize_box_item_missing', { details = { item = choice and choice.item } })
        return false
    end
    if not Carnival.Inventory.canCarry(src, choice.item, choice.count) then
        Carnival.Push.notify(src, 'Prize box', 'You have no room for what is inside.', 'error')
        return false
    end
    pendingBox[src] = choice
    return true
end

function Prizes.openBox(src)
    local choice = pendingBox[src]
    pendingBox[src] = nil
    if not choice then return end
    local ok, err = Carnival.Inventory.addItem(src, choice.item, choice.count)
    if not ok then
        -- give the box back rather than lose it
        Carnival.Inventory.addItem(src, Carnival.C.PRIZE_ITEMS.box, 1)
        Carnival.Monitor.log('warning', 'inventory', 'prize_box_open_failed', { actor = Carnival.Identity.actor(src), details = { item = choice.item, error = tostring(err) } })
        return
    end
    Carnival.Monitor.log('info', 'inventory', 'prize_box_opened', { actor = Carnival.Identity.actor(src), details = { item = choice.item, count = choice.count } })
    Carnival.Push.send(src, 'prize', { kind = 'box', item = choice.item, label = Carnival.Inventory.itemLabel(choice.item), count = choice.count })
end

AddEventHandler('playerDropped', function()
    pendingBox[source] = nil
end)
