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
* To end the night, move the event to *Final results* and then *Completed*. Results are frozen as usual and a fresh carnival opens by itself (players buy a new ticket).
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

* **Shooting Gallery** — aim game length, games per visit, simultaneous players (player limit), targets per game, lanes, crossing speed, points, bullseye bonus, golden target chance/points, spirit lantern chance/penalty, accuracy bonus, miss penalty, minimum time between shots, max score.
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

## Prize counter

Every point a player scores in the games also earns **prize points** (*Settings → Scoring & prizes → Prize counter*: *prize points per 100 game points*, default 100 = one for one). Staff score adjustments and corrections never earn prize points, and a replayed score never pays twice. Prize points belong to the character (citizen ID) and **carry over between nights**.

Players spend them at the **prize counter** NPC (location, NPC model and blip in the same settings section): targeting it opens a shop showing their balance and the items for sale with their inventory pictures. `/prizepoints` tells a player their balance, and the player hub (`/carnival`) shows it with a waypoint to the counter.

**Items for sale** are a list of `item`, optional shop name and description (blank = the item's own), `price`, *limit per player per day* (0 = none) and *for sale*. Any registered ox_inventory item can be sold, except the carnival tickets. The factory list sells the ten carnival foods plus trick/treat tokens and the prize box.

**Buying** is decided by the server: the player must be at the counter, have the points and room in their inventory; the points are taken and the item handed over, and if the hand-over fails the points are refunded straight away. Every purchase, refund and adjustment is a row in the prize ledger, and a double-clicked or retried purchase is only charged once.

*Players → Prize counter* (`shop.manage`) shows points held, earned and spent, purchases in the last 24 hours, best sellers, recent purchases and every wallet. **Adjust** adds or removes points with a reason (audited).

### Carnival food

Ten consumables ship with the resource (images in `images/inventory`, definitions in the ox_inventory snippet). They use ox_inventory's own `client.status` hunger/thirst values (qbx_core's ox_inventory bridge applies them), with an eating or drinking animation and a hand prop:

| Item | Name | Restores |
|---|---|---|
| `carnival_bloodfloss` | Bloodspun Candy Floss | hunger |
| `carnival_poison_apple` | Poisoned Toffee Apple | hunger |
| `carnival_finger_dog` | Severed Finger Corn Dog | hunger (a lot) |
| `carnival_grave_popcorn` | Graveyard Popcorn | hunger |
| `carnival_bone_pretzel` | Bone-Knot Pretzel | hunger |
| `carnival_web_cake` | Cobweb Funnel Cake | hunger (the most) |
| `carnival_eyeball_pop` | Eyeball Cake Pop | hunger (a little) |
| `carnival_witch_brew` | Witch's Brew Lemonade | thirst |
| `carnival_blood_slushie` | Blood Moon Slushie | thirst |
| `carnival_grave_shake` | Grave Dirt Shake | hunger + thirst |

Change the amounts, animations or props in `ox_inventory/data/items.lua` after pasting. To redraw the pictures: `python3 tools/generate_item_images.py`.

## Ambient sound

*Settings → Carnival → Ambient sound* holds the **sound zones**: each has a centre (use **Use my position**), a radius, a looping sound and a volume. Players hear a zone at full volume at its centre, fading to silence at its edge; zones overlap and fade smoothly as players walk. The factory zones (midway organ waltz, crowd murmur, Fortune Teller chimes, House of Horrors wind) sit at the default pier positions — move them with your attractions. The loops are original and bundled (`tools/generate_audio.py`); the master volume in *Audio* also applies. Any player can mute the ambience for themselves with `/carnivalambience`.

## Prizes

*Prizes & results* defines rank tiers (from/to rank, label, items). When results freeze, a reward row is created per winner and item (idempotent: re-freezing never duplicates a prize). Offline winners receive prizes when they next log in (if *retry on login* is on) or via Players → Prize deliveries.

## Group allocation

*Settings → Carnival → Ticket colours → Allocation*: `balanced` (fewest members first), `random`, or `manual` (players register without a colour and an admin assigns one under Players; tickets are issued on assignment). Capacity is enforced per colour.
