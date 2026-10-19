-- Coloured entry tickets (physical ox_inventory items or virtual).
--
-- Each ticket has a unique random serial stored in carnival_tickets and in the
-- item's metadata. A ticket is valid only if its serial matches the participant's
-- single active ticket row for the active event. Replaced/revoked serials are
-- stale; serials not found in the database are treated as forged.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Tickets = {}
Carnival.Tickets = Tickets

local current = {}  -- [participantId] = ticket row (status active | pending_delivery)

local SERIAL_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local function newSerial()
    local t = {}
    for i = 1, 10 do
        local n = math.random(1, #SERIAL_CHARS)
        t[i] = SERIAL_CHARS:sub(n, n)
    end
    return 'CTD-' .. table.concat(t, '', 1, 5) .. '-' .. table.concat(t, '', 6, 10)
end

function Tickets.loadForEvent(eventId)
    current = {}
    if not eventId then return end
    local rows = Carnival.Db.query("SELECT * FROM carnival_tickets WHERE event_id = ? AND status IN ('active', 'pending_delivery', 'issuing')", { eventId }) or {}
    for _, r in ipairs(rows) do
        if r.status == 'issuing' then
            -- interrupted mid-issue (restart): we cannot know if the item was added,
            -- so mark for delivery review; verify() still accepts it if the item exists.
            Carnival.Db.update("UPDATE carnival_tickets SET status = 'pending_delivery', delivery_error = 'interrupted' WHERE id = ?", { r.id })
            r.status = 'pending_delivery'
            r.delivery_error = 'interrupted'
            Carnival.Monitor.log('warning', 'recovery', 'ticket_issue_interrupted', { participantId = r.participant_id, details = { ticketId = r.id } })
        end
        current[r.participant_id] = r
    end
end

function Tickets.current(pid)
    return current[pid]
end

local function metadataFor(p, ticket)
    local cfg = Carnival.Config.get()
    local colourLabel = cfg.groups.colours[p.colour].label
    local e = Carnival.Events.active
    return {
        serial = ticket.serial,
        eventId = p.event_id,
        participantId = p.id,
        colour = p.colour,
        holder = p.display_name,
        label = ('%s Ticket'):format(colourLabel),
        description = ('%s · %s group · Admit %s · Serial %s'):format(e and e.name or 'Carnival of the Damned', colourLabel, p.display_name, ticket.serial),
    }
end

-- Try to put the physical item into the player's inventory.
local function deliver(p, ticket)
    local src = Carnival.Participants.sourceOf(p.id)
    if not src then return false, 'player_offline' end
    local item = ticket.item_name
    if not Carnival.Inventory.itemExists(item) then return false, 'item_not_registered' end
    local md = metadataFor(p, ticket)
    if not Carnival.Inventory.canCarry(src, item, 1, md) then return false, 'inventory_full' end
    local ok, err = Carnival.Inventory.addItem(src, item, 1, md)
    if not ok then return false, tostring(err) end
    return true
end

local function setStatus(ticket, status, err)
    Carnival.Db.updateRow('carnival_tickets', { status = status, delivery_error = err or Carnival.Db.NULL }, 'id = ?', { ticket.id })
    ticket.status = status
    ticket.delivery_error = err
end

-- Issue a ticket for a participant that has none. Returns true or false, error.
function Tickets.issue(p, actor, reason)
    return Carnival.withLock('ticket:' .. p.id, function()
        local e = Carnival.Events.active
        if not e or e.id ~= p.event_id then return false, 'stale_event' end
        if p.status ~= 'active' then return false, 'participant_inactive' end
        if not p.colour then return false, 'no_group' end
        if current[p.id] then return false, 'already_has_ticket' end

        local cfg = Carnival.Config.get()
        local virtual = cfg.registration.virtualTickets
        local item = C.TICKET_ITEMS[p.colour]
        local ticket
        for _ = 1, 5 do
            local serial = newSerial()
            local id = Carnival.Db.insertRow('carnival_tickets', {
                event_id = p.event_id, participant_id = p.id, colour = p.colour,
                item_name = virtual and nil or item, serial = serial, is_virtual = virtual and 1 or 0,
                status = virtual and 'active' or 'issuing', issued_by = actor and actor.license or nil,
                issue_reason = reason, issued_at = os.time(),
            })
            if id then
                ticket = Carnival.Db.single('SELECT * FROM carnival_tickets WHERE id = ?', { id })
                break
            end
        end
        if not ticket then
            Carnival.Monitor.log('error', 'ticket', 'ticket_issue_failed', { participantId = p.id, details = { reason = 'database' } })
            return false, 'database_error'
        end
        current[p.id] = ticket

        local delivered, derr = true, nil
        if not virtual then
            delivered, derr = deliver(p, ticket)
            setStatus(ticket, delivered and 'active' or 'pending_delivery', derr)
        end
        Carnival.Monitor.log(delivered and 'info' or 'warning', 'ticket', 'ticket_issued', {
            participantId = p.id, actor = actor, result = delivered and 'delivered' or 'pending',
            details = { serial = ticket.serial, colour = p.colour, virtual = virtual, error = derr },
        })
        Carnival.Audit.record(actor, 'ticket_issued', { eventId = p.event_id, targetType = 'participant', targetId = p.id, reason = reason,
            details = { ticketId = ticket.id, serial = ticket.serial, colour = p.colour, virtual = virtual, delivered = delivered, error = derr } })
        local src = Carnival.Participants.sourceOf(p.id)
        if src then
            if delivered then
                Carnival.Push.send(src, 'ticket', { action = 'issued', colour = p.colour, serial = ticket.serial, virtual = virtual, holder = p.display_name })
            else
                Carnival.Push.notify(src, 'Ticket pending', derr == 'inventory_full'
                    and 'Your pockets are full. Make space and visit the ticket booth to collect your ticket.'
                    or 'Your ticket could not be handed over yet. Staff have been notified.', 'warning')
            end
        end
        return delivered, derr
    end)
end

-- Invalidate the current ticket and issue a new one.
function Tickets.replace(p, actor, reason, opts)
    opts = opts or {}
    local ok, err = Carnival.withLock('ticket:' .. p.id, function()
        local old = current[p.id]
        if old then
            Carnival.Db.update("UPDATE carnival_tickets SET status = 'replaced', invalidated_at = ?, invalidated_reason = ? WHERE id = ?", { os.time(), reason, old.id })
            current[p.id] = nil
            -- Remove the old physical ticket if the player still carries it.
            local src = Carnival.Participants.sourceOf(p.id)
            if src and old.item_name then
                Carnival.Inventory.removeItem(src, old.item_name, 1, { serial = old.serial })
            end
            Carnival.Monitor.log('info', 'ticket', 'ticket_invalidated', { participantId = p.id, actor = actor, details = { serial = old.serial, reason = reason } })
        end
        if opts.selfService then
            Carnival.Db.update('UPDATE carnival_participants SET replacements = replacements + 1, last_replacement_at = ? WHERE id = ?', { os.time(), p.id })
            Carnival.Participants.refresh(p.id)
        end
        Carnival.Audit.record(actor, 'ticket_replaced', { eventId = p.event_id, targetType = 'participant', targetId = p.id, reason = reason,
            details = { oldSerial = old and old.serial or nil, selfService = opts.selfService, transfer = opts.transfer } })
        return true
    end)
    if not ok then return false, err end
    return Tickets.issue(Carnival.Participants.get(p.id), actor, reason)
end

-- Retry delivery of a pending physical ticket (on login or on request).
function Tickets.deliverPending(pid, actor)
    return Carnival.withLock('ticket:' .. pid, function()
        local t = current[pid]
        if not t or t.status ~= 'pending_delivery' then return false, 'nothing_pending' end
        local p = Carnival.Participants.get(pid)
        if not p or p.status ~= 'active' then return false, 'participant_inactive' end
        local src = Carnival.Participants.sourceOf(pid)
        -- If the interrupted issue actually delivered the item, accept it instead of duplicating.
        if src then
            for _, slot in ipairs(Carnival.Inventory.slots(src, t.item_name)) do
                if slot.metadata and slot.metadata.serial == t.serial then
                    setStatus(t, 'active')
                    return true
                end
            end
        end
        local ok, err = deliver(p, t)
        setStatus(t, ok and 'active' or 'pending_delivery', err)
        Carnival.Monitor.log(ok and 'info' or 'warning', 'ticket', 'ticket_delivery_retry', { participantId = pid, actor = actor, result = ok and 'delivered' or err })
        if ok and src then
            Carnival.Push.send(src, 'ticket', { action = 'issued', colour = p.colour, serial = t.serial, virtual = false, holder = p.display_name })
        end
        return ok, err
    end)
end

-- Validate the ticket a participant presents at an attraction.
-- Returns true or false, reasonCode.
function Tickets.verify(src, p)
    local cfg = Carnival.Config.get()
    local t = current[p.id]
    if not t then return false, 'no_ticket' end
    if t.is_virtual == 1 or not cfg.registration.requireTicketForAttractions then
        return true
    end
    if t.status ~= 'active' then return false, 'ticket_pending' end
    local found = false
    for _, colour in ipairs(C.COLOURS) do
        local item = C.TICKET_ITEMS[colour]
        for _, slot in ipairs(Carnival.Inventory.slots(src, item)) do
            local md = slot.metadata or {}
            if md.serial == t.serial and item == t.item_name and tonumber(md.participantId) == p.id and tonumber(md.eventId) == p.event_id then
                found = true
            elseif md.serial and md.serial ~= t.serial then
                -- a different carnival ticket: stale, someone else's, or forged
                Tickets.reportInvalid(src, p, md, item)
            end
        end
    end
    if not found then
        Carnival.Monitor.log('info', 'ticket_validation', 'ticket_not_presented', { participantId = p.id, actor = Carnival.Identity.actor(src) })
        return false, 'ticket_missing'
    end
    return true
end

local reported = {}
function Tickets.reportInvalid(src, p, md, item)
    local key = tostring(src) .. ':' .. tostring(md.serial)
    if reported[key] and os.time() - reported[key] < 300 then return end
    reported[key] = os.time()
    local row = Carnival.Db.single('SELECT id, participant_id, event_id, status FROM carnival_tickets WHERE serial = ?', { tostring(md.serial):sub(1, 32) })
    local kind
    if not row then
        kind = 'forged'
    elseif row.status ~= 'active' then
        kind = 'stale'
    elseif row.participant_id ~= (p and p.id) then
        kind = 'belongs_to_another_participant'
    else
        kind = 'metadata_mismatch'
    end
    local sev = kind == 'stale' and 'info' or 'warning'
    Carnival.Monitor.log(sev, kind == 'stale' and 'ticket_validation' or 'security', 'invalid_ticket_presented', {
        participantId = p and p.id, actor = Carnival.Identity.actor(src), result = kind,
        details = { item = item, serial = tostring(md.serial):sub(1, 32) },
    })
end

-- Ticket item used from the inventory: show the card with DB-validated status.
function Tickets.inspect(src, itemName, md)
    md = md or {}
    local serial = type(md.serial) == 'string' and md.serial:sub(1, 32) or nil
    local row = serial and Carnival.Db.single('SELECT t.*, e.name AS event_name, p.display_name FROM carnival_tickets t JOIN carnival_events e ON e.id = t.event_id JOIN carnival_participants p ON p.id = t.participant_id WHERE t.serial = ?', { serial })
    local status = 'invalid'
    if row then
        if row.status == 'active' and row.event_id == Carnival.Events.activeId() and row.item_name == itemName then
            status = 'valid'
        elseif row.status ~= 'active' then
            status = 'void'
        else
            status = 'expired'
        end
    end
    if status == 'invalid' or (row and row.item_name ~= itemName) then
        Tickets.reportInvalid(src, Carnival.Participants.getBySource(src), md, itemName)
    end
    Carnival.Push.send(src, 'ticket', {
        action = 'inspect',
        status = status,
        colour = C.TICKET_ITEM_COLOUR[itemName],
        serial = serial,
        holder = row and row.display_name or md.holder,
        eventName = row and row.event_name or nil,
    })
end

function Tickets.history(pid)
    return Carnival.Db.query('SELECT * FROM carnival_tickets WHERE participant_id = ? ORDER BY id DESC', { pid }) or {}
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local Api = Carnival.Api

-- Player at the ticket booth asks for a replacement (lost ticket) or for a pending delivery.
Api.register('registration.replaceTicket', {
    rate = 'action',
    handler = function(ctx)
        local p = Carnival.Participants.getBySource(ctx.source)
        if not p then return nil, 'not_registered', 'You are not registered.' end
        if p.status ~= 'active' then return nil, 'invalid', 'Your registration is not active.' end
        local cfg = Carnival.Config.get()
        if not Carnival.Identity.within(ctx.source, cfg.registration.entrance, cfg.registration.validationDistance) then
            return nil, 'too_far', 'You need to be at the ticket booth.'
        end
        local t = current[p.id]
        if t and t.status == 'pending_delivery' then
            local ok, err = Tickets.deliverPending(p.id, ctx.actor)
            if ok then return { delivered = true } end
            return nil, 'delivery_failed', err == 'inventory_full' and 'Make space in your inventory first.' or 'The ticket could not be delivered.'
        end
        if not cfg.registration.allowSelfReplacement then return nil, 'invalid', 'Ask a member of staff for a replacement.' end
        if (p.replacements or 0) >= cfg.registration.maxReplacements then
            return nil, 'limit', 'You have used all replacements. Ask a member of staff.'
        end
        if p.last_replacement_at and os.time() - p.last_replacement_at < cfg.registration.replacementCooldownSeconds then
            return nil, 'cooldown', 'Please wait before requesting another replacement.'
        end
        -- If they still hold the valid ticket there is nothing to replace.
        if t and Tickets.verify(ctx.source, p) then return nil, 'invalid', 'You still have your valid ticket.' end
        local ok, err = Tickets.replace(p, ctx.actor, 'Lost ticket (self-service)', { selfService = true })
        Carnival.Participants.pushOwn(p.id)
        return { delivered = ok, error = err }
    end,
})

Api.register('tickets.replace', {
    perm = 'participants.manage', rate = 'staff',
    handler = function(ctx, payload)
        local id, err = V.id(payload.participantId)
        if not id then return nil, 'invalid', 'participantId ' .. err end
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        local p = Carnival.Participants.get(id)
        if not p then return nil, 'not_found' end
        local ok, terr = Tickets.replace(p, ctx.actor, reason)
        Carnival.Participants.pushOwn(id)
        Carnival.Push.invalidate('participants')
        return { delivered = ok, error = terr }
    end,
})

Api.register('tickets.deliver', {
    perm = 'participants.manage', rate = 'staff',
    handler = function(ctx, payload)
        local id, err = V.id(payload.participantId)
        if not id then return nil, 'invalid', 'participantId ' .. err end
        local p = Carnival.Participants.get(id)
        if not p then return nil, 'not_found' end
        if not current[id] then
            local ok, terr = Tickets.issue(p, ctx.actor, 'Issued by staff')
            return { delivered = ok, error = terr }
        end
        local ok, terr = Tickets.deliverPending(id, ctx.actor)
        return { delivered = ok, error = terr }
    end,
})
