# Administrator manual

Open the configurator with `/carnivaladmin` (or `/carnival`, which opens the most privileged panel you have). **Minimise** hides the panel so you can walk around (for example to capture coordinates); reopen with the same command. **Escape** closes it.

## Pages

| Page | What it is for |
|---|---|
| Dashboard | Live state: event, registration, participants (online), round + timer, per-colour groups, attraction readiness, top 10, recent score transactions, outstanding rewards, recent staff actions, recent warnings/errors, database and dependency health, config/resource versions. Every figure comes from the server. |
| Events & history | Create an event, edit its details, move it through its lifecycle, recovery tools, history of every past event with results versions, CSV export, state history and settings snapshots. *Use as template* creates a new event from an old one (name, description and event-specific settings). |
| Live operations | Rotation grid and overrides, groups, attraction readiness (same tools as the staff panel). |
| Configuration pages | Every gameplay setting, grouped: General, Registration & tickets, Colours & groups, Rotation, Scoring, Leaderboard, Prizes & results, Reward items, Audio, and one page per attraction. |
| Participants | Search, open a participant: registration, tickets, group history, completed attractions, score breakdown + ledger, rewards; transfer, replace ticket, remove/reinstate, adjust score. |
| Score ledger | Every transaction with filters; *Reverse* adds a correction entry; *Verify ledger* recomputes totals, per-attraction summaries and the running-total chain from the ledger. |
| Rewards | Delivery reconciliation: approve, retry, reset to pending, mark delivered, cancel (reasons are audited). |
| Staff & roles | Grant/revoke in-game roles (bounded by config.lua). |
| Monitoring centre | Searchable operational + security log (date range, event, participant, staff, attraction, severity, category, text). |
| Audit trail | Append-only administrative record. |
| Items & health | Checks every carnival and configured reward item against ox_inventory. |

## Carnival mode: walk-up or scheduled

*General → Carnival mode* decides how the carnival runs.

**Walk-up (default): no staff needed.**
* When no event is active, the server creates a walk-up event and moves it straight to *running* (the transitions are recorded with the actor `system`). Registration stays open while it runs.
* A player buys a ticket at the booth and gets a colour. That colour's column of the rotation matrix is their personal order of games; the HUD and `/carnival` show the next one and set a waypoint.
* The player targets the next game's ped and plays. When they finish, their ticket moves on to the next game. They cannot play out of order (unless *Rotation → Walk-up mode → enforce order* is off), and they cannot repeat a game.
* Individual games (gallery, wheel, fortune) complete per player. Group games (theatre, Hall of Deception, House of Horrors) gather whoever arrives for that game during the lobby, run, then complete for everyone who took part. Nobody can join a show, maze run or mystery that is already under way.
* An attraction that is disabled or marked unavailable is passed over; the player plays the next one and comes back to it later.
* A visit nobody is playing is closed after *idle seconds* without counting as played, so the player can start again.
* The fortune teller can still be run by staff. In *staff* or *both* mode, a waiting player appears in the fortune console; staff present questions, award roleplay points and press **Finish reading** to complete their visit.
* Restarts do not pause a walk-up event.
* To end the night, move the event to *Final results* and then *Completed*. Results are frozen as usual and a fresh carnival opens by itself (players buy a new ticket).
* To stop the carnival opening again, switch the mode to *scheduled* first. While the walk-up event runs, the rotation matrix and colours may still be edited, because players progress individually.

**Scheduled.** Staff create the event and run it through the lifecycle below in timed rounds; each colour group visits one attraction per round.

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
* After a server/resource restart a running event comes back **paused**. Horror runs and shooting heats that were in progress are marked *interrupted* (never restarted automatically); rewards caught mid-delivery become *unknown* and need reconciliation. Resume when staff are ready.

Recovery tools (Events page, active event): reload state from the database, force pause, flag interrupted reward deliveries.

## Configuration

* **Scope.** *Global defaults* apply to every event. *This event only* creates an event-specific copy for the active event; *Use global settings* removes it.
* **Preview** shows exactly which settings change (secret values hidden), flags settings that need an attraction reset (`reset`) and settings locked while the event is in progress (`locked live`: rotation matrix, colour enable flags, virtual tickets).
* **Save** validates everything on the server (types, ranges, rotation matrix, wheel weights, fortune answers, mystery liar counts, item names in ox_inventory…). Errors are highlighted on the fields. Large or reset-requiring changes ask for confirmation.
* **Versions** lists every saved version; *Roll back* creates a new version with the old values (nothing is deleted). All saves are audited.
* **Use my position** on any coordinate field captures your current position (feet level) and heading.
* Secret fields (mystery answer keys, briefs, statements, fortune answers, wheel weights) are hidden from users without the matching permission and preserved when they save.

### Attraction settings at a glance

* **Shooting Gallery** — aim game length, games per visit, simultaneous players (player limit), targets per game, lanes, crossing speed, points, bullseye bonus, golden target chance/points, spirit lantern chance/penalty, accuracy bonus, miss penalty, minimum time between shots, max score.
* **Self-service vs staff modes** — Theatre, Hall of Deception and House of Horrors have a *Mode* setting. *self* (default) runs without staff; *staff* uses the operator consoles. Theatre self mode: lobby time, vote time, solo points. Deception self mode: clue unlock interval. Horror self mode: gather time before the doors open.
* **Wheel of Misfortune** — outcomes (label, type, weight, points ±, item + quantity, staff approval), spins per participant, cooldown, animation length, first-spin bonus, auto-complete.
* **Fortune Teller** — mode (automated / staff / both), questions per visit, visits, cooldown, answer time limit, question pool (multiple choice or riddle with accepted answers, points, wrong-answer penalty, lines), fortunes, roleplay award cap.
* **Puppet Master's Theatre** — scenario library (category, difficulty, performer counts, time limit, points range, suggested roles), default length, participation bonus, max award.
* **Hall of Deception** — mysteries (performers with public profile, statements, liar flag, private brief; clues; rules; liar count; scoring: per correct, penalty, perfect bonus, partial credit, reasoning max, tie-break), default mystery, questioning time, submissions per participant.
* **House of Horrors** — entry, exit + radius, boundary centre + radius, duration, warning thresholds (any list of seconds), sounds and volume, collection rule (once per player / once globally), token visibility, completion and time bonuses, penalties, keepsake items, token types (points, active quantity, model, distance, respawn) and positions, performer scare points.

## Prizes

*Prizes & results* defines rank tiers (from/to rank, label, items). When results freeze, a reward row is created per winner and item (idempotent: re-freezing never duplicates a prize). Offline winners receive prizes when they next log in (if *retry on login* is on) or via the Rewards page.

## Group allocation

*Colours & groups → Allocation*: `balanced` (fewest members first), `random`, or `manual` (players register without a colour and staff assign one; tickets are issued on assignment). Capacity is enforced per colour.
