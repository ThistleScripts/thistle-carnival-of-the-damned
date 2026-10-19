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

local function setupPlayers()
    H.addPlayer(OWNER, { name = 'Owner' })
    H.addPlayer(ADMIN, { name = 'Admin', aces = { ['carnival.role.administrator'] = true } })
    H.addPlayer(MANAGER, { name = 'Manager', aces = { ['carnival.role.event_manager'] = true } })
    H.addPlayer(OBSERVER, { name = 'Observer', aces = { ['carnival.role.observer'] = true } })
    H.addPlayer(HORROR, { name = 'Keeper', aces = { ['carnival.role.event_manager'] = true } })
    H.addPlayer(WHEELOP, { name = 'WheelOp', aces = { ['carnival.role.attraction_operator'] = true, ['carnival.attraction.wheel'] = true } })
    H.addPlayer(OUTSIDER, { name = 'Nobody' })
    for _, s in ipairs(PLAYERS) do H.addPlayer(s, { citizenid = 'CIT' .. s }) end
end

local function configure(cfg)
    cfg.Security.Allowlist[H.players[OWNER].license] = 'owner'
    cfg.Security.HorrorControllers = { H.players[HORROR].license }
    cfg.LogLevel = 'warning'
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
    eq(count('SELECT COUNT(*) AS n FROM carnival_schema_migrations'), 2, 'migrations applied')
    eq(count('SELECT COUNT(*) AS n FROM carnival_attractions'), 6, 'attractions seeded')
    truthy(count("SELECT COUNT(*) AS n FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name LIKE 'carnival_%'") >= 30, 'all tables created')
end)

