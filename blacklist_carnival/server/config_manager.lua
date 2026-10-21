-- Database-backed, versioned gameplay configuration.
--
-- Scopes:
--   global  - server-wide defaults (carnival_config_versions.scope = 'global')
--   event   - optional complete override for one event (scope = 'event')
-- The effective settings for the active event are the event document if one
-- exists, otherwise the global document; either is merged over shared/defaults.lua
-- so settings added by newer resource versions always have a value.
--
-- Every save creates a new version (append-only). Rollback re-activates an older
-- version's data as a new version. Bootstrap security settings (config.lua) are
-- never part of these documents.

local C, U, V = Carnival.C, Carnival.U, Carnival.Validate
local Cfg = {}
Carnival.Config = Cfg

local docs = { global = nil, event = nil }      -- raw stored documents (validated trees)
local versions = { global = nil, event = nil }  -- { id, version }
local effective = nil
local changeHandlers = {}

function Cfg.onChange(fn)
    changeHandlers[#changeHandlers + 1] = fn
end

-- Settings saved by older versions whose value should follow a new default:
-- the horror tokens used to be placeholder GTA props (or none) before the
-- carnival coins were bundled.
local LEGACY_TOKEN_MODELS = { [''] = true, prop_ld_case_01 = true, prop_money_bag_01 = true, prop_ld_gold_chest = true }

local function upgrade(doc)
    local h = type(doc) == 'table' and type(doc.attractions) == 'table' and doc.attractions.horror
    if type(h) ~= 'table' or type(h.tokenTypes) ~= 'table' then return doc end
    for ttype, t in pairs(h.tokenTypes) do
        if type(t) == 'table' and LEGACY_TOKEN_MODELS[t.model or ''] then t.model = 'carnivalcoin' .. ttype end
    end
    return doc
end

local function loadActive(scope, eventId)
    local row
    if scope == 'global' then
        row = Carnival.Db.single("SELECT * FROM carnival_config_versions WHERE scope = 'global' AND is_active = 1 ORDER BY version DESC LIMIT 1")
    else
        row = Carnival.Db.single("SELECT * FROM carnival_config_versions WHERE scope = 'event' AND event_id = ? AND is_active = 1 ORDER BY version DESC LIMIT 1", { eventId })
    end
    if not row then return nil end
    return upgrade(Carnival.Db.decode(row.data)), { id = row.id, version = row.version, createdAt = row.created_at, createdBy = row.created_by_name }
end

local function buildEffective()
    local base = docs.event or docs.global or {}
    local merged = U.deepMerge(Carnival.Defaults, base)
    local normalised, errors = V.config(merged)
    if #errors > 0 then
        Carnival.Monitor.log('critical', 'config', 'stored_config_invalid', { details = { errors = errors, scope = docs.event and 'event' or 'global' } })
        local fallback, ferrs = V.config(U.deepCopy(Carnival.Defaults))
        if #ferrs > 0 then error('factory defaults failed validation: ' .. json.encode(ferrs)) end
        return fallback
    end
    return normalised
end

local function fireChange(changes)
    for _, fn in ipairs(changeHandlers) do
        local ok, err = pcall(fn, effective, changes or {})
        if not ok then Carnival.Monitor.log('error', 'config', 'change_handler_failed', { details = { error = tostring(err) } }) end
    end
end

function Cfg.load()
    local g, gv = loadActive('global')
    if not g then
        -- First start: seed version 1 from factory defaults.
        local tree, errors = V.config(U.deepCopy(Carnival.Defaults))
        if #errors > 0 then error('factory defaults failed validation: ' .. json.encode(errors)) end
        local data = json.encode(tree)
        local id = Carnival.Db.insertRow('carnival_config_versions', {
            scope = 'global', version = 1, data = data, checksum = Carnival.Db.checksum(data),
            note = 'Factory defaults', is_active = 1, created_by = 'system', created_by_name = 'System', created_at = os.time(),
        })
        g, gv = tree, { id = id, version = 1 }
        Carnival.Monitor.log('info', 'config', 'config_seeded', { details = { version = 1 } })
    end
    docs.global, versions.global = g, gv
    Cfg.loadEventScope(Carnival.Events and Carnival.Events.activeId() or nil, true)
end

-- (Re)load the event override for the active event and rebuild effective settings.
function Cfg.loadEventScope(eventId, silent)
    docs.event, versions.event = nil, nil
    if eventId then
        docs.event, versions.event = loadActive('event', eventId)
    end
    effective = buildEffective()
    if not silent then
        fireChange({})
        if Carnival.Push then Carnival.Push.settings() end
    end
end

function Cfg.get()
    return effective
end

function Cfg.attraction(id)
    return effective and effective.attractions[id]
end

function Cfg.versionInfo()
    return {
        global = versions.global,
        event = versions.event,
        source = docs.event and 'event' or 'global',
    }
end

-- Raw document for a scope (falls back to global / defaults for a new event scope).
function Cfg.document(scope)
    if scope == 'event' then
        return docs.event and U.deepCopy(docs.event) or U.deepCopy(effective)
    end
    return U.deepMerge(Carnival.Defaults, docs.global or {})
end

---------------------------------------------------------------------------
-- Item references inside the configuration
---------------------------------------------------------------------------
function Cfg.referencedItems(tree)
    local items = {}
    local function add(name, path)
        if name and name ~= '' then items[#items + 1] = { item = name, path = path } end
    end
    local a = tree.attractions
    for i, o in ipairs(a.wheel.outcomes or {}) do add(o.item, ('attractions.wheel.outcomes.%d.item'):format(i)) end
    for i, t in ipairs(tree.prizes.tiers or {}) do
        for j, it in ipairs(t.items or {}) do add(it.item, ('prizes.tiers.%d.items.%d.item'):format(i, j)) end
    end
    for i, it in ipairs(tree.rewards.allowedItems or {}) do add(it, ('rewards.allowedItems.%d'):format(i)) end
    for i, it in ipairs(tree.rewards.prizeBox or {}) do add(it.item, ('rewards.prizeBox.%d.item'):format(i)) end
    if a.horror.physicalTokens then
        for _, t in ipairs(C.TOKEN_TYPES) do add(C.TOKEN_ITEMS[t], 'attractions.horror.physicalTokens') end
    end
    return items
end

-- Items that may be delivered as rewards under the current configuration.
function Cfg.permittedRewardItems()
    local set = {}
    for _, r in ipairs(Cfg.referencedItems(effective)) do set[r.item] = true end
    for _, it in ipairs(C.CUSTOM_ITEMS) do
        if not C.TICKET_ITEM_COLOUR[it] then set[it] = true end
    end
    return set
end

---------------------------------------------------------------------------
-- Preview / save / rollback
---------------------------------------------------------------------------

local function canSeeFn(src)
    return function(perm) return Carnival.Perms.has(src, perm) end
end

local function liveEventAffected(scope)
    local state = Carnival.Events.state()
    if not state then return false end
    local live = state == C.STATES.RUNNING or state == C.STATES.PAUSED or state == C.STATES.BETWEEN
    if not live then return false end
    -- walk-up events never close; players progress individually, so the matrix
    -- and colours may be edited while they are open
    if Carnival.Events.isWalkup() then return false end
    if scope == 'event' then return true end
    return docs.event == nil -- global changes only affect the event if it has no override
end

-- Returns analysis = { valid, errors, changes, warnings, normalised, needsConfirm }
function Cfg.analyse(src, scope, incoming)
    if scope ~= 'global' and scope ~= 'event' then return { valid = false, errors = { { path = '', message = 'invalid scope' } } } end
    if scope == 'event' and not Carnival.Events.activeId() then
        return { valid = false, errors = { { path = '', message = 'there is no active event to configure' } } }
    end
    if type(incoming) ~= 'table' then return { valid = false, errors = { { path = '', message = 'missing configuration' } } } end
    local current = Cfg.document(scope)
    incoming = V.restoreSecrets(U.deepCopy(incoming), current, canSeeFn(src))
    local normalised, errors = V.config(incoming)
    local warnings = {}

    if #errors == 0 then
        local inv = Carnival.Inventory
        if inv.available() then
            for _, ref in ipairs(Cfg.referencedItems(normalised)) do
                if not inv.itemExists(ref.item) then
                    errors[#errors + 1] = { path = ref.path, message = ('item "%s" is not registered in ox_inventory'):format(ref.item) }
                end
            end
        else
            warnings[#warnings + 1] = 'ox_inventory is not running - item names could not be verified.'
        end
    end

    local changes = #errors == 0 and V.diff(current, normalised) or {}
    local needsConfirm = false
    if #errors == 0 and liveEventAffected(scope) then
        for _, ch in ipairs(changes) do
            if ch.locked then
                errors[#errors + 1] = { path = ch.path, message = 'cannot be changed while the event is in progress' }
            end
        end
    end
    for _, ch in ipairs(changes) do
        if ch.restart then
            needsConfirm = true
            warnings[#warnings + 1] = ('%s: takes full effect after the attraction is reset or the next session starts.'):format(ch.path)
        end
    end
    if #changes > 10 then needsConfirm = true end
    -- redact secret values from the preview payload
    for _, ch in ipairs(changes) do
        if ch.secret and not Carnival.Perms.has(src, 'deception.secrets') then ch.before, ch.after = '(hidden)', '(hidden)' end
    end
    return { valid = #errors == 0, errors = errors, warnings = warnings, changes = changes, normalised = normalised, needsConfirm = needsConfirm }
end

local function nextVersion(scope, eventId)
    if scope == 'global' then
        return (Carnival.Db.scalar("SELECT MAX(version) FROM carnival_config_versions WHERE scope = 'global'") or 0) + 1
    end
    return (Carnival.Db.scalar("SELECT MAX(version) FROM carnival_config_versions WHERE scope = 'event' AND event_id = ?", { eventId }) or 0) + 1
end

local function store(src, scope, tree, note, rollbackOf, changes)
    return Carnival.withLock('config:' .. scope, function()
        local eventId = scope == 'event' and Carnival.Events.activeId() or nil
        local version = nextVersion(scope, eventId)
        local data = json.encode(tree)
        local actor = Carnival.Identity.actor(src)
        local deactivate, deactivateParams
        if scope == 'global' then
            deactivate, deactivateParams = "UPDATE carnival_config_versions SET is_active = 0 WHERE scope = 'global' AND is_active = 1", {}
        else
            deactivate, deactivateParams = "UPDATE carnival_config_versions SET is_active = 0 WHERE scope = 'event' AND event_id = ? AND is_active = 1", { eventId }
        end
        local insertSql, insertParams = Carnival.Db.buildInsert('carnival_config_versions', {
            scope = scope, event_id = eventId, version = version, data = data, checksum = Carnival.Db.checksum(data),
            note = note, rollback_of = rollbackOf, is_active = 1, created_by = actor.license, created_by_name = actor.name, created_at = os.time(),
        })
        local ok = Carnival.Db.transaction({
            { query = deactivate, values = deactivateParams },
            { query = insertSql, values = insertParams },
        })
        if not ok then return nil, 'database_error', 'The configuration could not be saved.' end

        local paths = {}
        for _, ch in ipairs(changes or {}) do paths[#paths + 1] = ch.path end
        Carnival.Audit.record(actor, rollbackOf and 'config_rolled_back' or 'config_saved', {
            targetType = 'config', targetId = ('%s:v%d'):format(scope, version), reason = note,
            details = { scope = scope, version = version, changed = paths, rollbackOf = rollbackOf },
        })
        Carnival.Monitor.log('info', 'config', 'config_changed', { actor = actor, details = { scope = scope, version = version, changes = #paths } })

        if scope == 'global' then
            docs.global, versions.global = tree, { version = version }
        else
            docs.event, versions.event = tree, { version = version }
        end
        effective = buildEffective()
        fireChange(changes)
        Carnival.Push.settings()
        Carnival.Push.invalidate('config', 'dashboard')
        return { version = version, scope = scope }
    end)
end

function Cfg.save(src, scope, incoming, note, confirm)
    local a = Cfg.analyse(src, scope, incoming)
    if not a.valid then return nil, 'invalid', a end
    if #a.changes == 0 then return nil, 'no_changes', 'Nothing changed.' end
    if a.needsConfirm and not confirm then
        return { needsConfirm = true, changes = a.changes, warnings = a.warnings }
    end
    return store(src, scope, a.normalised, note, nil, a.changes)
end

function Cfg.rollback(src, versionId, note, confirm)
    local row = Carnival.Db.single('SELECT * FROM carnival_config_versions WHERE id = ?', { versionId })
    if not row then return nil, 'not_found', 'Version not found.' end
    if row.scope == 'event' and row.event_id ~= Carnival.Events.activeId() then
        return nil, 'invalid', 'That version belongs to a different event.'
    end
    local tree = U.deepMerge(Carnival.Defaults, Carnival.Db.decode(row.data, {}))
    local a = Cfg.analyse(src, row.scope, tree)
    if not a.valid then return nil, 'invalid', a end
    if a.needsConfirm and not confirm then
        return { needsConfirm = true, changes = a.changes, warnings = a.warnings }
    end
    return store(src, row.scope, a.normalised, note ~= '' and note or ('Rollback to v' .. row.version), row.id, a.changes)
end

-- Remove the event override so the active event follows the global settings.
function Cfg.clearEventOverride(src, reason)
    local eventId = Carnival.Events.activeId()
    if not eventId or not docs.event then return nil, 'invalid', 'This event has no custom settings.' end
    if liveEventAffected('event') then return nil, 'invalid', 'Cannot remove event settings while the event is in progress.' end
    Carnival.Db.update("UPDATE carnival_config_versions SET is_active = 0 WHERE scope = 'event' AND event_id = ?", { eventId })
    Carnival.Audit.record(Carnival.Identity.actor(src), 'config_event_override_removed', { targetType = 'event', targetId = eventId, reason = reason })
    Cfg.loadEventScope(eventId)
    return true
end

function Cfg.listVersions(scope, page, pageSize)
    local eventId = Carnival.Events.activeId()
    local where, params = "scope = 'global'", {}
    if scope == 'event' then
        where, params = "scope = 'event' AND event_id = ?", { eventId or 0 }
    end
    local total = Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_config_versions WHERE ' .. where, params) or 0
    local lp = { table.unpack(params) }
    lp[#lp + 1] = pageSize
    lp[#lp + 1] = (page - 1) * pageSize
    local rows = Carnival.Db.query('SELECT id, scope, event_id, version, checksum, note, rollback_of, is_active, created_by_name, created_at FROM carnival_config_versions WHERE '
        .. where .. ' ORDER BY version DESC LIMIT ? OFFSET ?', lp) or {}
    return rows, total
end

---------------------------------------------------------------------------
-- Settings safe for every client
---------------------------------------------------------------------------
function Cfg.publicSettings()
    local e = effective
    if not e then return nil end
    local colours = {}
    for _, c in ipairs(C.COLOURS) do
        local g = e.groups.colours[c]
        colours[c] = { enabled = g.enabled, label = g.label, hex = g.hex }
    end
    local attractions = {}
    for _, id in ipairs(C.ATTRACTIONS) do
        local a = e.attractions[id]
        attractions[id] = {
            enabled = a.enabled, label = a.label, location = a.location, npcModel = a.npcModel,
            interactDistance = a.interactDistance, blip = a.blip, maxPlayers = a.maxPlayers,
        }
    end
    local sh = e.attractions.shooting
    attractions.shooting.durationSeconds = sh.durationSeconds
    attractions.shooting.lanes = sh.lanes
    attractions.shooting.targetLifetimeMs = sh.targetLifetimeMs
    local wh = e.attractions.wheel
    attractions.wheel.maxSpins = wh.maxSpins
    attractions.wheel.cooldownSeconds = wh.cooldownSeconds
    attractions.wheel.spinAnimationMs = wh.spinAnimationMs
    attractions.wheel.outcomes = U.map(wh.outcomes, function(o)
        return { id = o.id, label = o.label, type = o.type, colour = o.colour }
    end)
    attractions.fortune.mode = e.attractions.fortune.mode
    attractions.fortune.greeting = e.attractions.fortune.greeting
    attractions.fortune.farewell = e.attractions.fortune.farewell
    attractions.deception.maxSubmissions = e.attractions.deception.maxSubmissions
    local h = e.attractions.horror
    for _, k in ipairs({ 'entry', 'exit', 'exitRadius', 'boundaryCentre', 'boundaryRadius', 'durationSeconds', 'ambientSound',
        'warningSound', 'finalWarningSound', 'endSound', 'volume', 'visibility', 'visibilityDistance' }) do
        attractions.horror[k] = h[k]
    end
    attractions.horror.tokenTypes = {}
    for _, t in ipairs(C.TOKEN_TYPES) do
        attractions.horror.tokenTypes[t] = U.deepCopy(h.tokenTypes[t])
    end
    return {
        general = { mode = e.general.mode, eventName = e.general.eventName, blipLabel = e.general.blipLabel, hudEnabled = e.general.hudEnabled },
        registration = {
            entrance = e.registration.entrance, npcModel = e.registration.npcModel,
            interactDistance = e.registration.interactDistance, blip = e.registration.blip,
            virtualTickets = e.registration.virtualTickets, allowSelfReplacement = e.registration.allowSelfReplacement,
        },
        groups = { colours = colours },
        rotation = { matrix = e.rotation.matrix, roundDurationSeconds = e.rotation.roundDurationSeconds, transitionSeconds = e.rotation.transitionSeconds },
        leaderboard = e.leaderboard,
        audio = e.audio,
        rewards = { trickEffectSeconds = e.rewards.trickEffectSeconds },
        attractions = attractions,
    }
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local Api = Carnival.Api

local function serialiseSchema()
    return Carnival.Schema.root
end

Api.register('config.get', {
    perm = { 'panel.admin', 'config.view' }, rate = 'admin',
    handler = function(ctx, payload)
        local scope = payload.scope == 'event' and 'event' or 'global'
        local doc = Cfg.document(scope)
        return {
            scope = scope,
            data = V.redact(doc, canSeeFn(ctx.source)),
            schema = serialiseSchema(),
            versions = Cfg.versionInfo(),
            hasEventOverride = docs.event ~= nil,
            activeEventId = Carnival.Events.activeId(),
            canEdit = ctx:has('config.edit'),
            canSeeSecrets = ctx:has('deception.secrets'),
            sounds = C.SOUNDS,
            liveLocked = liveEventAffected(scope),
        }
    end,
})

Api.register('config.preview', {
    perm = { 'panel.admin', 'config.edit' }, rate = 'admin',
    handler = function(ctx, payload)
        local scope = payload.scope == 'event' and 'event' or 'global'
        local a = Cfg.analyse(ctx.source, scope, payload.data)
        a.normalised = nil
        return a
    end,
})

Api.register('config.save', {
    perm = { 'panel.admin', 'config.edit' }, rate = 'admin',
    handler = function(ctx, payload)
        local scope = payload.scope == 'event' and 'event' or 'global'
        local note = V.reason(payload.note, false) or ''
        local res, code, info = Cfg.save(ctx.source, scope, payload.data, note, payload.confirm == true)
        if code == 'invalid' and type(info) == 'table' then
            info.normalised = nil
            return { saved = false, analysis = info }
        end
        if code then return nil, code, info end
        if res.needsConfirm then return { saved = false, needsConfirm = true, changes = res.changes, warnings = res.warnings } end
        return { saved = true, version = res.version }
    end,
})

Api.register('config.versions', {
    perm = { 'panel.admin', 'config.view' }, rate = 'admin',
    handler = function(ctx, payload)
        local scope = payload.scope == 'event' and 'event' or 'global'
        local page = V.int(payload.page or 1, 1, 10000) or 1
        local rows, total = Cfg.listVersions(scope, page, 25)
        return { rows = rows, total = total, page = page, pageSize = 25 }
    end,
})

Api.register('config.rollback', {
    perm = { 'panel.admin', 'config.edit' }, rate = 'admin',
    handler = function(ctx, payload)
        local id, err = V.id(payload.versionId)
        if not id then return nil, 'invalid', 'versionId ' .. err end
        local note = V.reason(payload.note, false) or ''
        local res, code, info = Cfg.rollback(ctx.source, id, note, payload.confirm == true)
        if code == 'invalid' and type(info) == 'table' then
            info.normalised = nil
            return { saved = false, analysis = info }
        end
        if code then return nil, code, info end
        if res.needsConfirm then return { saved = false, needsConfirm = true, changes = res.changes, warnings = res.warnings } end
        return { saved = true, version = res.version }
    end,
})

Api.register('config.clearEventOverride', {
    perm = { 'panel.admin', 'config.edit' }, rate = 'admin',
    handler = function(ctx, payload)
        local reason, rerr = V.reason(payload.reason, true)
        if not reason then return nil, 'invalid', rerr end
        return Cfg.clearEventOverride(ctx.source, reason)
    end,
})
