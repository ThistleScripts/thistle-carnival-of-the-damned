-- The carnival prize box. Using it opens it: the server rolls the contents from
-- the prize box settings (Settings -> Scoring & prizes -> Prize box):
--   * a random number of prizes between prizeBox.minItems and maxItems
--   * each prize drawn from prizeBox.contents by its percentage chance
--   * a random quantity between that entry's minCount and maxCount
-- Prizes of the same item are merged. The box is only used up if the player
-- can carry everything; the reveal card shows what was inside.

local C, U = Carnival.C, Carnival.U
local Prizes = {}
Carnival.Prizes = Prizes

local function cfg() return Carnival.Config.get().prizeBox end

local function drawOne(contents)
    local roll = math.random() * 100
    local acc = 0
    for _, c in ipairs(contents) do
        acc = acc + c.chance
        if roll < acc then return c end
    end
    return contents[#contents]
end

-- Roll one box (the saved settings, or `box` for the simulator). Returns { { item, count } }.
function Prizes.roll(box)
    box = box or cfg()
    local n = math.random(box.minItems, math.max(box.minItems, box.maxItems))
    local merged, order = {}, {}
    for _ = 1, n do
        local c = drawOne(box.contents)
        if c and c.item ~= C.PRIZE_BOX then
            local count = math.random(c.minCount, math.max(c.minCount, c.maxCount))
            if not merged[c.item] then
                merged[c.item] = 0
                order[#order + 1] = c.item
            end
            merged[c.item] = merged[c.item] + count
        end
    end
    return U.map(order, function(item) return { item = item, count = merged[item] } end)
end

-- Open `boxes` boxes many times to show the odds in the admin panel.
function Prizes.simulate(boxes)
    local box = cfg()
    local seen, totals, items = {}, {}, 0
    for _ = 1, boxes do
        local got = Prizes.roll(box)
        for _, g in ipairs(got) do
            seen[g.item] = (seen[g.item] or 0) + 1
            totals[g.item] = (totals[g.item] or 0) + g.count
            items = items + g.count
        end
    end
    local rows = {}
    for _, c in ipairs(box.contents) do
        if not rows[c.item] then
            rows[c.item] = true
            rows[#rows + 1] = {
                item = c.item, label = Carnival.Inventory.itemLabel(c.item),
                inBoxes = math.floor((seen[c.item] or 0) / boxes * 1000 + 0.5) / 10,
                avgCount = math.floor((totals[c.item] or 0) / boxes * 100 + 0.5) / 100,
            }
        end
    end
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r end
    table.sort(out, function(a, b) return a.inBoxes > b.inBoxes end)
    return { boxes = boxes, avgItems = math.floor(items / boxes * 100 + 0.5) / 100, rows = out }
end

local pending = {}   -- [src] = contents rolled when the box started opening
local lastUse = {}

function Prizes.prepareBox(src)
    if lastUse[src] and os.time() - lastUse[src] < 2 then return false end
    lastUse[src] = os.time()
    local box = cfg()
    if #box.contents == 0 then
        Carnival.Push.notify(src, 'Prize box', 'The box is sealed shut.', 'error')
        return false
    end
    local contents = Prizes.roll(box)
    for _, c in ipairs(contents) do
        if not Carnival.Inventory.itemExists(c.item) then
            Carnival.Monitor.log('error', 'inventory', 'prize_box_item_missing', { details = { item = c.item } })
            Carnival.Push.notify(src, 'Prize box', 'The lock is jammed. Tell a carnival admin.', 'error')
            return false
        end
        if not Carnival.Inventory.canCarry(src, c.item, c.count) then
            Carnival.Push.notify(src, 'Prize box', 'You have no room for what is inside.', 'error')
            return false
        end
    end
    pending[src] = contents
    return true
end

function Prizes.openBox(src)
    local contents = pending[src]
    pending[src] = nil
    if not contents then return end
    local given = {}
    for _, c in ipairs(contents) do
        local ok, err = Carnival.Inventory.addItem(src, c.item, c.count)
        if ok then
            given[#given + 1] = { item = c.item, count = c.count, label = Carnival.Inventory.itemLabel(c.item) }
        else
            Carnival.Monitor.log('warning', 'inventory', 'prize_box_item_failed', { actor = Carnival.Identity.actor(src), details = { item = c.item, error = tostring(err) } })
        end
    end
    if #given == 0 then
        -- nothing could be handed over: give the box back rather than lose it
        Carnival.Inventory.addItem(src, C.PRIZE_BOX, 1)
        return
    end
    Carnival.Monitor.log('info', 'inventory', 'prize_box_opened', { actor = Carnival.Identity.actor(src), details = { contents = given } })
    Carnival.Push.send(src, 'prize', { kind = 'box', contents = given })
end

AddEventHandler('playerDropped', function()
    pending[source] = nil
    lastUse[source] = nil
end)

Carnival.Api.register('prizebox.simulate', {
    perm = 'config.view', rate = 'admin',
    handler = function(_, payload)
        local n = math.floor(math.max(100, math.min(20000, tonumber(payload.boxes) or 2000)))
        return Prizes.simulate(n)
    end,
})