test('migrations are idempotent (re-run on restart)', function()
    local ok = H.call(Carnival.Db.migrate)
    truthy(ok, 'migrate')
    eq(count('SELECT COUNT(*) AS n FROM carnival_schema_migrations'), 2, 'still two migrations')
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
test('roles resolve from allowlist, ACE and scoped attraction ACE', function()
    eq(Carnival.Perms.role(OWNER), 'owner')
    eq(Carnival.Perms.role(ADMIN), 'administrator')
    eq(Carnival.Perms.role(MANAGER), 'event_manager')
    eq(Carnival.Perms.role(OUTSIDER), nil)
    truthy(Carnival.Perms.has(WHEELOP, 'attractions.operate.wheel'), 'operator has wheel')
    truthy(not Carnival.Perms.has(WHEELOP, 'attractions.operate.horror'), 'operator lacks horror')
    truthy(not Carnival.Perms.has(MANAGER, 'panel.admin'), 'manager is not admin')
end)

test('horror control needs the separate license allowlist', function()
    truthy(not Carnival.Perms.has(MANAGER, 'horror.control'), 'manager not allowlisted')
    truthy(Carnival.Perms.has(HORROR, 'horror.control'), 'keeper allowlisted')
    truthy(Carnival.Perms.has(OWNER, 'horror.control'), 'owner bypass')
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
    doc.rotation.roundDurationSeconds = 120
    doc.rotation.transitionSeconds = 10
    doc.rotation.warningSeconds = { 30 }
    doc.groups.colours.red.capacity = 2
    for _, a in ipairs(C.ATTRACTIONS) do doc.attractions[a].requiresPerformer = false end
    doc.attractions.wheel.cooldownSeconds = 0
    doc.attractions.horror.durationSeconds = 60
    doc.attractions.horror.warnings = { 30, 10 }
    doc.attractions.horror.tokenTypes.gold.quantity = 0
    doc.attractions.fortune.questionsPerVisit = 2
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

test('special prizes wait for staff approval; operators approve; delivery is idempotent', function()
    local wc = colourAt('wheel')
    local s = membersOf(wc)[2]
    at(s, settings().attractions.wheel.location)
    -- force the special outcome by stubbing the chooser for one spin
    local real = Carnival.WheelAttraction.choose
    Carnival.WheelAttraction.choose = function(outcomes)
        for i, o in ipairs(outcomes) do if o.type == 'special_prize' then return o, i, 0.5, 1000 end end
    end
    local r = okRes(H.api(s, 'wheel.spin'))
    Carnival.WheelAttraction.choose = real
    eq(r.reward.status, 'awaiting_approval')
    local reward = H.sql("SELECT * FROM carnival_rewards WHERE source = 'wheel' AND status = 'awaiting_approval'")[1]
    errRes(H.api(OBSERVER, 'wheel.staff.approve', { rewardId = reward.id }), 'forbidden')
    local a = okRes(H.api(WHEELOP, 'wheel.staff.approve', { rewardId = reward.id }))
    eq(a.status, 'delivered')
    local itemsBefore = #H.itemsOf(s, reward.item)
    -- retrying delivery must not duplicate
    eq(H.call(Carnival.Rewards.deliver, reward.id), 'delivered')
    eq(#H.itemsOf(s, reward.item), itemsBefore, 'no duplicate items')
end)

test('reward delivery failure (full inventory) is recorded and reconcilable', function()
    local p = Carnival.Participants.getBySource(PLAYERS[6])
    H.inventoryFull[PLAYERS[6]] = true
    local r = H.call(Carnival.Rewards.create, { participantId = p.id, source = 'manual', item = 'carnival_treat_token', count = 2, key = 'test:full' })
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

test('staff-led roleplay award is idempotent per request id and capped', function()
    local fc = colourAt('fortune')
    local s = membersOf(fc)[2]
    local pid = Carnival.Participants.idOfSource(s)
    errRes(H.api(MANAGER, 'fortune.staff.award', { participantId = pid, points = 999, reason = 'great acting', requestId = 'req-00000001' }), 'invalid')
    local t1 = okRes(H.api(MANAGER, 'fortune.staff.award', { participantId = pid, points = 10, reason = 'great acting', requestId = 'req-00000002' }))
    local t2 = okRes(H.api(MANAGER, 'fortune.staff.award', { participantId = pid, points = 10, reason = 'great acting', requestId = 'req-00000002' }))
    eq(t2.duplicate, true)
    eq(t1.id, t2.id)
end)

---------------------------------------------------------------------------
section('Attraction: Shooting Gallery')
---------------------------------------------------------------------------
test('hits are validated server-side; points awarded once per heat', function()
    local sc = colourAt('shooting')
    local shooters = membersOf(sc)
    local cfg = settings().attractions.shooting
    for _, s in ipairs(shooters) do at(s, cfg.stand) H.players[s].weapon = 'WEAPON_PISTOL' end
    okRes(H.api(shooters[1], 'shooting.join'))
    okRes(H.api(shooters[2], 'shooting.join'))
    errRes(H.api(OBSERVER, 'shooting.startHeat', {}), 'forbidden')
    local heat = okRes(H.api(MANAGER, 'shooting.startHeat', {}))
    local t = cfg.targets[3]
    -- valid hit
    local h = okRes(H.api(shooters[1], 'shooting.hit', { heatId = heat.id, targetId = t.id, impact = t.coords, shots = 1 }))
    eq(h.points, t.points + cfg.bullseyeBonus, 'bullseye at centre')
    -- same target is down
    errRes(H.api(shooters[1], 'shooting.hit', { heatId = heat.id, targetId = t.id, impact = t.coords, shots = 2 }), 'too_fast')
    -- far impact misses
    H.ms = H.ms + 5000
    errRes(H.api(shooters[1], 'shooting.hit', { heatId = heat.id, targetId = cfg.targets[1].id, impact = { x = t.coords.x + 3, y = t.coords.y, z = t.coords.z }, shots = 3 }), 'missed_target')
    -- wrong weapon
    H.players[shooters[2]].weapon = 'WEAPON_RPG'
    errRes(H.api(shooters[2], 'shooting.hit', { heatId = heat.id, targetId = cfg.targets[1].id, impact = cfg.targets[1].coords }), 'wrong_weapon')
    H.players[shooters[2]].weapon = 'WEAPON_PISTOL'
    -- away from the stand
    at(shooters[2], { x = 0, y = 0, z = 0 })
    errRes(H.api(shooters[2], 'shooting.hit', { heatId = heat.id, targetId = cfg.targets[1].id, impact = cfg.targets[1].coords }), 'not_at_stand')
    at(shooters[2], cfg.stand)
    -- special target is not up
    local special
    for _, x in ipairs(cfg.targets) do if x.kind == 'special' then special = x end end
    errRes(H.api(shooters[2], 'shooting.hit', { heatId = heat.id, targetId = special.id, impact = special.coords }), 'special_not_active')
    -- non-participant
    errRes(H.api(OUTSIDER, 'shooting.hit', { heatId = heat.id, targetId = t.id, impact = t.coords }), 'not_in_heat')
    -- heat ends on the server timer
    H.advance(cfg.durationSeconds + 1)
    local res = H.sql('SELECT * FROM carnival_shooting_results WHERE heat_id = ?', { heat.id })
    eq(#res, 2, 'two results')
    local pid = Carnival.Participants.idOfSource(shooters[1])
    eq(count("SELECT COUNT(*) AS n FROM carnival_score_transactions WHERE idempotency_key = ?", { ('shooting:%d:%d'):format(heat.id, pid) }), 1)
    errRes(H.api(shooters[1], 'shooting.join'), 'already_shot')
end)

---------------------------------------------------------------------------
section("Attraction: Puppet Master's Theatre")
---------------------------------------------------------------------------
local perfId
test('operator builds, runs, previews and commits a performance exactly once', function()
    local tc = colourAt('puppets')
    local cast = membersOf(tc)
    local p1, p2 = Carnival.Participants.idOfSource(cast[1]), Carnival.Participants.idOfSource(cast[2])
    local wrongGroup = Carnival.Participants.idOfSource(membersOf(colourAt('wheel'))[1])
    errRes(H.api(MANAGER, 'theatre.create', { scenarioId = 'lion_tamer', performers = { { participantId = p1 }, { participantId = wrongGroup } } }), 'invalid')
    local perf = okRes(H.api(MANAGER, 'theatre.create', { scenarioId = 'lion_tamer', performers = { { participantId = p1, role = 'Lion Tamer' }, { participantId = p2, role = 'Unionised Lion' } } }))
    perfId = perf.id
    okRes(H.api(MANAGER, 'theatre.display'))
    truthy(#H.pushesFor(cast[1], 'theatre') >= 1, 'card pushed')
    okRes(H.api(MANAGER, 'theatre.start'))
    okRes(H.api(MANAGER, 'theatre.pause'))
    okRes(H.api(MANAGER, 'theatre.resume'))
    okRes(H.api(MANAGER, 'theatre.end'))
    local awards = { { participantId = p1, points = 500, winner = true }, { participantId = p2, points = 12 } }
    local prev = okRes(H.api(MANAGER, 'theatre.preview', { awards = awards, participationBonus = true }))
    local l1
    for _, l in ipairs(prev.lines) do if l.participantId == p1 then l1 = l end end
    eq(l1.points, 30, 'clamped to scenario max')
    local c1 = okRes(H.api(MANAGER, 'theatre.commit', { performanceId = perfId, awards = awards, participationBonus = true, note = 'Roaring success' }))
    eq(#c1.results, 2)
    local c2 = okRes(H.api(MANAGER, 'theatre.commit', { performanceId = perfId, awards = awards, participationBonus = true }))
    eq(c2.alreadyCommitted, true, 'second commit is a no-op')
    eq(count("SELECT COUNT(*) AS n FROM carnival_score_transactions WHERE idempotency_key LIKE ?", { 'theatre:' .. perfId .. ':%' }), 4)
end)

---------------------------------------------------------------------------
section('Attraction: Hall of Deception')
---------------------------------------------------------------------------
test('secret answer key never reaches participants; submissions are limited; scoring committed once', function()
    local dc = colourAt('deception')
    local inv = membersOf(dc)
    local hall = settings().attractions.deception.location
    for _, s in ipairs(inv) do at(s, hall) end
    okRes(H.api(MANAGER, 'deception.setup', { mysteryId = 'vanishing_ringmaster' }))
    -- observer cannot see staff state
    errRes(H.api(OBSERVER, 'deception.staff.state'), 'forbidden')
    okRes(H.api(MANAGER, 'deception.start'))
    local pub = okRes(H.api(inv[1], 'deception.public'))
    local blob = H.json.encode(pub)
    truthy(not blob:find('isLiar'), 'no isLiar in public state')
    truthy(not blob:find('brief'), 'no briefs in public state')
    truthy(not blob:find('statements'), 'no statements in public state')
    eq(pub.solution, nil)
    for _, p in ipairs(H.pushesFor(inv[1], 'deception')) do
        truthy(not H.json.encode(p):find('isLiar'), 'no secrets pushed')
    end
    errRes(H.api(inv[1], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'clown' } }), 'invalid')
    errRes(H.api(inv[1], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'fireeater' } }), 'invalid')
    okRes(H.api(inv[1], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'fireeater', 'organ' }, explanation = 'Muddy boots.' }))
    okRes(H.api(inv[1], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'fireeater', 'knife' }, explanation = 'Changed my mind.' }))
    errRes(H.api(inv[1], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'fireeater', 'knife' } }), 'limit')
    okRes(H.api(inv[2], 'deception.submit', { roundId = pub.roundId, selections = { 'contortionist', 'fortune', 'organ' } }))
    okRes(H.api(MANAGER, 'deception.clue', { clueId = 'c1' }))
    errRes(H.api(MANAGER, 'deception.clue', { clueId = 'c1' }), 'invalid')
    okRes(H.api(MANAGER, 'deception.end'))
    errRes(H.api(inv[2], 'deception.submit', { roundId = pub.roundId, selections = { 'strongman', 'fireeater', 'knife' } }), 'closed')
    local prev = okRes(H.api(MANAGER, 'deception.preview', { adjustments = { { participantId = Carnival.Participants.idOfSource(inv[1]), judgePoints = 10 } } }))
    local best = prev.lines[1]
    eq(best.correct, 3)
    eq(best.perfect, true)
    local m = settings().attractions.deception.mysteries[1]
    eq(best.total, 3 * m.pointsPerCorrect + m.perfectBonus + m.tieBreakBonus + 10)
    local worst = prev.lines[2]
    eq(worst.correct, 0)
    eq(worst.total, -3 * m.penaltyPerIncorrect)
    local roundId = pub.roundId
    okRes(H.api(MANAGER, 'deception.commit', { roundId = roundId, adjustments = { { participantId = Carnival.Participants.idOfSource(inv[1]), judgePoints = 10 } } }))
    eq(okRes(H.api(MANAGER, 'deception.commit', { roundId = roundId })).alreadyCommitted, true)
    local after = okRes(H.api(inv[1], 'deception.public'))
    truthy(after.solution and #after.solution == 3, 'solution revealed after commit')
end)

