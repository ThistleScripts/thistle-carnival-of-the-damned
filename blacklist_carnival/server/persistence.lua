-- Database access layer (oxmysql).
--
-- Every query in the resource goes through these wrappers so failures are caught,
-- reported to the monitoring log and surfaced as a health status instead of
-- crashing handlers. All SQL uses parameter placeholders.

local Db = {}
Carnival.Db = Db

Db.healthy = true
Db.lastError = nil
Db.lastErrorAt = nil
Db.lastOkAt = nil
Db.errorCount = 0

Db.MIGRATIONS = {
    { version = 1, name = 'initial', file = 'sql/migrations/001_initial.sql' },
    { version = 2, name = 'seed_attractions', file = 'sql/migrations/002_seed_attractions.sql' },
}

local function shorten(sql)
    sql = tostring(sql):gsub('%s+', ' ')
    if #sql > 160 then sql = sql:sub(1, 160) .. '...' end
    return sql
end

local function onError(sql, err)
    Db.healthy = false
    Db.lastError = tostring(err)
    Db.lastErrorAt = os.time()
    Db.errorCount = Db.errorCount + 1
    if Carnival.Monitor then
        -- avoid recursion: monitoring writes are queued, not immediate
        Carnival.Monitor.log('error', 'database', 'query_failed', { details = { sql = shorten(sql), error = tostring(err) }, noPersist = false })
    else
        print(('^1[blacklist_carnival] database error: %s (%s)^0'):format(tostring(err), shorten(sql)))
    end
end

local function onOk()
    Db.healthy = true
    Db.lastOkAt = os.time()
end

local function wrap(fnName)
    return function(sql, params)
        local ok, res = pcall(MySQL[fnName].await, sql, params or {})
        if not ok then
            onError(sql, res)
            return nil, res
        end
        onOk()
        return res
    end
end

Db.query = wrap('query')     -- rows
Db.single = wrap('single')   -- first row or nil
Db.scalar = wrap('scalar')   -- first column of first row
Db.insert = wrap('insert')   -- insert id
Db.update = wrap('update')   -- affected rows

-- queries: list of { query = sql, values = params }
-- Returns true if all statements were committed.
function Db.transaction(queries)
    local ok, res = pcall(MySQL.transaction.await, queries)
    if not ok then
        onError(queries[1] and queries[1].query or 'transaction', res)
        return false, res
    end
    if res ~= true then
        -- oxmysql returns false when the transaction was rolled back (e.g. duplicate key)
        return false, 'rolled_back'
    end
    onOk()
    return true
end

-- Sentinel for "set this column to NULL" in buildUpdate rows.
Db.NULL = setmetatable({}, { __tostring = function() return 'NULL' end })

