-- Chat / console commands. Each command checks the same permission as the
-- equivalent panel action; the server console (source 0) is always allowed.

local C, U = Carnival.C, Carnival.U
local S = C.STATES

local function reply(src, msg, kind)
    if src == 0 then
        print('[carnival] ' .. msg)
    else
        Carnival.Push.notify(src, 'Carnival', msg, kind or 'inform')
    end
end

local function guard(src, perm)
    if src == 0 then return true end
    if not Carnival.ready then reply(src, 'The carnival is still starting up.', 'error') return false end
    if not Carnival.Perms.has(src, perm) then
        Carnival.Monitor.security(src, 'permission_denied', { command = true, permission = perm }, 'permission')
        reply(src, 'You do not have permission to do that.', 'error')
        return false
    end
    return true
end

local function joinArgs(args)
    return U.sanitizeText(table.concat(args or {}, ' '), 500)
end

local function result(src, ok, code, msg)
    if ok then reply(src, 'Done.', 'success') else reply(src, msg or tostring(code), 'error') end
end

-- /carnival : the player's own view (ticket, route, scores, leaderboard).
RegisterCommand('carnival', function(src)
    if src == 0 then return end
    TriggerClientEvent('blacklist_carnival:client:openPanel', src, 'player')
end, false)

RegisterCommand('carnivaladmin', function(src)
    if src == 0 or not guard(src, 'panel.admin') then return end
    TriggerClientEvent('blacklist_carnival:client:openPanel', src, 'admin')
end, false)

RegisterCommand('carnivalboard', function(src)
    if src == 0 then return end
    TriggerClientEvent('blacklist_carnival:client:openPanel', src, 'leaderboard')
end, false)

RegisterCommand('carnivalstatus', function(src)
    local st = Carnival.Events.publicState()
    if not st.active then return reply(src, 'No carnival event is active.') end
    local msg = ('#%d %s — %s'):format(st.id, st.name, st.stateLabel)
    if st.round and st.round > 0 then msg = msg .. (' — round %d/%d'):format(st.round, st.totalRounds) end
    msg = msg .. (' — %d participants'):format(st.participantCount or 0)
    reply(src, msg)
end, false)

-- /carnivalstart : ready -> running. If registration is still open/closed it walks
-- the state machine forward (close registration, mark ready) first.
RegisterCommand('carnivalstart', function(src, args)
    if not guard(src, 'events.manage') then return end
    local e = Carnival.Events.active
    if not e then return reply(src, 'No event exists. Create one in /carnivaladmin.', 'error') end
    local reason = joinArgs(args)
    local path = {
        registration_open = { S.REG_CLOSED, S.READY, S.RUNNING },
        registration_closed = { S.READY, S.RUNNING },
        ready = { S.RUNNING },
    }
    local steps = path[e.state]
    if not steps then return reply(src, ('Cannot start from %s.'):format(C.STATE_LABELS[e.state]), 'error') end
    for _, to in ipairs(steps) do
        local ok, code, msg = Carnival.Events.transition(src, to, reason)
        if not ok then return result(src, false, code, msg) end
    end
    reply(src, 'The carnival has begun.', 'success')
end, false)

RegisterCommand('carnivalpause', function(src, args)
    if not guard(src, 'events.operate') then return end
    result(src, Carnival.Events.transition(src, S.PAUSED, joinArgs(args)))
end, false)

RegisterCommand('carnivalresume', function(src, args)
    if not guard(src, 'events.operate') then return end
    result(src, Carnival.Events.resume(src, joinArgs(args)))
end, false)

-- /carnivalstop <reason> : cancels a running event; during final results it completes it.
RegisterCommand('carnivalstop', function(src, args)
    if not guard(src, 'events.manage') then return end
    local e = Carnival.Events.active
    if not e then return reply(src, 'No event is active.', 'error') end
    local reason = joinArgs(args)
    if e.state == S.FINAL then
        return result(src, Carnival.Events.transition(src, S.COMPLETED, reason ~= '' and reason or 'Completed'))
    end
    if #reason < 3 then return reply(src, 'Usage: /carnivalstop <reason>', 'error') end
    result(src, Carnival.Events.transition(src, S.CANCELLED, reason))
end, false)

-- Console / admin: verify the configured inventory items exist.
RegisterCommand('carnivalitems', function(src)
    if not guard(src, 'panel.admin') then return end
    local r = Carnival.Inventory.validateDefinitions(false)
    if not r.inventoryRunning then return reply(src, 'ox_inventory is not running.', 'error') end
    if r.ok then
        reply(src, ('All %d carnival items are registered in ox_inventory.'):format(#r.checked), 'success')
    else
        reply(src, 'Missing items: ' .. table.concat(r.missing, ', '), 'error')
    end
end, false)

-- Console / admin: verify the score ledger of the active event.
RegisterCommand('carnivalverify', function(src)
    if not guard(src, 'scores.adjust') then return end
    local id = Carnival.Events.activeId()
    if not id then return reply(src, 'No event is active.', 'error') end
    local r = Carnival.Scoring.verify(id)
    reply(src, r.ok and ('Ledger OK (%d transactions).'):format(r.transactions)
        or ('Ledger mismatch: %d totals, %d summaries, %d chain breaks.'):format(#r.totals, #r.summaries, #r.chains), r.ok and 'success' or 'error')
end, false)

-- Coordinate capture helper for admins (prints to chat/F8 and clipboard via NUI).
RegisterCommand('carnivalcoords', function(src)
    if src == 0 or not guard(src, 'config.edit') then return end
    TriggerClientEvent('blacklist_carnival:client:captureCoords', src)
end, false)

TriggerEvent('chat:addSuggestion', '/carnival', 'Open the Carnival of the Damned panel')
TriggerEvent('chat:addSuggestion', '/carnivaladmin', 'Open the carnival configurator (admin)')
TriggerEvent('chat:addSuggestion', '/carnivalboard', 'Show the carnival leaderboard')
TriggerEvent('chat:addSuggestion', '/carnivalstatus', 'Show the carnival event status')
TriggerEvent('chat:addSuggestion', '/carnivalstart', 'Start the carnival event', { { name = 'reason', help = 'optional note' } })
TriggerEvent('chat:addSuggestion', '/carnivalpause', 'Pause the carnival event', { { name = 'reason', help = 'optional note' } })
TriggerEvent('chat:addSuggestion', '/carnivalresume', 'Resume the carnival event')
TriggerEvent('chat:addSuggestion', '/carnivalstop', 'Cancel the event (or complete it during final results)', { { name = 'reason', help = 'required when cancelling' } })
