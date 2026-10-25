# Administrator manual

Open the admin panel with `/carnivaladmin`. **Minimise** hides it so you can walk around (for example to capture coordinates); reopen with the same command. **Escape** closes it.

The games run themselves and staff are actors, so the panel is only for running the carnival as a whole. It has five sections:

| Section | What it is for |
|---|---|
| Overview | Is the carnival open, how many tickets are sold and who is online. The attractions, each with what is happening there and a **Close/Reopen** button. Who is playing where right now, the top of the board and the latest scores. Pause, end the night or cancel. |
| Players | **Participants** (search, open a player: ticket, route, scores, prizes; transfer, replace ticket, remove/reinstate, adjust score), the full **Leaderboard**, the **Score ledger** (every transaction, reversals, *Verify ledger*) and **Prize deliveries** (retry, reconcile, cancel). |
| Nights & results | Every carnival night: results (versioned), CSV export, state history and settings snapshots. *Use as template* creates a new night from an old one. |
| Settings | **Carnival** (general, ticket booth, ticket colours, rotation, audio), **Attractions** (pick an attraction from the chips: location, NPC, rules and content), **Scoring & prizes** and **Props** (the prop placer). |
| System | **Health & items** (database, dependencies, errors, item check), **Roles**, **Monitoring** and **Audit trail**. |

What you see depends on your role (see PERMISSIONS.md); every action is checked again on the server.

## Running with no staff

In walk-up mode (the default) the whole cycle runs by itself:

1. **Opens.** A carnival night opens on its own and the ticket booth sells tickets.
2. **Plays.** Players walk up to each game on their ticket and play; every game runs itself.
3. **Ends the night.** At *Rotation → Walk-up mode → end the night* (default: **daily at 04:00 server time**; or after a number of hours; or `manual`). Games still in progress get up to *grace minutes* (default 15) to finish. A night nobody played simply starts over with no results.
4. **Hands out prizes.** The results are frozen, the final results banner shows for 30 seconds and the prize tiers are delivered. A prize that cannot be handed over (full pockets, or the winner is offline) is retried every *retry minutes* (default 5) while they are online and when they log in, from any night.
5. **Opens again.** After *close the books* (default 2 minutes) a fresh night opens and players buy new tickets. Prize tickets and the prize counter carry on between nights.

**First-time setup.** The Overview shows a **Finish setting up** card until the carnival can run on its own: dependencies running, items added to ox_inventory, the booth, prize counter and attractions moved off the placeholder pier positions, the House of Horrors maze and coins placed, the ambient zones placed, and nights ending by themselves.

**What still needs a person, rarely:** a prize delivery cut off by a server restart (status *unknown*) is never retried automatically, because it may already have reached the player. Check those under *Players → Prize deliveries*. Everything else is optional: actors can roleplay around the games, and admins can still pause, end a night early, close an attraction or adjust scores from the panel.

## Carnival mode: walk-up or scheduled

*General → Carnival mode* decides how the carnival runs.

**Walk-up (default): no staff needed.**
* When no event is active, the server creates a walk-up event and moves it straight to *running* (the transitions are recorded with the actor `system`). Registration stays open while it runs.
* A player buys a ticket at the booth and gets a colour. That colour's column of the rotation matrix is their personal order of games; the HUD and `/carnival` show the next one and set a waypoint.
* The player targets the next game's ped and plays. When they finish, their ticket moves on to the next game. They cannot play out of order (unless *Rotation → Walk-up mode → enforce order* is off), and they cannot repeat a game.
* Individual games (gallery, wheel, fortune) complete per player. Group games (theatre, Hall of Deception, House of Horrors) gather whoever arrives for that game during the lobby, run, then complete for everyone who took part. Nobody can join a show, maze run or mystery that is already under way.
* An attraction that is disabled or closed from the Overview is passed over; the player plays the next one and comes back to it later.
* A visit nobody is playing is closed after *idle seconds* without counting as played, so the player can start again.
* Restarts do not pause a walk-up event.
* The night ends by itself on schedule (see *Running with no staff*). To end it early, press **End the night** on the Overview. The results are frozen and every player sees the final results banner for 30 seconds (it closes by itself); the HUD disappears. After *Rotation → Walk-up mode → open a fresh carnival after* (default 120 s) the books close by themselves and a fresh carnival opens (players buy a new ticket). Set it to 0 to keep the results up until an admin presses *Close the books*.
* To stop the carnival opening again, switch the mode to *scheduled* first. While the walk-up event runs, the rotation matrix and colours may still be edited, because players progress individually.

**Scheduled (timed rounds).** An admin creates the night and moves it through the lifecycle below; each colour group visits one attraction per round. The games still run themselves; a round that ends while a show, mystery or maze run is in progress waits for it to finish ("overtime").

## Event lifecycle

