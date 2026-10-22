-- Carnival of the Damned item definitions for ox_inventory.
-- Paste the entries below INSIDE the table returned by ox_inventory/data/items.lua
-- (for example just before its final closing brace). Do not replace the file.
-- Generated from blacklist_carnival/items/items.lua - keep the two in sync.

-- Coloured entry tickets: unique per player (stack = false) and carry server-
-- validated metadata (serial, eventId, participantId, colour, holder).
['carnival_ticket_red'] = {
    label = 'Red Carnival Ticket', weight = 5, stack = false, close = true, consume = 0,
    description = 'Admit one. Red group, Carnival of the Damned. Show it at every attraction.',
    server = { export = 'blacklist_carnival.useTicket' },
},
['carnival_ticket_blue'] = {
    label = 'Blue Carnival Ticket', weight = 5, stack = false, close = true, consume = 0,
    description = 'Admit one. Blue group, Carnival of the Damned. Show it at every attraction.',
    server = { export = 'blacklist_carnival.useTicket' },
},
['carnival_ticket_green'] = {
    label = 'Green Carnival Ticket', weight = 5, stack = false, close = true, consume = 0,
    description = 'Admit one. Green group, Carnival of the Damned. Show it at every attraction.',
    server = { export = 'blacklist_carnival.useTicket' },
},
['carnival_ticket_yellow'] = {
    label = 'Yellow Carnival Ticket', weight = 5, stack = false, close = true, consume = 0,
    description = 'Admit one. Yellow group, Carnival of the Damned. Show it at every attraction.',
    server = { export = 'blacklist_carnival.useTicket' },
},
['carnival_ticket_purple'] = {
    label = 'Purple Carnival Ticket', weight = 5, stack = false, close = true, consume = 0,
    description = 'Admit one. Purple group, Carnival of the Damned. Show it at every attraction.',
    server = { export = 'blacklist_carnival.useTicket' },
},
['carnival_ticket_orange'] = {
    label = 'Orange Carnival Ticket', weight = 5, stack = false, close = true, consume = 0,
    description = 'Admit one. Orange group, Carnival of the Damned. Show it at every attraction.',
    server = { export = 'blacklist_carnival.useTicket' },
},

-- House of Horrors keepsakes (only given when "physical tokens" is enabled).
-- Points are tracked by the server; these have no points value.
['carnival_token_bronze'] = {
    label = 'Bronze Horror Token', weight = 20, stack = true, close = true, consume = 0,
    description = 'A tarnished coin pulled from the House of Horrors. A keepsake only.',
    server = { export = 'blacklist_carnival.useToken' },
},
['carnival_token_silver'] = {
    label = 'Silver Horror Token', weight = 20, stack = true, close = true, consume = 0,
    description = 'A cold silver coin from the House of Horrors. A keepsake only.',
    server = { export = 'blacklist_carnival.useToken' },
},
['carnival_token_gold'] = {
    label = 'Gold Horror Token', weight = 20, stack = true, close = true, consume = 0,
    description = 'A gleaming gold coin few survivors ever find. A keepsake only.',
    server = { export = 'blacklist_carnival.useToken' },
},

-- Wheel / prize-tier rewards with real behaviour implemented by this resource.
['carnival_trick_token'] = {
    label = 'Trick Token', weight = 15, stack = true, close = true,
    description = 'Use it if you dare. The carnival enjoys a good trick.',
    client = { usetime = 1200 },
    server = { export = 'blacklist_carnival.useTrickToken' },
},
['carnival_treat_token'] = {
    label = 'Treat Token', weight = 15, stack = true, close = true,
    description = 'A sweet reward. Using it restores a little health.',
    client = { usetime = 1500 },
    server = { export = 'blacklist_carnival.useTreatToken' },
},
['carnival_prize_box'] = {
    label = 'Carnival Prize Box', weight = 250, stack = true, close = true,
    description = 'Sealed with a gold keyhole. Something rattles inside.',
    client = { usetime = 2500 },
    server = { export = 'blacklist_carnival.usePrizeBox' },
},

