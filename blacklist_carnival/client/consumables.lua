-- Eating carnival food: the server sends the animation, prop and time from
-- consumables.lua; we play the progress bar and hand the token back. The
-- server removes the item and applies hunger/thirst/stress, then we add the
-- armour and health it allows.

local eating = false

Carnival.onPush('consume', function(data)
    if eating or type(data) ~= 'table' or type(data.token) ~= 'string' then return end
    eating = true
    CreateThread(function()
        local opts = {
            duration = data.time or 3000,
            label = data.label or 'Eating',
            useWhileDead = false,
            canCancel = true,
            disable = { combat = true, sprint = true },
        }
        if data.anim then opts.anim = { dict = data.anim.dict, clip = data.anim.clip, flag = data.anim.flag or 49 } end
        if data.prop then
            local p = data.prop
            opts.prop = {
                model = p.model, bone = p.bone or 18905,
                pos = vec3(p.pos.x, p.pos.y, p.pos.z), rot = vec3(p.rot.x, p.rot.y, p.rot.z),
            }
        end
        local done = lib.progressBar(opts)
        eating = false
        if not done then return end
        local res, code, msg = Carnival.api('food.finish', { token = data.token })
        if not res then
            if code ~= 'invalid' then lib.notify({ title = 'Carnival', description = msg or code, type = 'error' }) end
            return
        end
        local ped = PlayerPedId()
        if (res.armour or 0) > 0 then
            SetPedArmour(ped, math.min(100, GetPedArmour(ped) + res.armour))
        end
        if (res.health or 0) > 0 then
            -- GTA health runs from 100 (down) to GetEntityMaxHealth (usually 200)
            local max = GetEntityMaxHealth(ped)
            local add = math.floor((max - 100) * res.health / 100)
            SetEntityHealth(ped, math.min(max, GetEntityHealth(ped) + add))
        end
        if res.message then lib.notify({ title = 'Carnival', description = res.message, type = 'success' }) end
    end)
end)

Carnival.onCleanup(function() eating = false end)