```
configuring → registration open ⇄ registration closed → ready → running ⇄ paused
                                                          running → between rounds → running …
                                         running / paused / between rounds → final results → completed
                                         (any non-final state) → cancelled (reason required)
```

* **Registration open** requires the ticket items to be registered (unless virtual tickets).
* **Ready** requires at least one participant and every participant to have a colour.
* **Running** starts round 1 and snapshots the effective settings.
* **Pause** freezes the round timer and every attraction timer; **Resume** restores them exactly.
* **Final results** closes open sessions, freezes the leaderboard as results version 1 and (if enabled) creates prize-tier rewards. Corrections made during final results create a new results version — old versions are kept.
* **Completed** is permanent; results and history stay viewable forever. Starting a new event never touches old ones.
* After a server/resource restart a timed-round event comes back **paused** (walk-up carnivals stay open). Horror runs and shooting games that were in progress are marked *interrupted* (never restarted automatically); prizes caught mid-delivery become *unknown* and need reconciliation under Players → Prize deliveries.

Recovery tools (Nights & results, active night): reload state from the database, force pause, flag interrupted prize deliveries.

## Configuration

* **Scope.** *Global defaults* apply to every event. *This event only* creates an event-specific copy for the active event; *Use global settings* removes it.
* **Preview** shows exactly which settings change (secret values hidden), flags settings that need an attraction reset (`reset`) and settings locked while the event is in progress (`locked live`: rotation matrix, colour enable flags, virtual tickets).
* **Save** validates everything on the server (types, ranges, rotation matrix, wheel weights, fortune answers, mystery liar counts, item names in ox_inventory…). Errors are highlighted on the fields. Large or reset-requiring changes ask for confirmation.
* **Versions** lists every saved version; *Roll back* creates a new version with the old values (nothing is deleted). All saves are audited.
* **Use my position** on any coordinate field captures your current position (feet level) and heading.
* Secret fields (mystery answer keys, briefs, statements, fortune answers, wheel weights) are hidden from users without the matching permission and preserved when they save.

### Attraction settings at a glance

* **Shooting Gallery** — a game is **several rounds, each harder than the last** (*Rounds*, 1-5, plus *break between rounds*). Each round has its own name, length, number of targets, lanes, crossing speed, target size, golden target and spirit lantern chances, movement (`straight`, or `wave` where targets bob as they cross) and a *points multiplier*. The factory game is three 20-second rounds:

  | Round | Targets | Lanes | Cross time | Size | Lanterns | Movement | Points |
  |---|---|---|---|---|---|---|---|
  | 1 · Warm-up | 14 | 2 | 3.4 s | 100 % | 6 % | straight | ×1 |
  | 2 · Quickfire | 20 | 3 | 2.5 s | 85 % | 14 % | straight | ×1.5 |
  | 3 · Dead Eye | 24 | 3 | 1.9 s | 70 % | 22 % | wave | ×2 |

  Between rounds the screen shows the next round's name, what got harder and its multiplier, with a countdown; clicks during the break are ignored. The result lists the points and hits of every round. Also: games per visit, simultaneous players (player limit), base points per target, bullseye bonus, golden target points, lantern penalty (all multiplied by the round), accuracy bonus, miss penalty, minimum time between shots, max score (default 500).
* **Wheel of Misfortune** — outcomes (label, type, weight, points ±, item + quantity, colour), spins per participant, cooldown, animation length, first-spin bonus.
* **Fortune Teller** — questions per reading, readings per player, cooldown, answer time limit, question pool (multiple choice or riddle with accepted answers, points, wrong-answer penalty, lines), fortunes and whether a fortune scores.
* **Puppet Master's Theatre** — time for players to join the cast, audience vote time, solo points, scenario library (category, difficulty, performer counts, time limit, points range, roles), default length, participation bonus, max award.
* **Hall of Deception** — clue unlock interval, questioning time, accusations per player, default mystery, mysteries (suspects with public profile, testimony and liar flag; clues; rules; liar count; scoring: per correct, penalty, perfect bonus, partial credit, tie-break).
* **House of Horrors** — entry, exit + radius, boundary centre + radius, duration, warning thresholds (any list of seconds), sounds and volume, collection rule (once per player / once globally), token visibility, completion and time bonuses, penalties, keepsake items, token types (points, active quantity, prop model, collection distance, respawn, float height, bob, spin speed, glow colour/radius/brightness) and positions.

### House of Horrors coins

The bronze, silver and gold coins are bundled in `stream/props/` (`carnivalcoinbronze`, `carnivalcoinsilver`, `carnivalcoingold`) and loaded by the resource's manifest. Each coin floats above its token position, bobs, spins and glows in its type's colour. If a model cannot load, a glowing spinning ring is shown instead so tokens are never invisible.

