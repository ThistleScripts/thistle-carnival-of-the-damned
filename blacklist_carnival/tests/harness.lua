-- Integration test harness.
--
-- Loads the REAL server scripts listed in fxmanifest.lua into a Lua 5.4 state with:
--   * a virtual clock (os.time / GetGameTimer) and a cooperative scheduler that
--     runs CreateThread / Wait / SetTimeout coroutines
--   * an oxmysql-compatible MySQL.* API backed by a real MariaDB/MySQL database
--     (luasql-mysql), including TINYINT(1) -> boolean conversion like oxmysql
--   * fakes for qbx_core, ox_inventory, ox_lib callbacks, ACE, players and peds
--
-- Requirements: lua5.4, lua-sql-mysql, lua-dkjson, a MySQL/MariaDB database.
-- Configure with env vars CARNIVAL_DB_NAME/USER/PASS/HOST/PORT.

local H = {}

local RESOURCE_DIR = os.getenv('CARNIVAL_RESOURCE_DIR') or '.'
local json = require('dkjson')
local luasql = require('luasql.mysql')

---------------------------------------------------------------------------
-- Database adapter
---------------------------------------------------------------------------
local BOOL_COLUMNS = {
    is_virtual = true, is_active = true, staff_judged = true, overtime = true, requires_approval = true,
    is_custom = true, is_winner = true, correct = true, timed_out = true, boundary_penalised = true,
}

local dbEnv, conn
local function connect()
    dbEnv = luasql.mysql()
    conn = assert(dbEnv:connect(os.getenv('CARNIVAL_DB_NAME') or 'carnival_test', os.getenv('CARNIVAL_DB_USER') or 'carnival',
        os.getenv('CARNIVAL_DB_PASS') or 'carnival', os.getenv('CARNIVAL_DB_HOST') or '127.0.0.1', tonumber(os.getenv('CARNIVAL_DB_PORT') or 3306)))
    conn:execute("SET NAMES utf8mb4")
end
H.dbFailNext = 0

local function literal(v)
    if v == nil or v == json.null then return 'NULL' end
    local t = type(v)
    if t == 'number' then
        if math.type(v) == 'integer' then return tostring(v) end
        return string.format('%.17g', v)
    elseif t == 'boolean' then
        return v and '1' or '0'
    end
    return "'" .. conn:escape(tostring(v)) .. "'"
end

