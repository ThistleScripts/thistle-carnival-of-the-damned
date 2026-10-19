-- Administrative audit trail (append-only).
--
-- Audit.record(actor, action, opts)
--   actor : identity table from Carnival.Identity.actor(src) or Carnival.Identity.SYSTEM
--   opts  : { eventId, targetType, targetId, reason, details }
--
-- The application only INSERTs into carnival_audit_log; there is no update or
-- delete path anywhere in the resource. Audit writes are synchronous so callers
-- know whether the record was persisted.

local Audit = {}
Carnival.Audit = Audit

function Audit.record(actor, action, opts)
    opts = opts or {}
    actor = actor or Carnival.Identity.SYSTEM
    local eventId = opts.eventId
    if eventId == nil then eventId = Carnival.Events.activeId() end
    local details = opts.details and Carnival.Db.encode(opts.details) or nil
    if details and #details > 8000 then details = details:sub(1, 8000) end
    local id = Carnival.Db.insertRow('carnival_audit_log', {
        event_id = eventId,
        actor_license = actor.license,
        actor_name = actor.name,
        action = action,
        target_type = opts.targetType,
        target_id = opts.targetId ~= nil and tostring(opts.targetId) or nil,
        reason = opts.reason ~= '' and opts.reason or nil,
        details = details,
        created_at = os.time(),
    })
    Carnival.Monitor.log('info', 'staff_action', action, {
        eventId = eventId, actor = actor, result = id and 'audited' or 'audit_failed',
        details = { target = opts.targetType and (opts.targetType .. ':' .. tostring(opts.targetId)) or nil, reason = opts.reason },
    })
    if not id then
        Carnival.Monitor.log('error', 'database', 'audit_write_failed', { actor = actor, details = { action = action } })
    end
    if Carnival.Discord then
        Carnival.Discord.send('admin', action, ('%s%s%s'):format(
            actor.name or actor.license or 'system',
            opts.targetType and (' → ' .. opts.targetType .. ' ' .. tostring(opts.targetId or '')) or '',
            (opts.reason and opts.reason ~= '') and ('\nReason: ' .. opts.reason) or ''), 0xb08d3c)
    end
    return id
end

-- filters: { eventId, actor, action, from, to, targetType, targetId }
function Audit.query(filters, page, pageSize)
    local where, params = {}, {}
    local function add(cond, ...)
        where[#where + 1] = cond
        for _, v in ipairs({ ... }) do params[#params + 1] = v end
    end
    if filters.eventId then add('event_id = ?', filters.eventId) end
    if filters.actor then add('(actor_license = ? OR actor_name LIKE ?)', filters.actor, '%' .. filters.actor .. '%') end
    if filters.action then add('action LIKE ?', '%' .. filters.action .. '%') end
    if filters.from then add('created_at >= ?', filters.from) end
    if filters.to then add('created_at <= ?', filters.to) end
    if filters.targetType then add('target_type = ?', filters.targetType) end
    if filters.targetId then add('target_id = ?', tostring(filters.targetId)) end
    local whereSql = #where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or ''
    local total = Carnival.Db.scalar('SELECT COUNT(*) FROM carnival_audit_log' .. whereSql, params) or 0
    local lp = { table.unpack(params) }
    lp[#lp + 1] = pageSize
    lp[#lp + 1] = (page - 1) * pageSize
    local rows = Carnival.Db.query('SELECT * FROM carnival_audit_log' .. whereSql .. ' ORDER BY id DESC LIMIT ? OFFSET ?', lp) or {}
    return rows, total
end
