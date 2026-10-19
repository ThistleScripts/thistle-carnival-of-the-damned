-- Puppet Master's Theatre client: the scenario card (non-blocking overlay so
-- players keep acting), joining a self-service show and the audience vote.

local Theatre = {}
Carnival.Theatre = Theatre

function Theatre.play()
    local res, code, msg = Carnival.api('theatre.play', {})
    if not res then
        return lib.notify({ title = "The Puppet Master's Theatre", description = msg or code, type = code == 'busy' and 'inform' or 'error' })
    end
    lib.notify({ title = "The Puppet Master's Theatre", description = ('You are in the cast (%d so far). The curtain rises in %ds!'):format(res.cast or 1, res.startsIn or 0), type = 'success' })
end

Carnival.onPush('theatre', function(data)
    if data.action == 'card' then
        Carnival.openView('theatre', data, { focus = false })
        if data.performer and (data.status == 'displayed' or data.status == 'running') then
            Carnival.playSound('carnival_chime', 0.8)
            lib.notify({ title = 'You are on stage!', description = 'Your role: ' .. (data.role or 'performer'), type = 'inform' })
        end
    elseif data.action == 'close' then
        Carnival.closeView('theatre')
        if data.text then lib.notify({ title = 'The Theatre', description = data.text, type = 'inform' }) end
    elseif data.action == 'vote' then
        Carnival.openView('theatreVote', data)
    elseif data.action == 'vote_closed' then
        Carnival.closeView('theatreVote')
        local names = data.winners and #data.winners > 0 and table.concat(data.winners, ', ') or 'nobody'
        lib.notify({ title = 'Audience choice', description = 'Star of the show: ' .. names, type = 'success', duration = 8000 })
    end
end)
