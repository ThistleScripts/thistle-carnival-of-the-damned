-- Shared constants for Carnival of the Damned.
-- Loaded on both client and server. Nothing in this file is secret.

Carnival = Carnival or {}

local C = {}
Carnival.C = C

C.RESOURCE = 'blacklist_carnival'
C.VERSION = '1.0.0'
C.EVENT_PREFIX = 'blacklist_carnival:'

-- Ticket colours / travelling groups. Order matters: it is the column order of
-- the rotation matrix.
C.COLOURS = { 'red', 'blue', 'green', 'yellow', 'purple', 'orange' }
C.COLOUR_INDEX = {}
for i, c in ipairs(C.COLOURS) do C.COLOUR_INDEX[c] = i end

C.TICKET_ITEMS = {
    red = 'carnival_ticket_red',
    blue = 'carnival_ticket_blue',
    green = 'carnival_ticket_green',
    yellow = 'carnival_ticket_yellow',
    purple = 'carnival_ticket_purple',
    orange = 'carnival_ticket_orange',
}
C.TICKET_ITEM_COLOUR = {}
for colour, item in pairs(C.TICKET_ITEMS) do C.TICKET_ITEM_COLOUR[item] = colour end

C.TOKEN_ITEMS = {
    bronze = 'carnival_token_bronze',
    silver = 'carnival_token_silver',
    gold = 'carnival_token_gold',
}
C.TOKEN_TYPES = { 'bronze', 'silver', 'gold' }
-- Players step into a glowing circle this wide (m) to open the maze doors or escape.
C.HORROR_DOOR_RADIUS = 1.5

-- The prize box: an ox_inventory container that arrives filled with prizes.
C.PRIZE_BOX = 'carnival_prize_box'

-- Items removed from the resource (saved settings that still name them are
-- upgraded on load).
C.RETIRED_ITEMS = { carnival_trick_token = true, carnival_treat_token = true }

-- Carnival food sold at the prize counter (plain ox_inventory consumables).
C.FOOD_ITEMS = {
    'carnival_bloodfloss', 'carnival_poison_apple', 'carnival_finger_dog',
    'carnival_grave_popcorn', 'carnival_bone_pretzel', 'carnival_web_cake',
    'carnival_eyeball_pop', 'carnival_witch_brew', 'carnival_blood_slushie',
    'carnival_grave_shake',
}

