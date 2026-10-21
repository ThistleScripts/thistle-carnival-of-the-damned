-- Rotation feedback on the client: round change sounds and a waypoint to the
-- player's current attraction (in walk-up mode: the next game on their ticket). The countdown itself is rendered by the NUI HUD from the
-- server's round end timestamp.

local lastRound = 0
local lastAttraction = nil

Carnival.onPush('event', function(e)
    if e.active and e.round and e.round ~= lastRound then
        if lastRound ~= 0 then Carnival.playSound('round_bell', 0.7) end
        lastRound = e.round
    end
end)

Carnival.onPush('participant', function(p)
    if not p.registered or not p.current then lastAttraction = nil return end
    local key = p.walkup and p.current.attraction or p.current.sessionId
    if key ~= lastAttraction and p.current.status == 'active' then
        lastAttraction = key
        local s = Carnival.Client.settings
        local a = s and s.attractions[p.current.attraction]
        if a then
            SetNewWaypoint(a.location.x + 0.0, a.location.y + 0.0)
        end
    end
end)
