-- Registration at the ticket booth and the ticket card.

local Tickets = {}
Carnival.Tickets = Tickets

function Tickets.register()
    local s = Carnival.Client.settings
    local e = Carnival.Client.event
    local confirm = lib.alertDialog({
        header = e and e.name or 'Carnival of the Damned',
        content = 'Register for tonight\'s carnival? You will receive a coloured ticket that decides which group you travel with. Keep it safe - you must show it at every attraction.',
        centered = true,
        cancel = true,
        labels = { confirm = 'Take a ticket', cancel = 'Not yet' },
    })
    if confirm ~= 'confirm' then return end
    local res, code, msg = Carnival.api('registration.register', {})
    if not res then
        return lib.notify({ title = 'Ticket booth', description = msg or code, type = 'error' })
    end
    if res.colour then
        local label = s.groups.colours[res.colour].label
        lib.notify({ title = 'Welcome to the carnival', description = ('You travel with the %s group.'):format(label), type = 'success' })
    else
        lib.notify({ title = 'Registered', description = 'Staff will assign your group colour shortly.', type = 'inform' })
    end
    if res.ticketError == 'inventory_full' then
        lib.notify({ title = 'Ticket booth', description = 'Your pockets are full. Make space, then collect your ticket here.', type = 'warning' })
    end
end

function Tickets.show()
    local p = Carnival.Client.participant
    if not p or not p.registered then return end
    Carnival.openView('ticket', {
        status = p.ticket and (p.ticket.status == 'active' and 'valid' or p.ticket.status) or 'none',
        colour = p.colour, serial = p.ticket and p.ticket.serial, holder = p.name,
        eventName = Carnival.Client.event and Carnival.Client.event.name, virtual = p.ticket and p.ticket.virtual,
    })
end

function Tickets.replace()
    local p = Carnival.Client.participant
    if p and p.ticket and p.ticket.status == 'pending_delivery' then
        local res, code, msg = Carnival.api('registration.replaceTicket', {})
        if res then lib.notify({ title = 'Ticket booth', description = 'Here is your ticket.', type = 'success' })
        else lib.notify({ title = 'Ticket booth', description = msg or code, type = 'error' }) end
        return
    end
    local confirm = lib.alertDialog({
        header = 'Lost your ticket?',
        content = 'Your old ticket will be voided and a new one issued. Replacements are limited.',
        centered = true, cancel = true, labels = { confirm = 'Replace it', cancel = 'Never mind' },
    })
    if confirm ~= 'confirm' then return end
    local res, code, msg = Carnival.api('registration.replaceTicket', {})
    if res then
        lib.notify({ title = 'Ticket booth', description = res.delivered and 'A fresh ticket, still warm.' or 'Replacement recorded; collect it when you have space.', type = res.delivered and 'success' or 'warning' })
    else
        lib.notify({ title = 'Ticket booth', description = msg or code, type = 'error' })
    end
end

-- Server sends 'ticket' on issue (animation) and on inventory inspection.
Carnival.onPush('ticket', function(data)
    if data.action == 'issued' then
        Carnival.playSound('carnival_chime', 0.8)
    end
    Carnival.openView('ticket', data)
end)
