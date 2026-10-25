# Testing checklist and results

## Automated results (this repository, run with `tests/run_all.sh`)

Environment: Lua 5.4.6, MariaDB 10.11 / luasql-mysql, Node 22, Vite 5, Vitest 2 (jsdom). Date of run: 2026-10-22.

| Suite | Result |
|---|---|
| Static checks (manifest paths, Lua compiles, items ↔ definitions ↔ manifest ↔ 256×256 RGBA PNGs ↔ ox_inventory copies, every client/NUI endpoint registered on the server, sounds present in source and build, every food has a consumables.lua entry and uses useFood, no clown content) | **1032 checks, 0 failures** (also: every column the server writes exists in the schema; every prop in stream/props has its archetype loaded) |
| Server integration (real server scripts, real database) | **80 tests, 80 passed** (no game has a staff control; a self-service event and a walk-up carnival that nobody starts; the prize counter) |
| NUI typecheck (`tsc --noEmit`) + jsdom tests | **clean; 32 tests passed** |
| `sql/schema.sql` imported twice into an empty MariaDB database | **40 tables, no errors (idempotent)** |

### Integration tests (server_spec.lua)

Database & bootstrap: clean install + migrations recorded · migrations idempotent · config v1 seeded and valid · no clown content.
Permissions: allowlist/ACE roles, unknown roles ignored, event managers/observers get a limited admin panel and actors none · no staff endpoint exists for any game · unauthorised calls rejected · rate limits without bans.
Configuration: invalid config rejected with field errors · secret redaction + restore · save → new version → preview → rollback (audited) · reward items validated against inventory.
Lifecycle & registration: invalid transitions rejected · registration blocked when ticket items missing · booth distance enforced · 12 players balanced 2 per colour with physical tickets + metadata · duplicate registration rejected · capacity on transfer · ticket replacement voids old serial · forged ticket logged and rejected · transfer reissues ticket (audited) · remove/reinstate · reconnect recovery with a new source id · start → six unique sessions matching the matrix + settings snapshot.
Wheel: wrong group refused · max spins · total equals ledger · 10 000-draw distribution within ±2.5 % of weights · special prizes delivered straight away, idempotent delivery · inventory-full failure then retry · tickets refused as rewards.
Fortune: no answer leak · resume same pending question · correct/incorrect marking · no re-answering · visit limit.
Shooting: server-owned schedule for every round · each round faster, smaller, with more lanterns and a bigger multiplier, targets stay inside their round and lanes, the break between rounds ignores clicks, round-3 hits are multiplied, results add up per round · countdown clicks refused · bullseye scored on the server · already-hit / off-screen / too-fast refused · server timer ends the game · one award · cannot play twice.
Theatre: players take the stage, random scenario and roles, audience vote (no self-votes, one vote each, ties), solo shows scored, committed once.
Deception: starts on arrival · no answer key in public state or pushes · selection count enforced · submission limit · clues unlock over time · marked automatically once everyone has accused (perfect bonus, tie-break, penalties) · scored once.
Horror: only allowlisted controllers start · too far · valid collect · replayed collect refused · invalid token · stale run · non-runner · warnings at configured thresholds · escape bonus once · expiry ends run once and completes the group.
Rotation: a show in progress holds the round past its timer (overtime) and completes it when it ends · between rounds → auto round 2 matching the matrix · pause freezes / resume restores exactly · extend/skip/delay audited, delay auto-releases.
Scoring: reason required · bounds · idempotent adjustment · negative totals clamped · reversal · ledger verification consistent · no player scoring path.
Recovery: restart → event paused, scores recovered, reward mid-delivery → `unknown` (retry refused until reconciled), horror run interrupted not restarted, resume works.
Completion: six rounds, each colour visits each attraction exactly once · final results frozen + prize rewards · correction creates results v2 · completed results unchanged after config change · no scoring after completion · new event leaves history intact · CSV export (audited, permission-gated).
Walk-up mode: switching the mode opens a carnival with only system transitions and keeps registration open · no rounds · each colour's first game is the first on its ticket · out-of-order games refused with directions · wheel, gallery, fortune, solo theatre, deception and horror each complete and advance the ticket · no joining a run in progress · idle visits close without credit · restart keeps it running with progress · finalising freezes results and a fresh carnival opens · after End the night the books close by themselves (system) and a fresh carnival opens · the night ends on its schedule (after_hours, daily HH:MM, manual never; a bad time is refused), an empty night rolls over with no results, games in progress get the grace period · undelivered prizes from any night are retried automatically and on login, never deliveries cut off by a restart · the setup checklist spots placeholder positions and clears once they are moved.
World props: only `props.manage` can place · model/position/rotation validated · placing, moving and removing push to every player and are audited · bootstrap carries every prop · removed props keep their row · props reload after a restart.
Prize boxes: the item count range, percentage chances and quantities are respected, a full inventory keeps the box shut, the odds preview matches the chances (admin only), chances must add up to 100%, no boxes in boxes, and saved settings naming the retired trick/treat tokens are upgraded (chances rescaled). Prize counter: each game pays tickets for finishing it and per 100 points scored at its own rate, capped per night; replays, staff adjustments and participation bonuses pay nothing; the shop lists what each game pays and has paid tonight · buying needs to be at the counter, enough points, and an item on sale (tickets never are) · a retried purchase charges and delivers once · daily limits reset after a day · a failed hand-over refunds · food effects come from consumables.lua (named animations, clamping, bad entries skipped), eating needs the progress time, removes one item, writes hunger/thirst/stress and a token works once · wallets and the overview are `shop.manage` only · wallet balance equals the ledger · tickets cannot be configured for sale; ambient zone sounds are validated.
Roles & audit: grants bounded by rank, revocation immediate · audit covers key actions and is never updated/deleted by code · DB failure reported and recovered · monitoring queryable with filters.

