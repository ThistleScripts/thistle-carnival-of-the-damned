-- Configuration schema.
--
-- Drives three things:
--   * server-side validation of every configuration save (shared/validation.lua)
--   * the generic form editor in the admin NUI (sent as JSON)
--   * redaction of secret fields for users without the matching permission
--
-- Node types: group, map, list, bool, int, number, string, text, select,
-- multiselect, vec3, vec4, color, sound, item, model, matrix.
-- Flags:
--   secret     -- only visible to users holding `secretPerm`
--   restart    -- change only takes effect after an attraction reset / new event
--   locked     -- cannot be changed while the event is running/paused/between rounds
--   help       -- tooltip text in the editor

Carnival = Carnival or {}
local C = Carnival.C

local S = {}
Carnival.Schema = S

local function f(key, node)
    node.key = key
    return node
end

local attractionOptions = {}
for _, a in ipairs(C.ATTRACTIONS) do attractionOptions[#attractionOptions + 1] = a end

local function baseAttraction(extra)
    local fields = {
        f('enabled', { type = 'bool', label = 'Enabled' }),
        f('label', { type = 'string', label = 'Display name', max = 64 }),
        f('location', { type = 'vec4', label = 'Location (NPC / interaction point)', restart = true }),
        f('npcModel', { type = 'model', label = 'NPC model (blank for none)', max = 64, allowEmpty = true, restart = true }),
        f('interactDistance', { type = 'number', label = 'Interaction distance (m)', min = 0.5, max = 15, step = 0.1 }),
        f('validationDistance', { type = 'number', label = 'Server distance tolerance (m)', min = 1, max = 100, step = 0.5,
            help = 'Maximum distance the server accepts for requests at this attraction.' }),
        f('maxPlayers', { type = 'int', label = 'Player limit', min = 1, max = 64 }),
        f('maxScore', { type = 'int', label = 'Maximum points per participant', min = 0, max = 100000,
            help = '0 = no attraction cap' }),
        f('blip', { type = 'group', label = 'Map blip', fields = {
            f('enabled', { type = 'bool', label = 'Show blip' }),
            f('sprite', { type = 'int', label = 'Sprite', min = 1, max = 900 }),
            f('colour', { type = 'int', label = 'Colour', min = 0, max = 85 }),
        } }),
    }
    for _, fld in ipairs(extra) do fields[#fields + 1] = fld end
    return fields
end

local vec3Item = { type = 'vec3' }

S.root = { type = 'group', fields = {
    f('general', { type = 'group', label = 'General', fields = {
        f('mode', { type = 'select', label = 'Carnival mode', options = { 'walkup', 'scheduled' },
            help = 'walkup: the carnival opens itself and stays open; players buy a ticket and play their games at their own pace, no staff needed. scheduled: staff create the event and run timed rounds.' }),
        f('eventName', { type = 'string', label = 'Default event name', max = 96 }),
        f('description', { type = 'text', label = 'Default description', max = 1000 }),
        f('blipLabel', { type = 'string', label = 'Carnival blip label', max = 64 }),
        f('hudEnabled', { type = 'bool', label = 'Show participant HUD' }),
    } }),

    f('registration', { type = 'group', label = 'Registration', fields = {
        f('entrance', { type = 'vec4', label = 'Entrance booth location', restart = true }),
        f('npcModel', { type = 'model', label = 'Ticket booth NPC model', max = 64, allowEmpty = true, restart = true }),
        f('interactDistance', { type = 'number', label = 'Interaction distance (m)', min = 0.5, max = 15, step = 0.1 }),
        f('validationDistance', { type = 'number', label = 'Server distance tolerance (m)', min = 1, max = 100, step = 0.5 }),
        f('maxParticipants', { type = 'int', label = 'Event participant limit', min = 1, max = 2048 }),
        f('virtualTickets', { type = 'bool', label = 'Virtual tickets (no inventory item)', locked = true }),
        f('requireTicketForAttractions', { type = 'bool', label = 'Require valid physical ticket at attractions' }),
        f('lateRegistration', { type = 'group', label = 'Late registration', fields = {
            f('enabled', { type = 'bool', label = 'Allow registration after the event starts' }),
            f('maxRound', { type = 'int', label = 'Latest round that accepts late registration', min = 1, max = 6 }),
        } }),
        f('allowSelfReplacement', { type = 'bool', label = 'Players may request replacement tickets at the booth' }),
        f('maxReplacements', { type = 'int', label = 'Maximum self-service replacements', min = 0, max = 20 }),
        f('replacementCooldownSeconds', { type = 'int', label = 'Replacement cooldown (s)', min = 0, max = 3600 }),
        f('blip', { type = 'group', label = 'Entrance blip', fields = {
            f('enabled', { type = 'bool', label = 'Show blip' }),
            f('sprite', { type = 'int', label = 'Sprite', min = 1, max = 900 }),
            f('colour', { type = 'int', label = 'Colour', min = 0, max = 85 }),
        } }),
    } }),

    f('groups', { type = 'group', label = 'Ticket colours & groups', fields = {
        f('allocation', { type = 'select', label = 'Allocation mode', options = { 'balanced', 'manual', 'random' },
            help = 'manual: players are registered without a colour until staff assign one.' }),
        f('colours', { type = 'map', label = 'Colours', keys = C.COLOURS, item = { type = 'group', fields = {
            f('enabled', { type = 'bool', label = 'Enabled', locked = true }),
            f('label', { type = 'string', label = 'Label', max = 32 }),
            f('hex', { type = 'color', label = 'Colour' }),
            f('capacity', { type = 'int', label = 'Group capacity', min = 1, max = 512 }),
        } } }),
    } }),

    f('rotation', { type = 'group', label = 'Rotation', fields = {
        f('matrix', { type = 'matrix', label = 'Rotation matrix', locked = true }),
        f('roundDurationSeconds', { type = 'int', label = 'Round duration (s)', min = 60, max = 7200 }),
        f('transitionSeconds', { type = 'int', label = 'Transition period between rounds (s)', min = 0, max = 1800 }),
        f('autoAdvance', { type = 'bool', label = 'Automatically start the next round after the transition' }),
        f('autoCompleteOnTimer', { type = 'bool', label = 'Complete automated attractions when the round timer expires' }),
        f('autoFinalise', { type = 'bool', label = 'Move to final results automatically after the last round' }),
        f('warningSeconds', { type = 'list', label = 'Round warnings (seconds remaining)', item = { type = 'int', min = 1, max = 3600 }, max = 10 }),
        f('unavailableBehaviour', { type = 'select', label = 'When an attraction is unavailable', options = { 'hold', 'skip' } }),
        f('walkup', { type = 'group', label = 'Walk-up mode', fields = {
            f('enforceOrder', { type = 'bool', label = 'Players must visit attractions in their ticket colour\'s order',
                help = 'Off: any attraction the player has not completed yet may be played.' }),
            f('idleSeconds', { type = 'int', label = 'Close an idle attraction visit after (s)', min = 60, max = 7200,
                help = 'A visit nobody is playing is closed (without completing it) so the next player can start fresh.' }),
        } }),
    } }),

    f('scoring', { type = 'group', label = 'Scoring', fields = {
        f('maxTotal', { type = 'int', label = 'Maximum event total per participant (0 = none)', min = 0, max = 1000000 }),
        f('allowNegativeTotal', { type = 'bool', label = 'Allow totals below zero' }),
        f('participationBonus', { type = 'int', label = 'Bonus per completed attraction', min = 0, max = 1000 }),
        f('maxManualAdjustment', { type = 'int', label = 'Maximum single manual adjustment', min = 1, max = 100000 }),
        f('allowRepeatAfterTransfer', { type = 'bool', label = 'Transferred players may score again at an attraction they already completed' }),
        f('tieBreak', { type = 'multiselect', label = 'Tie-break order', options = C.TIE_BREAKS }),
    } }),

    f('leaderboard', { type = 'group', label = 'Leaderboard', fields = {
        f('pushIntervalMs', { type = 'int', label = 'Live update interval (ms)', min = 1000, max = 60000 }),
        f('publicSize', { type = 'int', label = 'Public leaderboard size', min = 3, max = 200 }),
        f('showColours', { type = 'bool', label = 'Show ticket colour' }),
        f('showBreakdown', { type = 'bool', label = 'Show per-attraction breakdown' }),
        f('showCompleted', { type = 'bool', label = 'Show completed attractions' }),
        f('anonymise', { type = 'bool', label = 'Hide names on the public board' }),
    } }),

    f('prizes', { type = 'group', label = 'Prizes & final results', fields = {
        f('autoDeliver', { type = 'bool', label = 'Deliver prize items automatically when results are frozen' }),
        f('tiers', { type = 'list', label = 'Prize tiers', max = 20, itemLabel = 'label', item = { type = 'group', fields = {
            f('label', { type = 'string', label = 'Tier name', max = 64 }),
            f('fromRank', { type = 'int', label = 'From rank', min = 1, max = 500 }),
            f('toRank', { type = 'int', label = 'To rank', min = 1, max = 500 }),
            f('items', { type = 'list', label = 'Items', max = 10, item = { type = 'group', fields = {
                f('item', { type = 'item', label = 'Item' }),
                f('count', { type = 'int', label = 'Quantity', min = 1, max = 1000 }),
            } } }),
        } } }),
    } }),

    f('rewards', { type = 'group', label = 'Reward delivery', fields = {
        f('maxCount', { type = 'int', label = 'Maximum quantity per reward', min = 1, max = 10000 }),
        f('allowedItems', { type = 'list', label = 'Additional permitted reward items', max = 100, item = { type = 'item' } }),
        f('retryOnLogin', { type = 'bool', label = 'Retry pending rewards when the player logs in' }),
        f('prizeBox', { type = 'list', label = 'Prize box contents (weighted)', max = 30, itemLabel = 'item', item = { type = 'group', fields = {
            f('item', { type = 'item', label = 'Item' }),
            f('count', { type = 'int', label = 'Quantity', min = 1, max = 1000 }),
            f('weight', { type = 'int', label = 'Weight', min = 1, max = 100000 }),
        } } }),
        f('treatHeal', { type = 'int', label = 'Treat token: health restored', min = 0, max = 100 }),
        f('trickEffectSeconds', { type = 'int', label = 'Trick token: effect duration (s)', min = 1, max = 60 }),
    } }),

    f('audio', { type = 'group', label = 'Audio', fields = {
        f('masterVolume', { type = 'number', label = 'Master volume', min = 0, max = 1, step = 0.05 }),
        f('notificationSound', { type = 'sound', label = 'Notification sound' }),
        f('roundSound', { type = 'sound', label = 'Round change sound' }),
    } }),

    f('attractions', { type = 'group', label = 'Attractions', fields = {
        f('shooting', { type = 'group', label = C.ATTRACTION_LABELS.shooting, fields = baseAttraction({
            f('durationSeconds', { type = 'int', label = 'Game length (s)', min = 15, max = 300 }),
            f('playsPerVisit', { type = 'int', label = 'Games per participant per visit', min = 1, max = 10 }),
            f('targetCount', { type = 'int', label = 'Targets per game', min = 5, max = 200 }),
            f('lanes', { type = 'int', label = 'Lanes', min = 1, max = 5 }),
            f('targetLifetimeMs', { type = 'int', label = 'Time a target takes to cross (ms)', min = 600, max = 15000 }),
            f('targetPoints', { type = 'int', label = 'Points per target', min = 0, max = 1000 }),
            f('bullseyeBonus', { type = 'int', label = 'Bullseye bonus (centre ring)', min = 0, max = 1000 }),
            f('specialChance', { type = 'int', label = 'Golden target chance (%)', min = 0, max = 100 }),
            f('specialPoints', { type = 'int', label = 'Golden target points', min = 0, max = 1000 }),
            f('decoyChance', { type = 'int', label = 'Spirit lantern (do not shoot) chance (%)', min = 0, max = 100 }),
            f('decoyPenalty', { type = 'int', label = 'Penalty for shooting a lantern', min = 0, max = 1000 }),
            f('accuracyScoring', { type = 'bool', label = 'Accuracy bonus' }),
            f('accuracyBonusMax', { type = 'int', label = 'Accuracy bonus at 100%', min = 0, max = 1000 }),
            f('missPenalty', { type = 'int', label = 'Penalty per missed shot', min = 0, max = 100 }),
            f('minClickIntervalMs', { type = 'int', label = 'Minimum time between shots (ms)', min = 30, max = 2000 }),
        }) }),

        f('wheel', { type = 'group', label = C.ATTRACTION_LABELS.wheel, fields = baseAttraction({
            f('maxSpins', { type = 'int', label = 'Spins per participant', min = 1, max = 50 }),
            f('cooldownSeconds', { type = 'int', label = 'Cooldown between spins (s)', min = 0, max = 3600 }),
            f('spinAnimationMs', { type = 'int', label = 'Spin animation length (ms)', min = 1000, max = 20000 }),
            f('participationBonus', { type = 'int', label = 'Bonus for first spin', min = 0, max = 1000 }),
            f('autoCompleteWhenAllSpun', { type = 'bool', label = 'Complete the group when everyone has used all spins' }),
            f('outcomes', { type = 'list', label = 'Outcomes', min = 2, max = 24, itemLabel = 'label', item = { type = 'group', fields = {
                f('id', { type = 'string', label = 'ID', max = 32 }),
                f('label', { type = 'string', label = 'Label', max = 48 }),
                f('type', { type = 'select', label = 'Outcome type', options = C.WHEEL_OUTCOME_TYPES }),
                f('weight', { type = 'int', label = 'Weight', min = 0, max = 100000, secret = true, secretPerm = 'config.edit' }),
                f('points', { type = 'int', label = 'Points (negative = deduction)', min = -10000, max = 10000 }),
                f('item', { type = 'item', label = 'Reward item', allowEmpty = true }),
                f('count', { type = 'int', label = 'Reward quantity', min = 0, max = 1000 }),
                f('colour', { type = 'color', label = 'Segment colour' }),
            } } }),
        }) }),

        f('fortune', { type = 'group', label = C.ATTRACTION_LABELS.fortune, fields = baseAttraction({
            f('questionsPerVisit', { type = 'int', label = 'Questions per visit', min = 1, max = 20 }),
            f('maxVisits', { type = 'int', label = 'Visits per participant', min = 1, max = 10 }),
            f('cooldownSeconds', { type = 'int', label = 'Cooldown between visits (s)', min = 0, max = 3600 }),
            f('answerTimeoutSeconds', { type = 'int', label = 'Time allowed per question (s)', min = 10, max = 600 }),
            f('scoreFortunes', { type = 'bool', label = 'Award points for a random fortune' }),
            f('fortunePoints', { type = 'int', label = 'Points for a random fortune', min = 0, max = 100 }),
            f('greeting', { type = 'text', label = 'Greeting', max = 500 }),
            f('farewell', { type = 'text', label = 'Farewell', max = 500 }),
            f('fortunes', { type = 'list', label = 'Fortunes', max = 100, item = { type = 'text', max = 300 } }),
            f('questions', { type = 'list', label = 'Questions & riddles', max = 200, itemLabel = 'prompt', item = { type = 'group', fields = {
                f('id', { type = 'string', label = 'ID', max = 32 }),
                f('category', { type = 'string', label = 'Category / pool', max = 32 }),
                f('kind', { type = 'select', label = 'Type', options = { 'choice', 'riddle' } }),
                f('prompt', { type = 'text', label = 'Question / riddle', max = 500 }),
                f('choices', { type = 'list', label = 'Choices (multiple choice)', max = 6, item = { type = 'string', max = 120 } }),
                f('correctIndex', { type = 'int', label = 'Correct choice (1-based)', min = 0, max = 6, secret = true, secretPerm = 'config.edit' }),
                f('acceptedAnswers', { type = 'list', label = 'Accepted answers (riddles)', max = 10, item = { type = 'string', max = 120 }, secret = true, secretPerm = 'config.edit' }),
                f('points', { type = 'int', label = 'Points if correct', min = 0, max = 1000 }),
                f('wrongPoints', { type = 'int', label = 'Points if wrong (negative = penalty)', min = -1000, max = 0 }),
                f('successText', { type = 'text', label = 'Success line', max = 300 }),
                f('failureText', { type = 'text', label = 'Failure line', max = 300 }),
            } } }),
        }) }),

        f('puppets', { type = 'group', label = C.ATTRACTION_LABELS.puppets, fields = baseAttraction({
            f('lobbySeconds', { type = 'int', label = 'Time for players to join the cast (s)', min = 0, max = 120 }),
            f('voteSeconds', { type = 'int', label = 'Audience voting time (s)', min = 10, max = 300 }),
            f('soloPoints', { type = 'int', label = 'Points for a solo performance', min = 0, max = 10000 }),
            f('defaultDurationSeconds', { type = 'int', label = 'Default performance length (s)', min = 15, max = 1800 }),
            f('participationBonus', { type = 'int', label = 'Participation bonus', min = 0, max = 1000 }),
            f('maxPointsPerAward', { type = 'int', label = 'Maximum award per performer', min = 1, max = 10000 }),
            f('scenarios', { type = 'list', label = 'Scenario library', max = 200, itemLabel = 'title', item = { type = 'group', fields = {
                f('id', { type = 'string', label = 'ID', max = 32 }),
                f('title', { type = 'string', label = 'Title', max = 96 }),
                f('description', { type = 'text', label = 'Scenario', max = 1000 }),
                f('category', { type = 'string', label = 'Category', max = 32 }),
                f('difficulty', { type = 'select', label = 'Difficulty', options = { 'easy', 'medium', 'hard', 'absurd' } }),
                f('minPlayers', { type = 'int', label = 'Minimum performers', min = 1, max = 12 }),
                f('maxPlayers', { type = 'int', label = 'Maximum performers', min = 1, max = 12 }),
                f('timeLimit', { type = 'int', label = 'Time limit (s)', min = 15, max = 1800 }),
                f('minPoints', { type = 'int', label = 'Minimum award', min = 0, max = 10000 }),
                f('maxPoints', { type = 'int', label = 'Maximum award', min = 0, max = 10000 }),
                f('roles', { type = 'list', label = 'Suggested roles', max = 12, item = { type = 'string', max = 64 } }),
            } } }),
        }) }),

        f('deception', { type = 'group', label = C.ATTRACTION_LABELS.deception, fields = baseAttraction({
            f('clueIntervalSeconds', { type = 'int', label = 'Unlock a clue every (s)', min = 15, max = 3600 }),
            f('durationSeconds', { type = 'int', label = 'Questioning time (s)', min = 60, max = 7200 }),
            f('maxSubmissions', { type = 'int', label = 'Answer submissions per participant', min = 1, max = 10 }),
            f('defaultMystery', { type = 'string', label = 'Default mystery ID', max = 32 }),
            f('mysteries', { type = 'list', label = 'Mysteries', max = 50, itemLabel = 'title', item = { type = 'group', fields = {
                f('id', { type = 'string', label = 'ID', max = 32 }),
                f('title', { type = 'string', label = 'Title', max = 96 }),
                f('description', { type = 'text', label = 'Description', max = 2000 }),
                f('rules', { type = 'text', label = 'Questioning rules', max = 1000 }),
                f('liarCount', { type = 'int', label = 'Number of liars', min = 1, max = 10 }),
                f('pointsPerCorrect', { type = 'int', label = 'Points per liar identified', min = 0, max = 1000 }),
                f('penaltyPerIncorrect', { type = 'int', label = 'Penalty per wrong accusation', min = 0, max = 1000 }),
                f('perfectBonus', { type = 'int', label = 'Bonus for a perfect answer', min = 0, max = 1000 }),
                f('partialCredit', { type = 'bool', label = 'Partial credit' }),
                f('tieBreak', { type = 'select', label = 'Tie-break', options = { 'none', 'earliest_submission' } }),
                f('tieBreakBonus', { type = 'int', label = 'Tie-break bonus', min = 0, max = 1000 }),
                f('performers', { type = 'list', label = 'Performers', min = 2, max = 12, itemLabel = 'name', item = { type = 'group', fields = {
                    f('id', { type = 'string', label = 'ID', max = 32 }),
                    f('name', { type = 'string', label = 'Name', max = 64 }),
                    f('profile', { type = 'text', label = 'Public profile', max = 600 }),
                    f('statements', { type = 'list', label = 'Testimony (shown to investigators; liars lie here)', max = 10, item = { type = 'text', max = 300 } }),
                    f('isLiar', { type = 'bool', label = 'Is a liar', secret = true, secretPerm = 'deception.secrets' }),
                } } }),
                f('clues', { type = 'list', label = 'Clues', max = 20, itemLabel = 'text', item = { type = 'group', fields = {
                    f('id', { type = 'string', label = 'ID', max = 32 }),
                    f('text', { type = 'text', label = 'Clue text', max = 500, secret = true, secretPerm = 'deception.secrets' }),
                } } }),
            } } }),
        }) }),

        f('horror', { type = 'group', label = C.ATTRACTION_LABELS.horror, fields = baseAttraction({
            f('lobbySeconds', { type = 'int', label = 'Gather time before the doors open (s)', min = 0, max = 120 }),
            f('entry', { type = 'vec4', label = 'Maze entry', restart = true }),
            f('exit', { type = 'vec4', label = 'Maze exit', restart = true }),
            f('exitRadius', { type = 'number', label = 'Exit radius (m)', min = 0.5, max = 15, step = 0.5 }),
            f('boundaryCentre', { type = 'vec3', label = 'Boundary centre', restart = true }),
            f('boundaryRadius', { type = 'number', label = 'Boundary radius (m)', min = 5, max = 500, step = 1 }),
            f('durationSeconds', { type = 'int', label = 'Run duration (s)', min = 30, max = 3600 }),
            f('warnings', { type = 'list', label = 'Countdown warnings (seconds remaining)', max = 12, item = { type = 'int', min = 1, max = 3600 } }),
            f('ambientSound', { type = 'sound', label = 'Ambient loop' }),
            f('warningSound', { type = 'sound', label = 'Warning sound' }),
            f('finalWarningSound', { type = 'sound', label = 'Final warning sound (≤ 10 s)' }),
            f('endSound', { type = 'sound', label = 'End-of-run sound' }),
            f('volume', { type = 'number', label = 'Volume', min = 0, max = 1, step = 0.05 }),
            f('collectionRule', { type = 'select', label = 'Collection rule', options = { 'once_per_player', 'once_global' } }),
            f('visibility', { type = 'select', label = 'Token visibility', options = { 'always', 'proximity' } }),
            f('visibilityDistance', { type = 'number', label = 'Proximity distance (m)', min = 2, max = 100, step = 1 }),
            f('completionBonus', { type = 'int', label = 'Completion bonus', min = 0, max = 10000 }),
            f('timeBonus', { type = 'group', label = 'Time bonus', fields = {
                f('enabled', { type = 'bool', label = 'Enabled' }),
                f('pointsPerTenSeconds', { type = 'int', label = 'Points per 10 s remaining', min = 0, max = 1000 }),
                f('max', { type = 'int', label = 'Maximum time bonus', min = 0, max = 10000 }),
            } }),
            f('penalties', { type = 'group', label = 'Penalties', fields = {
                f('notEscaped', { type = 'int', label = 'Not escaped before time expired', min = 0, max = 10000 }),
                f('leftBoundary', { type = 'int', label = 'Left the maze boundary during a run', min = 0, max = 10000 }),
            } }),
            f('physicalTokens', { type = 'bool', label = 'Also give a keepsake token item (no points value)' }),
            f('autoCompleteSession', { type = 'bool', label = 'Complete the group when the run ends' }),
            f('tokenTypes', { type = 'map', label = 'Token types', keys = C.TOKEN_TYPES, item = { type = 'group', fields = {
                f('points', { type = 'int', label = 'Points', min = 0, max = 10000 }),
                f('quantity', { type = 'int', label = 'Active per run (0 = all positions)', min = 0, max = 200 }),
                f('model', { type = 'model', label = 'Prop model', max = 64,
                    help = 'The bundled coins are carnivalcoinbronze / carnivalcoinsilver / carnivalcoingold. The prop floats above the token position, spins and glows; if it cannot load, a glowing ring is shown.' }),
                f('distance', { type = 'number', label = 'Collection distance (m)', min = 0.5, max = 10, step = 0.1 }),
                f('floatHeight', { type = 'number', label = 'Float height above the position (m)', min = 0, max = 3, step = 0.05 }),
                f('bobHeight', { type = 'number', label = 'Bob up and down (m, 0 = still)', min = 0, max = 1, step = 0.01 }),
                f('spinSpeed', { type = 'int', label = 'Spin speed (degrees per second, 0 = still)', min = 0, max = 720 }),
                f('glowColour', { type = 'color', label = 'Glow colour' }),
                f('glowRange', { type = 'number', label = 'Glow radius (m, 0 = no glow)', min = 0, max = 15, step = 0.1 }),
                f('glowIntensity', { type = 'number', label = 'Glow brightness', min = 0, max = 50, step = 0.5 }),
                f('respawnSeconds', { type = 'int', label = 'Respawn after (s, once_global only; 0 = never)', min = 0, max = 3600 }),
            } } }),
            f('tokens', { type = 'list', label = 'Token positions', max = 200, itemLabel = 'id', restart = true, item = { type = 'group', fields = {
                f('id', { type = 'string', label = 'ID', max = 32 }),
                f('type', { type = 'select', label = 'Type', options = C.TOKEN_TYPES }),
                f('coords', { type = 'vec3', label = 'Position' }),
            } } }),
        }) }),
    } }),
} }

-- Locate a schema node by dotted path ("attractions.wheel.outcomes").
function S.nodeAt(path)
    local node = S.root
    for part in string.gmatch(path, '[^%.]+') do
        if node.type == 'group' then
            local found
            for _, fld in ipairs(node.fields) do
                if fld.key == part then found = fld break end
            end
            if not found then return nil end
            node = found
        elseif node.type == 'map' then
            node = node.item
        elseif node.type == 'list' then
            node = node.item
        else
            return nil
        end
    end
    return node
end

return S
