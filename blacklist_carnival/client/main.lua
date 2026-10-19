-- Client bootstrap: state store, server API bridge, push dispatch, NUI focus.
--
-- NUI focus is reference-counted per view: a view that needs the cursor
-- registers itself while open and focus is released as soon as no such view
-- remains (Escape, close buttons, resource stop and death all close views).

Carnival = Carnival or {}
local Client = {
    settings = nil,
    event = nil,
    participant = nil,
    permissions = {},
    role = nil,
    serverOffset = 0,
    nuiReady = false,
}
Carnival.Client = Client

local pushHandlers = {}
local focusViews = {}   -- [view] = { cursor = bool }

---------------------------------------------------------------------------
-- Server API
---------------------------------------------------------------------------
-- Returns data or nil, errorCode, message. Never throws.
function Carnival.api(name, payload)
    local ok, res = pcall(lib.callback.await, 'blacklist_carnival:api', false, name, payload or {})
    if not ok or type(res) ~= 'table' then return nil, 'network', 'The server did not respond.' end
    if res.ok then return res.data end
    return nil, res.error, res.message
end

-- Same as api() but shows the error to the player.
function Carnival.apiNotify(name, payload)
    local data, code, msg = Carnival.api(name, payload)
    if data == nil and code then
        lib.notify({ title = 'Carnival', description = msg or code, type = 'error' })
    end
    return data, code, msg
end

function Carnival.has(perm)
    return Client.permissions[perm] == true
end

function Carnival.serverNow()
    return GetCloudTimeAsInt() + Client.serverOffset
end