-- Build an INSERT from a column->value map. Nil values are simply omitted so the
-- parameter array never contains holes; Db.NULL emits a literal NULL. Column
-- names always come from code, never from user input.
function Db.buildInsert(tableName, row)
    local cols, ph, params = {}, {}, {}
    local keys = {}
    for col in pairs(row) do keys[#keys + 1] = col end
    table.sort(keys)
    for _, col in ipairs(keys) do
        local v = row[col]
        cols[#cols + 1] = col
        if v == Db.NULL then
            ph[#ph + 1] = 'NULL'
        else
            ph[#ph + 1] = '?'
            params[#params + 1] = v
        end
    end
    return ('INSERT INTO %s (%s) VALUES (%s)'):format(tableName, table.concat(cols, ', '), table.concat(ph, ', ')), params
end

-- Build an UPDATE. `set` is a column->value map (Db.NULL for NULL), `where` a SQL
-- fragment with ? placeholders and `whereParams` its values.
function Db.buildUpdate(tableName, set, where, whereParams)
    local parts, params = {}, {}
    local keys = {}
    for col in pairs(set) do keys[#keys + 1] = col end
    table.sort(keys)
    for _, col in ipairs(keys) do
        local v = set[col]
        if v == Db.NULL then
            parts[#parts + 1] = col .. ' = NULL'
        else
            parts[#parts + 1] = col .. ' = ?'
            params[#params + 1] = v
        end
    end
    for _, v in ipairs(whereParams or {}) do params[#params + 1] = v end
    return ('UPDATE %s SET %s WHERE %s'):format(tableName, table.concat(parts, ', '), where), params
end

function Db.insertRow(tableName, row)
    local sql, params = Db.buildInsert(tableName, row)
    return Db.insert(sql, params)
end

function Db.updateRow(tableName, set, where, whereParams)
    local sql, params = Db.buildUpdate(tableName, set, where, whereParams)
    return Db.update(sql, params)
end

function Db.ping()
    local res = Db.scalar('SELECT 1')
    return res ~= nil
end

function Db.encode(v)
    if v == nil then return nil end
    return json.encode(v)
end

function Db.decode(s, fallback)
    if type(s) ~= 'string' or s == '' then return fallback end
    local ok, v = pcall(json.decode, s)
    if ok and v ~= nil then return v end
    return fallback
end

-- Split a migration file into statements. Comments starting with -- are removed;
-- statements end with a semicolon at the end of a line.
function Db.splitStatements(sqlText)
    local statements = {}
    local buf = {}
    for line in (sqlText .. '\n'):gmatch('([^\n]*)\n') do
        local trimmed = line:gsub('^%s+', '')
        if trimmed:sub(1, 2) ~= '--' then
            buf[#buf + 1] = line
            if line:match(';%s*$') then
                local stmt = table.concat(buf, '\n'):gsub(';%s*$', '')
                if stmt:match('%S') then statements[#statements + 1] = stmt end
                buf = {}
            end
        end
    end
    local rest = table.concat(buf, '\n')
    if rest:match('%S') then statements[#statements + 1] = rest end
    return statements
end

local function checksum(text)
    -- Small non-cryptographic checksum (FNV-1a 32-bit) used to detect edited migrations.
    local h = 2166136261
    for i = 1, #text do
        h = h ~ text:byte(i)
        h = (h * 16777619) & 0xffffffff
    end
    return string.format('%08x', h)
end
Db.checksum = checksum

-- Apply all pending migrations. Safe to call repeatedly: tables are created with
-- IF NOT EXISTS and each migration is recorded once applied.
function Db.migrate()
    local resource = GetCurrentResourceName()
    local ok, err = pcall(MySQL.query.await, [[CREATE TABLE IF NOT EXISTS carnival_schema_migrations (
        version INT UNSIGNED NOT NULL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        checksum VARCHAR(64) NULL,
        applied_at BIGINT UNSIGNED NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    if not ok then return false, err end

    local applied = {}
    local rows = MySQL.query.await('SELECT version, checksum FROM carnival_schema_migrations')
    for _, r in ipairs(rows or {}) do applied[tonumber(r.version)] = r.checksum end

    for _, m in ipairs(Db.MIGRATIONS) do
        local text = LoadResourceFile(resource, m.file)
        if not text then return false, ('migration file missing: %s'):format(m.file) end
        local sum = checksum(text)
        if applied[m.version] then
            if applied[m.version] ~= sum and Carnival.Monitor then
                Carnival.Monitor.log('warning', 'database', 'migration_modified', { details = { version = m.version, file = m.file } })
            end
        else
            for i, stmt in ipairs(Db.splitStatements(text)) do
                local sok, serr = pcall(MySQL.query.await, stmt)
                if not sok then
                    return false, ('migration %d statement %d failed: %s'):format(m.version, i, tostring(serr))
                end
            end
            MySQL.insert.await('INSERT INTO carnival_schema_migrations (version, name, checksum, applied_at) VALUES (?, ?, ?, ?)',
                { m.version, m.name, sum, os.time() })
            if Carnival.Monitor then
                Carnival.Monitor.log('info', 'database', 'migration_applied', { details = { version = m.version, name = m.name } })
            end
        end
    end
    Db.healthy = true
    Db.lastOkAt = os.time()
    return true
end

function Db.schemaVersion()
    return Db.scalar('SELECT MAX(version) FROM carnival_schema_migrations') or 0
end

function Db.status()
    return {
        healthy = Db.healthy,
        lastError = Db.lastError,
        lastErrorAt = Db.lastErrorAt,
        lastOkAt = Db.lastOkAt,
        errorCount = Db.errorCount,
    }
end

-- Periodic health check so the dashboard reflects reality when idle.
CreateThread(function()
    while true do
        Wait(60000)
        if Carnival.ready then Db.ping() end
    end
end)
