-- Validation helpers.
--
-- Two families:
--   * Validate.config(tree)  -- schema-driven validation of a full settings tree
--   * Validate.<type>(...)   -- small input validators used by API handlers
--
-- Every function returns (value, nil) on success or (nil, errorMessage).

Carnival = Carnival or {}
local C = Carnival.C
local U = Carnival.U
local S = Carnival.Schema

local V = {}
Carnival.Validate = V

---------------------------------------------------------------------------
-- Primitive input validators (API payloads)
---------------------------------------------------------------------------

function V.int(v, min, max)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil, 'must be a number' end
    if math.floor(v) ~= v then return nil, 'must be a whole number' end
    if min and v < min then return nil, ('must be at least %s'):format(min) end
    if max and v > max then return nil, ('must be at most %s'):format(max) end
    return math.tointeger(v) or v
end

function V.number(v, min, max)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil, 'must be a number' end
    if min and v < min then return nil, ('must be at least %s'):format(min) end
    if max and v > max then return nil, ('must be at most %s'):format(max) end
    return v
end

function V.string(v, maxLen, allowEmpty)
    if type(v) ~= 'string' then return nil, 'must be text' end
    local s = U.sanitizeText(v, maxLen or 255)
    if s == '' and not allowEmpty then return nil, 'must not be empty' end
    return s
end

function V.text(v, maxLen, allowEmpty)
    if type(v) ~= 'string' then return nil, 'must be text' end
    local s = U.sanitizeMultiline(v, maxLen or 1000)
    if s == '' and not allowEmpty then return nil, 'must not be empty' end
    return s
end

function V.bool(v)
    if type(v) ~= 'boolean' then return nil, 'must be true or false' end
    return v
end

function V.oneOf(v, options)
    for _, o in ipairs(options) do
        if o == v then return v end
    end
    return nil, 'is not an allowed value'
end

function V.colour(v)
    if C.COLOUR_INDEX[v] then return v end
    return nil, 'is not a valid ticket colour'
end

function V.attraction(v)
    if C.ATTRACTION_INDEX[v] then return v end
    return nil, 'is not a valid attraction'
end

function V.id(v)
    -- database ids arrive as numbers (or numeric strings from NUI)
    return V.int(v, 1, 9007199254740991)
end

function V.requestId(v)
    if type(v) ~= 'string' or #v < 8 or #v > 64 or not v:match('^[%w%-_]+$') then
        return nil, 'invalid request id'
    end
    return v
end

function V.reason(v, required)
    if v == nil or v == '' then
        if required then return nil, 'a reason is required' end
        return ''
    end
    local s, err = V.text(v, 500, not required)
    if not s then return nil, err end
    if required and #s < 3 then return nil, 'a reason is required (min 3 characters)' end
    return s
end

local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end

function V.vec3(v)
    if type(v) ~= 'table' then return nil, 'must be coordinates' end
    if not (finite(v.x) and finite(v.y) and finite(v.z)) then return nil, 'coordinates must be numbers' end
    if math.abs(v.x) > 20000 or math.abs(v.y) > 20000 or v.z < -500 or v.z > 3000 then
        return nil, 'coordinates are outside the map'
    end
    return { x = U.round(v.x, 3), y = U.round(v.y, 3), z = U.round(v.z, 3) }
end

function V.vec4(v)
    local out, err = V.vec3(v)
    if not out then return nil, err end
    if not finite(v.w) then return nil, 'heading must be a number' end
    out.w = U.round(v.w % 360, 2)
    return out
end

---------------------------------------------------------------------------
-- Rotation matrix
---------------------------------------------------------------------------

