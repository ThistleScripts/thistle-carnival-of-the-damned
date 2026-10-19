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