### NUI tests (web/src/__tests__/nui.test.tsx)

HUD (round and walk-up modes) · ticket card open + Escape releases view · void ticket · wheel spin uses the server outcome · wheel error state · fortune answer payload · deception requires exact liar count · theatre/horror/shooting overlays · live leaderboard push · admin panel has five sections; the settings editor renders every section from the real Lua schema with no staff modes, shows server validation errors and disables locked fields while live · coordinate tool fills vec4 fields · overview shows attractions, who is playing, the board and recovers from errors, with no round controls in walk-up · props tab lists props, starts the in-world placer (new and move) and removes after confirming · prize booth shows the ticket balance, shelves and how to win tickets, blocks unaffordable/sold-out prizes, redeems with a fresh request id and follows wallet pushes · item pictures fall back from the item's own ox_inventory image to the inventory image path to an icon · ambient levels reach the mixer · the prize box reveal shows the contents and closes by itself · admin prize counter adjusts a wallet with a reason · permission loss hides gated navigation.

### Visual review

`node tools/ui-screens.mjs <outDir> [scene ...]` renders the built NUI (`web/dist`) in headless Chromium with a fake game bridge and realistic demo data, and saves a PNG of every screen: HUD, hub, ticket, leaderboard, wheel, fortune, shooting gallery (a round in play, the break card and the per-round result), deception, theatre card and vote, horror HUD, prize counter, and the admin overview, players, prize counter and settings pages. Use it after changing the UI or adding background artwork.

## Manual in-game test plan (not yet executed — requires a FiveM server)

Run these on a staging server before the first live event. IDs are referenced from SECURITY.md.

**Install**
- M-INS-1 Start order as in INSTALLATION.md; console shows `resource_ready`; `/carnivalitems` → all registered.
- M-INS-2 `/carnivaladmin` → *Items & health*: database healthy, dependencies running.

**Lifecycle**
- M-LC-1 Create event, open registration, register two characters on two clients; tickets appear with correct image, label and description; *use* the ticket → ticket card shows *Valid ticket*.
- M-LC-2 Drop a ticket on the ground / give it to another player; at an attraction the other player is refused (ticket_missing), and the monitoring log shows `invalid_ticket_presented` (`belongs_to_another_participant`).
- M-LC-3 `/carnivalstart`; HUD shows round 1 and countdown; waypoint set to the attraction.
- M-LC-4 Restart the resource mid-round: event comes back paused, HUD and interactions rebuild, `/carnivalresume` continues the timer.

**Attractions**
- M-AT-1 Shooting: target the gallery ped; the aim game opens with a countdown, targets slide across, clicks register with sound and points; golden targets and lanterns appear; result at the end.
- M-AT-2 Wheel: spin animation lands on the segment shown in the result; the Trick! outcome plays the screen effect; special prize waits for approval.
- M-AT-3 Fortune: riddle typed answer accepted case-insensitively; fortune shown; visit completes.
- M-AT-4 Theatre: two players take the stage; role cards visible without blocking movement; timer; vote screen; results.
- M-AT-5 Deception: terminal shows testimony; clues arrive over time; accusation scored; reveal shows liars.
- M-AT-6 Horror: ambient audio plays, tokens visible within proximity distance, collection via ox_target, warnings at 120/60/30/10/5 s with sounds, scares shake/flash, exit zone grants bonus, run end stops ambient.

**NUI**
- M-NUI-1 Every panel opens/closes; Escape closes; the cursor is never left captured; `/carnivalclose` always recovers.
- M-NUI-2 Minimise the admin panel, walk, reopen.
- M-PROP-1 Drop a prop into `stream/props/`, restart, place it from *Settings → Props*: preview follows your aim, scroll/arrow/G/X work, Enter places it; a second player sees it; restart the server and it is still there; move and remove it by targeting it.
- M-NUI-3 Remove an admin role while the panel is open → panel closes / navigation shrinks within 30 s.
- M-NUI-4 `stop blacklist_carnival` while a panel is open → focus released, peds/props/blips removed.

**Inventory**
- M-INV-1 Full inventory at registration → ticket pending; make space; booth *Replace or collect my ticket* delivers it.
- M-INV-2 A prize box opens into 1-3 configured prizes and shows the reveal card; with a full inventory it stays shut.
- M-INV-3 Restart ox_inventory during an event; ticket validation keeps working after it is back.
