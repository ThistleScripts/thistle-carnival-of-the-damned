-- Request router for every client / NUI → server call.
--
-- All requests arrive through ONE ox_lib callback ('blacklist_carnival:api') with
-- an endpoint name and a payload. Each endpoint is declared with the permission
-- it requires and a rate-limit bucket; the router enforces both before the
-- handler runs, catches handler errors and logs rejected requests.
--
-- Api.register(name, {
--     perm = 'events.manage' | { 'a', 'b' } (all required) | nil,
--     anyPerm = { 'a', 'b' },         -- at least one required
--     rate = 'participant'|'action'|'staff'|'admin'|'shooting',
--     audit = false,                   -- handlers do their own auditing
--     handler = function(ctx, payload) return data | nil, errCode, message end,
-- })

local Api = {}
Carnival.Api = Api

local endpoints = {}
local buckets = {}   -- [src] = { [bucket] = { count, windowStart } }

function Api.register(name, def)
    assert(type(def.handler) == 'function', 'endpoint handler required: ' .. name)
    if endpoints[name] then error('duplicate endpoint ' .. name) end
    endpoints[name] = def
end

function Api.endpoints()
    return endpoints
end

local function rateLimited(src, bucketName)
    local limit = Config.RateLimits[bucketName] or Config.RateLimits.default
    local now = os.time()
    buckets[src] = buckets[src] or {}
    local b = buckets[src][bucketName]
    if not b or now - b.windowStart >= limit[2] then
        b = { count = 0, windowStart = now }
        buckets[src][bucketName] = b
    end
    b.count = b.count + 1
    return b.count > limit[1]
end

local function fail(code, message)
    return { ok = false, error = code, message = message }
end

-- Context helpers available to handlers.
local ctxMeta = {}
ctxMeta.__index = function(self, k)
    if k == 'actor' then
        local a = Carnival.Identity.actor(self.source)
        rawset(self, 'actor', a)
        return a
    end
    return ctxMeta[k]
end
function ctxMeta.has(self, perm) return Carnival.Perms.has(self.source, perm) end

function Api.call(src, name, payload)
    if type(name) ~= 'string' or #name > 64 then
        Carnival.Monitor.security(src, 'api_malformed_request', { name = tostring(name):sub(1, 64) }, 'invalid_request')
        return fail('bad_request')
    end
    local def = endpoints[name]
    if not def then
        Carnival.Monitor.security(src, 'api_unknown_endpoint', { name = name }, 'invalid_request')
        return fail('unknown_endpoint')
    end
    if not Carnival.ready and not def.allowBeforeReady then
        return fail('not_ready', 'The carnival is still starting up.')
    end
    if payload ~= nil and type(payload) ~= 'table' then
        Carnival.Monitor.security(src, 'api_bad_payload', { name = name }, 'invalid_request')
        return fail('bad_request')
    end
    payload = payload or {}

    if rateLimited(src, def.rate or 'default') then
        Carnival.Monitor.security(src, 'rate_limited', { name = name }, 'invalid_request')
        return fail('rate_limited', 'Slow down a little.')
    end

    local perms = def.perm
    if type(perms) == 'string' then perms = { perms } end
    for _, p in ipairs(perms or {}) do
        if not Carnival.Perms.has(src, p) then
            Carnival.Monitor.security(src, 'permission_denied', { endpoint = name, permission = p }, 'permission')
            return fail('forbidden', 'You do not have permission to do that.')
        end
    end
    if def.anyPerm and not Carnival.Perms.hasAny(src, def.anyPerm) then
        Carnival.Monitor.security(src, 'permission_denied', { endpoint = name, anyOf = def.anyPerm }, 'permission')
        return fail('forbidden', 'You do not have permission to do that.')
    end

    local ctx = setmetatable({ source = src, endpoint = name }, ctxMeta)
    local ok, data, errCode, message = pcall(def.handler, ctx, payload)
    if not ok then
        Carnival.Monitor.log('error', 'callback', 'handler_error', { actor = Carnival.Identity.actor(src), details = { endpoint = name, error = tostring(data) } })
        return fail('internal_error', 'Something went wrong. Staff have been notified.')
    end
    if errCode then
        if errCode == 'invalid' or errCode == 'bad_request' then
            Carnival.Monitor.log('debug', 'invalid_request', 'validation_failed', { actor = Carnival.Identity.actor(src), details = { endpoint = name, message = message } })
        end
        return fail(errCode, message)
    end
    return { ok = true, data = data }
end

lib.callback.register('blacklist_carnival:api', function(src, name, payload)
    return Api.call(src, name, payload)
end)

AddEventHandler('playerDropped', function()
    buckets[source] = nil
end)

---------------------------------------------------------------------------
-- Payload validation helper: schema = { field = function(v) -> value|nil, err }
-- Returns validated table or nil, 'invalid', message.
---------------------------------------------------------------------------
function Api.validate(payload, schema)
    local out = {}
    for field, fn in pairs(schema) do
        local v, err = fn(payload[field])
        if err then return nil, 'invalid', ('%s %s'):format(field, err) end
        out[field] = v
    end
    return out
end

-- Wrap a validator so nil is accepted.
function Api.optional(fn)
    return function(v)
        if v == nil or v == '' then return nil end
        return fn(v)
    end
end
