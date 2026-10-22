-- Carnival of the Damned - consumables (server only).
--
-- What each carnival food and drink does when eaten. Edit the numbers, restart
-- the resource, and that's it: nothing needs changing in ox_inventory beyond
-- pasting the item definitions once (they only point at this resource).
--
-- Per item:
--   hunger, thirst  0-100 points added to the QBX hunger / thirst (100 = full).
--   stress          points added to QBX stress; negative calms the player down.
--   armour          body armour added (0-100, capped at 100).
--   health          health restored (0-100; 100 = from near death to full).
--   time            how long eating takes, in milliseconds.
--   anim            'eat', 'drink', or a custom { dict = '...', clip = '...', flag = 49 }.
--   prop            hand prop: { model = '...', pos = { x, y, z }, rot = { x, y, z }, bone = 18905 }.
--                   Leave it out for no prop.
--   label           progress bar text ("Eating ..." by default).
--   message         notification after eating (optional).
--
-- Your own items can use this too: give the item `server = { export =
-- 'blacklist_carnival.useFood' }` in ox_inventory/data/items.lua and add an
-- entry below with the item's name.

local HAND = 18905 -- left hand

local function prop(model, x, y, z, rx, ry, rz)
    return { model = model, pos = { x = x, y = y, z = z }, rot = { x = rx or 0.0, y = ry or 0.0, z = rz or 0.0 }, bone = HAND }
end

Config.Consumables = {
    -- Food --------------------------------------------------------------------
    carnival_bloodfloss = {
        hunger = 15, thirst = 0, stress = -5, armour = 0, health = 0,
        time = 3000, anim = 'eat', prop = prop('prop_candy_pqs', 0.13, 0.05, 0.02, -50.0, 16.0, 60.0),
        message = 'The floss melts like it was never there.',
    },
    carnival_poison_apple = {
        hunger = 25, thirst = 0, stress = 0, armour = 0, health = 0,
        time = 4000, anim = 'eat', prop = prop('prop_amb_donut', 0.13, 0.05, 0.02, -50.0, 16.0, 60.0),
        message = 'Crunchy. Sour. You feel fine. For now.',
    },
    carnival_finger_dog = {
        hunger = 35, thirst = -5, stress = 0, armour = 0, health = 0,
        time = 4000, anim = 'eat', prop = prop('prop_cs_hotdog_01', 0.13, 0.05, 0.02, -50.0, 16.0, 60.0),
        message = 'Surprisingly good, considering.',
    },
    carnival_grave_popcorn = {
        hunger = 20, thirst = -5, stress = -5, armour = 0, health = 0,
        time = 3500, anim = 'eat', prop = prop('prop_candy_pqs', 0.13, 0.05, 0.02, -50.0, 16.0, 60.0),
        message = 'A handful of popcorn, half of it black as soot.',
    },
    carnival_bone_pretzel = {
        hunger = 30, thirst = -5, stress = 0, armour = 0, health = 0,
        time = 4000, anim = 'eat', prop = prop('prop_sandwich_01', 0.13, 0.05, 0.02, -50.0, 16.0, 60.0),
        message = 'Salty, chewy and only a little bit ominous.',
    },
    carnival_web_cake = {
        hunger = 40, thirst = 0, stress = -10, armour = 0, health = 0,
        time = 4500, anim = 'eat', prop = prop('prop_amb_donut', 0.13, 0.05, 0.02, -50.0, 16.0, 60.0),
        message = 'Sugar dust everywhere. The spider was decorative. You hope.',
    },
    carnival_eyeball_pop = {
        hunger = 10, thirst = 0, stress = -5, armour = 0, health = 0,
        time = 2500, anim = 'eat', prop = prop('prop_choc_ego', 0.13, 0.05, 0.02, -50.0, 16.0, 60.0),
        message = 'It stopped staring at you. Eventually.',
    },

    -- Drinks ------------------------------------------------------------------
    carnival_witch_brew = {
        hunger = 0, thirst = 30, stress = 0, armour = 0, health = 0,
        time = 3500, anim = 'drink', prop = prop('prop_food_bs_juice01', 0.03, 0.0, 0.02, 0.0, -13.5, -1.5),
        message = 'Fizzy, sour and faintly glowing.',
    },
    carnival_blood_slushie = {
        hunger = 0, thirst = 35, stress = -5, armour = 0, health = 0,
        time = 3500, anim = 'drink', prop = prop('prop_food_bs_juice01', 0.03, 0.0, 0.02, 0.0, -13.5, -1.5),
        message = 'Brain freeze, the carnival way.',
    },
    carnival_grave_shake = {
        hunger = 15, thirst = 25, stress = -10, armour = 5, health = 0,
        time = 4500, anim = 'drink', prop = prop('prop_food_bs_juice01', 0.03, 0.0, 0.02, 0.0, -13.5, -1.5),
        message = 'You dug all the way to the bottom.',
    },
}

-- Named animations for `anim = 'eat'` / `anim = 'drink'`.
Config.ConsumableAnims = {
    eat = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', flag = 49 },
    drink = { dict = 'mp_player_intdrink', clip = 'loop_bottle', flag = 49 },
}
