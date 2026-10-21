-- Shooting Gallery client: opens the mouse-aim mini-game in the NUI. The NUI
-- reports each click through the API bridge; the server validates it against
-- the target schedule it generated and keeps the score.

local Shooting = {}
Carnival.Shooting = Shooting

function Shooting.play()
    local data, code, msg = Carnival.api('shooting.start', {})
    if not data then
        return lib.notify({ title = 'Shooting Gallery', description = msg or code, type = 'error' })
    end
    Carnival.openView('shootingGame', data)
end

Carnival.onPush('shooting', function(data)
    -- results and pause re-syncs are delivered to the open game via the NUI push channel
    if data.action == 'result' and not Carnival.isViewOpen('shootingGame') then
        local r = data.result or {}
        lib.notify({ title = 'Shooting Gallery', description = ('Your game scored %d points (%d hits / %d shots).'):format(r.points or 0, r.hits or 0, r.shots or 0), type = 'success' })
    end
end)