Tune them under *Settings → Attractions → House of Horrors → Token types* (float height, bob, spin speed, glow colour/radius/brightness; a glow radius of 0 turns the light off). Place token positions with **Use my position** while standing where the coin should hover: the position is feet level and the coin floats *float height* above it. To use your own coins instead, drop them into `stream/props/` (see *World props* below) and enter their model names.

Coins are created only within about 60 m of the player, so they are always placed after the area has streamed in.

## World props (prop placer)

Dress the carnival with your own props. Every placed prop is saved in the database (`carnival_props`), survives restarts and is spawned by every player's game when they are within about 150 m, so everyone sees the same thing.

**Adding prop files.** Put each prop's `.ydr`, `.ytd` and `.ytyp` into `blacklist_carnival/stream/props/` next to the coins and restart the resource. Every `.ytyp` in that folder is loaded automatically (`data_file 'DLC_ITYP_REQUEST' 'stream/props/*.ytyp'`), so there is nothing to edit — just keep the files directly in `stream/props/`, not in sub-folders. The model name is the file name without the extension.

**Placing.** *Settings → Props*, type the model name (known models are suggested), optionally a name and whether it is solid, and press **Place in the world**. Or type `/carnivalprop <model> [name]`. The panel minimises and a see-through copy of the prop follows where you look:

| Control | Does |
|---|---|
| Look around | Move the prop (it sits on whatever you are looking at) |
| Mouse wheel | Rotate (hold Shift for 1° steps) |
| Arrow up / down | Raise / lower (hold Shift to move faster) |
| Arrow left / right | Tilt |
| G | Drop it onto the ground |
| X | Reset rotation, tilt and height |
| Enter or left click | Place |
| Backspace or right click | Cancel |

**Moving and removing.** Target a placed prop for *Admin: move prop* / *Admin: remove prop*, or use **Move**, **Waypoint** and **Remove** on the Props list. Every placement, move and removal is in the audit trail; removed props keep their database row. Placing needs the `props.manage` permission (owners and administrators by default); up to 1,000 props can be placed.

## Prize counter and prize tickets

The games pay out **prize tickets**, a currency separate from leaderboard points (like arcade tickets). Set what each game pays under *Settings → Scoring & prizes → Prize counter → Tickets each game pays out*:

| Setting | Meaning | Default |
|---|---|---|
| *Tickets for finishing the game* | Paid once each time a player completes that game. | 3-10 |
| *Tickets per 100 points scored in it* | Paid as points are scored there, so better play wins more tickets. | 20-25 |
| *Most tickets one player can win here per night* | Cap per game per player per night (0 = no cap). | 40-80 |

Staff score adjustments, corrections and the participation bonus never pay tickets, and a replayed score never pays twice. Tickets belong to the character (citizen ID) and **carry over between nights**. Players get a toast ("+12 Prize Tickets from House of Horrors") whenever they win some. The currency name is a setting too.

Players spend tickets at the **prize counter** NPC (location, NPC model and blip in the same settings section). Targeting it opens the prize booth: the ticket balance on a ticket stub, shelves (*Treats*, *Drinks*, *Prizes*, *Curiosities*), the item pictures from ox_inventory, a detail panel with quantity, cost and tickets left after, and a *Win tickets at the games* strip showing what each game pays and how much of tonight's cap the player has already won. `/prizetickets` tells a player their balance, and the player hub (`/carnival`) shows it with a waypoint to the counter.

**Item pictures** are taken from ox_inventory, exactly as the inventory shows them: an item's own `client.image` in `ox_inventory/data/items.lua` (a file name in the image folder or a full URL) if it has one, otherwise `<inventory:imagepath>/<item>.png` (the `inventory:imagepath` convar, default `nui://ox_inventory/web/images`). So any item you sell shows the picture you already gave it in ox_inventory, including images hosted on a CDN; if none loads, a gift icon is shown. The admin *Prize counter* page uses the same pictures.

**Items for sale** are a list of `item`, optional shop name and description (blank = the item's own), *shelf*, price in tickets, *limit per player per day* (0 = none) and *for sale*. Any registered ox_inventory item can be sold, except the carnival tickets. The factory list sells the ten carnival foods plus trick/treat tokens and the prize box.

**Redeeming** is decided by the server: the player must be at the counter, have the tickets and room in their inventory; the tickets are taken and the item handed over, and if the hand-over fails the tickets are refunded straight away. Every win, purchase, refund and adjustment is a row in the prize ledger, and a double-clicked or retried purchase is only charged once.

*Players → Prize counter* (`shop.manage`) shows tickets held, won and spent, purchases in the last 24 hours, best sellers, recent purchases and every wallet. **Adjust** adds or removes tickets with a reason (audited).

### Carnival food (`consumables.lua`)

Ten foods and drinks ship with the resource (images in `images/inventory`, definitions in the ox_inventory snippet). **What each one does is set in `blacklist_carnival/consumables.lua`**, one entry per item:

```lua
carnival_finger_dog = {
    hunger = 35, thirst = -5, stress = 0, armour = 0, health = 0,
    time = 4000, anim = 'eat', prop = prop('prop_cs_hotdog_01', 0.13, 0.05, 0.02, -50.0, 16.0, 60.0),
    message = 'Surprisingly good, considering.',
},
```

| Field | Meaning |
|---|---|
| `hunger`, `thirst` | Points added to the QBX hunger / thirst, 0-100 scale (100 = full). Negative takes some away (salty food makes you thirsty). |
| `stress` | Points added to QBX stress; negative calms the player down. |
| `armour` | Body armour added (capped at 100). |
| `health` | Health restored, as a percentage of a full bar. |
| `time` | How long eating takes, in milliseconds (the progress bar can be cancelled). |
| `anim` | `'eat'`, `'drink'` (defined in `Config.ConsumableAnims` at the bottom of the file) or your own `{ dict = '...', clip = '...', flag = 49 }`. |
| `prop` | Hand prop: model, position and rotation offsets, bone. Leave it out for none. |
| `label` / `message` | Progress bar text (default "Eating <item>") / notification afterwards. |

Restart the resource after editing. Values are clamped to sensible ranges, and an entry with a mistake (for example an unknown `anim`) is skipped with a warning in the server console and the monitoring log, so a typo never breaks the other items. The ox_inventory definitions only point at the resource (`server = { export = 'blacklist_carnival.useFood' }`), so nothing in ox_inventory needs changing when you rebalance.

Eating is checked by the server: using the item starts the progress bar, and the item is only removed and the effects applied when the bar finishes (it cannot be skipped or repeated). Hunger, thirst and stress are written to the QBX character's metadata and state bags; armour and health are applied on the player's ped.

**Your own items** can use the same system: give the item `server = { export = 'blacklist_carnival.useFood' }` in `ox_inventory/data/items.lua` and add an entry with its name to `consumables.lua`.

The food pictures are your own artwork (256×256 transparent PNGs in `images/inventory/`, copied to `ox_inventory_additions/web/images/`). To replace one, save the new PNG under the item name in both folders (and in `ox_inventory/web/images/`). `tools/generate_item_images.py` leaves them alone unless run with `--food-placeholders`.

## Ambient sound

*Settings → Carnival → Ambient sound* holds the **sound zones**: each has a centre (use **Use my position**), a radius, a looping sound and a volume. Players hear a zone at full volume at its centre, fading to silence at its edge; zones overlap and fade smoothly as players walk. The factory zones (midway organ waltz, crowd murmur, Fortune Teller chimes, House of Horrors wind) sit at the default pier positions — move them with your attractions. The loops are original and bundled (`tools/generate_audio.py`); the master volume in *Audio* also applies. Any player can mute the ambience for themselves with `/carnivalambience`.

## Prizes

*Prizes & results* defines rank tiers (from/to rank, label, items). When results freeze, a reward row is created per winner and item (idempotent: re-freezing never duplicates a prize). Offline winners receive prizes when they next log in (if *retry on login* is on) or via Players → Prize deliveries.

### Prize boxes

The **Carnival Prize Box** is handed out by the prize tiers (ranks 1–10 by default), the wheel's prize segments and the prize counter. A player uses it from their inventory to open it, and a card shows what was inside. You decide what is inside in *Settings → Scoring & prizes → Prize box*:

| Setting | Meaning |
|---|---|
| *Fewest / Most prizes in a box* | Each box gives a random number of prizes in this range (factory: 1–3). |
| *Possible prizes* | A list of items, each with a **chance per prize (%)** and a **quantity from / up to**. Every prize in a box is drawn separately by these chances (so the same item can come up twice and is then added together), then gets a random quantity in its range. |

The chances must add up to exactly 100%: the list shows a running total, and the save is refused otherwise. A prize box cannot contain a prize box, and tickets cannot be prizes. Below the settings, **What players will get** opens 2,000 boxes on the server with the saved settings and shows how often each prize turns up and how many of it a box gives on average, so you can check the odds before players see them.

The factory box holds 1–3 carnival foods, with a 2% chance per prize of a Gold Horror Token. A box only opens if the player has room for everything inside; otherwise it stays shut with a message.

The old trick and treat tokens have been removed. Saved settings that still mention them are upgraded automatically on start: they disappear from the prize box list (the remaining chances are rescaled to 100%), prize tiers give a prize box instead, the wheel's *Treat!* segment gives candy floss, and *Trick!* only plays its spooky screen effect.

## Group allocation

*Settings → Carnival → Ticket colours → Allocation*: `balanced` (fewest members first), `random`, or `manual` (players register without a colour and an admin assigns one under Players; tickets are issued on assignment). Capacity is enforced per colour.
