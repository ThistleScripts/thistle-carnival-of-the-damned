-- End-to-end server tests: real server scripts + real MariaDB.
-- Run from the resource directory:  lua5.4 tests/server_spec.lua
-- (see tests/README.md for database setup)

package.path = './tests/?.lua;' .. package.path
local H = require('harness')

local results, current = {}, nil
local function test(name, fn)
    current = name
    local ok, err = xpcall(fn, debug.traceback)
    results[#results + 1] = { name = name, ok = ok, err = err }
    H.print((ok and '  \27[32mPASS\27[0m ' or '  \27[31mFAIL\27[0m ') .. name .. (ok and '' or ('\n' .. tostring(err))))
end
local function section(name) H.print('\n\27[33m' .. name .. '\27[0m') end
local function eq(a, b, msg)
    if a ~= b then error(('%s: expected %s, got %s'):format(msg or 'value', tostring(b), tostring(a)), 2) end
end
local function truthy(v, msg) if not v then error((msg or 'expected truthy') .. ' (got ' .. tostring(v) .. ')', 2) end end
local function okRes(r, msg)
    if not r or not r.ok then error((msg or 'expected ok') .. ': ' .. tostring(r and r.error) .. ' / ' .. H.json.encode(r and r.message), 2) end
    return r.data
end
local function errRes(r, code, msg)
    if not r or r.ok then error((msg or 'expected error') .. ' but request succeeded', 2) end
    if code and r.error ~= code then error(('%s: expected error %s, got %s (%s)'):format(msg or 'error', code, tostring(r.error), H.json.encode(r.message)), 2) end
end
local function count(sql, p) return H.sql(sql, p)[1].n end

---------------------------------------------------------------------------
-- Cast
---------------------------------------------------------------------------
local OWNER, ADMIN, MANAGER, OBSERVER, HORROR, WHEELOP, OUTSIDER = 1, 2, 3, 4, 5, 6, 7
local PLAYERS = {}
for i = 10, 21 do PLAYERS[#PLAYERS + 1] = i end
local WALKERS = {}
for i = 30, 35 do WALKERS[#WALKERS + 1] = i end

local function setupPlayers()
    H.addPlayer(OWNER, { name = 'Owner' })
    H.addPlayer(ADMIN, { name = 'Admin', aces = { ['carnival.role.administrator'] = true } })
    H.addPlayer(MANAGER, { name = 'Manager', aces = { ['carnival.role.event_manager'] = true } })
    H.addPlayer(OBSERVER, { name = 'Observer', aces = { ['carnival.role.observer'] = true } })
    H.addPlayer(HORROR, { name = 'Keeper', aces = { ['carnival.role.event_manager'] = true } })
    -- staff who only act at the carnival need no role
    H.addPlayer(WHEELOP, { name = 'Actor' })
    H.addPlayer(OUTSIDER, { name = 'Nobody' })
    for _, s in ipairs(PLAYERS) do H.addPlayer(s, { citizenid = 'CIT' .. s }) end
    for _, s in ipairs(WALKERS) do H.addPlayer(s, { citizenid = 'WALK' .. s }) end
end

local function configure(cfg)
    cfg.Security.Allowlist[H.players[OWNER].license] = 'owner'
    -- a role removed from config.lua must simply be ignored
    cfg.Security.Allowlist[H.players[WHEELOP].license] = 'performer'
    cfg.LogLevel = 'warning'
    -- The suite runs staff-scheduled events first; walk-up mode (the factory
    -- default) has its own section near the end.
    Carnival.Defaults.general.mode = 'scheduled'
    -- The suite fires many requests within one virtual second; rate limiting has its own test.
    for k, v in pairs(cfg.RateLimits) do if type(v) == 'table' then cfg.RateLimits[k] = { 1000, 10 } end end
end

local C
local function settings() return Carnival.Config.get() end
local function colourOf(src) return Carnival.Participants.getBySource(src).colour end
local function membersOf(colour)
    local out = {}
    for _, s in ipairs(PLAYERS) do if colourOf(s) == colour then out[#out + 1] = s end end
    return out
end
local function attractionOfColour(colour) return Carnival.Rotation.sessionForColour(colour).attraction_id end
local function colourAt(attraction)
    for _, c in ipairs(C.COLOURS) do
        local s = Carnival.Rotation.sessionForColour(c)
        if s and s.attraction_id == attraction then return c end
    end
end
local function at(src, point) H.moveTo(src, point) end

---------------------------------------------------------------------------
section('Database & bootstrap')
---------------------------------------------------------------------------
H.resetDatabase()
local itemNames = {}
do
    local f = assert(loadfile('shared/constants.lua'))
    f()
    C = Carnival.C
    for _, n in ipairs(C.CUSTOM_ITEMS) do itemNames[#itemNames + 1] = n end
    itemNames[#itemNames + 1] = 'WEAPON_PISTOL'
    itemNames[#itemNames + 1] = 'ammo-9'
end
H.registerItems(itemNames)
setupPlayers()

test('schema installs from a clean database and migrations are recorded', function()
    H.start({ configure = configure })
    C = Carnival.C
    eq(count("SELECT COUNT(*) AS n FROM carnival_schema_migrations"), 7, 'migrations applied')
    eq(count('SELECT COUNT(*) AS n FROM carnival_attractions'), 6, 'attractions seeded')
    truthy(count("SELECT COUNT(*) AS n FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name LIKE 'carnival_%'") >= 30, 'all tables created')
end)

test('migrations are idempotent (re-run on restart)', function()
    local ok = H.call(Carnival.Db.migrate)
    truthy(ok, 'migrate')
    eq(count("SELECT COUNT(*) AS n FROM carnival_schema_migrations"), 7, 'no duplicates')
end)

test('factory configuration is seeded as global version 1 and validates', function()
    eq(count("SELECT COUNT(*) AS n FROM carnival_config_versions WHERE scope = 'global' AND is_active = 1"), 1)
    local _, errors = Carnival.Validate.config(Carnival.Defaults)
    eq(#errors, 0, 'defaults valid')
    eq(settings().attractions.wheel.maxSpins, 2)
end)

test('no clowns anywhere in default content or NPC models', function()
    local blob = H.json.encode(Carnival.Defaults):lower()
    truthy(not blob:find('clown'), 'defaults mention a clown')
    truthy(not blob:find('mime'), 'defaults mention a mime')
end)

---------------------------------------------------------------------------
section('Permissions')
---------------------------------------------------------------------------
test('roles resolve from allowlist and ACE; event managers and observers get a limited admin panel', function()
    eq(Carnival.Perms.role(OWNER), 'owner')
    eq(Carnival.Perms.role(ADMIN), 'administrator')
    eq(Carnival.Perms.role(MANAGER), 'event_manager')
    eq(Carnival.Perms.role(OUTSIDER), nil)
    eq(Carnival.Perms.role(WHEELOP), nil, 'unknown role in the allowlist is ignored')
    truthy(Carnival.Perms.has(MANAGER, 'panel.admin'), 'manager opens the admin panel')
    truthy(not Carnival.Perms.has(MANAGER, 'config.edit'), 'manager cannot edit settings')
    truthy(Carnival.Perms.has(OBSERVER, 'panel.admin') and not Carnival.Perms.has(OBSERVER, 'scores.adjust'), 'observer is read-only')
    truthy(not Carnival.Perms.has(WHEELOP, 'panel.admin'), 'actors have no panel')
end)

test('there are no staff controls for any game', function()
    for _, name in ipairs({ 'staff.checkIn', 'staff.dashboard', 'wheel.staff.approve', 'fortune.staff.present', 'fortune.staff.award',
        'shooting.allowReplay', 'theatre.create', 'theatre.commit', 'deception.setup', 'deception.commit', 'horror.start', 'horror.scare' }) do
        errRes(H.api(OWNER, name, {}), 'unknown_endpoint', name)
    end
    for name, def in pairs(Carnival.Api.endpoints()) do
        truthy(not name:find('%.staff%.') and def.perm ~= 'panel.staff', 'staff endpoint left: ' .. name)
    end
end)

test('unauthorised panel and privileged calls are rejected server-side', function()
    errRes(H.api(OUTSIDER, 'admin.dashboard'), 'forbidden')
    errRes(H.api(OUTSIDER, 'config.save', { scope = 'global', data = {} }), 'forbidden')
    errRes(H.api(MANAGER, 'config.save', { scope = 'global', data = {} }), 'forbidden')
    errRes(H.api(OBSERVER, 'scores.adjust', { participantId = 1, delta = 5, reason = 'x', requestId = 'abcdefgh1' }), 'forbidden')
    errRes(H.api(OUTSIDER, 'does.not.exist'), 'unknown_endpoint')
    truthy(count("SELECT COUNT(*) AS n FROM carnival_monitor_log WHERE 1=0") == 0)
end)

test('rate limits reject floods without banning (security log only)', function()
    local saved = Config.RateLimits.participant
    Config.RateLimits.participant = { 3, 10 }
    for _ = 1, 3 do okRes(H.api(OUTSIDER, 'participant.state')) end
    errRes(H.api(OUTSIDER, 'participant.state'), 'rate_limited')
    Config.RateLimits.participant = saved
    H.advance(11)
    okRes(H.api(OUTSIDER, 'participant.state'), 'allowed again after the window')
end)

---------------------------------------------------------------------------
section('Configuration versioning')
---------------------------------------------------------------------------
test('invalid configuration is rejected with field errors', function()
    local doc = okRes(H.api(ADMIN, 'config.get', { scope = 'global' })).data
    doc.rotation.matrix[1][2] = 'shooting' -- duplicate attraction in round 1
    doc.attractions.wheel.maxSpins = 999
    local r = okRes(H.api(ADMIN, 'config.save', { scope = 'global', data = doc, note = 'bad' }))
    eq(r.saved, false)
    truthy(#r.analysis.errors >= 1, 'has errors')
end)

test('secret fields are redacted for users without the permission and preserved on save', function()
    -- observer cannot open config at all
    errRes(H.api(OBSERVER, 'config.get', { scope = 'global' }), 'forbidden')
    -- admin sees secrets (has deception.secrets)
    local doc = okRes(H.api(ADMIN, 'config.get', { scope = 'global' })).data
    truthy(doc.attractions.deception.mysteries[1].performers[1].isLiar ~= nil, 'admin sees answer key')
    -- simulate an editor without secrets: redact then restore
    local red = Carnival.Validate.redact(settings(), function(p) return p ~= 'deception.secrets' end)
    eq(red.attractions.deception.mysteries[1].performers[1].isLiar, nil, 'redacted')
    local restored = Carnival.Validate.restoreSecrets(red, settings(), function(p) return p ~= 'deception.secrets' end)
    eq(restored.attractions.deception.mysteries[1].performers[1].isLiar, true, 'restored')
end)

test('valid change creates a new version, can be previewed and rolled back', function()
    local doc = okRes(H.api(ADMIN, 'config.get', { scope = 'global' })).data
    doc.attractions.wheel.maxSpins = 3
    local p = okRes(H.api(ADMIN, 'config.preview', { scope = 'global', data = doc }))
    eq(p.valid, true)
    eq(#p.changes, 1)
    local r = okRes(H.api(ADMIN, 'config.save', { scope = 'global', data = doc, note = 'more spins' }))
    eq(r.saved, true)
    eq(r.version, 2)
    eq(settings().attractions.wheel.maxSpins, 3)
    local v1 = H.sql("SELECT id FROM carnival_config_versions WHERE scope = 'global' AND version = 1")[1].id
    local rb = okRes(H.api(ADMIN, 'config.rollback', { versionId = v1, note = 'undo' }))
    eq(rb.saved, true)
    eq(rb.version, 3)
    eq(settings().attractions.wheel.maxSpins, 2)
    truthy(count("SELECT COUNT(*) AS n FROM carnival_audit_log WHERE action IN ('config_saved','config_rolled_back')") >= 2, 'audited')
end)

test('reward items in config are validated against the inventory registry', function()
    local doc = okRes(H.api(ADMIN, 'config.get', { scope = 'global' })).data
    doc.attractions.wheel.outcomes[1].item = 'not_a_real_item'
    doc.attractions.wheel.outcomes[1].count = 1
    local r = okRes(H.api(ADMIN, 'config.save', { scope = 'global', data = doc }))
    eq(r.saved, false)
    truthy(r.analysis.errors[1].message:find('not registered'), 'item error')
end)

-- Make the event short and deterministic for the rest of the suite.
test('apply test configuration (short timers, everyone ready)', function()
    local doc = okRes(H.api(OWNER, 'config.get', { scope = 'global' })).data
    doc.rotation.roundDurationSeconds = 300
    doc.rotation.transitionSeconds = 10
    doc.rotation.warningSeconds = { 30 }
    doc.groups.colours.red.capacity = 2
    doc.attractions.wheel.cooldownSeconds = 0
    doc.attractions.horror.durationSeconds = 60
    doc.attractions.horror.warnings = { 30, 10 }
    doc.attractions.horror.tokenTypes.gold.quantity = 0
    doc.attractions.fortune.questionsPerVisit = 2
    doc.attractions.horror.lobbySeconds = 5
    doc.attractions.shooting.roundBreakSeconds = 2
    for i, r in ipairs(doc.attractions.shooting.rounds) do
        r.durationSeconds = 8
        r.targetCount = 3 + i
    end
    local r = okRes(H.api(OWNER, 'config.save', { scope = 'global', data = doc, note = 'test', confirm = true }))
    eq(r.saved, true)
end)

---------------------------------------------------------------------------
section('Event lifecycle & registration')
---------------------------------------------------------------------------
local eventId
test('admin creates an event; invalid transitions are rejected', function()
    eventId = okRes(H.api(ADMIN, 'events.create', { name = 'Test Night' })).id
    eq(Carnival.Events.state(), 'configuring')
    errRes(H.api(ADMIN, 'events.transition', { to = 'running' }), 'invalid_transition')
    errRes(H.api(ADMIN, 'events.create', { name = 'Second' }), 'invalid')
    errRes(H.api(MANAGER, 'events.transition', { to = 'registration_open' }), 'forbidden')
end)

test('registration cannot open while ticket items are missing from ox_inventory', function()
    H.itemRegistry.carnival_ticket_red = nil
    errRes(H.api(ADMIN, 'events.transition', { to = 'registration_open' }), 'precondition')
    H.itemRegistry.carnival_ticket_red = { name = 'carnival_ticket_red' }
    okRes(H.api(ADMIN, 'events.transition', { to = 'registration_open' }))
    eq(Carnival.Events.state(), 'registration_open')
end)

test('players must be at the ticket booth to register', function()
    at(PLAYERS[1], { x = 0, y = 0, z = 0 })
    errRes(H.api(PLAYERS[1], 'registration.register'), 'too_far')
end)

test('twelve players register with balanced colours and receive physical tickets', function()
    for _, s in ipairs(PLAYERS) do
        at(s, settings().registration.entrance)
        local r = okRes(H.api(s, 'registration.register'), 'register ' .. s)
        truthy(r.colour, 'colour assigned')
        eq(r.ticketIssued, true, 'ticket issued')
    end
    local counts = Carnival.Groups.counts().byColour
    for _, c in ipairs(C.COLOURS) do eq(counts[c], 2, 'colour ' .. c) end
    local p = Carnival.Participants.getBySource(PLAYERS[1])
    local slots = H.itemsOf(PLAYERS[1], C.TICKET_ITEMS[p.colour])
    eq(#slots, 1, 'one ticket item')
    eq(slots[1].metadata.participantId, p.id)
    eq(slots[1].metadata.eventId, eventId)
    truthy(slots[1].metadata.serial:match('^CTD%-'), 'serial')
end)

test('duplicate registration is rejected', function()
    errRes(H.api(PLAYERS[1], 'registration.register'), 'already_registered')
    eq(count('SELECT COUNT(*) AS n FROM carnival_participants WHERE event_id = ?', { eventId }), 12)
end)

test('group capacity is enforced on transfer', function()
    local p = Carnival.Participants.getBySource(PLAYERS[1])
    local target = p.colour == 'red' and 'blue' or 'red'
    if target == 'red' then
        errRes(H.api(MANAGER, 'participants.reassign', { id = p.id, colour = 'red', reason = 'testing capacity' }), 'group_full')
    end
end)

test('ticket replacement voids the old serial and forged tickets are detected', function()
    local s = PLAYERS[2]
    local p = Carnival.Participants.getBySource(s)
    local oldSerial = Carnival.Tickets.current(p.id).serial
    -- player "loses" the ticket
    H.inventories[s].items = {}
    local r = okRes(H.api(s, 'registration.replaceTicket'))
    eq(r.delivered, true)
    local newSerial = Carnival.Tickets.current(p.id).serial
    truthy(newSerial ~= oldSerial, 'new serial')
    eq(H.sql('SELECT status FROM carnival_tickets WHERE serial = ?', { oldSerial })[1].status, 'replaced')
    -- forged ticket with a made-up serial
    table.insert(H.inventories[s].items, { name = C.TICKET_ITEMS[p.colour], count = 1, metadata = { serial = 'CTD-FAKE1-FAKE2', participantId = p.id, eventId = eventId } })
    local ok = H.call(Carnival.Tickets.verify, s, p)
    eq(ok, true, 'still valid (holds real ticket)')
    truthy(count("SELECT COUNT(*) AS n FROM carnival_monitor_log WHERE action = 'invalid_ticket_presented'") >= 0)
    H.call(Carnival.Monitor.flush)
    truthy(count("SELECT COUNT(*) AS n FROM carnival_monitor_log WHERE action = 'invalid_ticket_presented' AND result = 'forged'") >= 1, 'forged logged')
    -- presenting only the forged ticket is rejected
    H.inventories[s].items = { { name = C.TICKET_ITEMS[p.colour], count = 1, metadata = { serial = 'CTD-FAKE1-FAKE2', participantId = p.id, eventId = eventId } } }
    local ok2, why = H.call(Carnival.Tickets.verify, s, p)
    eq(ok2, false)
    eq(why, 'ticket_missing')
    -- staff re-issue to restore
    okRes(H.api(MANAGER, 'tickets.replace', { participantId = p.id, reason = 'test restore' }))
    eq(H.call(Carnival.Tickets.verify, s, p), true)
end)

test('manual group transfer reissues a ticket in the new colour (audited)', function()
    local s = PLAYERS[3]
    local p = Carnival.Participants.getBySource(s)
    local from = p.colour
    local to = from == 'blue' and 'green' or 'blue'
    -- make room: capacity 20 for non-red
    local r = okRes(H.api(MANAGER, 'participants.reassign', { id = p.id, colour = to, reason = 'Friends together' }))
    eq(r.to, to)
    eq(#H.itemsOf(s, C.TICKET_ITEMS[to]), 1, 'new ticket colour')
    eq(#H.itemsOf(s, C.TICKET_ITEMS[from]), 0, 'old ticket removed')
    -- move back to keep the groups balanced
    okRes(H.api(MANAGER, 'participants.reassign', { id = p.id, colour = from, reason = 'Back again' }))
    truthy(count("SELECT COUNT(*) AS n FROM carnival_audit_log WHERE action = 'participant_group_transferred'") == 2)
end)

test('remove and reinstate a participant', function()
    local p = Carnival.Participants.getBySource(PLAYERS[4])
    okRes(H.api(MANAGER, 'participants.remove', { id = p.id, reason = 'Left early' }))
    eq(Carnival.Participants.get(p.id).status, 'removed')
    errRes(H.api(MANAGER, 'participants.remove', { id = p.id, reason = 'again' }), 'invalid')
    okRes(H.api(MANAGER, 'participants.reinstate', { id = p.id, reason = 'Came back' }))
    eq(Carnival.Participants.get(p.id).status, 'active')
end)

test('reconnecting players recover their registration', function()
    local s = PLAYERS[5]
    local pid = Carnival.Participants.idOfSource(s)
    H.triggerFrom(s, 'playerDropped')
    eq(Carnival.Participants.sourceOf(pid), nil, 'unbound')
    -- reconnects with a new server id
    local p = H.players[s]
    H.players[s] = nil
    H.addPlayer(40, { citizenid = p.citizenid, license = p.license })
    H.inventories[40] = H.inventories[s]
    H.triggerFrom(40, 'blacklist_carnival:server:clientReady')
    eq(Carnival.Participants.sourceOf(pid), 40, 'rebound to new source')
    -- swap back for the rest of the suite
    H.triggerFrom(40, 'playerDropped')
    H.players[40] = nil
    H.players[s] = p
    H.triggerFrom(s, 'blacklist_carnival:server:clientReady')
    eq(Carnival.Participants.sourceOf(pid), s)
end)

test('registration closes, event becomes ready and starts round 1 with six sessions', function()
    okRes(H.api(ADMIN, 'events.transition', { to = 'registration_closed' }))
    okRes(H.api(ADMIN, 'events.transition', { to = 'ready' }))
    okRes(H.api(ADMIN, 'events.transition', { to = 'running', reason = 'Let the show begin' }))
    eq(Carnival.Events.state(), 'running')
    eq(Carnival.Rotation.currentRoundNumber(), 1)
    local seen = {}
    for _, c in ipairs(C.COLOURS) do
        local s = Carnival.Rotation.sessionForColour(c)
        eq(s.status, 'active', 'session ' .. c)
        truthy(not seen[s.attraction_id], 'unique attraction')
        seen[s.attraction_id] = true
        eq(s.attraction_id, settings().rotation.matrix[1][C.COLOUR_INDEX[c]], 'matrix')
    end
    eq(count('SELECT COUNT(*) AS n FROM carnival_event_settings WHERE event_id = ? AND reason = ?', { eventId, 'start' }), 1, 'settings snapshot')
end)


---------------------------------------------------------------------------
section('Attraction: Wheel of Misfortune')
---------------------------------------------------------------------------
test('wrong group cannot use the wheel; right group spins with server-chosen outcomes', function()
    local wc = colourAt('wheel')
    local other = colourAt('shooting')
    local s = membersOf(wc)[1]
    local o = membersOf(other)[1]
    at(o, settings().attractions.wheel.location)
    errRes(H.api(o, 'wheel.spin'), 'wrong_attraction')
    at(s, settings().attractions.wheel.location)
    local before = Carnival.Participants.getBySource(s).total_score
    local r1 = okRes(H.api(s, 'wheel.spin'))
    truthy(r1.index >= 1 and r1.outcome.id, 'outcome')
    local r2 = okRes(H.api(s, 'wheel.spin'))
    eq(r2.spinsUsed, 2)
    errRes(H.api(s, 'wheel.spin'), 'no_spins')
    eq(count('SELECT COUNT(*) AS n FROM carnival_wheel_spins WHERE participant_id = ?', { Carnival.Participants.idOfSource(s) }), 2)
    -- ledger matches total
    local after = Carnival.Participants.getBySource(s).total_score
    local ledger = H.sql('SELECT COALESCE(SUM(delta),0) AS n FROM carnival_score_transactions WHERE participant_id = ?', { Carnival.Participants.idOfSource(s) })[1].n
    eq(after, tonumber(ledger), 'total equals ledger')
    truthy(after >= before - 20, 'sane total')
end)

test('wheel weights follow configured probabilities (10k draws)', function()
    local outcomes = settings().attractions.wheel.outcomes
    local hits, total = {}, 0
    for _, o in ipairs(outcomes) do total = total + o.weight end
    for _ = 1, 10000 do
        local o = Carnival.WheelAttraction.choose(outcomes)
        hits[o.id] = (hits[o.id] or 0) + 1
    end
    for _, o in ipairs(outcomes) do
        local expected = o.weight / total
        local got = (hits[o.id] or 0) / 10000
        truthy(math.abs(got - expected) < 0.025, ('%s expected %.3f got %.3f'):format(o.id, expected, got))
    end
end)

test('special prizes are delivered straight away and delivery is idempotent', function()
    local wc = colourAt('wheel')
    local s = membersOf(wc)[2]
    at(s, settings().attractions.wheel.location)
    -- force the special outcome by stubbing the chooser for one spin
    local real = Carnival.WheelAttraction.choose
    Carnival.WheelAttraction.choose = function(outcomes)
        for i, o in ipairs(outcomes) do if o.type == 'special_prize' then return o, i, 0.5, 1000 end end
    end
    local scoresBefore = #H.pushesFor(s, 'score')
    local r = okRes(H.api(s, 'wheel.spin'))
    Carnival.WheelAttraction.choose = real
    eq(r.reward.status, 'pending', 'no staff approval step')
    -- nothing is announced or handed over while the wheel is still turning
    eq(#H.pushesFor(s, 'score'), scoresBefore, 'no score toast mid-spin')
    eq(H.sql('SELECT status FROM carnival_rewards WHERE id = (SELECT reward_id FROM carnival_wheel_spins ORDER BY id DESC LIMIT 1)')[1].status, 'pending')
    H.advance(math.ceil(settings().attractions.wheel.spinAnimationMs / 1000) + 1)
    truthy(#H.pushesFor(s, 'score') > scoresBefore, 'score toast once the wheel stops')
    local reward = H.sql("SELECT * FROM carnival_rewards WHERE source = 'wheel' AND status = 'delivered' ORDER BY id DESC LIMIT 1")[1]
    local itemsBefore = #H.itemsOf(s, reward.item)
    -- retrying delivery must not duplicate
    eq(H.call(Carnival.Rewards.deliver, reward.id), 'delivered')
    eq(#H.itemsOf(s, reward.item), itemsBefore, 'no duplicate items')
end)

test('reward delivery failure (full inventory) is recorded and reconcilable', function()
    local p = Carnival.Participants.getBySource(PLAYERS[6])
    H.inventoryFull[PLAYERS[6]] = true
    local r = H.call(Carnival.Rewards.create, { participantId = p.id, source = 'manual', item = 'carnival_bloodfloss', count = 2, key = 'test:full' })
    eq(H.call(Carnival.Rewards.deliver, r.id), 'failed')
    eq(H.sql('SELECT last_error FROM carnival_rewards WHERE id = ?', { r.id })[1].last_error, 'inventory_full')
    H.inventoryFull[PLAYERS[6]] = nil
    eq(okRes(H.api(MANAGER, 'rewards.retry', { id = r.id })).status, 'delivered')
    -- invalid configured item is refused before any delivery
    local bad, code = H.call(Carnival.Rewards.create, { participantId = p.id, source = 'manual', item = 'carnival_ticket_red', count = 1, key = 'test:ticket' })
    eq(bad, nil)
    eq(code, 'item_not_permitted')
end)

---------------------------------------------------------------------------
section('Attraction: Fortune Teller')
---------------------------------------------------------------------------
test('automated visit: server-marked answers, no answer leak, no retry farming', function()
    local fc = colourAt('fortune')
    local s = membersOf(fc)[1]
    at(s, settings().attractions.fortune.location)
    local v = okRes(H.api(s, 'fortune.begin'))
    truthy(v.question, 'question')
    eq(v.question.correctIndex, nil, 'no correct index sent')
    eq(v.question.acceptedAnswers, nil, 'no answers sent')
    -- resuming returns the same pending question
    local v2 = okRes(H.api(s, 'fortune.begin'))
    eq(v2.question.id, v.question.id, 'resume same question')
    local q = nil
    for _, x in ipairs(settings().attractions.fortune.questions) do if x.id == v.question.id then q = x end end
    local payload = { visitId = v.visitId, questionId = q.id }
    if q.kind == 'choice' then payload.choice = q.correctIndex else payload.text = q.acceptedAnswers[1] end
    local a = okRes(H.api(s, 'fortune.answer', payload))
    eq(a.correct, true)
    eq(a.points, q.points)
    -- answering the same question again is rejected
    errRes(H.api(s, 'fortune.answer', payload), 'stale')
    -- wrong answer to the next question
    local q2 = a.question
    local wrong = { visitId = v.visitId, questionId = q2.id }
    if q2.kind == 'choice' then wrong.choice = 1 local real for _, x in ipairs(settings().attractions.fortune.questions) do if x.id == q2.id then real = x end end if real.correctIndex == 1 then wrong.choice = 2 end
    else wrong.text = 'definitely wrong' end
    local b = okRes(H.api(s, 'fortune.answer', wrong))
    eq(b.correct, false)
    eq(b.finished, true)
    errRes(H.api(s, 'fortune.begin'), 'no_visits')
end)

---------------------------------------------------------------------------
section('Attraction: Shooting Gallery')
---------------------------------------------------------------------------
test('aim game: the server owns the schedule, validates every click and scores once', function()
    local sc = colourAt('shooting')
    local shooters = membersOf(sc)
    local cfg = settings().attractions.shooting
    local s = shooters[1]
    at(s, cfg.location)
    errRes(H.api(membersOf(colourAt('wheel'))[1], 'shooting.start'), 'wrong_attraction')
    local g = okRes(H.api(s, 'shooting.start'))
    local targets = 0
    for _, r in ipairs(cfg.rounds) do targets = targets + r.targetCount end
    eq(#g.plan, targets, 'schedule for every round sent')
    eq(#g.rounds, #cfg.rounds)
    truthy(g.elapsedMs < 0, 'countdown first')
    -- resuming returns the same game
    eq(okRes(H.api(s, 'shooting.start')).gameId, g.gameId)
    -- clicking during the countdown is refused
    errRes(H.api(s, 'shooting.shot', { gameId = g.gameId, targetId = g.plan[1].id }), 'before_start')
    -- jump to when target 1 is on screen
    local t1 = g.plan[1]
    H.ms = H.ms + 3000 + t1.t + 100
    local hit = okRes(H.api(s, 'shooting.shot', { gameId = g.gameId, targetId = t1.id, ring = 'inner' }))
    eq(hit.hit, true)
    local expected = t1.kind == 'decoy' and -cfg.decoyPenalty or t1.kind == 'special' and cfg.specialPoints or cfg.targetPoints + cfg.bullseyeBonus
    eq(hit.points, expected, 'server-side points')
    -- the same target again is refused
    H.ms = H.ms + 200
    errRes(H.api(s, 'shooting.shot', { gameId = g.gameId, targetId = t1.id }), 'already_hit')
    -- a target that is not on screen yet is refused
    local late
    for _, t in ipairs(g.plan) do if t.t > t1.t + t1.life + 3000 then late = t break end end
    if late then
        H.ms = H.ms + 200
        errRes(H.api(s, 'shooting.shot', { gameId = g.gameId, targetId = late.id }), 'off_screen')
    end
    -- clicking too fast is refused
    H.ms = H.ms + 200
    okRes(H.api(s, 'shooting.shot', { gameId = g.gameId }))
    errRes(H.api(s, 'shooting.shot', { gameId = g.gameId }), 'too_fast')
    -- someone else cannot shoot in this game
    errRes(H.api(shooters[2], 'shooting.shot', { gameId = g.gameId, targetId = 2 }), 'stale')
    -- finishing early is refused; the server timer ends the game
    errRes(H.api(s, 'shooting.finish', { gameId = g.gameId }), 'too_early')
    H.advance(math.ceil(Carnival.ShootingGameLengthMs() / 1000) + 6)
    local res = H.sql('SELECT * FROM carnival_shooting_results WHERE heat_id = ?', { g.gameId })
    eq(#res, 1)
    local pid = Carnival.Participants.idOfSource(s)
    eq(count('SELECT COUNT(*) AS n FROM carnival_score_transactions WHERE idempotency_key = ?', { ('shooting:%d:%d'):format(g.gameId, pid) }), res[1].points ~= 0 and 1 or 0)
    errRes(H.api(s, 'shooting.start'), 'already_shot')
end)

test('three rounds, each harder and worth more; the break between rounds ignores clicks', function()
    local sc = colourAt('shooting')
    local s = membersOf(sc)[2]
    local cfg = settings().attractions.shooting
    at(s, cfg.location)
    local g = okRes(H.api(s, 'shooting.start'))
    eq(#g.rounds, 3)
    for i = 2, 3 do
        local prev, r = cfg.rounds[i - 1], cfg.rounds[i]
        truthy(r.targetLifetimeMs < prev.targetLifetimeMs, 'round ' .. i .. ' targets are faster')
        truthy(r.targetSize < prev.targetSize, 'round ' .. i .. ' targets are smaller')
        truthy(r.decoyChance > prev.decoyChance, 'round ' .. i .. ' has more lanterns')
        truthy(r.pointsPercent > prev.pointsPercent, 'round ' .. i .. ' is worth more')
        eq(g.rounds[i].startMs, g.rounds[i - 1].endMs + cfg.roundBreakSeconds * 1000, 'break between rounds')
    end
    for _, t in ipairs(g.plan) do
        local r = g.rounds[t.round]
        truthy(t.t >= r.startMs and t.t + t.life <= r.endMs, 'target inside its round')
        truthy(t.lane >= 1 and t.lane <= r.lanes, 'lane inside its round')
    end
    local start = H.ms
    -- a click during the first break is ignored
    H.ms = start + 3000 + g.rounds[1].endMs + 500
    errRes(H.api(s, 'shooting.shot', { gameId = g.gameId }), 'between_rounds')
    -- a normal target in round 3 is worth pointsPercent of the base
    local t3
    for _, t in ipairs(g.plan) do if t.round == 3 and t.kind == 'normal' then t3 = t break end end
    if t3 then
        H.ms = start + 3000 + t3.t + 50
        local hit = okRes(H.api(s, 'shooting.shot', { gameId = g.gameId, targetId = t3.id, ring = 'outer' }))
        eq(hit.round, 3)
        eq(hit.points, math.floor(cfg.targetPoints * cfg.rounds[3].pointsPercent / 100 + 0.5), 'round 3 multiplier')
    end
    H.pushes = {}
    H.advance(math.ceil(Carnival.ShootingGameLengthMs() / 1000) + 6)
    local pushed = H.pushesFor(s, 'shooting')
    local result = pushed[#pushed].result
    eq(#result.rounds, 3, 'result has every round')
    if t3 then eq(result.rounds[3].hits, 1) end
    eq(result.rounds[1].points + result.rounds[2].points + result.rounds[3].points, result.targetPoints, 'rounds add up')
end)

---------------------------------------------------------------------------
section('Attraction: Hall of Deception')
---------------------------------------------------------------------------
test('secret answer key never reaches participants; submissions are limited; scoring committed once', function()
    local dc = colourAt('deception')
    local inv = membersOf(dc)
    local hall = settings().attractions.deception.location
    for _, s in ipairs(inv) do at(s, hall) end
    -- the mystery started by itself when the group arrived at the hall
    local pub = okRes(H.api(inv[1], 'deception.public'))
    eq(pub.status, 'questioning')
    local blob = H.json.encode(pub)
    truthy(not blob:find('isLiar'), 'no isLiar in public state')
    truthy(not blob:find('brief'), 'no briefs in public state')
    truthy(blob:find('statements'), 'testimony is public (whether it is a lie is not)')
    eq(pub.solution, nil)
    for _, p in ipairs(H.pushesFor(inv[1], 'deception')) do
        truthy(not H.json.encode(p):find('isLiar'), 'no secrets pushed')
    end
    errRes(H.api(inv[1], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'nobody' } }), 'invalid')
    errRes(H.api(inv[1], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'fireeater' } }), 'invalid')
    okRes(H.api(inv[1], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'fireeater', 'organ' }, explanation = 'Muddy boots.' }))
    okRes(H.api(inv[1], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'fireeater', 'knife' }, explanation = 'Changed my mind.' }))
    errRes(H.api(inv[1], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'fireeater', 'knife' } }), 'limit')
    okRes(H.api(inv[2], 'deception.submit', { roundId = pub.roundId, selections = { 'contortionist', 'fortune', 'organ' } }))
    -- everyone has accused: marked and revealed automatically, exactly once
    H.advance(6)
    eq(H.sql('SELECT status FROM carnival_deception_rounds WHERE id = ?', { pub.roundId })[1].status, 'committed')
    errRes(H.api(inv[2], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'fireeater', 'knife' } }), 'session_not_active')
    local m = settings().attractions.deception.mysteries[1]
    local function points(src)
        return tonumber(H.sql('SELECT COALESCE(SUM(requested_delta), 0) AS n FROM carnival_score_transactions WHERE idempotency_key = ?',
            { ('deception:%d:%d:auto'):format(pub.roundId, Carnival.Participants.idOfSource(src)) })[1].n)
    end
    eq(points(inv[1]), 3 * m.pointsPerCorrect + m.perfectBonus + m.tieBreakBonus, 'perfect accusation')
    eq(points(inv[2]), -3 * m.penaltyPerIncorrect, 'all wrong')
    eq(count('SELECT COUNT(*) AS n FROM carnival_score_transactions WHERE idempotency_key LIKE ?', { ('deception:%d:%%'):format(pub.roundId) }), 2, 'scored once')
    eq(Carnival.Rotation.sessionForColour(dc).status, 'completed', 'group moves on')
end)

---------------------------------------------------------------------------
section('Attraction: House of Horrors')
---------------------------------------------------------------------------
local runId
test('a player opens the doors; tokens validated; duplicates refused', function()
    local hc = colourAt('horror')
    local runners = membersOf(hc)
    local h = settings().attractions.horror
    at(runners[1], h.entry)
    eq(okRes(H.api(runners[1], 'horror.enter')).startsIn, h.lobbySeconds)
    H.advance(h.lobbySeconds + 1)
    runId = H.sql("SELECT id FROM carnival_horror_runs WHERE status = 'running'")[1].id
    local st = okRes(H.api(runners[1], 'horror.state'))
    eq(st.active, true)
    local token = st.tokens[1]
    -- too far
    at(runners[1], h.boundaryCentre)
    H.moveTo(runners[1], { x = token.coords.x + 10, y = token.coords.y, z = token.coords.z })
    errRes(H.api(runners[1], 'horror.collect', { runId = runId, tokenId = token.id }), 'too_far')
    -- valid
    H.moveTo(runners[1], token.coords)
    local c = okRes(H.api(runners[1], 'horror.collect', { runId = runId, tokenId = token.id }))
    truthy(c.points > 0, 'points')
    -- duplicate (replayed request)
    errRes(H.api(runners[1], 'horror.collect', { runId = runId, tokenId = token.id }), 'collected')
    -- invalid token id
    errRes(H.api(runners[1], 'horror.collect', { runId = runId, tokenId = 999999 }), 'invalid')
    -- stale run id
    errRes(H.api(runners[1], 'horror.collect', { runId = runId + 1, tokenId = token.id }), 'stale')
    -- non-runner
    H.moveTo(PLAYERS[1], token.coords)
    if colourOf(PLAYERS[1]) ~= hc then errRes(H.api(PLAYERS[1], 'horror.collect', { runId = runId, tokenId = token.id }), 'wrong_attraction') end
    eq(count('SELECT COUNT(*) AS n FROM carnival_horror_collections WHERE run_id = ?', { runId }), 1)
end)

test('countdown warnings fire at configured thresholds from the server timer', function()
    local hc = colourAt('horror')
    local runner = membersOf(hc)[1]
    H.pushes = {}
    H.advance(31)
    local warns = {}
    for _, p in ipairs(H.pushesFor(runner, 'horror')) do if p.action == 'warning' then warns[#warns + 1] = p.remaining end end
    eq(#warns, 1, 'one warning so far')
    truthy(warns[1] <= 30, 'warning at 30')
end)

test('escape awards completion + time bonus once; timer expiry ends the run', function()
    local hc = colourAt('horror')
    local runners = membersOf(hc)
    local h = settings().attractions.horror
    at(runners[1], h.exit)
    local e = okRes(H.api(runners[1], 'horror.exit', { runId = runId }))
    truthy(e.bonus >= h.completionBonus, 'bonus')
    errRes(H.api(runners[1], 'horror.exit', { runId = runId }), 'escaped')
    H.pushes = {}
    H.advance(40)
    eq(H.sql('SELECT status, end_reason FROM carnival_horror_runs WHERE id = ?', { runId })[1].end_reason, 'expired')
    local ends = 0
    for _, p in ipairs(H.pushesFor(runners[2], 'horror')) do if p.action == 'end' then ends = ends + 1 end end
    eq(ends, 1, 'end pushed once')
    -- the group session was completed by the run
    eq(Carnival.Rotation.sessionForColour(hc).status, 'completed')
end)

---------------------------------------------------------------------------
section('Rotation, timers, overtime, pause')
---------------------------------------------------------------------------
test('a show in progress holds the round past its timer (overtime) and completes it when it ends', function()
    -- start a show at the theatre just before the round timer runs out
    local tc = colourAt('puppets')
    local cast = membersOf(tc)
    for _, s in ipairs(cast) do at(s, settings().attractions.puppets.location) end
    local left = Carnival.Rotation.currentRound().ends_at - os.time()
    local lead = settings().attractions.puppets.lobbySeconds + 10
    if left > lead then H.advance(left - lead) end
    okRes(H.api(cast[1], 'theatre.play'))
    H.advance(lead + 5)
    for _, c in ipairs(C.COLOURS) do
        local s = Carnival.Rotation.sessionForColour(c)
        eq(s.status, s.attraction_id == 'puppets' and 'active' or 'completed', s.attraction_id)
    end
    eq(Carnival.Events.publicState().overtime, true)
    eq(Carnival.Events.state(), 'running')
end)

test('event moves between rounds when the show ends and auto-starts round 2', function()
    local perf = H.sql("SELECT * FROM carnival_theatre_performances WHERE status = 'running' ORDER BY id DESC LIMIT 1")[1]
    H.advance(perf.duration_seconds + 2)
    eq(H.sql('SELECT status FROM carnival_theatre_performances WHERE id = ?', { perf.id })[1].status, 'committed', 'solo show scored')
    eq(count("SELECT COUNT(*) AS n FROM carnival_event_transitions WHERE event_id = ? AND to_state = 'between_rounds'", { eventId }), 1, 'round 1 closed')
    eq(count("SELECT COUNT(*) AS n FROM carnival_attraction_participation WHERE event_id = ? AND status = 'completed'", { eventId }), 12)
    eq(Carnival.Events.state(), 'running')
    eq(Carnival.Rotation.currentRoundNumber(), 2)
    for _, c in ipairs(C.COLOURS) do
        eq(Carnival.Rotation.sessionForColour(c).attraction_id, settings().rotation.matrix[2][C.COLOUR_INDEX[c]], 'round 2 matrix ' .. c)
    end
end)


test('pause freezes the round timer and resume restores it', function()
    local endsBefore = Carnival.Rotation.currentRound().ends_at
    local remaining = endsBefore - os.time()
    okRes(H.api(MANAGER, 'events.transition', { to = 'paused', reason = 'Medical break' }))
    H.advance(50)
    eq(Carnival.Events.publicState().roundRemaining, remaining, 'frozen remaining')
    -- scoring refused while paused
    local s = membersOf(colourAt('wheel'))[1]
    at(s, settings().attractions.wheel.location)
    errRes(H.api(s, 'wheel.spin'), 'paused')
    okRes(H.api(MANAGER, 'events.resume', { reason = 'back' }))
    eq(Carnival.Rotation.currentRound().ends_at - os.time(), remaining, 'restored remaining')
end)

test('skip, delay and extend are audited overrides', function()
    okRes(H.api(MANAGER, 'rotation.extend', { seconds = 60, reason = 'Roleplay running long' }))
    okRes(H.api(MANAGER, 'rotation.skip', { colour = colourAt('fortune'), reason = 'Performer missing' }))
    local wheelColour = colourAt('wheel')
    okRes(H.api(MANAGER, 'rotation.delay', { colour = wheelColour, seconds = 30, reason = 'Queue' }))
    eq(Carnival.Rotation.sessionForColour(wheelColour).status, 'pending')
    H.advance(31)
    eq(Carnival.Rotation.sessionForColour(wheelColour).status, 'active', 'delay elapsed')
    for _, a in ipairs({ 'round_extended', 'session_skipped', 'session_delayed' }) do
        eq(count('SELECT COUNT(*) AS n FROM carnival_audit_log WHERE action = ?', { a }), 1, a)
    end
end)

test('the group at the wheel in round 2 can spin', function()
    -- group at the wheel in round 2 has not spun before
    local s = membersOf(colourAt('wheel'))[1]
    at(s, settings().attractions.wheel.location)
    okRes(H.api(s, 'wheel.spin'))
end)

---------------------------------------------------------------------------
section('Scoring ledger')
---------------------------------------------------------------------------
test('manual adjustment requires a reason, is bounded and idempotent; negative totals are clamped', function()
    local pid = Carnival.Participants.idOfSource(PLAYERS[7])
    errRes(H.api(MANAGER, 'scores.adjust', { participantId = pid, delta = 5, reason = '', requestId = 'adj-0000001' }), 'invalid')
    errRes(H.api(MANAGER, 'scores.adjust', { participantId = pid, delta = 100000, reason = 'too much', requestId = 'adj-0000002' }), 'invalid')
    local before = Carnival.Participants.get(pid).total_score
    local tx = okRes(H.api(MANAGER, 'scores.adjust', { participantId = pid, delta = -(before + 50), reason = 'penalty test', requestId = 'adj-0000003' }))
    eq(tx.total, 0, 'clamped at zero')
    local again = okRes(H.api(MANAGER, 'scores.adjust', { participantId = pid, delta = -(before + 50), reason = 'penalty test', requestId = 'adj-0000003' }))
    eq(again.duplicate, true)
    local rev = okRes(H.api(MANAGER, 'scores.reverse', { txId = tx.id, reason = 'Mistake' }))
    eq(rev.total, before, 'reversal restores')
end)

test('ledger verification: cached totals, summaries and chains match', function()
    local r = okRes(H.api(ADMIN, 'scores.verify', {}))
    eq(r.ok, true, 'ledger consistent')
    truthy(r.transactions > 10)
end)

test('players cannot award themselves points (no client scoring endpoint exists)', function()
    for name in pairs(Carnival.Api.endpoints()) do
        local def = Carnival.Api.endpoints()[name]
        if name:match('^scores%.') then truthy(def.perm or def.anyPerm, name .. ' must be permission gated') end
    end
    errRes(H.api(PLAYERS[1], 'scores.adjust', { participantId = 1, delta = 50, reason = 'me', requestId = 'self-000001' }), 'forbidden')
end)

---------------------------------------------------------------------------
section('Restart & recovery')
---------------------------------------------------------------------------
test('resource restart pauses a running event and never replays interrupted work', function()
    -- start a horror run in round 2 so it is interrupted
    local hc = colourAt('horror')
    local runner = membersOf(hc)[1]
    at(runner, settings().attractions.horror.entry)
    okRes(H.api(runner, 'horror.enter'))
    H.advance(settings().attractions.horror.lobbySeconds + 1)
    -- a reward stuck mid-delivery
    local pid = Carnival.Participants.idOfSource(PLAYERS[8])
    local rw = H.call(Carnival.Rewards.create, { participantId = pid, source = 'manual', item = 'carnival_bloodfloss', count = 1, key = 'test:stuck' })
    H.sql("UPDATE carnival_rewards SET status = 'delivering' WHERE id = ?", { rw.id })
    local totalBefore = Carnival.Participants.get(pid).total_score
    -- restart
    H.start({ configure = configure })
    eq(Carnival.Events.activeId(), eventId)
    eq(Carnival.Events.state(), 'paused', 'auto-paused')
    eq(Carnival.Rotation.currentRoundNumber(), 2)
    eq(Carnival.Participants.get(pid).total_score, totalBefore, 'scores recovered')
    eq(H.sql('SELECT status FROM carnival_rewards WHERE id = ?', { rw.id })[1].status, 'unknown', 'reward flagged for reconciliation')
    eq(count("SELECT COUNT(*) AS n FROM carnival_horror_runs WHERE status = 'interrupted'"), 1, 'horror run interrupted, not restarted')
    errRes(H.api(MANAGER, 'rewards.retry', { id = rw.id }), 'invalid')
    okRes(H.api(MANAGER, 'rewards.markDelivered', { id = rw.id, reason = 'Checked inventory' }))
    okRes(H.api(MANAGER, 'events.resume', { reason = 'after restart' }))
    eq(Carnival.Events.state(), 'running')
end)

---------------------------------------------------------------------------
section('Completing the event')
---------------------------------------------------------------------------
test('all six rounds complete via staff advance; final results freeze with prizes', function()
    for _ = 1, 10 do
        local st = Carnival.Events.state()
        if st == 'between_rounds' and Carnival.Rotation.currentRoundNumber() >= 6 then break end
        okRes(H.api(MANAGER, 'rotation.advance', { reason = 'fast forward' }))
    end
    eq(Carnival.Rotation.currentRoundNumber(), 6)
    eq(Carnival.Events.state(), 'between_rounds')
    -- each colour visited each attraction exactly once
    local rows = H.sql('SELECT colour, COUNT(DISTINCT attraction_id) AS a, COUNT(*) AS n FROM carnival_attraction_sessions WHERE event_id = ? GROUP BY colour', { eventId })
    eq(#rows, 6)
    for _, r in ipairs(rows) do eq(r.a, 6, r.colour) eq(r.n, 6, r.colour) end
    okRes(H.api(ADMIN, 'events.transition', { to = 'final_results' }))
    eq(count('SELECT COUNT(*) AS n FROM carnival_event_results WHERE event_id = ?', { eventId }), 1)
    H.advance(1)
    truthy(count("SELECT COUNT(*) AS n FROM carnival_rewards WHERE source = 'prize_tier'") >= 3, 'prizes created')
    -- correction during final results re-versions the results
    local pid = Carnival.Participants.idOfSource(PLAYERS[9])
    okRes(H.api(MANAGER, 'scores.adjust', { participantId = pid, delta = 1, reason = 'late correction', requestId = 'late-000001' }))
    eq(count('SELECT COUNT(*) AS n FROM carnival_event_results WHERE event_id = ?', { eventId }), 2, 'new results version')
    okRes(H.api(ADMIN, 'events.transition', { to = 'completed' }))
    eq(Carnival.Events.activeId(), nil)
end)

test('completed results are frozen: later config changes do not alter them; history preserved', function()
    local res = okRes(H.api(ADMIN, 'results.get', { eventId = eventId }))
    local top = res.results.entries[1]
    -- change tie-break config afterwards
    local doc = okRes(H.api(OWNER, 'config.get', { scope = 'global' })).data
    doc.scoring.tieBreak = { 'registration_order' }
    okRes(H.api(OWNER, 'config.save', { scope = 'global', data = doc, confirm = true }))
    local res2 = okRes(H.api(ADMIN, 'results.get', { eventId = eventId }))
    eq(res2.results.entries[1].participantId, top.participantId)
    -- scoring after completion is refused
    local ok, code = H.call(Carnival.Scoring.award, { participantId = top.participantId, delta = 5, key = 'after' })
    eq(ok, false)
    -- a new event does not touch the old one
    local newId = okRes(H.api(ADMIN, 'events.duplicate', { id = eventId })).id
    truthy(newId > eventId)
    eq(count('SELECT COUNT(*) AS n FROM carnival_participants WHERE event_id = ?', { eventId }), 12, 'old participants kept')
    eq(H.sql('SELECT state FROM carnival_events WHERE id = ?', { eventId })[1].state, 'completed')
    local ex = okRes(H.api(ADMIN, 'results.export', { eventId = eventId }))
    truthy(ex.csv:find('^rank,name'), 'csv export')
    errRes(H.api(MANAGER, 'results.export', { eventId = eventId }), 'forbidden')
end)

---------------------------------------------------------------------------
section('Self-service attractions (no staff involved)')
---------------------------------------------------------------------------
test('second event in self-service mode starts with players registered', function()
    local doc = okRes(H.api(OWNER, 'config.get', { scope = 'global' })).data
    doc.rotation.roundDurationSeconds = 900
    doc.attractions.puppets.lobbySeconds = 5
    doc.attractions.puppets.voteSeconds = 15
    doc.attractions.deception.clueIntervalSeconds = 30
    doc.attractions.deception.durationSeconds = 900
    doc.attractions.horror.lobbySeconds = 5
    okRes(H.api(OWNER, 'config.save', { scope = 'global', data = doc, confirm = true }))
    okRes(H.api(ADMIN, 'events.transition', { to = 'registration_open' }))
    for _, s in ipairs(PLAYERS) do
        at(s, settings().registration.entrance)
        okRes(H.api(s, 'registration.register'), 'register ' .. s)
    end
    okRes(H.api(ADMIN, 'events.transition', { to = 'registration_closed' }))
    okRes(H.api(ADMIN, 'events.transition', { to = 'ready' }))
    okRes(H.api(ADMIN, 'events.transition', { to = 'running' }))
    eq(Carnival.Rotation.currentRoundNumber(), 1)
end)

test('theatre: each player has the stage alone in turn, then the group votes for the best', function()
    local tc = colourAt('puppets')
    local cast = membersOf(tc)
    local c = settings().attractions.puppets
    local loc = c.location
    for _, s in ipairs(cast) do at(s, loc) end
    eq(okRes(H.api(cast[1], 'theatre.play')).cast, 1)
    eq(okRes(H.api(cast[2], 'theatre.play')).cast, 2, 'second player joined the show')
    H.pushes = {}
    H.advance(c.lobbySeconds + 1)
    errRes(H.api(cast[1], 'theatre.play'), 'busy')
    local perf = H.sql("SELECT * FROM carnival_theatre_performances WHERE status = 'running' ORDER BY id DESC LIMIT 1")[1]
    eq(perf.duration_seconds, 2 * (c.turnSeconds + c.turnGapSeconds), 'two turns')
    local function lastCard(src)
        local card
        for _, p in ipairs(H.pushesFor(src, 'theatre')) do if p.action == 'card' then card = p end end
        return card
    end
    local card = lastCard(cast[1])
    eq(card.mode, 'turns')
    eq(card.total, 2)
    truthy(card.upNext and not card.onStage, 'an "up next" pause before the first turn')
    -- first turn
    H.pushes = {}
    H.advance(c.turnGapSeconds + 1)
    local a, b = lastCard(cast[1]), lastCard(cast[2])
    truthy(a.onStage and b.onStage, 'both see who is on stage')
    eq(a.onStage.name, b.onStage.name)
    truthy(a.isYou ~= b.isYou, 'exactly one of them is performing')
    local first = a.isYou and cast[1] or cast[2]
    local second = first == cast[1] and cast[2] or cast[1]
    local firstPrompt = a.onStage.title
    truthy(a.onStage.description and #a.onStage.description > 0, 'the audience sees the prompt')
    eq(a.order[1].now, true)
    -- second turn, with a different prompt
    H.pushes = {}
    H.advance(c.turnSeconds + c.turnGapSeconds + 1)
    local s2 = lastCard(second)
    truthy(s2.isYou, 'second performer is on')
    truthy(s2.onStage.title ~= firstPrompt, 'each performer gets their own prompt')
    eq(s2.order[1].done, true, 'first turn ticked off')
    eq(H.sql('SELECT status FROM carnival_theatre_performances WHERE id = ?', { perf.id })[1].status, 'running', 'no vote until everyone has performed')
    -- vote
    H.pushes = {}
    H.advance(c.turnSeconds + 1)
    local vote
    for _, p in ipairs(H.pushesFor(cast[1], 'theatre')) do if p.action == 'vote' then vote = p end end
    truthy(vote and #vote.candidates == 2, 'the group votes after the last turn')
    local p1, p2 = Carnival.Participants.idOfSource(cast[1]), Carnival.Participants.idOfSource(cast[2])
    errRes(H.api(cast[1], 'theatre.vote', { performanceId = perf.id, participantId = p1 }), 'invalid', 'no voting for yourself')
    okRes(H.api(cast[1], 'theatre.vote', { performanceId = perf.id, participantId = p2 }))
    errRes(H.api(cast[1], 'theatre.vote', { performanceId = perf.id, participantId = p2 }), 'duplicate')
    -- cast[2] abstains: the vote closes on time and p2 wins
    H.advance(c.voteSeconds + 1)
    eq(H.sql('SELECT status FROM carnival_theatre_performances WHERE id = ?', { perf.id })[1].status, 'committed', 'committed by the vote')
    local rows = H.sql('SELECT participant_id, is_winner, points FROM carnival_theatre_performers WHERE performance_id = ?', { perf.id })
    for _, r in ipairs(rows) do
        if r.participant_id == p2 then
            eq(r.is_winner == 1 or r.is_winner == true, true, 'most votes wins')
            eq(r.points, c.winnerPoints)
        else
            eq(r.points, c.performerPoints, 'everyone else who performed')
        end
    end
    errRes(H.api(cast[1], 'theatre.play'), 'done')
end)

test('deception: mystery starts on arrival, clues unlock over time, accusations are marked automatically', function()
    local dc = colourAt('deception')
    local inv = membersOf(dc)
    for _, s in ipairs(inv) do at(s, settings().attractions.deception.location) end
    local pub = okRes(H.api(inv[1], 'deception.public'))
    eq(pub.active, true)
    eq(pub.status, 'questioning', 'started without staff')
    truthy(pub.mystery.performers[1].statements and #pub.mystery.performers[1].statements > 0, 'testimony visible')
    truthy(not H.json.encode(pub):find('isLiar'), 'answer key hidden')
    H.advance(31)
    truthy(#okRes(H.api(inv[1], 'deception.public')).clues >= 1, 'clue unlocked automatically')
    okRes(H.api(inv[1], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'fireeater', 'knife' } }))
    okRes(H.api(inv[2], 'deception.submit', { roundId = pub.roundId, selections = { 'contortionist', 'fortune', 'organ' } }))
    H.advance(6)
    eq(H.sql('SELECT status FROM carnival_deception_rounds WHERE id = ?', { pub.roundId })[1].status, 'committed', 'scored automatically')
    eq(Carnival.Rotation.sessionForColour(dc).status, 'completed', 'group moves on')
    local best = H.sql([[SELECT SUM(delta) AS n FROM carnival_score_transactions WHERE idempotency_key = ?]], { ('deception:%d:%d:auto'):format(pub.roundId, Carnival.Participants.idOfSource(inv[1])) })[1].n
    truthy(tonumber(best) > 0, 'correct accusations scored')
end)

test('horror: a player opens the doors, the group gathers and the run starts by itself', function()
    local hc = colourAt('horror')
    local runners = membersOf(hc)
    local h = settings().attractions.horror
    at(runners[1], h.entry)
    local e = okRes(H.api(runners[1], 'horror.enter'))
    eq(e.startsIn, 5)
    at(runners[2], h.entry)
    truthy(okRes(H.api(runners[2], 'horror.enter')).startsIn <= 5, 'same lobby')
    H.advance(6)
    eq(count("SELECT COUNT(*) AS n FROM carnival_horror_runs WHERE status = 'running'"), 1, 'run started without a controller')
    eq(okRes(H.api(runners[1], 'horror.enter')).running, true)
    local st = okRes(H.api(runners[1], 'horror.state'))
    eq(st.active, true)
end)

---------------------------------------------------------------------------
section('Walk-up mode (no staff: the carnival opens itself)')
---------------------------------------------------------------------------
local walkEvent
local byFirst = {}   -- first attraction on the ticket -> walker source
local function pidOf(src) return Carnival.Participants.idOfSource(src) end
local function nextOf(src) return okRes(H.api(src, 'participant.state')).current end
local function answerAll(src, v)
    local q = v.question
    while q do
        local payload = { visitId = v.visitId, questionId = q.id }
        if q.kind == 'choice' then payload.choice = 1 else payload.text = 'no idea' end
        local a = okRes(H.api(src, 'fortune.answer', payload))
        q = a.question
        if a.finished then return a end
    end
end

test('switching to walk-up opens a carnival automatically and sells tickets without staff', function()
    okRes(H.api(ADMIN, 'events.transition', { to = 'cancelled', reason = 'End of the scheduled tests' }))
    local doc = okRes(H.api(OWNER, 'config.get', { scope = 'global' })).data
    eq(Carnival.Defaults.general.mode, 'scheduled', 'suite override')
    doc.general.mode = 'walkup'
    doc.rotation.walkup.enforceOrder, doc.rotation.walkup.idleSeconds = true, 300
    okRes(H.api(OWNER, 'config.save', { scope = 'global', data = doc, confirm = true }))
    H.advance(6)
    local e = Carnival.Events.active
    truthy(e, 'event created')
    eq(e.mode, 'walkup')
    eq(e.state, 'running', 'opened and running with nobody pressing a button')
    walkEvent = e.id
    eq(count("SELECT COUNT(*) AS n FROM carnival_event_transitions WHERE event_id = ? AND actor = 'system'", { walkEvent }), 5, 'all transitions by the system')
    local pub = okRes(H.api(WALKERS[1], 'event.public'))
    eq(pub.mode, 'walkup')
    eq(pub.registrationOpen, true)
    for _, s in ipairs(WALKERS) do
        at(s, settings().registration.entrance)
        local r = okRes(H.api(s, 'registration.register'), 'register ' .. s)
        truthy(r.colour and r.ticketIssued, 'ticket with a colour')
        byFirst[Carnival.Rotation.sequenceFor(r.colour)[1]] = s
    end
    eq(count('SELECT COUNT(*) AS n FROM carnival_rounds WHERE event_id = ?', { walkEvent }), 0, 'no rounds')
    for first, s in pairs(byFirst) do
        local st = okRes(H.api(s, 'participant.state'))
        eq(st.walkup, true)
        eq(st.current.attraction, first, 'first game is the first on the ticket')
    end
end)

test('a player plays the game on their ticket at its ped; other games wait their turn', function()
    local s = byFirst.wheel
    at(s, settings().attractions.shooting.location)
    local r = H.api(s, 'shooting.start')
    errRes(r, 'wrong_attraction')
    truthy(r.message:find('Wheel'), 'tells the player where to go: ' .. tostring(r.message))
    at(s, settings().attractions.wheel.location)
    for i = 1, settings().attractions.wheel.maxSpins do
        okRes(H.api(s, 'wheel.spin'), 'spin ' .. i)
    end
    H.advance(math.ceil(settings().attractions.wheel.spinAnimationMs / 1000) + 2)
    truthy(Carnival.Rotation.hasCompleted(pidOf(s), 'wheel'), 'wheel completed')
    eq(count("SELECT COUNT(*) AS n FROM carnival_attraction_participation WHERE participant_id = ? AND attraction_id = 'wheel' AND status = 'completed'", { pidOf(s) }), 1)
    eq(nextOf(s).attraction, Carnival.Rotation.sequenceFor(colourOf(s))[2], 'ticket moves on to the next game')
    errRes(H.api(s, 'wheel.spin'), 'already_completed')
    eq(Carnival.Rotation.sessionFor('wheel'), nil, 'the empty visit closed')
end)

test('shooting gallery: walk up, play the aim game, move on', function()
    local s = byFirst.shooting
    at(s, settings().attractions.shooting.location)
    local g = okRes(H.api(s, 'shooting.start'))
    truthy(g.gameId and #g.plan > 0, 'game started')
    H.advance(math.ceil(Carnival.ShootingGameLengthMs() / 1000) + 6)
    truthy(Carnival.Rotation.hasCompleted(pidOf(s), 'shooting'), 'completed')
    eq(nextOf(s).attraction, 'wheel')
end)

test('fortune teller: an automated reading completes the visit', function()
    local s = byFirst.fortune
    at(s, settings().attractions.fortune.location)
    local v = okRes(H.api(s, 'fortune.begin'))
    local a = answerAll(s, v)
    truthy(a and a.finished, 'reading finished')
    H.advance(1)
    truthy(Carnival.Rotation.hasCompleted(pidOf(s), 'fortune'), 'completed')
end)

test('theatre: a lone player performs a solo show and is scored', function()
    local s = byFirst.puppets
    at(s, settings().attractions.puppets.location)
    eq(okRes(H.api(s, 'theatre.play')).cast, 1)
    H.advance(6)
    local perf = H.sql("SELECT * FROM carnival_theatre_performances WHERE status = 'running' ORDER BY id DESC LIMIT 1")[1]
    truthy(perf, 'show started')
    H.advance(perf.duration_seconds + 2)
    eq(H.sql('SELECT status FROM carnival_theatre_performances WHERE id = ?', { perf.id })[1].status, 'committed')
    truthy(Carnival.Rotation.hasCompleted(pidOf(s), 'puppets'), 'completed')
    truthy(Carnival.Scoring.attractionPoints(pidOf(s), 'puppets') >= settings().attractions.puppets.soloPoints, 'solo points')
end)

test('hall of deception: the mystery starts on arrival and an accusation ends the visit', function()
    local s = byFirst.deception
    at(s, settings().attractions.deception.location)
    local pub = okRes(H.api(s, 'deception.public'))
    eq(pub.status, 'questioning')
    local sel = {}
    for i = 1, pub.mystery.liarCount do sel[i] = pub.mystery.performers[i].id end
    okRes(H.api(s, 'deception.submit', { roundId = pub.roundId, selections = sel }))
    H.advance(7)
    eq(H.sql('SELECT status FROM carnival_deception_rounds WHERE id = ?', { pub.roundId })[1].status, 'committed')
    truthy(Carnival.Rotation.hasCompleted(pidOf(s), 'deception'), 'completed')
end)

test('house of horrors: a player opens the doors; nobody can barge into a run in progress', function()
    local s = byFirst.horror
    local h = settings().attractions.horror
    at(s, h.entry)
    eq(okRes(H.api(s, 'horror.enter')).startsIn, h.lobbySeconds)
    H.advance(h.lobbySeconds + 1)
    eq(count("SELECT COUNT(*) AS n FROM carnival_horror_runs WHERE status = 'running'"), 1, 'run started by itself')
    -- with free order, another player could choose horror, but not mid-run
    local doc = okRes(H.api(OWNER, 'config.get', { scope = 'global' })).data
    doc.rotation.walkup.enforceOrder = false
    okRes(H.api(OWNER, 'config.save', { scope = 'global', data = doc, confirm = true }))
    local other = byFirst.wheel
    at(other, h.entry)
    errRes(H.api(other, 'horror.enter'), 'busy')
    H.advance(h.durationSeconds + 2)
    truthy(Carnival.Rotation.hasCompleted(pidOf(s), 'horror'), 'run over: visit completed')
    truthy(not Carnival.Rotation.hasCompleted(pidOf(other), 'horror'), 'the other player was not credited')
    doc.rotation.walkup.enforceOrder = true
    okRes(H.api(OWNER, 'config.save', { scope = 'global', data = doc, confirm = true }))
end)

test('an abandoned visit closes after being idle without counting as played', function()
    local s = byFirst.horror        -- orange: horror, shooting, wheel, fortune, ...
    local p = Carnival.Participants.get(pidOf(s))
    -- play through to the fortune teller, then walk off mid-reading
    for _, a in ipairs({ 'shooting', 'wheel' }) do
        if not Carnival.Rotation.hasCompleted(p.id, a) then H.call(Carnival.Rotation.memberFinished, H.call(Carnival.Rotation.joinWalkup, p, a).id, p.id, 'test') end
    end
    eq(nextOf(s).attraction, 'fortune')
    at(s, settings().attractions.deception.location)
    errRes(H.api(s, 'deception.public'), 'wrong_attraction')
    at(s, settings().attractions.fortune.location)
    local v = okRes(H.api(s, 'fortune.begin'))
    local sess = Carnival.Rotation.sessionFor('fortune')
    H.advance(settings().rotation.walkup.idleSeconds + 2)
    eq(H.sql('SELECT status FROM carnival_attraction_sessions WHERE id = ?', { sess.id })[1].status, 'interrupted')
    truthy(not Carnival.Rotation.hasCompleted(p.id, 'fortune'), 'not credited')
    eq(nextOf(s).attraction, 'fortune', 'still next on the ticket')
    -- coming back starts a fresh reading (the abandoned one does not use up the visit)
    local v2 = okRes(H.api(s, 'fortune.begin'))
    truthy(v2.visitId ~= v.visitId and not v2.resumed, 'new reading')
    answerAll(s, v2)
    H.advance(1)
    truthy(Carnival.Rotation.hasCompleted(p.id, 'fortune'), 'completed on return')
end)

test('a restart keeps the walk-up carnival open (not paused) and keeps progress', function()
    local s = byFirst.deception
    local done = #Carnival.Rotation.completedFor(pidOf(s))
    H.start({ configure = configure })
    eq(Carnival.Events.activeId(), walkEvent)
    eq(Carnival.Events.state(), 'running', 'not auto-paused')
    eq(#Carnival.Rotation.completedFor(pidOf(s)), done, 'progress recovered')
    eq(nextOf(s).attraction, Carnival.Rotation.sequenceFor(colourOf(s))[2])
end)

test('finalising the night freezes results and a fresh carnival opens by itself', function()
    okRes(H.api(ADMIN, 'events.transition', { to = 'final_results' }))
    okRes(H.api(ADMIN, 'events.transition', { to = 'completed' }))
    H.advance(6)
    local e = Carnival.Events.active
    truthy(e and e.id ~= walkEvent, 'new event')
    eq(e.state, 'running')
    eq(H.sql('SELECT state FROM carnival_events WHERE id = ?', { walkEvent })[1].state, 'completed')
    eq(count('SELECT COUNT(*) AS n FROM carnival_event_results WHERE event_id = ?', { walkEvent }), 1, 'results frozen')
    eq(okRes(H.api(WALKERS[1], 'participant.state')).registered, false, 'a new ticket is needed')
end)

test('after "End the night" the books close by themselves and a fresh carnival opens', function()
    local night = Carnival.Events.activeId()
    local wait = settings().rotation.walkup.closeBooksSeconds
    truthy(wait > 0, 'auto close configured by default')
    okRes(H.api(ADMIN, 'events.transition', { to = 'final_results' }))
    H.advance(math.floor(wait / 2))
    eq(Carnival.Events.activeId(), night, 'results stay up for a while')
    eq(Carnival.Events.state(), 'final_results')
    H.advance(math.ceil(wait / 2) + 12)
    eq(H.sql('SELECT state FROM carnival_events WHERE id = ?', { night })[1].state, 'completed', 'books closed')
    eq(H.sql("SELECT actor FROM carnival_event_transitions WHERE event_id = ? AND to_state = 'completed'", { night })[1].actor, 'system')
    local e = Carnival.Events.active
    truthy(e and e.id ~= night and e.state == 'running', 'a fresh carnival is open')
end)

test('the night ends on its own schedule; an empty night just starts over', function()
    local function saveWalkup(patch)
        local doc = okRes(H.api(OWNER, 'config.get', { scope = 'global' })).data
        for k, v in pairs(patch) do doc.rotation.walkup[k] = v end
        okRes(H.api(OWNER, 'config.save', { scope = 'global', data = doc, confirm = true }))
    end
    saveWalkup({ endNight = 'after_hours', endNightAfterHours = 1, endNightGraceMinutes = 15 })
    local wk = settings().rotation.walkup
    -- nobody registered: the night is cancelled quietly and a fresh one opens
    local empty = Carnival.Events.activeId()
    eq(Carnival.Participants.count(), 0, 'fresh night')
    H.advance(3600 + 12)
    eq(H.sql('SELECT state FROM carnival_events WHERE id = ?', { empty })[1].state, 'cancelled', 'empty night rolled over')
    eq(count('SELECT COUNT(*) AS n FROM carnival_event_results WHERE event_id = ?', { empty }), 0, 'no results for an empty night')
    local night = Carnival.Events.activeId()
    truthy(night and night ~= empty and Carnival.Events.state() == 'running', 'a new night is open')
    local endsAt = Carnival.Events.publicState().nightEndsAt
    truthy(endsAt and math.abs(endsAt - (os.time() + 3600)) <= 15, 'players see when the night ends')

    -- somebody played: results are frozen by the system, then the books close
    local s = WALKERS[1]
    at(s, settings().registration.entrance)
    okRes(H.api(s, 'registration.register'))
    H.advance(3600 + 12)
    eq(H.sql('SELECT state FROM carnival_events WHERE id = ?', { night })[1].state, 'final_results', 'night ended on schedule')
    eq(H.sql("SELECT actor FROM carnival_event_transitions WHERE event_id = ? AND to_state = 'final_results'", { night })[1].actor, 'system')
    eq(count('SELECT COUNT(*) AS n FROM carnival_event_results WHERE event_id = ?', { night }), 1, 'results frozen')
    H.advance(wk.closeBooksSeconds + 12)
    truthy(Carnival.Events.activeId() ~= night, 'and a fresh carnival opened')

    -- games in progress may finish first, up to the grace period
    local realBusy, realFor = Carnival.Attractions.sessionBusy, Carnival.Rotation.sessionFor
    Carnival.Attractions.sessionBusy = function() return true end
    Carnival.Rotation.sessionFor = function() return { id = 1 } end
    local due = os.time() + 3600 + 5
    eq(Carnival.Events.walkupNightOver(due), false, 'waits while a game is running')
    eq(Carnival.Events.walkupNightOver(due + 14 * 60), false, 'still within the grace period')
    eq(Carnival.Events.walkupNightOver(due + 15 * 60 + 1), true, 'grace period over')
    Carnival.Attractions.sessionBusy, Carnival.Rotation.sessionFor = realBusy, realFor

    -- daily: ends at the next HH:MM after the night started
    local inTwoHours = os.date('*t', os.time() + 7200)
    saveWalkup({ endNight = 'daily', endNightAt = ('%02d:%02d'):format(inTwoHours.hour, inTwoHours.min) })
    local ends = Carnival.Events.nightEndsAt()
    truthy(ends and math.abs(ends - (os.time() + 7200)) < 60, 'next daily end is today at that time')
    eq(Carnival.Events.walkupNightOver(), false, 'not yet')
    local bad = okRes(H.api(OWNER, 'config.get', { scope = 'global' })).data
    bad.rotation.walkup.endNightAt = '25:99'
    local r = H.api(OWNER, 'config.save', { scope = 'global', confirm = true, data = bad })
    truthy(not r.ok or r.data.saved ~= true, 'a bad end time is refused')
    saveWalkup({ endNight = 'manual' })
    eq(Carnival.Events.nightEndsAt(), nil, 'manual nights have no end time')
    eq(Carnival.Events.walkupNightOver(os.time() + 86400 * 3), false, 'manual nights never end by themselves')
    saveWalkup({ endNight = 'daily', endNightAt = '04:00' })
end)

test('prizes nobody could hand over are retried automatically, from any night', function()
    local s = WALKERS[3]
    at(s, settings().registration.entrance)
    okRes(H.api(s, 'registration.register'))
    local pid = Carnival.Participants.getBySource(s).id
    local cid = H.players[s].citizenid
    -- pockets full when the prize is created
    H.inventoryFull[s] = true
    local r = H.call(Carnival.Rewards.create, { participantId = pid, source = 'manual', item = 'carnival_bloodfloss', count = 2, key = 'test:retry1' })
    eq(H.call(Carnival.Rewards.deliver, r.id, Carnival.Identity.SYSTEM), 'failed')
    -- pretend it was won on an earlier night
    local old = H.sql("SELECT id FROM carnival_events WHERE id <> ? ORDER BY id LIMIT 1", { Carnival.Events.activeId() })[1].id
    H.sql('UPDATE carnival_rewards SET event_id = ? WHERE id = ?', { old, r.id })
    H.advance(settings().rewards.retryMinutes * 60 + 2)
    eq(H.sql('SELECT status FROM carnival_rewards WHERE id = ?', { r.id })[1].status, 'failed', 'still full: still owed')
    H.inventoryFull[s] = nil
    H.advance(settings().rewards.retryMinutes * 60 + 2)
    eq(H.sql('SELECT status FROM carnival_rewards WHERE id = ?', { r.id })[1].status, 'delivered', 'delivered by the automatic retry')
    eq(#H.itemsOf(s, 'carnival_bloodfloss') > 0, true)

    -- logging in also collects anything owed
    local r2 = H.call(Carnival.Rewards.create, { participantId = pid, source = 'manual', item = 'carnival_grave_shake', count = 1, key = 'test:retry2' })
    H.sql("UPDATE carnival_rewards SET event_id = ?, status = 'pending' WHERE id = ?", { old, r2.id })
    H.call(Carnival.Participants.bind, s)
    H.advance(1)
    eq(H.sql('SELECT status FROM carnival_rewards WHERE id = ?', { r2.id })[1].status, 'delivered', 'delivered on login')
    -- a delivery cut off by a restart is never retried automatically
    local r3 = H.call(Carnival.Rewards.create, { participantId = pid, source = 'manual', item = 'carnival_web_cake', count = 1, key = 'test:retry3' })
    H.sql("UPDATE carnival_rewards SET status = 'unknown' WHERE id = ?", { r3.id })
    H.advance(settings().rewards.retryMinutes * 60 + 2)
    eq(H.sql('SELECT status FROM carnival_rewards WHERE id = ?', { r3.id })[1].status, 'unknown', 'left for a human check')
    eq(cid ~= nil, true)
end)

test('the setup checklist lists what still needs a human, and clears as it is done', function()
    errRes(H.api(WALKERS[1], 'setup.checklist'), 'forbidden')
    local list = okRes(H.api(ADMIN, 'setup.checklist'))
    local by = {}
    for _, i in ipairs(list.items) do by[i.id] = i end
    eq(list.done, false)
    eq(by.items.ok, true, 'items registered')
    eq(by.locations.ok, false, 'placeholder positions spotted')
    truthy(by.locations.detail:find('ticket booth'), by.locations.detail)
    eq(by.schedule.ok, true, 'nights end by themselves (daily)')
    -- place everything somewhere real
    local doc = okRes(H.api(OWNER, 'config.get', { scope = 'global' })).data
    local function moved(v) local c = Carnival.U.deepCopy(v); c.x = c.x + 500; return c end
    doc.registration.entrance = moved(doc.registration.entrance)
    doc.shop.location = moved(doc.shop.location)
    for _, id in ipairs(Carnival.C.ATTRACTIONS) do doc.attractions[id].location = moved(doc.attractions[id].location) end
    okRes(H.api(OWNER, 'config.save', { scope = 'global', data = doc, confirm = true }))
    list = okRes(H.api(ADMIN, 'setup.checklist'))
    for _, i in ipairs(list.items) do by[i.id] = i end
    eq(by.locations.ok, true, 'locations done')
    eq(okRes(H.api(ADMIN, 'admin.dashboard')).setup ~= nil, true, 'shown on the Overview')
end)

---------------------------------------------------------------------------
section('World props (prop placer)')
---------------------------------------------------------------------------
local propId
test('only prop managers can place props; input is validated', function()
    errRes(H.api(MANAGER, 'props.create', { model = 'carnivalcoingold', x = 1, y = 2, z = 3 }), 'forbidden')
    errRes(H.api(PLAYERS[1], 'props.list'), 'forbidden')
    errRes(H.api(ADMIN, 'props.create', { model = 'bad model!', x = 1, y = 2, z = 3 }), 'invalid')
    errRes(H.api(ADMIN, 'props.create', { model = 'carnival_gate', x = 1, y = 2 }), 'invalid')
    errRes(H.api(ADMIN, 'props.create', { model = 'carnival_gate', x = 1, y = 2, z = 99999 }), 'invalid')
    errRes(H.api(ADMIN, 'props.create', { model = 'carnival_gate', x = 1, y = 2, z = 3, rz = 9000 }), 'invalid')
end)

test('a placed prop is saved, audited and pushed to every player', function()
    H.pushes = {}
    local p = okRes(H.api(ADMIN, 'props.create', { model = 'carnival_gate', label = 'Main gate', x = -1630.5, y = -1050.25, z = 13.1, rz = 90, collision = true }))
    propId = p.id
    eq(p.label, 'Main gate')
    eq(p.collision, true)
    local pushed = H.pushesFor(PLAYERS[1], 'props')
    eq(#pushed, 1, 'one push')
    eq(pushed[1].action, 'upsert')
    eq(pushed[1].prop.id, propId)
    eq(count('SELECT COUNT(*) AS n FROM carnival_props WHERE id = ? AND deleted_at IS NULL', { propId }), 1)
    eq(count("SELECT COUNT(*) AS n FROM carnival_audit_log WHERE action = 'prop_placed'"), 1)
    -- a player who joins later receives every prop in the bootstrap
    local boot = Carnival.Push.bootstrapData(PLAYERS[2])
    eq(boot.props[#boot.props].id, propId)
end)

test('moving a prop updates everyone; removing one hides it but keeps the record', function()
    H.pushes = {}
    local p = okRes(H.api(ADMIN, 'props.update', { id = propId, x = -1631, y = -1051, z = 13.2, rz = 180, collision = false }))
    eq(p.rz, 180)
    eq(p.collision, false)
    eq(p.label, 'Main gate', 'unchanged fields kept')
    eq(H.pushesFor(PLAYERS[1], 'props')[1].prop.x, -1631)
    local gone = okRes(H.api(ADMIN, 'props.create', { model = 'carnivalcoinsilver', x = 1, y = 2, z = 3 }))
    okRes(H.api(ADMIN, 'props.delete', { id = gone.id }))
    errRes(H.api(ADMIN, 'props.delete', { id = gone.id }), 'not_found')
    errRes(H.api(ADMIN, 'props.update', { id = gone.id, z = 5 }), 'not_found')
    local pushes = H.pushesFor(PLAYERS[1], 'props')
    eq(pushes[#pushes].action, 'remove')
    eq(pushes[#pushes].id, gone.id)
    truthy(H.sql('SELECT deleted_at FROM carnival_props WHERE id = ?', { gone.id })[1].deleted_at, 'record kept')
    eq(#okRes(H.api(ADMIN, 'props.list')).props, 1)
    eq(count("SELECT COUNT(*) AS n FROM carnival_audit_log WHERE action IN ('prop_updated', 'prop_removed')"), 2)
end)

test('props persist across a restart', function()
    H.start({ configure = configure })
    local all = Carnival.Props.all()
    eq(#all, 1)
    eq(all[1].id, propId)
    eq(all[1].rz, 180)
    eq(all[1].collision, false)
    eq(Carnival.Push.bootstrapData(PLAYERS[1]).props[1].model, 'carnival_gate')
end)

---------------------------------------------------------------------------
section('Prize counter')
---------------------------------------------------------------------------
local BUYER
local function balanceOf(src)
    local w = Carnival.Shop.wallet(H.players[src].citizenid)
    return w and w.balance or 0
end
local function shopItem(name)
    for _, it in ipairs(settings().shop.items) do if it.item == name then return it end end
end

test('games pay prize tickets for playing and scoring, capped per night; staff changes and replays pay nothing', function()
    BUYER = WALKERS[1]
    if not Carnival.Participants.getBySource(BUYER) then
        at(BUYER, settings().registration.entrance)
        okRes(H.api(BUYER, 'registration.register'), 'buy a ticket')
    end
    local p = Carnival.Participants.getBySource(BUYER)
    truthy(p and p.status == 'active', 'walk-up participant')
    local cid = H.players[BUYER].citizenid
    local rule = settings().shop.earning.fortune
    local saved = { perPlay = rule.perPlay, per100Points = rule.per100Points, maxPerNight = rule.maxPerNight }
    rule.perPlay, rule.per100Points, rule.maxPerNight = 5, 50, 30
    local before = balanceOf(BUYER)
    H.pushes = {}
    local ok, tx = H.call(Carnival.Scoring.award, { participantId = p.id, delta = 40, key = 'shoptest:1', source = 'test', attractionId = 'fortune' })
    truthy(ok and tx.delta > 0, 'scored')
    local fromScore = math.floor(tx.delta * 50 / 100)
    eq(balanceOf(BUYER), before + fromScore, 'tickets for points scored, at the game\'s rate')
    local pushed = H.pushesFor(BUYER, 'wallet')
    eq(pushed[#pushed].delta, fromScore, 'wallet pushed')
    eq(pushed[#pushed].attraction, 'fortune')
    local mid = balanceOf(BUYER)
    H.call(Carnival.Scoring.award, { participantId = p.id, delta = 40, key = 'shoptest:1', source = 'test', attractionId = 'fortune' })
    eq(balanceOf(BUYER), mid, 'replayed score pays nothing')
    okRes(H.api(ADMIN, 'scores.adjust', { participantId = p.id, delta = 30, reason = 'testing the counter', requestId = 'shopadj000001', attractionId = 'fortune' }))
    eq(balanceOf(BUYER), mid, 'staff adjustments pay nothing')
    H.call(Carnival.Scoring.award, { participantId = p.id, delta = 10, key = 'shoptest:2', source = 'participation_bonus', txType = 'participation', attractionId = 'fortune' })
    eq(balanceOf(BUYER), mid, 'participation bonus points pay nothing (finishing pays perPlay)')

    local eventId = Carnival.Events.activeId()
    H.call(Carnival.Shop.played, p, 'fortune', 9001, eventId)
    eq(balanceOf(BUYER), mid + 5, 'tickets for finishing the game')
    H.call(Carnival.Shop.played, p, 'fortune', 9001, eventId)
    eq(balanceOf(BUYER), mid + 5, 'finishing pays once per visit')
    -- the cap: fortune may pay at most 30 tonight
    H.call(Carnival.Scoring.award, { participantId = p.id, delta = 100, key = 'shoptest:3', source = 'test', attractionId = 'fortune', skipAttractionCap = true })
    eq(tonumber(H.sql([[SELECT SUM(delta) AS n FROM carnival_prize_ledger WHERE citizenid = ? AND event_id = ? AND attraction_id = 'fortune' AND kind = 'earned']], { cid, eventId })[1].n), 30, 'capped per night')
    local capped = balanceOf(BUYER)
    H.call(Carnival.Shop.played, p, 'fortune', 9002, eventId)
    eq(balanceOf(BUYER), capped, 'nothing more once the cap is reached')

    local open = okRes(H.api(BUYER, 'shop.open'))
    local fortune
    for _, r in ipairs(open.earning) do if r.attraction == 'fortune' then fortune = r end end
    eq(fortune.wonTonight, 30, 'shop shows what this game has paid tonight')
    eq(fortune.perPlay, 5)
    truthy(open.items[1].category, 'items carry their shelf')
    rule.perPlay, rule.per100Points, rule.maxPerNight = saved.perPlay, saved.per100Points, saved.maxPerNight
end)

test('buying checks distance, stock rules and balance, and retries never charge twice', function()
    local cid = H.players[BUYER].citizenid
    H.moveTo(BUYER, { x = 0, y = 0, z = 0 })
    okRes(H.api(ADMIN, 'shop.adjust', { citizenid = cid, delta = 100, reason = 'float for testing', requestId = 'shopadj000002' }))
    errRes(H.api(BUYER, 'shop.buy', { item = 'carnival_witch_brew', count = 1, requestId = 'buy000000001' }), 'too_far')
    at(BUYER, settings().shop.location)
    errRes(H.api(BUYER, 'shop.buy', { item = 'carnival_ticket_red', count = 1, requestId = 'buy000000002' }), 'not_for_sale')
    errRes(H.api(BUYER, 'shop.buy', { item = 'carnival_prize_box', count = 1, requestId = 'buy000000003' }), 'insufficient')
    errRes(H.api(BUYER, 'shop.buy', { item = 'carnival_witch_brew', count = 0, requestId = 'buy000000004' }), 'invalid')

    local before = balanceOf(BUYER)
    local price = shopItem('carnival_witch_brew').price
    local r = okRes(H.api(BUYER, 'shop.buy', { item = 'carnival_witch_brew', count = 2, requestId = 'buy000000005' }))
    eq(r.balance, before - price * 2)
    eq(#H.itemsOf(BUYER, 'carnival_witch_brew'), 1, 'item handed over')
    local again = okRes(H.api(BUYER, 'shop.buy', { item = 'carnival_witch_brew', count = 2, requestId = 'buy000000005' }))
    truthy(again.duplicate, 'retry recognised')
    eq(balanceOf(BUYER), before - price * 2, 'charged once')
    eq(#H.itemsOf(BUYER, 'carnival_witch_brew'), 1, 'delivered once')
    eq(count("SELECT COUNT(*) AS n FROM carnival_audit_log WHERE action = 'prize_purchase'"), 1)

    local open = okRes(H.api(BUYER, 'shop.open'))
    eq(open.wallet.balance, balanceOf(BUYER))
    for _, it in ipairs(open.items) do truthy(not C.TICKET_ITEM_COLOUR[it.item], 'no tickets listed') end

    -- daily limit
    local limited = shopItem('carnival_prize_box')
    okRes(H.api(ADMIN, 'shop.adjust', { citizenid = cid, delta = limited.price * (limited.dailyLimit + 1), reason = 'limit test', requestId = 'shopadj000003' }))
    okRes(H.api(BUYER, 'shop.buy', { item = 'carnival_prize_box', count = limited.dailyLimit, requestId = 'buy000000006' }))
    errRes(H.api(BUYER, 'shop.buy', { item = 'carnival_prize_box', count = 1, requestId = 'buy000000007' }), 'limit')
    H.advance(86401)
    okRes(H.api(BUYER, 'shop.buy', { item = 'carnival_prize_box', count = 1, requestId = 'buy000000008' }), 'limit resets after a day')
end)

test('a failed hand-over refunds the points; wallets are admin-only to change', function()
    local cid = H.players[BUYER].citizenid
    okRes(H.api(ADMIN, 'shop.adjust', { citizenid = cid, delta = 200, reason = 'refund test', requestId = 'shopadj000004' }))
    local before = balanceOf(BUYER)
    local saved = H.itemRegistry.carnival_web_cake
    H.itemRegistry.carnival_web_cake = nil
    errRes(H.api(BUYER, 'shop.buy', { item = 'carnival_web_cake', count = 1, requestId = 'buy000000009' }), 'delivery_failed')
    H.itemRegistry.carnival_web_cake = saved
    eq(balanceOf(BUYER), before, 'refunded')
    eq(count("SELECT COUNT(*) AS n FROM carnival_prize_ledger WHERE citizenid = ? AND kind = 'refund'", { cid }), 1)

    errRes(H.api(BUYER, 'shop.adjust', { citizenid = cid, delta = 1000, reason = 'free points', requestId = 'shopadj000005' }), 'forbidden')
    errRes(H.api(MANAGER, 'shop.overview'), 'forbidden')
    errRes(H.api(ADMIN, 'shop.adjust', { citizenid = cid, delta = -1000000, reason = 'too much', requestId = 'shopadj000006' }), 'insufficient')
    errRes(H.api(ADMIN, 'shop.adjust', { citizenid = 'NOBODY', delta = 5, reason = 'no wallet', requestId = 'shopadj000007' }), 'not_found')
    local ov = okRes(H.api(ADMIN, 'shop.overview'))
    truthy(ov.totals.wallets >= 1 and ov.totals.purchasesToday >= 1, 'overview totals')
    eq(ov.popular[1] ~= nil, true, 'best sellers listed')
    eq(#okRes(H.api(ADMIN, 'shop.search', { query = 'WALK' })).wallets >= 1, true, 'search by citizen id')
    eq(count("SELECT COUNT(*) AS n FROM carnival_audit_log WHERE action = 'prize_points_adjusted'"), 3, 'only applied adjustments')

    -- wallet totals always match the ledger
    local w = Carnival.Shop.wallet(cid)
    eq(w.balance, tonumber(H.sql('SELECT SUM(delta) AS n FROM carnival_prize_ledger WHERE citizenid = ?', { cid })[1].n), 'ledger balances')
end)

test('food effects come from consumables.lua and eating is checked by the server', function()
    local src = BUYER
    local p = H.players[src]
    p.metadata.hunger, p.metadata.thirst, p.metadata.stress = 50, 50, 20
    local useFood = H.ownExports.useFood
    truthy(useFood, 'useFood export registered')
    local function give(item) table.insert(H.inventories[src].items, { name = item, count = 1, metadata = {}, slot = #H.inventories[src].items + 1 }) end
    local function use(item)
        H.pushes = {}
        local r = H.call(useFood, 'usingItem', { name = item, label = item }, { id = src, items = H.inventories[src].items }, 1)
        eq(r, false, 'ox_inventory is told not to consume it itself')
        local pushed = H.pushesFor(src, 'consume')
        return pushed[#pushed]
    end

    give('carnival_finger_dog')
    local cfg = Config.Consumables.carnival_finger_dog
    local job = use('carnival_finger_dog')
    truthy(job and job.token, 'eating started')
    eq(job.time, cfg.time)
    eq(job.anim.dict, Config.ConsumableAnims.eat.dict, 'named animation resolved')
    eq(job.prop.model, cfg.prop.model)
    eq(use('carnival_finger_dog'), nil, 'cannot start a second one while eating')
    errRes(H.api(src, 'food.finish', { token = job.token }), 'too_fast', 'finishing instantly is refused')

    job = (function() H.advance(30) return use('carnival_finger_dog') end)()
    truthy(job, 'restarted after the last one expired')
    H.ms = H.ms + cfg.time
    local res = okRes(H.api(src, 'food.finish', { token = job.token }))
    eq(p.metadata.hunger, 50 + cfg.hunger, 'hunger added')
    eq(p.metadata.thirst, 50 + cfg.thirst, 'thirst changed')
    eq(H.stateBags[src].hunger, 50 + cfg.hunger, 'state bag replicated')
    eq(res.armour, cfg.armour)
    eq(#H.itemsOf(src, 'carnival_finger_dog'), 0, 'item removed')
    errRes(H.api(src, 'food.finish', { token = job.token }), 'invalid', 'a token works once')

    -- values are clamped to 0-100 and armour/health are passed to the client
    give('carnival_grave_shake')
    Config.Consumables.carnival_grave_shake = { hunger = 500, thirst = 10, stress = -100, armour = 40, health = 25, time = 1000, anim = 'drink' }
    Carnival.Consumables.load()
    job = use('carnival_grave_shake')
    H.ms = H.ms + 1000
    res = okRes(H.api(src, 'food.finish', { token = job.token }))
    eq(p.metadata.hunger, 100, 'capped at 100')
    eq(p.metadata.stress, 0, 'stress cannot go below 0')
    eq(res.armour, 40)
    eq(res.health, 25)
    eq(job.prop, nil, 'no prop configured')

    -- bad entries are skipped with a warning, unconfigured items are refused
    Config.Consumables.carnival_web_cake = { hunger = 10, anim = 'dance' }
    local _, bad = Carnival.Consumables.load()
    eq(#bad, 1, 'invalid anim reported')
    give('carnival_web_cake')
    eq(use('carnival_web_cake'), nil, 'unconfigured treat does nothing')
    eq(#H.itemsOf(src, 'carnival_web_cake'), 1, 'and is not taken')
end)

test('prize boxes give what the admin set: item count range, percentage chances and quantities', function()
    local src = BUYER
    local box = settings().prizeBox
    local saved = Carnival.U.deepCopy(box)
    box.minItems, box.maxItems = 2, 3
    box.contents = {
        { item = 'carnival_bloodfloss', minCount = 1, maxCount = 2, chance = 70 },
        { item = 'carnival_token_gold', minCount = 1, maxCount = 1, chance = 30 },
    }
    local usePrizeBox = H.ownExports.usePrizeBox
    truthy(usePrizeBox, 'usePrizeBox export registered')
    local function count(item) local n = 0 for _, s in ipairs(H.itemsOf(src, item)) do n = n + s.count end return n end
    local before = count('carnival_bloodfloss') + count('carnival_token_gold')
    H.pushes = {}
    H.ms = H.ms + 5000
    eq(H.call(usePrizeBox, 'usingItem', { name = 'carnival_prize_box' }, { id = src }, 1), true, 'box opens')
    H.call(usePrizeBox, 'usedItem', { name = 'carnival_prize_box' }, { id = src }, 1)
    local pushed = H.pushesFor(src, 'prize')
    local got = pushed[#pushed].contents
    truthy(#got >= 1, 'something inside')
    local total = 0
    for _, g in ipairs(got) do
        truthy(g.item == 'carnival_bloodfloss' or g.item == 'carnival_token_gold', 'only configured prizes')
        total = total + g.count
    end
    truthy(total >= 2 and total <= 6, 'between 2 and 3 prizes, each 1-2: ' .. total)
    eq(count('carnival_bloodfloss') + count('carnival_token_gold') - before, total, 'prizes handed over')
    -- a full inventory keeps the box closed
    H.inventoryFull[src] = true
    H.ms = H.ms + 5000
    eq(H.call(usePrizeBox, 'usingItem', { name = 'carnival_prize_box' }, { id = src }, 1), false, 'no room, box stays shut')
    H.inventoryFull[src] = nil

    -- the odds preview matches the chances (admin only)
    errRes(H.api(src, 'prizebox.simulate', { boxes = 2000 }), 'forbidden')
    box.minItems, box.maxItems = 1, 1
    local sim = okRes(H.api(ADMIN, 'prizebox.simulate', { boxes = 4000 }))
    eq(sim.avgItems > 1 and sim.avgItems < 2, true, 'one prize of 1-2 floss or 1 token: ' .. sim.avgItems)
    for _, r in ipairs(sim.rows) do
        local expected = r.item == 'carnival_bloodfloss' and 70 or 30
        truthy(math.abs(r.inBoxes - expected) < 4, ('%s found in %s%% of boxes, expected about %d%%'):format(r.item, r.inBoxes, expected))
    end
    settings().prizeBox = saved
end)

test('prize box settings: chances must add up to 100%, ranges must make sense, no boxes inside boxes', function()
    local function errorsFor(mutate)
        local tree = Carnival.U.deepCopy(settings())
        mutate(tree.prizeBox)
        local _, errors = Carnival.Validate.config(tree)
        local paths = {}
        for _, e in ipairs(errors or {}) do paths[e.path] = e.message end
        return paths
    end
    truthy(errorsFor(function(b) b.contents[1].chance = b.contents[1].chance + 5 end)['prizeBox.contents'], 'chances over 100%')
    truthy(errorsFor(function(b) b.minItems, b.maxItems = 4, 2 end)['prizeBox.minItems'], 'min above max')
    truthy(errorsFor(function(b) b.contents[1].minCount, b.contents[1].maxCount = 3, 1 end)['prizeBox.contents.1.minCount'], 'quantity range')
    truthy(errorsFor(function(b) b.contents[1].item = 'carnival_prize_box' end)['prizeBox.contents.1.item'], 'box in a box')
    local ok = errorsFor(function() end)
    eq(next(ok), nil, 'factory prize box is valid')
end)

test('saved settings that still use trick/treat tokens are upgraded on load', function()
    local doc = okRes(H.api(OWNER, 'config.get', { scope = 'global' })).data
    -- what an older version saved
    doc.prizeBox = nil
    doc.rewards.prizeBox = {
        { item = 'carnival_treat_token', count = 2, weight = 50 },
        { item = 'carnival_grave_shake', count = 1, weight = 30 },
        { item = 'carnival_eyeball_pop', count = 3, weight = 10 },
    }
    doc.rewards.treatHeal = 25
    doc.attractions.wheel.outcomes[6].item, doc.attractions.wheel.outcomes[6].count = 'carnival_trick_token', 1
    doc.prizes.tiers[4].items = { { item = 'carnival_treat_token', count = 3 } }
    H.sql("UPDATE carnival_config_versions SET data = ? WHERE scope = 'global' AND is_active = 1", { H.json.encode(doc) })
    H.start({ configure = configure })
    local cfg = settings()
    local contents = cfg.prizeBox.contents
    eq(#contents, 2, 'token dropped from the prize box')
    eq(contents[1].item, 'carnival_grave_shake')
    eq(contents[1].chance + contents[2].chance, 100, 'remaining chances rescaled to 100%')
    eq(contents[2].minCount, 3)
    for _, o in ipairs(cfg.attractions.wheel.outcomes) do truthy(not Carnival.C.RETIRED_ITEMS[o.item], 'wheel token removed: ' .. o.id) end
    eq(cfg.prizes.tiers[4].items[1].item, 'carnival_prize_box', 'prize tier gives a box instead')
    eq(cfg.rewards.treatHeal, nil)
end)

test('saved settings with the old shooting points are rebalanced to fit the cap', function()
    local doc = okRes(H.api(OWNER, 'config.get', { scope = 'global' })).data
    local sh = doc.attractions.shooting
    sh.targetPoints, sh.bullseyeBonus, sh.specialPoints, sh.decoyPenalty, sh.maxScore = 5, 3, 15, 10, 250
    H.sql("UPDATE carnival_config_versions SET data = ? WHERE scope = 'global' AND is_active = 1", { H.json.encode(doc) })
    H.start({ configure = configure })
    local c = settings().attractions.shooting
    eq(c.targetPoints, 1) eq(c.bullseyeBonus, 1) eq(c.specialPoints, 4) eq(c.decoyPenalty, 3) eq(c.maxScore, 200)
    -- an admin's own numbers are left alone
    doc = okRes(H.api(OWNER, 'config.get', { scope = 'global' })).data
    doc.attractions.shooting.targetPoints, doc.attractions.shooting.maxScore = 7, 300
    H.sql("UPDATE carnival_config_versions SET data = ? WHERE scope = 'global' AND is_active = 1", { H.json.encode(doc) })
    H.start({ configure = configure })
    eq(settings().attractions.shooting.targetPoints, 7)
    eq(settings().attractions.shooting.maxScore, 300)
end)

test('tickets cannot be put on sale and ambient zones are validated', function()
    local function errorPaths(mutate)
        local tree = Carnival.U.deepCopy(settings())
        mutate(tree)
        local _, errors = Carnival.Validate.config(tree)
        local paths = {}
        for _, e in ipairs(errors or {}) do paths[e.path] = e.message end
        return paths, tree
    end
    local paths, tree = errorPaths(function(t)
        t.shop.items[#t.shop.items + 1] = { item = 'carnival_ticket_red', price = 1, dailyLimit = 0, category = 'prize', enabled = true }
    end)
    truthy(paths['shop.items.' .. #tree.shop.items .. '.item'], 'ticket rejected')
    paths = errorPaths(function(t) t.ambience.zones[1].sound = 'not_a_sound' end)
    truthy(paths['ambience.zones.1.sound'], 'unknown sound rejected')
    local pub = Carnival.Config.publicSettings()
    truthy(pub.shop and pub.shop.currency and pub.shop.items == nil, 'public shop settings omit prices')
    eq(#pub.ambience.zones, #settings().ambience.zones)
end)

---------------------------------------------------------------------------
section('Staff grants & audit')
---------------------------------------------------------------------------
test('in-game grants cannot exceed the bootstrap rank limits', function()
    errRes(H.api(ADMIN, 'staff.grant', { source = OUTSIDER, role = 'administrator', reason = 'promote' }))
    errRes(H.api(ADMIN, 'staff.grant', { source = OUTSIDER, role = 'owner', reason = 'promote' }))
    local g = okRes(H.api(ADMIN, 'staff.grant', { source = OUTSIDER, role = 'observer', reason = 'Watching the night' }))
    truthy(Carnival.Perms.has(OUTSIDER, 'panel.admin'), 'grant applied')
    okRes(H.api(ADMIN, 'staff.revoke', { id = g.id, reason = 'Done' }))
    truthy(not Carnival.Perms.has(OUTSIDER, 'panel.admin'), 'revoked immediately')
end)

test('audit log is append-only from the application and covers key actions', function()
    for _, action in ipairs({ 'event_state_changed', 'ticket_issued', 'ticket_replaced', 'score_adjusted', 'score_corrected',
        'theatre_results_committed', 'deception_results_committed', 'horror_run_started', 'staff_role_granted', 'results_exported' }) do
        truthy(count('SELECT COUNT(*) AS n FROM carnival_audit_log WHERE action = ?', { action }) >= 1, 'audited: ' .. action)
    end
    -- no UPDATE/DELETE statements against the audit table anywhere in the server code
    for _, f in ipairs(H.manifest().server) do
        if not f:match('^@') then
            local src = io.open(f):read('a')
            truthy(not src:find('UPDATE carnival_audit_log') and not src:find('DELETE FROM carnival_audit_log'), f)
        end
    end
end)

test('database failures are reported, not swallowed', function()
    H.dbFailNext = 1
    local r = H.call(Carnival.Db.query, 'SELECT 1')
    eq(r, nil)
    eq(Carnival.Db.healthy, false)
    H.call(Carnival.Db.ping)
    eq(Carnival.Db.healthy, true)
end)

test('monitoring records are persisted and queryable with filters', function()
    H.call(Carnival.Monitor.flush)
    local r = okRes(H.api(ADMIN, 'monitoring.query', { category = 'permission', page = 1 }))
    truthy(r.total >= 1, 'permission failures recorded')
    errRes(H.api(MANAGER, 'monitoring.query', {}), 'forbidden')
    local a = okRes(H.api(ADMIN, 'audit.query', { action = 'config' }))
    truthy(a.total >= 1)
end)

---------------------------------------------------------------------------
local failed = 0
for _, r in ipairs(results) do if not r.ok then failed = failed + 1 end end
H.print(('\n%d tests, %d passed, %d failed'):format(#results, #results - failed, failed))
os.exit(failed == 0 and 0 or 1)
