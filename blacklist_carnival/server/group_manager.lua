-- Colour groups: allocation, capacity and transfers.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Groups = {}
Carnival.Groups = Groups

function Groups.enabledColours()
    local out = {}
    local cfg = Carnival.Config.get()
    for _, c in ipairs(C.COLOURS) do
        if cfg.groups.colours[c].enabled then out[#out + 1] = c end
    end
    return out
end

function Groups.counts()
    local out = { total = 0, unassigned = 0, byColour = {}, online = {} }
    for _, c in ipairs(C.COLOURS) do out.byColour[c] = 0 out.online[c] = 0 end
    for _, p in pairs(Carnival.Participants.byId) do
        if p.status == 'active' then
            out.total = out.total + 1
            if p.colour then
                out.byColour[p.colour] = (out.byColour[p.colour] or 0) + 1
                if Carnival.Participants.sourceOf(p.id) then out.online[p.colour] = out.online[p.colour] + 1 end
            else
                out.unassigned = out.unassigned + 1
            end
        end
    end
    return out
end

function Groups.hasCapacity(colour)
    local cfg = Carnival.Config.get().groups.colours[colour]
    if not cfg or not cfg.enabled then return false end
    return Groups.counts().byColour[colour] < cfg.capacity
end

-- Returns colour, method. colour is nil when allocation is manual or all groups are full.
function Groups.allocate()
    local cfg = Carnival.Config.get().groups
    if cfg.allocation == 'manual' then return nil, 'manual' end
    local counts = Groups.counts().byColour
    local candidates = {}
    for _, c in ipairs(Groups.enabledColours()) do
        if counts[c] < cfg.colours[c].capacity then candidates[#candidates + 1] = c end
    end
    if #candidates == 0 then return nil, 'full' end
    if cfg.allocation == 'random' then
        return candidates[math.random(#candidates)], 'random'
    end
    -- balanced: fewest members, ties broken by spare capacity then colour order
    table.sort(candidates, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] < counts[b] end
        local sa, sb = cfg.colours[a].capacity - counts[a], cfg.colours[b].capacity - counts[b]
        if sa ~= sb then return sa > sb end
        return C.COLOUR_INDEX[a] < C.COLOUR_INDEX[b]
    end)
    return candidates[1], 'balanced'
end

function Groups.transfer(src, pid, colour, reason)
    return Carnival.withLock('registration', function()
        local p = Carnival.Participants.get(pid)
        if not p then return nil, 'not_found', 'Participant not found.' end
        if p.status ~= 'active' then return nil, 'invalid', 'Participant is not active.' end
        if p.colour == colour then return nil, 'invalid', 'Participant is already in that group.' end
        if not Groups.hasCapacity(colour) then return nil, 'group_full', 'That group is full or disabled.' end
        local actor = Carnival.Identity.actor(src)
        local now = os.time()
        local ins, insParams = Carnival.Db.buildInsert('carnival_group_assignments', {
            event_id = p.event_id, participant_id = pid, from_colour = p.colour, to_colour = colour,
            method = p.colour and 'transfer' or 'manual', actor = actor.license, reason = reason, created_at = now,
        })
        local ok = Carnival.Db.transaction({
            { query = 'UPDATE carnival_participants SET colour = ? WHERE id = ?', values = { colour, pid } },
            { query = ins, values = insParams },
        })
        if not ok then return nil, 'database_error', 'The transfer could not be saved.' end
        local from = p.colour
        local row = Carnival.Participants.refresh(pid)
        Carnival.Audit.record(actor, from and 'participant_group_transferred' or 'participant_group_assigned', {
            targetType = 'participant', targetId = pid, reason = reason, details = { from = from, to = colour },
        })
        Carnival.Monitor.log('info', 'group', 'group_changed', { participantId = pid, actor = actor, details = { from = from, to = colour } })

        -- Tickets carry the colour: issue a new ticket for the new group.
        local tok, terr
        if from then
            tok, terr = Carnival.Tickets.replace(row, actor, 'Group transfer: ' .. from .. ' → ' .. colour, { transfer = true })
        else
            tok, terr = Carnival.Tickets.issue(row, actor, 'Group assigned')
        end
        local s = Carnival.Participants.sourceOf(pid)
        if s then
            Carnival.Push.notify(s, 'Ticket colour changed', ('You now travel with the %s group.'):format(Carnival.Config.get().groups.colours[colour].label), 'inform')
        end
        Carnival.Participants.pushOwn(pid)
        Carnival.Leaderboard.markDirty()
        Carnival.Push.invalidate('participants', 'dashboard', 'rotation')
        return { from = from, to = colour, ticketIssued = tok == true, ticketError = terr }
    end)
end

function Groups.overview()
    local cfg = Carnival.Config.get()
    local counts = Groups.counts()
    local out = {}
    for _, c in ipairs(C.COLOURS) do
        local g = cfg.groups.colours[c]
        local session = Carnival.Rotation.sessionForColour(c)
        out[#out + 1] = {
            colour = c, label = g.label, hex = g.hex, enabled = g.enabled, capacity = g.capacity,
            members = counts.byColour[c], online = counts.online[c],
            current = session and { attraction = session.attraction_id, status = session.status, sessionId = session.id } or nil,
            next = Carnival.Rotation.nextAttractionFor(c),
            completed = Carnival.Rotation.completedForColour(c),
        }
    end
    return { groups = out, unassigned = counts.unassigned, total = counts.total }
end

local Api = Carnival.Api

Api.register('participants.reassign', {
    perm = 'participants.manage', rate = 'staff',
    handler = function(ctx, payload)
        local id, err = V.id(payload.id)
        if not id then return nil, 'invalid', 'id ' .. err end
        local colour = V.colour(payload.colour)
        if not colour then return nil, 'invalid', 'Invalid colour.' end
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        return Groups.transfer(ctx.source, id, colour, reason)
    end,
})

Api.register('groups.overview', {
    perm = 'participants.view', rate = 'staff',
    handler = function() return Groups.overview() end,
})
