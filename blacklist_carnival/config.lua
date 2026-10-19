-- Carnival of the Damned - BOOTSTRAP configuration (server only).
--
-- This file holds security-sensitive settings that must never be editable from
-- in game: roles, permission allowlists, Discord webhooks, logging and recovery
-- behaviour. It is loaded as a server script and is never sent to clients.
--
-- Ordinary gameplay settings (locations, durations, scoring, prizes, attraction
-- content...) live in the database and are edited through /carnivaladmin.
-- Their factory defaults are in shared/defaults.lua.

Config = {}

-- Logging -------------------------------------------------------------------
-- Minimum severity printed to the server console and stored in the monitoring log.
-- One of: debug, info, warning, error, critical
Config.LogLevel = GetConvar('carnival_log_level', 'info')

-- Retention (days) for the high-volume monitoring log by severity.
-- The administrative audit log is never pruned automatically.
Config.Retention = {
    debug = 2,
    info = 14,
    warning = 60,
    error = 120,
    critical = 365,
}

-- Security ---------------------------------------------------------------------
Config.Security = {
    -- ACE prefix. Roles: `add_ace group.admin carnival.role.administrator allow`
    -- Individual permissions: `add_ace identifier.license:xxx carnival.perm.scores.adjust allow`
    -- Attraction scoping for operators/performers: `carnival.attraction.<id>`
    AcePrefix = 'carnival',

    -- License allowlist: identifier -> role. Accepts license: or license2: identifiers.
    -- Example: ['license:0123456789abcdef0123456789abcdef01234567'] = 'owner',
    Allowlist = {
    },

    -- Logical roles. `rank` orders roles (higher = more senior). Permission strings
    -- support a trailing `*` wildcard. `attractions.operate.@assigned` expands to the
    -- attractions this staff member is assigned to (ACE carnival.attraction.<id>
    -- or an in-game staff assignment).
    Roles = {
        owner = {
            label = 'Owner', rank = 100,
            permissions = { '*' },
        },
        administrator = {
            label = 'Administrator', rank = 80,
            permissions = {
                'panel.admin', 'panel.staff', 'config.view', 'config.edit',
                'events.manage', 'events.operate', 'events.history',
                'participants.view', 'participants.manage', 'scores.view', 'scores.adjust',
                'rewards.manage', 'attractions.operate.*', 'theatre.custom', 'deception.secrets',
                'horror.control', 'monitoring.view', 'audit.view', 'export.history',
                'staff.manage', 'leaderboard.staff',
            },
        },
        event_manager = {
            label = 'Event Manager', rank = 60,
            permissions = {
                'panel.staff', 'events.operate', 'participants.view', 'participants.manage',
                'scores.view', 'scores.adjust', 'rewards.manage', 'attractions.operate.*',
                'theatre.custom', 'deception.secrets', 'horror.control', 'leaderboard.staff',
            },
        },
        attraction_operator = {
            label = 'Attraction Operator', rank = 40,
            permissions = {
                'panel.staff', 'participants.view', 'scores.view', 'attractions.operate.@assigned',
                'leaderboard.staff',
            },
        },
        performer = {
            label = 'Performer / Judge', rank = 30,
            permissions = {
                'panel.staff', 'participants.view', 'attractions.operate.@assigned', 'theatre.custom',
            },
        },
        observer = {
            label = 'Read-only Observer', rank = 10,
            permissions = { 'panel.staff', 'participants.view', 'scores.view', 'leaderboard.staff' },
        },
    },

    -- Allow staff with `staff.manage` to grant roles in game (stored in the database).
    -- Grants can never exceed MaxGrantableRank, so owner/administrator always come
    -- from this file or ACE.
    AllowDatabaseGrants = true,
    MaxGrantableRank = 60,

    -- Separate allowlist for the House of Horrors controls. When RequireHorrorAllowlist
    -- is true, `horror.control` additionally requires the player's license to be listed
    -- here (roles listed in HorrorAllowlistBypassRoles are exempt).
    RequireHorrorAllowlist = true,
    HorrorControllers = {
        -- 'license:0123456789abcdef0123456789abcdef01234567',
    },
    HorrorAllowlistBypassRoles = { owner = true },

    -- Seconds a resolved permission set is cached per player.
    PermissionCacheSeconds = 30,
}

-- Rate limits ----------------------------------------------------------------------
-- Per player, per endpoint group. { requests, windowSeconds }
Config.RateLimits = {
    default = { 20, 10 },
    participant = { 12, 10 },
    action = { 6, 5 },
    shooting = { 40, 5 },
    staff = { 40, 10 },
    admin = { 60, 10 },
    -- After this many rejected requests in a minute a security warning is raised.
    -- Players are never automatically banned.
    abuseThreshold = 30,
}

-- Recovery -----------------------------------------------------------------------------
Config.Recovery = {
    -- After a restart, a running event is placed in `paused` and must be resumed by staff.
    PauseRunningEventOnStart = true,
}

-- Inventory ---------------------------------------------------------------------------
Config.Inventory = {
    resource = 'ox_inventory',
    -- Refuse to start registration if the ticket items are missing from ox_inventory.
    RequireItemDefinitions = true,
}

-- Discord ---------------------------------------------------------------------------------
-- Webhook URLs are read from server convars so they never live in resource files:
--   set carnival_webhook_event    "https://discord.com/api/webhooks/..."
--   set carnival_webhook_security "https://discord.com/api/webhooks/..."
--   set carnival_webhook_admin    "https://discord.com/api/webhooks/..."
--   set carnival_webhook_error    "https://discord.com/api/webhooks/..."
Config.Discord = {
    Enabled = GetConvar('carnival_discord', 'false') == 'true',
    Webhooks = {
        event = GetConvar('carnival_webhook_event', ''),
        security = GetConvar('carnival_webhook_security', ''),
        admin = GetConvar('carnival_webhook_admin', ''),
        error = GetConvar('carnival_webhook_error', ''),
    },
    Username = 'Carnival of the Damned',
    -- Minimum seconds between messages per webhook (messages are batched meanwhile).
    MinInterval = 3,
    MaxQueue = 100,
}
