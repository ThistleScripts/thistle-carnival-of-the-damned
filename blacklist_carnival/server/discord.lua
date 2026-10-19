-- Optional Discord webhook relay.
-- Messages are queued per channel and sent at most once per Config.Discord.MinInterval
-- seconds (batched into a single message with several embeds). Failures are
-- printed once and never propagate to callers. Webhook URLs come from convars
-- and are never sent to clients.

local Discord = {}
Carnival.Discord = Discord

local queues = {}     -- [channel] = { embeds... }
local lastSent = {}
local failureReported = {}

local function enabled(channel)
    local cfg = Config.Discord
    return cfg and cfg.Enabled and cfg.Webhooks[channel] and cfg.Webhooks[channel] ~= ''
end

function Discord.send(channel, title, description, colour)
    if not enabled(channel) then return end
    local q = queues[channel]
    if not q then
        q = {}
        queues[channel] = q
    end
    if #q >= (Config.Discord.MaxQueue or 100) then return end
    q[#q + 1] = {
        title = tostring(title):sub(1, 250),
        description = tostring(description or ''):sub(1, 1800),
        color = colour or 0x6e0f1d,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        footer = { text = 'Carnival of the Damned' },
    }
end

local function flush(channel)
    local q = queues[channel]
    if not q or #q == 0 then return end
    local embeds = {}
    for i = 1, math.min(10, #q) do embeds[i] = q[i] end
    for _ = 1, #embeds do table.remove(q, 1) end
    lastSent[channel] = os.time()
    local ok, err = pcall(PerformHttpRequest, Config.Discord.Webhooks[channel], function(status)
        if status < 200 or status >= 300 then
            if not failureReported[channel] then
                failureReported[channel] = true
                print(('^3[blacklist_carnival] Discord webhook "%s" returned HTTP %s^0'):format(channel, tostring(status)))
            end
        else
            failureReported[channel] = nil
        end
    end, 'POST', json.encode({ username = Config.Discord.Username, embeds = embeds }), { ['Content-Type'] = 'application/json' })
    if not ok then print(('^3[blacklist_carnival] Discord webhook error: %s^0'):format(tostring(err))) end
end

CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for channel in pairs(queues) do
            if now - (lastSent[channel] or 0) >= (Config.Discord.MinInterval or 3) then
                flush(channel)
            end
        end
    end
end)
