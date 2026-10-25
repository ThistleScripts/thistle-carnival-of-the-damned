-- Puppet Master's Theatre client: the scenario card (non-blocking overlay so
-- players keep acting), joining a self-service show and the audience vote.

local Theatre = {}
Carnival.Theatre = Theatre

function Theatre.play()
    local res, code, msg = Carnival.api('theatre.play', {})
    if not res then
        return lib.notify({ title = "The Puppet Master's Theatre", description = msg or code, type = code == 'busy' and 'inform' or 'error' })
    end
    lib.notify({ title = "The Puppet Master's Theatre", description = ('You are in the show (%d performer%s so far). It starts in %ds; everyone takes a turn on stage.'):format(res.cast or 1, (res.cast or 1) == 1 and '' or 's', res.startsIn or 0), type = 'success' })
end

Carnival.onPush('theatre', function(data)
    if data.action == 'card' then
        -- the server announces each turn ("You're on stage!") itself
        Carnival.openView('theatre', data, { focus = false })
    elseif data.action == 'close' then
        Carnival.closeView('theatre')
        if data.text then lib.notify({ title = 'The Theatre', description = data.text, type = 'inform' }) end
    elseif data.action == 'vote' then
        Carnival.openView('theatreVote', data)
    elseif data.action == 'vote_closed' then
        Carnival.closeView('theatreVote')
        local names = data.winners and #data.winners > 0 and table.concat(data.winners, ', ') or 'nobody (no votes)'
        lib.notify({ title = 'The group has voted', description = 'Best performance: ' .. names, type = 'success', duration = 8000 })
    end
end)
