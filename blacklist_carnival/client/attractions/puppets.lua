-- Puppet Master's Theatre client: shows the scenario card (performer or
-- audience view) as a non-blocking overlay so players can keep acting.

Carnival.onPush('theatre', function(data)
    if data.action == 'card' then
        Carnival.openView('theatre', data, { focus = false })
        if data.performer and data.status == 'displayed' then
            Carnival.playSound('carnival_chime', 0.8)
            lib.notify({ title = 'The Puppet Master calls you!', description = 'Your role: ' .. (data.role or 'performer'), type = 'inform' })
        end
    elseif data.action == 'close' then
        Carnival.closeView('theatre')
        if data.text then lib.notify({ title = 'The Theatre', description = data.text, type = 'inform' }) end
    end
end)
