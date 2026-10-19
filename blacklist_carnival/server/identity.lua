-- Player identity resolution (QBX).
--
-- Stable identities:
--   * participants are keyed by QBX character citizenid (per event)
--   * staff / permissions are keyed by Rockstar license (license2 preferred)
-- The transient FiveM source id is only used for routing messages.

local Identity = {}
Carnival.Identity = Identity

Identity.SYSTEM = { license = 'system', name = 'System', source = 0 }

local function qbxPlayer(src)
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if ok then return player end
    return nil
end
Identity.qbxPlayer = qbxPlayer

function Identity.license(src)
    if not src or src <= 0 then return nil end
    local l = GetPlayerIdentifierByType(tostring(src), 'license2') or GetPlayerIdentifierByType(tostring(src), 'license')
    return l
end

-- All license-type identifiers of a player (for allowlist matching).
function Identity.licenses(src)
    local out = {}
    for _, t in ipairs({ 'license', 'license2' }) do
        local id = GetPlayerIdentifierByType(tostring(src), t)
        if id then out[#out + 1] = id end
    end
    return out
end

function Identity.citizenid(src)
    local p = qbxPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

function Identity.characterName(src)
    local p = qbxPlayer(src)
    local ci = p and p.PlayerData and p.PlayerData.charinfo
    if ci and ci.firstname then
        return Carnival.U.sanitizeText(('%s %s'):format(ci.firstname, ci.lastname or ''), 96)
    end
    return Carnival.U.sanitizeText(GetPlayerName(src) or ('Player ' .. tostring(src)), 96)
end

-- Actor descriptor used for audit / monitoring records.
function Identity.actor(src)
    if not src or src <= 0 then return Identity.SYSTEM end
    return {
        source = src,
        license = Identity.license(src) or ('src:' .. tostring(src)),
        name = Identity.characterName(src),
    }
end

-- Full participant-oriented identity. Returns nil if the player has no loaded character.
function Identity.get(src)
    local cid = Identity.citizenid(src)
    if not cid then return nil end
    return {
        source = src,
        citizenid = cid,
        license = Identity.license(src),
        name = Identity.characterName(src),
    }
end

function Identity.online()
    local out = {}
    for _, s in ipairs(GetPlayers()) do out[#out + 1] = tonumber(s) end
    return out
end

function Identity.pedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

-- Server-side distance check against a configured point.
function Identity.within(src, point, maxDist)
    local c = Identity.pedCoords(src)
    if not c or not point then return false, nil end
    local d = Carnival.U.dist3(c, point)
    return d <= maxDist, d
end
