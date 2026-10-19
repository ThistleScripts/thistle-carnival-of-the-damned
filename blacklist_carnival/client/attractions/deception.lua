-- Hall of Deception client: the accusation terminal (NUI) and live updates.
-- The client never receives the answer key until the server reveals it.

local Deception = {}
Carnival.Deception = Deception

function Deception.open()
    local data, code, msg = Carnival.api('deception.public', {})
    if not data then
        return lib.notify({ title = 'Hall of Deception', description = msg or code, type = 'error' })
    end
    if not data.active then
        return lib.notify({ title = 'Hall of Deception', description = 'The hall is quiet. Wait for the investigation to begin.', type = 'inform' })
    end
    Carnival.openView('deception', data)
end

Carnival.onPush('deception', function(data)
    if data.action == 'open' then
        lib.notify({ title = 'Hall of Deception', description = ('"%s" - the investigation has begun. Question the performers!'):format(data.mystery and data.mystery.title or ''), type = 'inform' })
        Carnival.playSound('round_bell', 0.6)
    elseif data.action == 'clue' then
        lib.notify({ title = 'New clue', description = data.clues and data.clues[#data.clues] and data.clues[#data.clues].text or 'A clue was released.', type = 'inform', duration = 10000 })
        Carnival.playSound('carnival_chime', 0.6)
    elseif data.action == 'closed' then
        lib.notify({ title = 'Hall of Deception', description = 'Accusations are closed.', type = 'warning' })
    elseif data.action == 'revealed' then
        Carnival.openView('deceptionReveal', data, { focus = false })
        SetTimeout(20000, function() Carnival.closeView('deceptionReveal') end)
    elseif data.action == 'brief_assigned' then
        lib.notify({ title = 'Performer brief', description = ('You play %s. Open the staff panel to read your brief.'):format(data.profile), type = 'inform', duration = 10000 })
    end
end)
