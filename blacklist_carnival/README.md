# blacklist_carnival — Carnival of the Damned

A self-running, roleplay-focused carnival for **Blacklist RP** (QBX/Qbox · ox_lib · ox_target · ox_inventory · oxmysql · React/TypeScript NUI).

Players buy a ticket at the booth and receive one of six coloured tickets; the colour sets the order in which they play the six attractions. **Scores are individual.** Players run every attraction themselves by targeting its ped; **no staff are needed to run any game**, so staff are free to be actors (see the [actor guide](docs/ACTOR_GUIDE.md)). Owners and admins manage everything from one in-game admin panel, with no Lua edits for ordinary setup, including a **prop placer** that saves props to the database so every player sees them and they survive restarts. The games also pay out **prize tickets** (for playing and for how well you score) to spend at the **prize counter** on ten horror-carnival treats (candy floss, a severed-finger corn dog, a blood moon slushie…), and **ambient sound zones** fill the grounds with an organ waltz, crowd murmur, chimes and wind.

**Runs with no staff.** In walk-up mode the carnival opens itself, ends the night on a schedule (daily at 04:00 by default), freezes the results, hands out prizes (retrying anyone who was offline or had full pockets) and opens a fresh night. The admin Overview lists anything left to set up.

**Two carnival modes** (*General → Carnival mode*):

* **Walk-up** (default): the carnival opens itself and stays open. Nobody has to create, open or start an event. A player buys a ticket, walks to the first game on it and plays, then the next, at their own pace.
* **Scheduled**: an admin creates a night and it runs in timed rounds, with each colour group moving together.

| Attraction | Type | Highlights |
|---|---|---|
| The Shooting Gallery | solo | Mouse-aim NUI game in three rounds that get harder (faster, smaller, weaving targets, more lanterns, bigger multipliers); golden targets, spirit lanterns not to shoot; schedule and scoring on the server. |
| The Wheel of Misfortune | solo | Marquee wheel with weighted server-side outcomes, points ±, prize boxes, a candy floss *Treat!* and a spooky *Trick!*. |
| The Fortune Teller's Curse | solo | A reading with riddles and multiple choice marked on the server, and a fortune. |
| The Puppet Master's Theatre | group | A solo showcase: each player has the stage alone for 60 seconds with their own random prompt, one after another, then the group votes for the best performance. |
| The Hall of Deception | group | Starts when players arrive; suspects' testimony on the terminal, clues unlock over time, accusations auto-marked. |
| The House of Horrors | group | A player opens the doors, the group gathers, server timer with warnings, floating glowing bronze/silver/gold coins, escape bonuses. |

## Documentation

* [Installation & start order](docs/INSTALLATION.md)
* [Administrator manual](docs/ADMIN_MANUAL.md) · [Actor guide](docs/ACTOR_GUIDE.md)
* [Permissions](docs/PERMISSIONS.md) · [Commands](docs/COMMANDS.md) · [Exports](docs/EXPORTS.md)
* [Database reference](docs/DATABASE.md)
* [Testing checklist & results](docs/TESTING.md) · [Security checklist](docs/SECURITY.md)
* [Known limitations & unverified functionality](docs/KNOWN_LIMITATIONS.md)

## Quick start

1. Add the items from `../ox_inventory_additions/data/carnival_items.lua` to `ox_inventory/data/items.lua` and copy `../ox_inventory_additions/web/images/*.png` to `ox_inventory/web/images/`.
2. Put your license in `Config.Security.Allowlist` (config.lua) as `owner`.
3. `ensure blacklist_carnival` after its dependencies. Tables are created automatically.
4. In game: `/carnivaladmin` → set the booth and attraction locations with **Use my position**. In walk-up mode (the default) the carnival is already open: players can buy a ticket and play. For a night in timed rounds, switch *Settings → Carnival → General → Carnival mode* to *scheduled*, then *Nights & results* → *Create event* → open registration.

## Layout

```
config.lua                bootstrap security (roles, allowlists, webhooks via convars, logging) — server only
consumables.lua           what each carnival food/drink gives (hunger, thirst, stress, armour, health, anim, prop) — server only
shared/                   constants, utils, config schema, factory defaults, validation
server/                   bootstrap, persistence, monitoring, audit, discord, identity, permissions,
                          api router, push, config manager, inventory, prizes, events, registration,
                          groups, tickets, scoring, rewards, leaderboard, rotation, attraction registry,
                          attractions/*, admin api, commands, exports
client/                   NUI bridge + focus, audio, interactions (NPCs/ox_target/blips), tickets,
                          participants/HUD, rotation, leaderboard, attractions/*
web/                      React + TypeScript (Vite) source; web/dist is the built UI
sql/                      migrations (applied automatically) + schema.sql
stream/props/             props: House of Horrors coins + your own props for the prop placer
items/                    ox_inventory definitions + item manifest
images/inventory/         original 256×256 item images
locales/en.json           message strings used by the NUI
tools/                    generators for the item images and sounds; ui-screens.mjs renders every NUI screen to PNG
tests/                    static checks, integration harness + suite, NUI fixture exporter
docs/                     manuals and references
```

## Design notes

* **Server-authoritative**: state machine, timers, random outcomes, distance checks, scoring and rewards run on the server; clients render and request.
* **One scoring ledger** with idempotency keys, transactional summaries and a verification tool.
* **Versioned configuration** in the database with validation, preview, history and rollback; bootstrap security stays in `config.lua`.
* **Persistent history**: every event, participant, ticket, session, score, reward, judgement and results version is kept.
* **Owner content rule**: no clowns in any content, models or imagery (enforced by a static check).
