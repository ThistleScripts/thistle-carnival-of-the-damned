-- Small, dependency-free helpers shared by client and server.

Carnival = Carnival or {}
local U = {}
Carnival.U = U

function U.deepCopy(v, seen)
    if type(v) ~= 'table' then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, val in pairs(v) do out[U.deepCopy(k, seen)] = U.deepCopy(val, seen) end
    return out
end

local function isArray(t)
    if type(t) ~= 'table' then return false end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= 'number' then return false end
        n = n + 1
    end
    return n == #t
end
U.isArray = isArray

-- Merge `override` onto a copy of `base`. Arrays are replaced wholesale, maps are
-- merged recursively. Neither input is mutated.
function U.deepMerge(base, override)
    if override == nil then return U.deepCopy(base) end
    if type(base) ~= 'table' or type(override) ~= 'table' or isArray(override) or isArray(base) then
        return U.deepCopy(override)
    end
    local out = U.deepCopy(base)
    for k, v in pairs(override) do
        if type(v) == 'table' and type(out[k]) == 'table' and not isArray(v) and not isArray(out[k]) then
            out[k] = U.deepMerge(out[k], v)
        else
            out[k] = U.deepCopy(v)
        end
    end
    return out
end

function U.getPath(tbl, path)
    local cur = tbl
    for part in string.gmatch(path, '[^%.]+') do
        if type(cur) ~= 'table' then return nil end
        local idx = tonumber(part)
        cur = cur[idx or part]
    end
    return cur
end

function U.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function U.round(v, places)
    local m = 10 ^ (places or 0)
    return math.floor(v * m + 0.5) / m
end

function U.trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Remove control characters and clamp length. Used for every free-text field that
-- reaches the database or other clients.
function U.sanitizeText(s, maxLen)
    if type(s) ~= 'string' then return '' end
    s = s:gsub('[%c]', ' ')
    s = U.trim(s)
    maxLen = maxLen or 255
    if #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

-- Same as sanitizeText but keeps line breaks (for notes / explanations).
function U.sanitizeMultiline(s, maxLen)
    if type(s) ~= 'string' then return '' end
    s = s:gsub('\r\n', '\n'):gsub('[%z\1-\9\11-\31\127]', ' ')
    s = U.trim(s)
    maxLen = maxLen or 1000
    if #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

function U.normaliseAnswer(s)
    s = string.lower(U.trim(s or ''))
    s = s:gsub('[%p]', ''):gsub('%s+', ' ')
    s = s:gsub('^the ', ''):gsub('^an? ', '')
    return U.trim(s)
end

function U.dist3(a, b)
    local dx, dy, dz = (a.x - b.x), (a.y - b.y), ((a.z or 0) - (b.z or 0))
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function U.dist2(a, b)
    local dx, dy = (a.x - b.x), (a.y - b.y)
    return math.sqrt(dx * dx + dy * dy)
end

function U.count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function U.keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

function U.find(list, pred)
    for i, v in ipairs(list or {}) do
        if pred(v, i) then return v, i end
    end
    return nil
end

function U.map(list, fn)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = fn(v, i) end
    return out
end

function U.filter(list, fn)
    local out = {}
    for _, v in ipairs(list or {}) do
        if fn(v) then out[#out + 1] = v end
    end
    return out
end

function U.indexBy(list, key)
    local out = {}
    for _, v in ipairs(list or {}) do out[v[key]] = v end
    return out
end

function U.toSet(list)
    local s = {}
    for _, v in ipairs(list or {}) do s[v] = true end
    return s
end

function U.formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format('%d:%02d', seconds // 60, seconds % 60)
end

-- Plain table coords {x,y,z,w} from a vector or table.
function U.coords(v)
    if v == nil then return nil end
    return { x = (v.x or 0) + 0.0, y = (v.y or 0) + 0.0, z = (v.z or 0) + 0.0, w = v.w and (v.w + 0.0) or nil }
end

return U
