-- Server → client push channel.
--
-- Everything is sent through a single net event 'blacklist_carnival:client:push'
-- with (channel, data). Only data appropriate for the recipient is sent; staff
-- panels receive lightweight "invalidate" notices and re-fetch through the API
-- (which re-checks permissions) instead of receiving broadcast payloads.

local Push = {}
Carnival.Push = Push

local EVENT = 'blacklist_carnival:client:push'
local subscribers = { staff = {}, admin = {}, leaderboard = {} }
local pendingInvalidate = {}

function Push.send(src, channel, data)
    if not src or src <= 0 then return end
    TriggerClientEvent(EVENT, src, channel, data)
end

function Push.all(channel, data)
    TriggerClientEvent(EVENT, -1, channel, data)
end

function Push.many(sources, channel, data)
    for _, s in ipairs(sources) do TriggerClientEvent(EVENT, s, channel, data) end
end

function Push.subscribe(src, topic, on)
    if not subscribers[topic] then return false end
    subscribers[topic][src] = on and true or nil
    return true
end

function Push.subscribers(topic)
    local out = {}
    for s in pairs(subscribers[topic] or {}) do out[#out + 1] = s end
    return out
end

-- Notify open staff/admin panels that some data changed. Batched once per second.
function Push.invalidate(...)
    for _, t in ipairs({ ... }) do pendingInvalidate[t] = true end
end

function Push.notify(src, title, description, nType, sound)
    Push.send(src, 'notify', { title = title, description = description, type = nType or 'inform', sound = sound })
end

-- Online participants of a colour group (active status only).
function Push.group(colour, channel, data)
    local P = Carnival.Participants
    for _, p in pairs(P.byId) do
        if p.colour == colour and p.status == 'active' then
            local s = P.sourceOf(p.id)
            if s then Push.send(s, channel, data) end
        end
    end
end

function Push.participantIds(ids, channel, data)
    local P = Carnival.Participants
    for _, id in ipairs(ids) do
        local s = P.sourceOf(id)
        if s then Push.send(s, channel, data) end
    end
end

function Push.permissions(src)
    if not GetPlayerName(src) then return end
    Push.send(src, 'perms', {
        role = Carnival.Perms.role(src),
        permissions = Carnival.Perms.list(src),
    })
end

function Push.bootstrapData(src)
    return {
        serverTime = os.time(),
        resourceVersion = Carnival.C.VERSION,
        role = Carnival.Perms.role(src),
        permissions = Carnival.Perms.list(src),
        settings = Carnival.Config.publicSettings(),
        event = Carnival.Events.publicState(),
        participant = Carnival.Participants.ownState(src),
    }
end

function Push.bootstrap(src)
    Push.send(src, 'bootstrap', Push.bootstrapData(src))
end

function Push.broadcastBootstrap()
    for _, s in ipairs(Carnival.Identity.online()) do Push.bootstrap(s) end
end

-- Public event state to everyone (event state changes are rare).
function Push.eventState()
    Push.all('event', Carnival.Events.publicState())
end

function Push.settings()
    Push.all('settings', Carnival.Config.publicSettings())
end

CreateThread(function()
    while true do
        Wait(1000)
        if next(pendingInvalidate) then
            local topics = {}
            for t in pairs(pendingInvalidate) do topics[#topics + 1] = t end
            pendingInvalidate = {}
            local sent = {}
            for _, topic in ipairs({ 'staff', 'admin' }) do
                for s in pairs(subscribers[topic]) do
                    if not sent[s] then
                        sent[s] = true
                        TriggerClientEvent(EVENT, s, 'invalidate', topics)
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, set in pairs(subscribers) do set[src] = nil end
end)

Carnival.Api.register('ui.subscribe', {
    rate = 'participant',
    handler = function(ctx, payload)
        local topic = payload.topic
        if (topic == 'staff' or topic == 'admin') and not ctx:has('panel.admin') then return nil, 'forbidden' end
        if not Push.subscribe(ctx.source, topic, payload.on == true) then return nil, 'invalid', 'unknown topic' end
        if topic == 'leaderboard' and payload.on == true then
            Push.send(ctx.source, 'leaderboard', Carnival.Leaderboard.publicView(ctx.source))
        end
        return true
    end,
})

Carnival.Api.register('session.bootstrap', {
    rate = 'participant',
    handler = function(ctx)
        return Push.bootstrapData(ctx.source)
    end,
})