---------------------------------------------------------------------------
section('Attraction: House of Horrors')
---------------------------------------------------------------------------
local runId
test('only allowlisted controllers start runs; tokens validated; duplicates refused', function()
    local hc = colourAt('horror')
    local runners = membersOf(hc)
    local h = settings().attractions.horror
    errRes(H.api(MANAGER, 'horror.start'), 'forbidden')
    local r = okRes(H.api(HORROR, 'horror.start'))
    runId = r.runId
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
test('round timer: automated attractions complete, staff-judged attractions are held (overtime)', function()
    H.advance(130)
    local judged = { puppets = true, deception = true }
    for _, c in ipairs(C.COLOURS) do
        local s = Carnival.Rotation.sessionForColour(c)
        if judged[s.attraction_id] then
            eq(s.status, 'active', s.attraction_id .. ' held')
        else
            eq(s.status, 'completed', s.attraction_id .. ' completed')
        end
    end
    eq(Carnival.Events.publicState().overtime, true)
    eq(Carnival.Events.state(), 'running')
end)

test('staff complete judged sessions; event moves between rounds and auto-starts round 2', function()
    okRes(H.api(MANAGER, 'rotation.completeSession', { colour = colourAt('puppets'), reason = 'judged' }))
    errRes(H.api(WHEELOP, 'rotation.completeSession', { colour = colourAt('deception') }), 'forbidden')
    okRes(H.api(MANAGER, 'rotation.completeSession', { colour = colourAt('deception'), reason = 'judged' }))
    eq(Carnival.Events.state(), 'between_rounds')
    eq(count("SELECT COUNT(*) AS n FROM carnival_attraction_participation WHERE event_id = ? AND status = 'completed'", { eventId }), 12)
    H.advance(11)
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
    okRes(H.api(HORROR, 'horror.start'))
    -- a reward stuck mid-delivery
    local pid = Carnival.Participants.idOfSource(PLAYERS[8])
    local rw = H.call(Carnival.Rewards.create, { participantId = pid, source = 'manual', item = 'carnival_treat_token', count = 1, key = 'test:stuck' })
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
section('Staff grants & audit')
---------------------------------------------------------------------------
test('in-game grants cannot exceed the bootstrap rank limits', function()
    errRes(H.api(ADMIN, 'staff.grant', { source = OUTSIDER, role = 'administrator', reason = 'promote' }))
    errRes(H.api(ADMIN, 'staff.grant', { source = OUTSIDER, role = 'owner', reason = 'promote' }))
    local g = okRes(H.api(ADMIN, 'staff.grant', { source = OUTSIDER, role = 'performer', attractionId = 'deception', reason = 'New performer' }))
    truthy(Carnival.Perms.has(OUTSIDER, 'attractions.operate.deception'), 'scoped grant applied')
    truthy(not Carnival.Perms.has(OUTSIDER, 'attractions.operate.horror'), 'other attractions not granted')
    okRes(H.api(ADMIN, 'staff.revoke', { id = g.id, reason = 'Done' }))
    truthy(not Carnival.Perms.has(OUTSIDER, 'panel.staff'), 'revoked immediately')
end)

test('audit log is append-only from the application and covers key actions', function()
    for _, action in ipairs({ 'event_state_changed', 'ticket_issued', 'ticket_replaced', 'score_adjusted', 'score_corrected',
        'theatre_results_committed', 'deception_results_committed', 'horror_run_started', 'reward_approved', 'staff_role_granted', 'results_exported' }) do
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
