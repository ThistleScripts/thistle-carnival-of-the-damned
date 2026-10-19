-- Public leaderboard view. While open the client subscribes to throttled server
-- pushes; closing the view unsubscribes.

function Carnival.openLeaderboard()
    local data = Carnival.api('leaderboard.public', {})
    Carnival.api('ui.subscribe', { topic = 'leaderboard', on = true })
    Carnival.openView('leaderboard', data or {})
end