-- Replace ? placeholders (outside quotes) with escaped literals.
local function interpolate(sql, params)
    params = params or {}
    local out, i, n = {}, 1, 0
    local inq = nil
    for c in sql:gmatch('.') do
        if inq then
            if c == inq then inq = nil end
            out[#out + 1] = c
        elseif c == "'" or c == '"' then
            inq = c
            out[#out + 1] = c
        elseif c == '?' then
            n = n + 1
            out[#out + 1] = literal(params[n])
        else
            out[#out + 1] = c
        end
        i = i + 1
    end
    return table.concat(out)
end

local function run(sql, params)
    if H.dbFailNext > 0 then
        H.dbFailNext = H.dbFailNext - 1
        error('simulated database failure')
    end
    local q = interpolate(sql, params)
    local cur, err = conn:execute(q)
    if not cur then error(err .. ' :: ' .. q:sub(1, 300)) end
    if type(cur) == 'number' then return cur end
    local types = cur:getcoltypes()
    local names = cur:getcolnames()
    local rows = {}
    local row = cur:fetch({}, 'a')
    while row do
        local r = {}
        for idx, name in ipairs(names) do
            local v = row[name]
            if v ~= nil then
                local ty = types[idx] or ''
                if BOOL_COLUMNS[name] and ty:match('^number') then
                    v = (tonumber(v) == 1)
                elseif ty:match('^number') then
                    v = math.tointeger(tonumber(v)) or tonumber(v)
                end
            end
            r[name] = v
        end
        rows[#rows + 1] = r
        row = cur:fetch({}, 'a')
    end
    cur:close()
    return rows
end

H.sql = run

MySQL = {
    query = { await = function(sql, p) local r = run(sql, p) return type(r) == 'table' and r or { affectedRows = r } end },
    single = { await = function(sql, p) local r = run(sql, p) return type(r) == 'table' and r[1] or nil end },
    scalar = { await = function(sql, p)
        local r = run(sql, p)
        if type(r) ~= 'table' or not r[1] then return nil end
        local _, v = next(r[1])
        -- scalar of a single column: pick the only value
        for _, val in pairs(r[1]) do return val end
        return v
    end },
    insert = { await = function(sql, p) run(sql, p) return math.tointeger(conn:getlastautoid()) end },
    update = { await = function(sql, p) return run(sql, p) end },
    prepare = { await = function(sql, p) return run(sql, p) end },
    transaction = { await = function(queries)
        conn:execute('START TRANSACTION')
        for _, q in ipairs(queries) do
            local ok = pcall(run, q.query, q.values)
            if not ok then
                conn:execute('ROLLBACK')
                return false
            end
        end
        conn:execute('COMMIT')
        return true
    end },
}

function H.resetDatabase()
    connect()
    conn:execute('SET FOREIGN_KEY_CHECKS = 0')
    local cur = conn:execute('SHOW TABLES')
    local tables = {}
    local row = cur:fetch({})
    while row do tables[#tables + 1] = row[1] row = cur:fetch({}) end
    cur:close()
    for _, t in ipairs(tables) do conn:execute('DROP TABLE `' .. t .. '`') end
    conn:execute('SET FOREIGN_KEY_CHECKS = 1')
end

---------------------------------------------------------------------------
-- Virtual time + scheduler
---------------------------------------------------------------------------
H.clock = 1760000000
H.ms = 0
local realTime = os.time
os.time = function(t) if t then return realTime(t) end return H.clock end

local threads = {}
local function spawn(fn, delayMs)
    local co = coroutine.create(fn)
    threads[#threads + 1] = { co = co, wake = H.ms + (delayMs or 0) }
end

function CreateThread(fn) spawn(fn, 0) end
Citizen = { CreateThread = CreateThread }
function SetTimeout(ms, fn) spawn(fn, ms) end
function Wait(ms)
    local co, main = coroutine.running()
    if main or not co then return end
    coroutine.yield(ms or 0)
end
function GetGameTimer() return H.ms end

local function resumeThread(t)
    local ok, res = coroutine.resume(t.co)
    if not ok then
        error('thread error: ' .. tostring(res) .. '\n' .. debug.traceback(t.co), 0)
    end
    if coroutine.status(t.co) == 'dead' then return false end
    t.wake = H.ms + (tonumber(res) or 0)
    return true
end

-- Run everything due now (repeatedly, threads may spawn threads).
function H.pump()
    for _ = 1, 50 do
        local ran = false
        local i = 1
        while i <= #threads do
            local t = threads[i]
            if t.wake <= H.ms then
                ran = true
                if not resumeThread(t) then table.remove(threads, i) else i = i + 1 end
            else
                i = i + 1
            end
        end
        if not ran then return end
    end
end

-- Advance virtual time in 1 s steps, pumping the scheduler.
function H.advance(seconds)
    for _ = 1, seconds do
        H.ms = H.ms + 1000
        H.clock = H.clock + 1
        H.pump()
    end
end

-- Run a function as a coroutine (callbacks run in threads in FiveM).
function H.call(fn, ...)
    local args = table.pack(...)
    local res
    local co = coroutine.create(function() res = table.pack(fn(table.unpack(args, 1, args.n))) end)
    local ok, err = coroutine.resume(co)
    if not ok then error(tostring(err) .. '\n' .. debug.traceback(co), 0) end
    while coroutine.status(co) ~= 'dead' do
        H.ms = H.ms + 1
        H.pump()
        ok, err = coroutine.resume(co)
        if not ok then error(tostring(err) .. '\n' .. debug.traceback(co), 0) end
    end
    return table.unpack(res, 1, res.n)
end

---------------------------------------------------------------------------
-- FiveM natives / events
---------------------------------------------------------------------------
_G.json = {
    encode = function(v) return json.encode(v) end,
    decode = function(s) return json.decode(s) end,
}

local eventHandlers = {}
function AddEventHandler(name, fn) eventHandlers[name] = eventHandlers[name] or {} table.insert(eventHandlers[name], fn) end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...)
    for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
end
function H.triggerFrom(src, name, ...)
    for _, fn in ipairs(eventHandlers[name] or {}) do
        source = src
        H.call(fn, ...)
    end
end

-- Player(src).state:set(...) records replicated state bags
H.stateBags = {}
function Player(src)
    local bag = H.stateBags[src] or {}
    H.stateBags[src] = bag
    return { state = setmetatable({ set = function(_, k, v) bag[k] = v end }, { __index = bag }) }
end

H.pushes = {}
function TriggerClientEvent(name, target, channel, data)
    local list = H.pushes
    list[#list + 1] = { target = target, event = name, channel = channel, data = data }
end
function H.pushesFor(src, channel)
    local out = {}
    for _, p in ipairs(H.pushes) do
        if (p.target == src or p.target == -1) and (not channel or p.channel == channel) then out[#out + 1] = p.data end
    end
    return out
end

H.commands = {}
function RegisterCommand(name, fn) H.commands[name] = fn end

function GetCurrentResourceName() return 'blacklist_carnival' end
function GetInvokingResource() return 'test_resource' end
function GetConvar(_, default) return default end
function LoadResourceFile(_, path)
    local f = io.open(RESOURCE_DIR .. '/' .. path, 'r')
    if not f then return nil end
    local s = f:read('a')
    f:close()
    return s
end
function PerformHttpRequest() end
function GetResourceState(name)
    if name == 'ox_inventory' then return H.inventoryState or 'started' end
    return 'started'
end
function GetHashKey(s) return 'hash:' .. string.upper(tostring(s)) end

-- Players --------------------------------------------------------------------
H.players = {}   -- [src] = { name, license, citizenid, firstname, lastname, coords, weapon, aces = set }
function H.addPlayer(src, opts)
    opts = opts or {}
    H.players[src] = {
        name = opts.name or ('Player' .. src),
        license = opts.license or ('license:' .. string.format('%040x', src)),
        citizenid = opts.citizenid or ('CID' .. src),
        firstname = opts.firstname or ('First' .. src),
        lastname = opts.lastname or ('Last' .. src),
        coords = opts.coords or { x = 0, y = 0, z = 0 },
        weapon = opts.weapon,
        aces = opts.aces or {},
        metadata = opts.metadata or { hunger = 50, thirst = 50, stress = 20 },
    }
    H.inventories[src] = H.inventories[src] or { items = {}, maxWeight = opts.maxWeight or 100000 }
end
function H.removePlayer(src) H.players[src] = nil end
function H.moveTo(src, c) H.players[src].coords = { x = c.x, y = c.y, z = c.z } end

function GetPlayers()
    local out = {}
    for s in pairs(H.players) do out[#out + 1] = tostring(s) end
    table.sort(out)
    return out
end
function GetPlayerName(src) local p = H.players[tonumber(src)] return p and p.name or nil end
function GetPlayerIdentifierByType(src, t)
    local p = H.players[tonumber(src)]
    if not p then return nil end
    if t == 'license' then return p.license end
    return nil
end
function IsPlayerAceAllowed(src, ace)
    local p = H.players[tonumber(src)]
    return p ~= nil and p.aces[ace] == true
end
function GetPlayerPed(src) return H.players[tonumber(src)] and tonumber(src) * 100 or 0 end
function GetEntityCoords(ped)
    local p = H.players[ped // 100]
    local c = p and p.coords or { x = 0, y = 0, z = 0 }
    return { x = c.x, y = c.y, z = c.z }
end
function GetSelectedPedWeapon(ped)
    local p = H.players[ped // 100]
    return p and p.weapon and GetHashKey(p.weapon) or 'hash:WEAPON_UNARMED'
end

-- Inventory fake (ox_inventory semantics we rely on) --------------------------
H.inventories = {}
H.itemRegistry = {}
H.inventoryFull = {}
local function matches(md, filter)
    if not filter then return true end
    for k, v in pairs(filter) do if (md or {})[k] ~= v then return false end end
    return true
end
local ox = {
    Items = function(_, name)
        if name == nil then return H.itemRegistry end
        return H.itemRegistry[name]
    end,
    AddItem = function(_, inv, item, count, metadata)
        if not H.itemRegistry[item] then return false, 'invalid_item' end
        if H.inventoryFull[inv] then return false, 'inventory_full' end
        local i = H.inventories[inv]
        if not i then return false, 'invalid_inventory' end
        i.items[#i.items + 1] = { name = item, count = count, metadata = metadata or {} }
        return true, { name = item, count = count }
    end,
    RemoveItem = function(_, inv, item, count, metadata)
        local i = H.inventories[inv]
        if not i then return false end
        for idx, slot in ipairs(i.items) do
            if slot.name == item and matches(slot.metadata, metadata) then
                slot.count = slot.count - count
                if slot.count <= 0 then table.remove(i.items, idx) end
                return true
            end
        end
        return false
    end,
    CanCarryItem = function(_, inv, item, count)
        return not H.inventoryFull[inv]
    end,
    Search = function(_, inv, kind, item)
        local i = H.inventories[inv]
        local out = {}
        for _, slot in ipairs(i and i.items or {}) do
            if slot.name == item then out[#out + 1] = slot end
        end
        return out
    end,
    GetItemCount = function(_, inv, item)
        local n = 0
        for _, slot in ipairs((H.inventories[inv] or { items = {} }).items) do if slot.name == item then n = n + slot.count end end
        return n
    end,
}
function H.itemsOf(src, name)
    local out = {}
    for _, slot in ipairs(H.inventories[src].items) do if slot.name == name then out[#out + 1] = slot end end
    return out
end

local qbx = {
    GetPlayer = function(_, src)
        local p = H.players[tonumber(src)]
        if not p then return nil end
        return { PlayerData = { source = tonumber(src), citizenid = p.citizenid, license = p.license, charinfo = { firstname = p.firstname, lastname = p.lastname }, metadata = p.metadata },
            Functions = { SetMetaData = function(key, value) p.metadata[key] = value end } }
    end,
    GetPlayerByCitizenId = function(self, cid)
        for s, p in pairs(H.players) do
            if p.citizenid == cid then return self.GetPlayer(self, s) end
        end
        return nil
    end,
}

H.ownExports = {}
exports = setmetatable({}, {
    __call = function(_, name, fn) H.ownExports[name] = fn end,
    __index = function(_, resource)
        if resource == 'ox_inventory' then return ox end
        if resource == 'qbx_core' then return qbx end
        if resource == 'blacklist_carnival' then
            return setmetatable({}, { __index = function(_, k) return function(_, ...) return H.ownExports[k](...) end end })
        end
        error('unknown export resource ' .. tostring(resource))
    end,
})

-- ox_lib (server parts used) -------------------------------------------------
H.callbacks = {}
lib = { callback = { register = function(name, fn) H.callbacks[name] = fn end } }

-- Call the API as a given player.
function H.api(src, endpoint, payload)
    return H.call(H.callbacks['blacklist_carnival:api'], src, endpoint, payload or {})
end

-- Silence console output unless debugging.
H.logs = {}
local realPrint = print
print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    H.logs[#H.logs + 1] = table.concat(parts, ' ')
    if os.getenv('CARNIVAL_TEST_VERBOSE') then realPrint(...) end
end
H.print = realPrint

---------------------------------------------------------------------------
-- Resource loading (parses fxmanifest.lua)
---------------------------------------------------------------------------
function H.manifest()
    local m = { shared = {}, server = {}, client = {}, files = {} }
    local env = setmetatable({}, { __index = function(_, k)
        return function(arg)
            if k == 'shared_scripts' then m.shared = arg
            elseif k == 'server_scripts' then m.server = arg
            elseif k == 'client_scripts' then m.client = arg
            elseif k == 'files' then m.files = arg
            elseif k == 'ui_page' then m.ui = arg end
            return function() end
        end
    end })
    local chunk = assert(loadfile(RESOURCE_DIR .. '/fxmanifest.lua', 't', env))
    chunk()
    return m
end

function H.loadResource()
    local m = H.manifest()
    local list = {}
    for _, f in ipairs(m.shared) do list[#list + 1] = f end
    for _, f in ipairs(m.server) do list[#list + 1] = f end
    for _, f in ipairs(list) do
        if not f:match('^@') then
            local chunk = assert(loadfile(RESOURCE_DIR .. '/' .. f))
            chunk()
        end
    end
end

-- Full (re)start of the resource against the current database contents.
function H.start(opts)
    opts = opts or {}
    Carnival = nil
    Config = nil
    threads = {}
    eventHandlers = {}
    H.callbacks = {}
    H.ownExports = {}
    H.commands = {}
    H.loadResource()
    if opts.configure then opts.configure(Config) end
    H.pump()
    for _ = 1, 20 do
        if Carnival.ready then break end
        H.ms = H.ms + 100
        H.pump()
    end
    assert(Carnival.ready, 'resource did not become ready')
end

function H.registerItems(names)
    for _, n in ipairs(names) do H.itemRegistry[n] = { name = n, label = n } end
end

H.json = json
return H
