-- Static consistency checks (no database needed). Run from the resource directory:
--   lua5.4 tests/static_checks.lua
-- Verifies:
--   * every file referenced by fxmanifest.lua exists (globs must match >= 1 file)
--   * every Lua file compiles
--   * item names == item definitions == manifest == PNG files (256x256, RGBA)
--   * every API endpoint used by the client Lua and the NUI is registered on the server
--   * every sound referenced by defaults/constants exists as an .ogg
--   * no clown references in shipped content

package.path = './tests/?.lua;' .. package.path
local failures, checks = {}, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures[#failures + 1] = msg end
end

local function read(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('a')
    f:close()
    return s
end

local function ls(dir)
    local out = {}
    local p = io.popen('find "' .. dir .. '" -type f 2>/dev/null')
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

local function glob(pattern)
    local dir, filePat = pattern:match('^(.*)/([^/]*)$')
    local lp = '^' .. filePat:gsub('%.', '%%.'):gsub('%*', '.*') .. '$'
    local out = {}
    local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
    for name in p:lines() do if name:match(lp) then out[#out + 1] = dir .. '/' .. name end end
    p:close()
    return out
end

-- fxmanifest --------------------------------------------------------------------
local m = { shared = {}, server = {}, client = {}, files = {}, dataFiles = {} }
local env = setmetatable({}, { __index = function(_, k)
    return function(arg)
        if k == 'data_file' then return function(path) m.dataFiles[#m.dataFiles + 1] = path end end
        if k == 'shared_scripts' then m.shared = arg
        elseif k == 'server_scripts' then m.server = arg
        elseif k == 'client_scripts' then m.client = arg
        elseif k == 'files' then m.files = arg
        elseif k == 'ui_page' then m.ui = arg end
        return function() end
    end
end })
assert(loadfile('fxmanifest.lua', 't', env))()
local all = {}
for _, list in ipairs({ m.shared, m.server, m.client, m.files, m.dataFiles }) do
    for _, f in ipairs(list) do all[#all + 1] = f end
end
-- every streamed coin prop is complete (model, textures, archetype) and declared
for _, c in ipairs({ 'bronze', 'silver', 'gold' }) do
    for _, ext in ipairs({ 'ydr', 'ytd', 'ytyp' }) do
        check(read('stream/carnivalcoin' .. c .. '.' .. ext) ~= nil, 'stream file missing: carnivalcoin' .. c .. '.' .. ext)
    end
    local declared = false
    for _, f in ipairs(m.dataFiles) do if f == 'stream/carnivalcoin' .. c .. '.ytyp' then declared = true end end
    check(declared, 'coin archetype not loaded with data_file: ' .. c)
end
all[#all + 1] = m.ui
for _, f in ipairs(all) do
    if not f:match('^@') then
        if f:find('%*') then
            check(#glob(f) > 0, 'manifest glob matches nothing: ' .. f)
        else
            check(read(f) ~= nil, 'manifest file missing: ' .. f)
        end
    end
end

-- Lua compiles -----------------------------------------------------------------
for _, f in ipairs(ls('.')) do
    if f:match('%.lua$') and not f:match('node_modules') then
        local ok, err = loadfile(f)
        check(ok ~= nil, 'syntax error: ' .. tostring(err))
    end
end

-- Items ---------------------------------------------------------------------------
Carnival = {}
dofile('shared/constants.lua')
local C = Carnival.C
local defs = dofile('items/items.lua')
local manifest = require('dkjson').decode(read('items/item-manifest.json'))
local manifestNames = {}
for _, it in ipairs(manifest.items) do manifestNames[it.name] = it.image end
for _, name in ipairs(C.CUSTOM_ITEMS) do
    check(defs[name] ~= nil, 'item definition missing: ' .. name)
    check(manifestNames[name] == name .. '.png', 'manifest entry wrong: ' .. name)
    local png = read('images/inventory/' .. name .. '.png')
    check(png ~= nil, 'image missing: ' .. name)
    if png then
        check(png:sub(1, 8) == '\137PNG\r\n\26\n', 'not a PNG: ' .. name)
        local w = string.unpack('>I4', png, 17)
        local h = string.unpack('>I4', png, 21)
        local colourType = png:byte(26)
        check(w == 256 and h == 256, ('image %s is %dx%d'):format(name, w, h))
        check(colourType == 6, 'image is not RGBA (transparent): ' .. name)
    end
    check(read('../ox_inventory_additions/web/images/' .. name .. '.png') == png, 'ox_inventory copy differs: ' .. name)
    if defs[name] and defs[name].server then
        local export = defs[name].server.export:match('^blacklist_carnival%.(.+)$')
        check(export and read('server/inventory.lua'):find("exports%('" .. export .. "'"), 'item export not implemented: ' .. tostring(export))
    end
    if C.TICKET_ITEM_COLOUR[name] then
        check(defs[name].stack == false, 'tickets must not stack: ' .. name)
    end
end
for name in pairs(defs) do check(manifestNames[name], 'definition not in manifest: ' .. name) end
local snippet = read('../ox_inventory_additions/data/carnival_items.lua')
check(snippet ~= nil, 'ox_inventory snippet missing')
for _, name in ipairs(C.CUSTOM_ITEMS) do check(snippet and snippet:find("%['" .. name .. "'%]"), 'snippet missing ' .. name) end

-- Endpoints -------------------------------------------------------------------------
local registered = {}
for _, f in ipairs(ls('server')) do
    local src = read(f)
    for name in src:gmatch("Api%.register%('([%w%._]+)'") do registered[name] = true end
    for name in src:gmatch("Api%.register%('([%w%._]+)' %.%.") do registered[name] = true end
end
-- endpoints registered in loops
for _, a in ipairs({ 'display', 'start', 'pause', 'resume', 'end' }) do registered['theatre.' .. a] = true end
for _, a in ipairs({ 'start', 'end', 'clue', 'reveal' }) do registered['deception.' .. a] = true end
for _, a in ipairs({ 'approve', 'retry', 'markDelivered', 'resetPending', 'cancel' }) do registered['rewards.' .. a] = true end

local used = {}
for _, f in ipairs(ls('client')) do
    for name in read(f):gmatch("Carnival%.api[%w]*%('([%w%._]+)'") do used[name] = f end
end
for _, f in ipairs(ls('web/src')) do
    local src = read(f)
    for _, pat in ipairs({ "useApi%b<>%('([%w%._]+)'", "useApi%('([%w%._]+)'", "[^%w]api%('([%w%._]+)'", "api%b<>%('([%w%._]+)'", "run%('([%w%._]+)'", "run%b<>%('([%w%._]+)'" }) do
        for name in src:gmatch(pat) do used[name] = f end
    end
end
local n = 0
for name, f in pairs(used) do
    n = n + 1
    check(registered[name], ('endpoint %s used in %s is not registered on the server'):format(name, f))
end
check(n > 60, 'expected to find the NUI endpoints (found ' .. n .. ')')

-- Columns written by the server exist in the schema ---------------------------------------
local schemaCols = {}
for _, f in ipairs(ls('sql/migrations')) do
    local sql = read(f)
    for tname, body in sql:gmatch('CREATE TABLE IF NOT EXISTS (%w[%w_]*) %((.-)\n%) ENGINE') do
        schemaCols[tname] = schemaCols[tname] or {}
        for line in body:gmatch('[^\n]+') do
            local col = line:match('^%s*([a-z_]+) ')
            if col and col ~= 'KEY' then schemaCols[tname][col] = true end
        end
    end
    for tname, col in sql:gmatch('ALTER TABLE (%w[%w_]*)(.-);') do
        schemaCols[tname] = schemaCols[tname] or {}
        for c in col:gmatch('ADD COLUMN ([a-z_]+)') do schemaCols[tname][c] = true end
    end
end
-- top-level keys of the table literal starting at position i (which is '{')
local function topKeys(src, i)
    local keys, depth, j = {}, 0, i
    while j <= #src do
        local ch = src:sub(j, j)
        if ch == '{' then depth = depth + 1
        elseif ch == '}' then depth = depth - 1 if depth == 0 then break end
        elseif depth == 1 then
            local k = src:match('^([%a_][%w_]*)%s*=', j)
            if k and src:sub(j - 1, j - 1):match('[%s,{]') then keys[#keys + 1] = k end
        end
        j = j + 1
    end
    return keys
end
local LOCAL_WRITERS = {
    ['server/attractions/puppets.lua'] = { 'persist%(perf, ', 'carnival_theatre_performances' },
    ['server/attractions/deception.lua'] = { 'persist%(', 'carnival_deception_rounds' },
    ['server/attractions/horror.lua'] = { 'persistRun%(', 'carnival_horror_runs' },
    ['server/rotation_manager.lua'] = { 'setSession%(s, ', 'carnival_attraction_sessions' },
}
for _, f in ipairs(ls('server')) do
    local src = read(f)
    local rel = f:gsub('^%./', '')
    local pos = 1
    while true do
        local s1, e1, tname = src:find("[iu][np][sd]%a+Row%('([%w_]+)', ", pos)
        local s2, e2, tname2 = src:find("build%a+%('([%w_]+)', ", pos)
        if not s1 and not s2 then break end
        local s, e, t = s1, e1, tname
        if not s1 or (s2 and s2 < s1) then s, e, t = s2, e2, tname2 end
        if src:sub(e + 1, e + 1) == '{' and schemaCols[t] then
            for _, k in ipairs(topKeys(src, e + 1)) do check(schemaCols[t][k], ('%s writes unknown column %s.%s'):format(rel, t, k)) end
        end
        pos = e + 1
    end
    local lw = LOCAL_WRITERS[rel]
    if lw then
        local p2 = 1
        while true do
            local s, e = src:find(lw[1] .. '{', p2)
            if not s then break end
            for _, k in ipairs(topKeys(src, e)) do check(schemaCols[lw[2]][k], ('%s writes unknown column %s.%s'):format(rel, lw[2], k)) end
            p2 = e + 1
        end
    end
end
check(next(schemaCols) ~= nil, 'schema parsed')

-- Sounds ------------------------------------------------------------------------------
for _, s in ipairs(C.SOUNDS) do
    check(read('web/public/sounds/' .. s .. '.ogg') ~= nil, 'sound missing: ' .. s)
    check(read('web/dist/sounds/' .. s .. '.ogg') ~= nil, 'sound missing from built NUI: ' .. s)
end

-- No clowns in shipped content (docs that state the rule are excluded) ------------------
for _, f in ipairs(ls('.')) do
    if not f:match('node_modules') and not f:match('%.png$') and not f:match('%.ogg$') and not f:match('/tests/')
        and not f:match('/docs/') and not f:match('README') and not f:match('/assets/') then
        local s = (read(f) or ''):lower()
        check(not s:find('clown') and not s:find('s_m_y_clown'), 'clown reference in ' .. f)
    end
end

-- NUI build present ----------------------------------------------------------------------
check(read('web/dist/index.html') and read('web/dist/index.html'):find('./assets/'), 'NUI build missing or not using relative paths')

print(('%d checks, %d failures'):format(checks, #failures))
for _, f in ipairs(failures) do print('  FAIL ' .. f) end
os.exit(#failures == 0 and 0 or 1)
