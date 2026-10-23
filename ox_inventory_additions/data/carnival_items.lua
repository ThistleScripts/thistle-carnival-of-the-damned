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

-- Prize box: using it opens it. What is inside is set by the server owner in the
-- admin panel (Settings -> Scoring & prizes -> Prize box): how many prizes a box
-- gives and the percentage chance of each.
['carnival_prize_box'] = {
    label = 'Carnival Prize Box', weight = 250, stack = true, close = true,
    description = 'Sealed with a gold keyhole. Something rattles inside.',
    client = { usetime = 2500 },
    server = { export = 'blacklist_carnival.usePrizeBox' },
},

-- Carnival food sold at the prize counter. What each one does (hunger, thirst,
-- stress, armour, health, animation, prop, time) is set in
-- blacklist_carnival/consumables.lua, not here.
['carnival_bloodfloss'] = {
    label = 'Bloodspun Candy Floss', weight = 40, stack = true, close = true,
    description = 'Spun from sugar and something darker. It leaves your lips red.',
    server = { export = 'blacklist_carnival.useFood' },
},
['carnival_poison_apple'] = {
    label = 'Poisoned Toffee Apple', weight = 120, stack = true, close = true,
    description = 'Black toffee over a green apple. The skull on the stick is only a joke. Probably.',
    server = { export = 'blacklist_carnival.useFood' },
},
['carnival_finger_dog'] = {
    label = 'Severed Finger Corn Dog', weight = 160, stack = true, close = true,
    description = 'Battered, fried and dressed in ketchup. Do not count the knuckles.',
    server = { export = 'blacklist_carnival.useFood' },
},
['carnival_grave_popcorn'] = {
    label = 'Graveyard Popcorn', weight = 100, stack = true, close = true,
    description = 'Buttered and charcoal-black kernels in a coffin-striped box.',
    server = { export = 'blacklist_carnival.useFood' },
},
['carnival_bone_pretzel'] = {
    label = 'Bone-Knot Pretzel', weight = 140, stack = true, close = true,
    description = 'A soft pretzel twisted into a femur and crusted with salt.',
    server = { export = 'blacklist_carnival.useFood' },
},
['carnival_web_cake'] = {
    label = 'Cobweb Funnel Cake', weight = 180, stack = true, close = true,
    description = 'Fried batter under a web of powdered sugar. Mind the resident.',
    server = { export = 'blacklist_carnival.useFood' },
},
['carnival_eyeball_pop'] = {
    label = 'Eyeball Cake Pop', weight = 80, stack = true, close = true,
    description = 'A cake pop that watches you eat it. Raspberry glaze.',
    server = { export = 'blacklist_carnival.useFood' },
},
['carnival_witch_brew'] = {
    label = 'Witch\'s Brew Lemonade', weight = 90, stack = true, close = true,
    description = 'Sour green lemonade that will not stop bubbling.',
    server = { export = 'blacklist_carnival.useFood' },
},
['carnival_blood_slushie'] = {
    label = 'Blood Moon Slushie', weight = 110, stack = true, close = true,
    description = 'Crushed ice and cherry syrup the colour of an eclipse.',
    server = { export = 'blacklist_carnival.useFood' },
},
['carnival_grave_shake'] = {
    label = 'Grave Dirt Shake', weight = 200, stack = true, close = true,
    description = 'Chocolate shake buried under cookie crumbs, gummy worms and a headstone.',
    server = { export = 'blacklist_carnival.useFood' },
},