-- Validates the rotation matrix against the enabled colours: every round assigns
-- each enabled colour a different attraction, and over all rounds each colour
-- visits each attraction exactly once.
function V.rotationMatrix(matrix, enabledColours)
    if type(matrix) ~= 'table' or #matrix < 1 or #matrix > #C.ATTRACTIONS then
        return nil, ('rotation must have between 1 and %d rounds'):format(#C.ATTRACTIONS)
    end
    enabledColours = enabledColours or C.COLOURS
    local enabledIdx = {}
    for _, c in ipairs(enabledColours) do enabledIdx[C.COLOUR_INDEX[c]] = c end

    local visited = {}
    local out = {}
    for r, row in ipairs(matrix) do
        if type(row) ~= 'table' or #row ~= #C.COLOURS then
            return nil, ('round %d must list one attraction per colour (%d columns)'):format(r, #C.COLOURS)
        end
        local used = {}
        out[r] = {}
        for i = 1, #C.COLOURS do
            local a = row[i]
            if not C.ATTRACTION_INDEX[a] then
                return nil, ('round %d, %s: unknown attraction "%s"'):format(r, C.COLOURS[i], tostring(a))
            end
            if enabledIdx[i] then
                if used[a] then
                    return nil, ('round %d assigns %s to more than one group'):format(r, a)
                end
                used[a] = true
                visited[i] = visited[i] or {}
                if visited[i][a] then
                    return nil, ('%s visits %s more than once'):format(C.COLOURS[i], a)
                end
                visited[i][a] = true
            end
            out[r][i] = a
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Schema-driven config validation
---------------------------------------------------------------------------

local validateNode

local function pathJoin(base, key)
    if base == '' then return tostring(key) end
    return base .. '.' .. tostring(key)
end

local function validateScalar(node, value, path, errors)
    local t = node.type
    local out, err
    if t == 'bool' then
        out, err = V.bool(value)
    elseif t == 'int' then
        out, err = V.int(value, node.min, node.max)
    elseif t == 'number' then
        out, err = V.number(value, node.min, node.max)
    elseif t == 'string' or t == 'model' then
        if value == nil then value = '' end
        out, err = V.string(value, node.max or 255, node.allowEmpty)
        if out and t == 'model' and out ~= '' and not out:match('^[%w_]+$') then
            out, err = nil, 'model names may only contain letters, numbers and underscores'
        end
    elseif t == 'item' then
        if value == nil then value = '' end
        out, err = V.string(value, 64, node.allowEmpty)
        if out and out ~= '' and not out:match('^[%w_%-]+$') then
            out, err = nil, 'item names may only contain letters, numbers, - and _'
        end
    elseif t == 'text' then
        if value == nil then value = '' end
        out, err = V.text(value, node.max or 1000, true)
    elseif t == 'select' then
        out, err = V.oneOf(value, node.options)
    elseif t == 'multiselect' then
        if type(value) ~= 'table' then
            out, err = nil, 'must be a list'
        else
            out = {}
            local seen = {}
            for _, v in ipairs(value) do
                if not V.oneOf(v, node.options) then
                    err = ('"%s" is not an allowed value'):format(tostring(v))
                    out = nil
                    break
                end
                if not seen[v] then
                    seen[v] = true
                    out[#out + 1] = v
                end
            end
        end
    elseif t == 'vec3' then
        out, err = V.vec3(value)
    elseif t == 'vec4' then
        out, err = V.vec4(value)
    elseif t == 'color' then
        if type(value) == 'string' and value:match('^#%x%x%x%x%x%x$') then out = value:lower() else err = 'must be a hex colour like #aa0011' end
    elseif t == 'sound' then
        if C.SOUND_SET[value] then out = value else err = 'must be one of the bundled sounds' end
    elseif t == 'matrix' then
        out, err = V.rotationMatrix(value)
    else
        err = 'unknown field type ' .. tostring(t)
    end
    if err then errors[#errors + 1] = { path = path, message = err } end
    return out
end

validateNode = function(node, value, path, errors)
    if node.type == 'group' then
        if type(value) ~= 'table' then
            errors[#errors + 1] = { path = path, message = 'missing section' }
            return nil
        end
        local out = {}
        for _, fld in ipairs(node.fields) do
            out[fld.key] = validateNode(fld, value[fld.key], pathJoin(path, fld.key), errors)
        end
        return out
    elseif node.type == 'map' then
        if type(value) ~= 'table' then
            errors[#errors + 1] = { path = path, message = 'missing section' }
            return nil
        end
        local out = {}
        for _, key in ipairs(node.keys) do
            out[key] = validateNode(node.item, value[key], pathJoin(path, key), errors)
        end
        return out
    elseif node.type == 'list' then
        if type(value) ~= 'table' then
            errors[#errors + 1] = { path = path, message = 'must be a list' }
            return nil
        end
        local n = #value
        if node.min and n < node.min then
            errors[#errors + 1] = { path = path, message = ('needs at least %d entries'):format(node.min) }
        end
        if node.max and n > node.max then
            errors[#errors + 1] = { path = path, message = ('allows at most %d entries'):format(node.max) }
        end
        local out = {}
        local ids = {}
        for i = 1, math.min(n, node.max or n) do
            local item = validateNode(node.item, value[i], pathJoin(path, i), errors)
            out[i] = item
            if type(item) == 'table' and item.id ~= nil then
                if ids[item.id] then
                    errors[#errors + 1] = { path = pathJoin(path, i) .. '.id', message = ('duplicate id "%s"'):format(item.id) }
                end
                ids[item.id] = true
                if type(item.id) == 'string' and not item.id:match('^[%w_%-]+$') then
                    errors[#errors + 1] = { path = pathJoin(path, i) .. '.id', message = 'ids may only contain letters, numbers, - and _' }
                end
            end
        end
        return out
    else
        return validateScalar(node, value, path, errors)
    end
end

-- Cross-field rules that the per-field schema cannot express.
local function crossValidate(cfg, errors)
    local function err(path, msg) errors[#errors + 1] = { path = path, message = msg } end

    local enabled = {}
    for _, c in ipairs(C.COLOURS) do
        if cfg.groups and cfg.groups.colours and cfg.groups.colours[c] and cfg.groups.colours[c].enabled then
            enabled[#enabled + 1] = c
        end
    end
    if #enabled == 0 then err('groups.colours', 'at least one colour must be enabled') end
    if cfg.rotation and cfg.rotation.matrix then
        local _, merr = V.rotationMatrix(cfg.rotation.matrix, enabled)
        if merr then err('rotation.matrix', merr) end
    end

    if cfg.shop and cfg.shop.items then
        local seen = {}
        for i, it in ipairs(cfg.shop.items) do
            if C.TICKET_ITEM_COLOUR[it.item] then
                err(('shop.items.%d.item'):format(i), 'carnival tickets cannot be sold at the prize counter')
            end
            if seen[it.item] then err(('shop.items.%d.item'):format(i), ('"%s" is listed twice'):format(it.item)) end
            seen[it.item] = true
        end
    end

    local a = cfg.attractions or {}
    if a.wheel and a.wheel.outcomes then
        local total = 0
        for _, o in ipairs(a.wheel.outcomes) do
            total = total + (o.weight or 0)
            if o.item and o.item ~= '' and (o.count or 0) < 1 then
                err('attractions.wheel.outcomes', ('outcome "%s" has an item but quantity 0'):format(o.id or '?'))
            end
        end
        if total <= 0 then err('attractions.wheel.outcomes', 'the total weight of all outcomes must be above zero') end
    end
    if a.fortune and a.fortune.questions then
        for i, q in ipairs(a.fortune.questions) do
            if q.kind == 'choice' then
                if #(q.choices or {}) < 2 then err(('attractions.fortune.questions.%d.choices'):format(i), 'multiple-choice questions need at least two choices') end
                if (q.correctIndex or 0) < 1 or (q.correctIndex or 0) > #(q.choices or {}) then
                    err(('attractions.fortune.questions.%d.correctIndex'):format(i), 'correct choice must point at one of the choices')
                end
            elseif q.kind == 'riddle' and #(q.acceptedAnswers or {}) < 1 then
                err(('attractions.fortune.questions.%d.acceptedAnswers'):format(i), 'riddles need at least one accepted answer')
            end
        end
    end
    if a.puppets and a.puppets.scenarios then
        for i, sc in ipairs(a.puppets.scenarios) do
            if (sc.minPlayers or 1) > (sc.maxPlayers or 1) then err(('attractions.puppets.scenarios.%d'):format(i), 'minimum performers exceeds maximum') end
            if (sc.minPoints or 0) > (sc.maxPoints or 0) then err(('attractions.puppets.scenarios.%d'):format(i), 'minimum award exceeds maximum') end
        end
    end
    if a.deception and a.deception.mysteries then
        local found = false
        for i, m in ipairs(a.deception.mysteries) do
            if m.id == a.deception.defaultMystery then found = true end
            local liars = 0
            for _, p in ipairs(m.performers or {}) do if p.isLiar then liars = liars + 1 end end
            -- isLiar is redacted for users without deception.secrets; the server
            -- restores it before validation, so this check always sees real data.
            if liars ~= m.liarCount then
                err(('attractions.deception.mysteries.%d'):format(i), ('mystery "%s" marks %d liars but liarCount is %d'):format(m.id or '?', liars, m.liarCount or 0))
            end
            if (m.liarCount or 0) >= #(m.performers or {}) then
                err(('attractions.deception.mysteries.%d'):format(i), 'there must be at least one truthful performer')
            end
        end
        if not found and #a.deception.mysteries > 0 then
            err('attractions.deception.defaultMystery', 'default mystery id does not match any mystery')
        end
    end
    if a.horror then
        local seen = {}
        for _, w in ipairs(a.horror.warnings or {}) do
            if seen[w] then err('attractions.horror.warnings', 'duplicate warning threshold ' .. w) end
            seen[w] = true
            if w >= (a.horror.durationSeconds or 0) then err('attractions.horror.warnings', ('warning at %ds is not shorter than the run'):format(w)) end
        end
    end
    if cfg.prizes and cfg.prizes.tiers then
        for i, t in ipairs(cfg.prizes.tiers) do
            if (t.fromRank or 1) > (t.toRank or 1) then err(('prizes.tiers.%d'):format(i), 'from rank is after to rank') end
        end
    end
end

-- Validate and normalise a complete settings tree.
-- Returns normalisedTree, errors (errors is an empty list on success).
function V.config(tree)
    local errors = {}
    local out = validateNode(S.root, tree, '', errors)
    if #errors == 0 then crossValidate(out, errors) end
    return out, errors
end

---------------------------------------------------------------------------
-- Secret handling
---------------------------------------------------------------------------

-- Walk a settings tree alongside the schema and replace secret values the
-- caller may not see with nil. `canSee(perm)` returns boolean.
function V.redact(tree, canSee)
    local function walk(node, value)
        if value == nil then return nil end
        if node.secret and not canSee(node.secretPerm or 'config.edit') then return nil end
        if node.type == 'group' then
            local out = {}
            for _, fld in ipairs(node.fields) do out[fld.key] = walk(fld, value[fld.key]) end
            return out
        elseif node.type == 'map' then
            local out = {}
            for _, key in ipairs(node.keys) do out[key] = walk(node.item, value[key]) end
            return out
        elseif node.type == 'list' then
            local out = {}
            for i, v in ipairs(value) do out[i] = walk(node.item, v) end
            return out
        end
        return U.deepCopy(value)
    end
    return walk(S.root, tree)
end

-- Restore secret values from `current` into `incoming` wherever the caller could
-- not see them. List items are matched by their `id` field.
function V.restoreSecrets(incoming, current, canSee)
    local function walk(node, inc, cur)
        if node.secret and not canSee(node.secretPerm or 'config.edit') then
            return U.deepCopy(cur)
        end
        if inc == nil then return nil end
        if node.type == 'group' and type(inc) == 'table' then
            for _, fld in ipairs(node.fields) do
                inc[fld.key] = walk(fld, inc[fld.key], type(cur) == 'table' and cur[fld.key] or nil)
            end
        elseif node.type == 'map' and type(inc) == 'table' then
            for _, key in ipairs(node.keys) do
                inc[key] = walk(node.item, inc[key], type(cur) == 'table' and cur[key] or nil)
            end
        elseif node.type == 'list' and type(inc) == 'table' then
            local byId = {}
            if type(cur) == 'table' then
                for _, v in ipairs(cur) do
                    if type(v) == 'table' and v.id ~= nil then byId[v.id] = v end
                end
            end
            for i, v in ipairs(inc) do
                local match = (type(v) == 'table' and v.id ~= nil) and byId[v.id] or nil
                inc[i] = walk(node.item, v, match)
            end
        end
        return inc
    end
    return walk(S.root, incoming, current)
end

-- Collect paths whose values differ between two trees, annotated with schema
-- flags. Used for previews and live-change warnings.
function V.diff(old, new)
    local changes = {}
    local function walk(node, a, b, path)
        if node.type == 'group' then
            for _, fld in ipairs(node.fields) do
                walk(fld, type(a) == 'table' and a[fld.key] or nil, type(b) == 'table' and b[fld.key] or nil, pathJoin(path, fld.key))
            end
            return
        elseif node.type == 'map' then
            for _, key in ipairs(node.keys) do
                walk(node.item, type(a) == 'table' and a[key] or nil, type(b) == 'table' and b[key] or nil, pathJoin(path, key))
            end
            return
        end
        if not U.deepEqual(a, b) then
            changes[#changes + 1] = {
                path = path,
                label = node.label,
                restart = node.restart or false,
                locked = node.locked or false,
                secret = node.secret or false,
                before = node.secret and '(hidden)' or a,
                after = node.secret and '(hidden)' or b,
            }
        end
    end
    walk(S.root, old, new, '')
    return changes
end

return V