---------------------------------------------------------------------------
-- NUI
---------------------------------------------------------------------------
function Carnival.nui(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function applyFocus()
    local any, cursor = false, false
    for _, v in pairs(focusViews) do
        any = true
        if v.cursor then cursor = true end
    end
    SetNuiFocus(any, cursor)
    SetNuiFocusKeepInput(false)
end

-- Open a NUI view. opts.focus (default true) captures keyboard+mouse.
function Carnival.openView(view, data, opts)
    opts = opts or {}
    if opts.focus ~= false then
        focusViews[view] = { cursor = opts.cursor ~= false }
    end
    Carnival.nui('open', { view = view, data = data })
    applyFocus()
end

function Carnival.closeView(view)
    focusViews[view] = nil
    Carnival.nui('close', { view = view })
    applyFocus()
end

function Carnival.closeAllViews()
    focusViews = {}
    Carnival.nui('closeAll', {})
    SetNuiFocus(false, false)
end

function Carnival.isViewOpen(view)
    return focusViews[view] ~= nil
end

RegisterNUICallback('ready', function(_, cb)
    Client.nuiReady = true
    cb({ ok = true })
    if Client.settings then
        Carnival.nui('push', { channel = 'bootstrap', data = Client.lastBootstrap })
    end
end)

RegisterNUICallback('close', function(data, cb)
    if type(data) == 'table' and data.view then
        Carnival.closeView(data.view)
        if data.view == 'leaderboard' then Carnival.api('ui.subscribe', { topic = 'leaderboard', on = false }) end
        if data.view == 'staff' then Carnival.api('ui.subscribe', { topic = 'staff', on = false }) end
        if data.view == 'admin' then Carnival.api('ui.subscribe', { topic = 'admin', on = false }) end
    else
        Carnival.closeAllViews()
    end
    cb({ ok = true })
end)

-- Generic bridge: NUI -> server API. The server enforces every permission.
RegisterNUICallback('api', function(data, cb)
    if type(data) ~= 'table' or type(data.endpoint) ~= 'string' then
        cb({ ok = false, error = 'bad_request' })
        return
    end
    local ok, res = pcall(lib.callback.await, 'blacklist_carnival:api', false, data.endpoint, data.payload or {})
    if not ok or type(res) ~= 'table' then
        cb({ ok = false, error = 'network', message = 'The server did not respond.' })
        return
    end
    cb(res)
end)

-- Admin coordinate tool: current position + heading of the player.
RegisterNUICallback('captureCoords', function(_, cb)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    cb({ ok = true, data = {
        x = math.floor(c.x * 100 + 0.5) / 100,
        y = math.floor(c.y * 100 + 0.5) / 100,
        z = math.floor((c.z - 1.0) * 100 + 0.5) / 100, -- feet level
        w = math.floor(GetEntityHeading(ped) * 100 + 0.5) / 100,
    } })
end)

RegisterNUICallback('setWaypoint', function(data, cb)
    if type(data) == 'table' and tonumber(data.x) and tonumber(data.y) then
        SetNewWaypoint(tonumber(data.x) + 0.0, tonumber(data.y) + 0.0)
    end
    cb({ ok = true })
end)

-- Visual effects requested by NUI after an animation (e.g. wheel trick).
RegisterNUICallback('effect', function(data, cb)
    if type(data) == 'table' and Carnival.effects and Carnival.effects[data.kind] then
        Carnival.effects[data.kind](data)
    end
    cb({ ok = true })
end)

-- Temporarily hide a panel so a staff member can move, without closing it.
RegisterNUICallback('releaseFocus', function(data, cb)
    if type(data) == 'table' and data.view and focusViews[data.view] then
        focusViews[data.view] = nil
        applyFocus()
        Carnival.nui('minimised', { view = data.view })
    end
    cb({ ok = true })
end)

---------------------------------------------------------------------------
-- Push channel
---------------------------------------------------------------------------
function Carnival.onPush(channel, fn)
    pushHandlers[channel] = pushHandlers[channel] or {}
    table.insert(pushHandlers[channel], fn)
end

local function setPermissions(list)
    Client.permissions = {}
    for _, p in ipairs(list or {}) do Client.permissions[p] = true end
end

RegisterNetEvent('blacklist_carnival:client:push', function(channel, data)
    if channel == 'bootstrap' then
        Client.lastBootstrap = data
        Client.serverOffset = (data.serverTime or GetCloudTimeAsInt()) - GetCloudTimeAsInt()
        Client.settings = data.settings
        Client.event = data.event
        Client.participant = data.participant
        Client.role = data.role
        setPermissions(data.permissions)
    elseif channel == 'event' then
        Client.event = data
        if data.serverTime then Client.serverOffset = data.serverTime - GetCloudTimeAsInt() end
    elseif channel == 'participant' then
        Client.participant = data
    elseif channel == 'perms' then
        Client.role = data.role
        setPermissions(data.permissions)
        -- close panels the player may no longer use
        if focusViews.admin and not Carnival.has('panel.admin') then Carnival.closeView('admin') end
        if focusViews.staff and not Carnival.has('panel.staff') then Carnival.closeView('staff') end
    elseif channel == 'settings' then
        Client.settings = data
    end
    for _, fn in ipairs(pushHandlers[channel] or {}) do
        local ok, err = pcall(fn, data)
        if not ok then print(('^1[blacklist_carnival] push handler %s failed: %s^0'):format(channel, err)) end
    end
    Carnival.nui('push', { channel = channel, data = data })
end)

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------
function Carnival.openPanel(mode)
    if mode == 'admin' then
        if not Carnival.has('panel.admin') then return lib.notify({ title = 'Carnival', description = 'You do not have access.', type = 'error' }) end
        Carnival.api('ui.subscribe', { topic = 'admin', on = true })
        Carnival.openView('admin', {})
    elseif mode == 'staff' then
        if not Carnival.has('panel.staff') then return lib.notify({ title = 'Carnival', description = 'You do not have access.', type = 'error' }) end
        Carnival.api('ui.subscribe', { topic = 'staff', on = true })
        Carnival.openView('staff', {})
    elseif mode == 'leaderboard' then
        Carnival.openLeaderboard()
    else
        Carnival.openView('player', {})
    end
end

RegisterNetEvent('blacklist_carnival:client:openPanel', function(mode)
    Carnival.openPanel(mode)
end)

RegisterNetEvent('blacklist_carnival:client:captureCoords', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local text = ('{ x = %.2f, y = %.2f, z = %.2f, w = %.2f }'):format(c.x, c.y, c.z - 1.0, GetEntityHeading(ped))
    lib.setClipboard(text)
    lib.notify({ title = 'Coordinates copied', description = text, type = 'success' })
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local function announce()
    TriggerServerEvent('blacklist_carnival:server:clientReady')
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    Wait(1000)
    announce()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    Carnival.closeAllViews()
    Client.participant = nil
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    Wait(2000)
    if LocalPlayer.state.isLoggedIn then announce() end
end)

-- Close focus views on death so the player is never trapped in a panel.
AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' and args[1] == PlayerPedId() and IsEntityDead(PlayerPedId()) then
        for view in pairs(focusViews) do
            if view ~= 'admin' and view ~= 'staff' then Carnival.closeView(view) end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    if Carnival.cleanup then
        for _, fn in ipairs(Carnival.cleanup) do pcall(fn) end
    end
end)

Carnival.cleanup = Carnival.cleanup or {}
function Carnival.onCleanup(fn)
    table.insert(Carnival.cleanup, fn)
end

RegisterCommand('carnivalclose', function()
    Carnival.closeAllViews()
end, false)
