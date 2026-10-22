-- Carnival food effects, driven by consumables.lua (Config.Consumables).
--
-- Eating is a two-step, server-checked flow: using the item (ox_inventory
-- export useFood) hands the client a one-time token and the configured
-- animation/prop/time; when the progress bar completes the client returns the
-- token (food.finish), the server removes one item and applies hunger, thirst
-- and stress to the QBX character, and tells the client how much armour and
-- health to add. A token is single-use, tied to the player and expires.

local U = Carnival.U
local Consumables = {}
Carnival.Consumables = Consumables

local defs = {}       -- [item] = normalised entry
local pending = {}    -- [src] = { token, item, slot, label, startedAt, expiresAt }
local NUMBERS = {
    hunger = { -100, 100 }, thirst = { -100, 100 }, stress = { -100, 100 },
    armour = { 0, 100 }, health = { 0, 100 },
}

local function num(v, lo, hi, fallback)
    v = tonumber(v)
    if not v or v ~= v then return fallback end
    return math.max(lo, math.min(hi, v))
end

local function vec(v)
    if type(v) ~= 'table' then return { x = 0.0, y = 0.0, z = 0.0 } end
    return { x = num(v.x or v[1], -10, 10, 0) + 0.0, y = num(v.y or v[2], -10, 10, 0) + 0.0, z = num(v.z or v[3], -10, 10, 0) + 0.0 }
end

-- Validate one entry; returns the normalised entry or nil, problem.
function Consumables.normalise(name, e)
    if type(name) ~= 'string' or not name:match('^[%w_%-]+$') then return nil, 'invalid item name' end
    if type(e) ~= 'table' then return nil, 'entry must be a table' end
    local out = {}
    for k, range in pairs(NUMBERS) do out[k] = math.floor(num(e[k], range[1], range[2], 0) + 0.5) end
    out.time = math.floor(num(e.time, 500, 30000, 3000))
    local anims = Config.ConsumableAnims or {}
    local anim = e.anim
    if type(anim) == 'string' then
        if not anims[anim] then return nil, ('unknown anim "%s" (use eat, drink or a { dict, clip } table)'):format(anim) end
        anim = anims[anim]
    end
    if anim ~= nil then
        if type(anim) ~= 'table' or type(anim.dict) ~= 'string' or type(anim.clip) ~= 'string' then return nil, 'anim needs dict and clip' end
        out.anim = { dict = anim.dict, clip = anim.clip, flag = math.floor(num(anim.flag, 0, 1024, 49)) }
    end
    if e.prop ~= nil then
        local p = e.prop
        if type(p) ~= 'table' or type(p.model) ~= 'string' or not p.model:match('^[%w_]+$') then return nil, 'prop needs a model name' end
        out.prop = { model = p.model, pos = vec(p.pos), rot = vec(p.rot), bone = math.floor(num(p.bone, 0, 65535, 18905)) }
    end
    out.label = type(e.label) == 'string' and U.sanitizeText(e.label, 64) or nil
    out.message = type(e.message) == 'string' and U.sanitizeText(e.message, 200) or nil
    return out
end

function Consumables.load()
    defs = {}
    local count, bad = 0, {}
    for name, e in pairs(Config.Consumables or {}) do
        local d, err = Consumables.normalise(name, e)
        if d then
            defs[name] = d
            count = count + 1
        else
            bad[#bad + 1] = name .. ': ' .. err
        end
    end
    if #bad > 0 then
        Carnival.Monitor.log('warning', 'config', 'consumables_invalid', { details = { problems = bad } })
    end
    return count, bad
end

function Consumables.get(name) return defs[name] end

local function token()
    local t = {}
    for i = 1, 16 do t[i] = string.format('%x', math.random(0, 15)) end
    return table.concat(t)
end

-- Called from the useFood item export.
function Consumables.begin(src, item, slot, label)
    local d = item and defs[item]
    if not d then
        Carnival.Push.notify(src, 'Carnival', 'This treat has not been set up (consumables.lua).', 'error')
        Carnival.Monitor.log('warning', 'inventory', 'consumable_not_configured', { details = { item = tostring(item) } })
        return false
    end
    local now = GetGameTimer()
    local cur = pending[src]
    if cur and cur.expiresAt > now then return false end -- already eating
    local p = { token = token(), item = item, slot = slot, startedAt = now, expiresAt = now + d.time + 15000 }
    pending[src] = p
    Carnival.Push.send(src, 'consume', {
        token = p.token, item = item, time = d.time, anim = d.anim, prop = d.prop,
        label = d.label or ('Eating %s'):format(label or item),
    })
    return true
end

local function setNeed(player, src, key, delta)
    if delta == 0 then return nil end
    local md = player.PlayerData and player.PlayerData.metadata or {}
    local current = tonumber(md[key]) or (key == 'stress' and 0 or 100)
    local value = math.max(0, math.min(100, current + delta))
    if player.Functions and player.Functions.SetMetaData then
        player.Functions.SetMetaData(key, value)
    else
        pcall(function() exports.qbx_core:SetMetadata(src, key, value) end)
    end
    pcall(function() Player(src).state:set(key, value, true) end)
    return value
end

-- Called when the client's progress bar completed.
function Consumables.finish(src, tok)
    local p = pending[src]
    if not p or p.token ~= tok then return nil, 'invalid', 'You are not eating anything.' end
    local now = GetGameTimer()
    pending[src] = nil
    if now > p.expiresAt then return nil, 'expired', 'That took too long.' end
    local d = defs[p.item]
    if not d then return nil, 'invalid', 'This treat is no longer set up.' end
    if now - p.startedAt < d.time * 0.8 then
        Carnival.Monitor.log('warning', 'security', 'consumable_too_fast', { details = { item = p.item, ms = now - p.startedAt } })
        return nil, 'too_fast', 'Slow down.'
    end
    local Inv = Carnival.Inventory
    if not Inv.removeItem(src, p.item, 1, nil, p.slot) and not Inv.removeItem(src, p.item, 1) then
        return nil, 'not_found', 'You no longer have it.'
    end
    local result = { item = p.item, armour = d.armour, health = d.health, message = d.message }
    local player = Carnival.Identity.qbxPlayer(src)
    if player then
        result.hunger = setNeed(player, src, 'hunger', d.hunger)
        result.thirst = setNeed(player, src, 'thirst', d.thirst)
        result.stress = setNeed(player, src, 'stress', d.stress)
        if result.hunger or result.thirst then
            local md = player.PlayerData.metadata or {}
            TriggerClientEvent('hud:client:UpdateNeeds', src, result.hunger or md.hunger, result.thirst or md.thirst)
        end
    end
    Carnival.Monitor.log('debug', 'inventory', 'consumable_used', { details = { item = p.item } })
    return result
end

AddEventHandler('playerDropped', function() pending[source] = nil end)

Carnival.onReady(function()
    local n, bad = Consumables.load()
    if #bad > 0 then
        print(('^3[blacklist_carnival] consumables.lua: %d item(s) ignored: %s^0'):format(#bad, table.concat(bad, '; ')))
    end
    Carnival.Monitor.log('info', 'config', 'consumables_loaded', { details = { count = n } })
end)

Carnival.Api.register('food.finish', {
    rate = 'action',
    handler = function(ctx, payload)
        if type(payload.token) ~= 'string' or #payload.token > 64 then return nil, 'invalid', 'Bad request.' end
        return Consumables.finish(ctx.source, payload.token)
    end,
})