-- Carnival food sold at the prize counter. Plain ox_inventory consumables:
-- `client.status` feeds hunger/thirst (works with qbx_core's ox_inventory bridge).
['carnival_bloodfloss'] = {
    label = 'Bloodspun Candy Floss', weight = 40, stack = true, close = true,
    description = 'Spun from sugar and something darker. It leaves your lips red.',
    client = {
        status = { hunger = 150000 },
        anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
        prop = { model = 'prop_candy_pqs', pos = vec3(0.02, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) },
        usetime = 3000,
        notification = 'The floss melts like it was never there.',
    },
},
['carnival_poison_apple'] = {
    label = 'Poisoned Toffee Apple', weight = 120, stack = true, close = true,
    description = 'Black toffee over a green apple. The skull on the stick is only a joke. Probably.',
    client = {
        status = { hunger = 250000 },
        anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
        prop = { model = 'prop_amb_donut', pos = vec3(0.02, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) },
        usetime = 4000,
        notification = 'Crunchy. Sour. You feel fine. For now.',
    },
},
['carnival_finger_dog'] = {
    label = 'Severed Finger Corn Dog', weight = 160, stack = true, close = true,
    description = 'Battered, fried and dressed in ketchup. Do not count the knuckles.',
    client = {
        status = { hunger = 350000 },
        anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
        prop = { model = 'prop_cs_hotdog_01', pos = vec3(0.02, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) },
        usetime = 4000,
        notification = 'Surprisingly good, considering.',
    },
},
['carnival_grave_popcorn'] = {
    label = 'Graveyard Popcorn', weight = 100, stack = true, close = true,
    description = 'Buttered and charcoal-black kernels in a coffin-striped box.',
    client = {
        status = { hunger = 200000 },
        anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
        prop = { model = 'prop_candy_pqs', pos = vec3(0.02, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) },
        usetime = 3500,
        notification = 'A handful of popcorn, half of it black as soot.',
    },
},
['carnival_bone_pretzel'] = {
    label = 'Bone-Knot Pretzel', weight = 140, stack = true, close = true,
    description = 'A soft pretzel twisted into a femur and crusted with salt.',
    client = {
        status = { hunger = 300000 },
        anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
        prop = { model = 'prop_sandwich_01', pos = vec3(0.02, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) },
        usetime = 4000,
        notification = 'Salty, chewy and only a little bit ominous.',
    },
},
['carnival_web_cake'] = {
    label = 'Cobweb Funnel Cake', weight = 180, stack = true, close = true,
    description = 'Fried batter under a web of powdered sugar. Mind the resident.',
    client = {
        status = { hunger = 400000 },
        anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
        prop = { model = 'prop_amb_donut', pos = vec3(0.02, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) },
        usetime = 4500,
        notification = 'Sugar dust everywhere. The spider was decorative. You hope.',
    },
},
['carnival_eyeball_pop'] = {
    label = 'Eyeball Cake Pop', weight = 80, stack = true, close = true,
    description = 'A cake pop that watches you eat it. Raspberry glaze.',
    client = {
        status = { hunger = 120000 },
        anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
        prop = { model = 'prop_choc_ego', pos = vec3(0.02, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) },
        usetime = 2500,
        notification = 'It stopped staring at you. Eventually.',
    },
},
['carnival_witch_brew'] = {
    label = 'Witch\'s Brew Lemonade', weight = 90, stack = true, close = true,
    description = 'Sour green lemonade that will not stop bubbling.',
    client = {
        status = { thirst = 300000 },
        anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
        prop = { model = 'prop_food_bs_juice01', pos = vec3(0.01, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
        usetime = 3500,
        notification = 'Fizzy, sour and faintly glowing.',
    },
},
['carnival_blood_slushie'] = {
    label = 'Blood Moon Slushie', weight = 110, stack = true, close = true,
    description = 'Crushed ice and cherry syrup the colour of an eclipse.',
    client = {
        status = { thirst = 350000 },
        anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
        prop = { model = 'prop_food_bs_juice01', pos = vec3(0.01, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
        usetime = 3500,
        notification = 'Brain freeze, the carnival way.',
    },
},
['carnival_grave_shake'] = {
    label = 'Grave Dirt Shake', weight = 200, stack = true, close = true,
    description = 'Chocolate shake buried under cookie crumbs, gummy worms and a headstone.',
    client = {
        status = { hunger = 150000, thirst = 250000 },
        anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
        prop = { model = 'prop_food_bs_juice01', pos = vec3(0.01, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
        usetime = 4500,
        notification = 'You dug all the way to the bottom.',
    },
},