-- Every custom item shipped by this resource (used by validation tooling).
C.CUSTOM_ITEMS = {
    'carnival_ticket_red', 'carnival_ticket_blue', 'carnival_ticket_green',
    'carnival_ticket_yellow', 'carnival_ticket_purple', 'carnival_ticket_orange',
    'carnival_token_bronze', 'carnival_token_silver', 'carnival_token_gold',
    'carnival_prize_box',
}
for _, item in ipairs(C.FOOD_ITEMS) do C.CUSTOM_ITEMS[#C.CUSTOM_ITEMS + 1] = item end

C.ATTRACTIONS = { 'shooting', 'wheel', 'fortune', 'puppets', 'deception', 'horror' }
C.ATTRACTION_INDEX = {}
for i, a in ipairs(C.ATTRACTIONS) do C.ATTRACTION_INDEX[a] = i end

C.ATTRACTION_LABELS = {
    shooting = 'The Shooting Gallery',
    wheel = 'The Wheel of Misfortune',
    fortune = "The Fortune Teller's Curse",
    puppets = "The Puppet Master's Theatre",
    deception = 'The Hall of Deception',
    horror = 'The House of Horrors',
}

-- Attractions whose results require human judgement. Their sessions are never
-- completed automatically when the round timer expires.

-- Event state machine ------------------------------------------------------
C.STATES = {
    INACTIVE = 'inactive',
    CONFIGURING = 'configuring',
    REG_OPEN = 'registration_open',
    REG_CLOSED = 'registration_closed',
    READY = 'ready',
    RUNNING = 'running',
    PAUSED = 'paused',
    BETWEEN = 'between_rounds',
    FINAL = 'final_results',
    COMPLETED = 'completed',
    CANCELLED = 'cancelled',
}

C.STATE_LABELS = {
    inactive = 'Inactive',
    configuring = 'Configuring',
    registration_open = 'Registration open',
    registration_closed = 'Registration closed',
    ready = 'Ready to start',
    running = 'Running',
    paused = 'Paused',
    between_rounds = 'Between rounds',
    final_results = 'Final results',
    completed = 'Completed',
    cancelled = 'Cancelled',
}

-- Allowed transitions: from -> { to = true }
C.TRANSITIONS = {
    inactive = { configuring = true, cancelled = true },
    configuring = { inactive = true, registration_open = true, cancelled = true },
    registration_open = { registration_closed = true, cancelled = true },
    registration_closed = { registration_open = true, ready = true, cancelled = true },
    ready = { registration_closed = true, running = true, cancelled = true },
    running = { paused = true, between_rounds = true, final_results = true, cancelled = true },
    paused = { running = true, between_rounds = true, final_results = true, cancelled = true },
    between_rounds = { running = true, paused = true, final_results = true, cancelled = true },
    final_results = { completed = true },
    completed = {},
    cancelled = {},
}

C.TERMINAL_STATES = { completed = true, cancelled = true }
-- States in which the rotation is live and attractions may score.
C.LIVE_STATES = { running = true, between_rounds = true }
-- States in which late registration may be accepted (if enabled).
C.LATE_REG_STATES = { running = true, paused = true, between_rounds = true }

C.SESSION_STATUS = {
    PENDING = 'pending', ACTIVE = 'active', COMPLETED = 'completed',
    SKIPPED = 'skipped', INTERRUPTED = 'interrupted',
}

-- Permissions -----------------------------------------------------------------
C.PERMISSIONS = {
    'panel.admin',
    'config.view', 'config.edit',
    'events.manage', 'events.operate', 'events.history',
    'participants.view', 'participants.manage',
    'scores.view', 'scores.adjust',
    'rewards.manage',
    'deception.secrets',
    'monitoring.view', 'audit.view',
    'export.history',
    'staff.manage',
    'props.manage',
    'shop.manage',
    'leaderboard.staff',
}

C.ROLE_ORDER = { 'observer', 'performer', 'attraction_operator', 'event_manager', 'administrator', 'owner' }

-- Monitoring --------------------------------------------------------------------
C.SEVERITIES = { 'debug', 'info', 'warning', 'error', 'critical' }
C.SEVERITY_RANK = { debug = 1, info = 2, warning = 3, error = 4, critical = 5 }

C.MONITOR_CATEGORIES = {
    'lifecycle', 'event_state', 'registration', 'ticket', 'ticket_validation', 'group',
    'rotation', 'attraction', 'player', 'score', 'reward', 'staff_action', 'permission',
    'invalid_request', 'duplicate', 'database', 'callback', 'countdown', 'token',
    'config', 'recovery', 'security', 'staff_report', 'inventory', 'props', 'shop',
}

-- Bundled sound assets (web/public/sounds). Config fields that reference sounds
-- may only choose from this list.
C.SOUNDS = {
    'horror_ambient', 'horror_warning', 'horror_final', 'horror_end', 'horror_scare',
    'wheel_tick', 'wheel_win', 'wheel_lose', 'carnival_chime', 'round_bell',
    'shooting_hit', 'shooting_bullseye', 'trick_laugh', 'treat_sparkle',
    'ambient_organ', 'ambient_crowd', 'ambient_chimes', 'ambient_wind', 'shop_purchase',
}
C.SOUND_SET = {}
for _, s in ipairs(C.SOUNDS) do C.SOUND_SET[s] = true end

C.WHEEL_OUTCOME_TYPES = {
    'small_points', 'large_points', 'bonus', 'nothing', 'penalty',
    'trick', 'treat', 'common_prize', 'rare_prize', 'special_prize',
}

C.TIE_BREAKS = {
    'attractions_completed', 'earliest_to_score', 'highest_single_attraction',
    'fewest_deductions', 'most_gold_tokens', 'registration_order',
}

return C
