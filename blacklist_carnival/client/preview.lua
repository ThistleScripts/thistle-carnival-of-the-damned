-- Staff/admin preview of the player game screens.
--
-- Opens each game screen with clearly labelled demo data so the screens (and
-- owner-supplied backgrounds) can be checked without running an event. Preview
-- screens never call the server: spins, answers and accusations are resolved
-- locally in the NUI and no points, items or records are created.

local Preview = {}
Carnival.Preview = Preview

local function allowed()
    return Carnival.has('panel.staff') or Carnival.has('panel.admin')
end

local function now() return Carnival.serverNow() end

local SCREENS = {}

SCREENS.wheel = function(s)
    local a = s.attractions.wheel
    Carnival.openView('wheel', {
        preview = true, outcomes = a.outcomes, spinsUsed = 0, maxSpins = a.maxSpins,
        cooldownRemaining = 0, animationMs = a.spinAnimationMs, label = a.label,
    })
end

SCREENS.fortune = function(s)
    local a = s.attractions.fortune
    Carnival.openView('fortune', {
        preview = true, visitId = 0, greeting = a.greeting, farewell = a.farewell,
        fortune = 'A stranger in a velvet mask will offer you a gift. Refuse it.',
        question = {
            id = 'preview', kind = 'choice', prompt = 'PREVIEW: How many coloured tickets travel the carnival?',
            choices = { 'Four', 'Five', 'Six', 'Seven' }, index = 1, total = 1, timeout = 90, previewCorrect = 3,
        },
    })
end

SCREENS.deception = function()
    Carnival.openView('deception', {
        preview = true, active = true, roundId = 0, status = 'questioning', maxSubmissions = 2, submissionsUsed = 0,
        endsAt = now() + 900, serverTime = now(),
        clues = { { id = 'p1', text = 'PREVIEW clue: muddy boot prints lead to the caravans.', releasedAt = now() } },
        mystery = {
            title = 'PREVIEW: The Vanishing Ringmaster',
            description = 'Six performers were backstage. Three of them are lying. Pick the liars.',
            rules = 'Question each performer in character.', liarCount = 3,
            performers = {
                { id = 'a', name = 'Bruno the Strongman', profile = 'Lifts anvils, cries at sad songs.' },
                { id = 'b', name = 'Madame Twist', profile = 'Contortionist. Speaks only in whispers.' },
                { id = 'c', name = 'Lady Ash', profile = 'The fire-eater. Never seen without her veil.' },
                { id = 'd', name = 'Old Zelda', profile = 'Fortune teller.' },
                { id = 'e', name = 'The Great Valentino', profile = 'Knife thrower. Never misses.' },
                { id = 'f', name = 'Silent Pete', profile = 'Plays the calliope.' },
            },
        },
    })
end

SCREENS.puppets = function()
    Carnival.openView('theatre', {
        action = 'card', status = 'running', performer = true, role = 'Lion Tamer', endsAt = now() + 120, serverTime = now(),
        scenario = { title = 'PREVIEW: The Reluctant Lion Tamer', description = 'Your partner is the lion. The lion has unionised and is presenting its demands.', difficulty = 'medium' },
        performers = { { name = 'You', role = 'Lion Tamer' }, { name = 'Another player', role = 'Unionised Lion' } },
    }, { focus = false })
    SetTimeout(20000, function() Carnival.closeView('theatre') end)
end

SCREENS.horror = function(s)
    Carnival.nui('horror', { active = true, status = 'running', endsAt = now() + 60, serverTime = now(), collected = 3, points = 25, runnerStatus = 'inside' })
    SetTimeout(4000, function() Carnival.nui('horror', { warning = 30 }) end)
    SetTimeout(20000, function() Carnival.nui('horror', { active = false }) end)
end

SCREENS.shooting = function()
    Carnival.nui('shooting', { active = true, endsAt = now() + 30, serverTime = now(), hits = 4, shots = 6, total = 35, special = true })
    SetTimeout(3000, function() Carnival.nui('shooting', { active = true, hit = { points = 15, bullseye = true }, total = 50, hits = 5 }) end)
    SetTimeout(20000, function() Carnival.nui('shooting', { active = false }) end)
end

SCREENS.ticket = function()
    local p = Carnival.Client.participant
    Carnival.openView('ticket', { action = 'issued', colour = (p and p.colour) or 'red', serial = 'CTD-PREVW-00000', holder = 'Preview Holder', eventName = 'Carnival of the Damned' })
end

SCREENS.leaderboard = function() Carnival.openLeaderboard() end
SCREENS.hub = function() Carnival.openView('player', {}) end

function Preview.open(screen)
    if not allowed() then
        return lib.notify({ title = 'Carnival', description = 'Previews are for staff.', type = 'error' })
    end
    local s = Carnival.Client.settings
    local fn = SCREENS[screen]
    if not s or not fn then
        return lib.notify({ title = 'Carnival preview', description = 'Screens: wheel, fortune, deception, puppets, horror, shooting, ticket, leaderboard, hub', type = 'inform' })
    end
    fn(s)
    lib.notify({ title = 'Preview mode', description = 'Demo data only - nothing is sent to the server and no points are awarded.', type = 'inform' })
end

RegisterCommand('carnivalpreview', function(_, args)
    Preview.open(args[1])
end, false)

TriggerEvent('chat:addSuggestion', '/carnivalpreview', 'Preview a carnival game screen (staff)', {
    { name = 'screen', help = 'wheel | fortune | deception | puppets | horror | shooting | ticket | leaderboard | hub' },
})
