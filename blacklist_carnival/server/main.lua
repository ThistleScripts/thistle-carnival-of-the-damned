-- Server bootstrap: namespace, locks, startup sequence, central ticker and cleanup.
-- Loaded first among server scripts; the startup thread runs after every server
-- script has been loaded.

Carnival = Carnival or {}
Carnival.ready = false
Carnival.startedAt = os.time()
Carnival.tickHandlers = {}
Carnival.stopHandlers = {}
Carnival.readyHandlers = {}

local C = Carnival.C

function Carnival.now()
    return os.time()
end

-- Register a function called once per second by the central ticker. Using a
-- single ticker guarantees there are never duplicate timers for the same thing.
function Carnival.onTick(name, fn)
    Carnival.tickHandlers[#Carnival.tickHandlers + 1] = { name = name, fn = fn }
end

function Carnival.onStop(fn)
    Carnival.stopHandlers[#Carnival.stopHandlers + 1] = fn
end

-- Called after migrations, config and event recovery have completed.
function Carnival.onReady(fn)
    Carnival.readyHandlers[#Carnival.readyHandlers + 1] = fn
end

---------------------------------------------------------------------------
-- Cooperative locks. Callback handlers run in separate coroutines and yield
-- while awaiting the database, so any read-modify-write sequence that spans
-- an await must hold a lock. Locks are re-entrant for the owning coroutine.
---------------------------------------------------------------------------
local locks = {}

function Carnival.withLock(key, fn, ...)
    local co = coroutine.running()
    local lock = locks[key]
    if lock and lock.owner == co then
        lock.depth = lock.depth + 1
    else
        local started = GetGameTimer()
        while locks[key] do
            if GetGameTimer() - started > 15000 then
                return false, 'busy'
            end
            Wait(0)
        end
        lock = { owner = co, depth = 1 }
        locks[key] = lock
    end
    local res = table.pack(pcall(fn, ...))
    lock.depth = lock.depth - 1
    if lock.depth == 0 then locks[key] = nil end
    if not res[1] then
        if Carnival.Monitor then
            Carnival.Monitor.log('error', 'callback', 'lock_handler_error', { details = { key = key, error = tostring(res[2]) } })
        end
        return false, 'internal_error'
    end
    return table.unpack(res, 2, res.n)
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
local function startup()
    local Monitor = Carnival.Monitor
    Monitor.log('info', 'lifecycle', 'resource_starting', { details = { version = C.VERSION } })

    -- 1. Database migrations (retry until the database is reachable).
    while true do
        local ok, err = Carnival.Db.migrate()
        if ok then break end
        Monitor.log('critical', 'database', 'migration_failed', { details = { error = tostring(err) } })
        Wait(30000)
    end

    -- 2. Inventory item definitions (warning only; registration checks again).
    Carnival.Inventory.validateDefinitions(false)

    -- 3. Configuration.
    Carnival.Config.load()

    -- 4. Active event recovery.
    Carnival.Events.recover()

    Carnival.ready = true

    -- 5. Walk-up mode: open the carnival if none is running.
    Carnival.Events.ensureWalkup()

    for _, fn in ipairs(Carnival.readyHandlers) do
        local ok, err = pcall(fn)
        if not ok then Monitor.log('error', 'lifecycle', 'ready_handler_failed', { details = { error = tostring(err) } }) end
    end
    Monitor.log('info', 'lifecycle', 'resource_ready', { details = {
        version = C.VERSION,
        event = Carnival.Events.activeId(),
        state = Carnival.Events.state(),
    } })
    Carnival.Push.broadcastBootstrap()
end

CreateThread(function()
    local ok, err = pcall(startup)
    if not ok then
        print(('^1[blacklist_carnival] startup failed: %s^0'):format(tostring(err)))
        if Carnival.Monitor then
            Carnival.Monitor.log('critical', 'lifecycle', 'startup_failed', { details = { error = tostring(err) } })
        end
    end
end)

-- Central 1 Hz ticker.
CreateThread(function()
    while true do
        Wait(1000)
        if Carnival.ready then
            local now = os.time()
            for _, h in ipairs(Carnival.tickHandlers) do
                local ok, err = pcall(h.fn, now)
                if not ok then
                    Carnival.Monitor.log('error', 'callback', 'tick_failed', { details = { handler = h.name, error = tostring(err) } })
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, fn in ipairs(Carnival.stopHandlers) do pcall(fn) end
    if Carnival.Monitor then
        Carnival.Monitor.log('info', 'lifecycle', 'resource_stopping', {})
        Carnival.Monitor.flush()
    end
end)
