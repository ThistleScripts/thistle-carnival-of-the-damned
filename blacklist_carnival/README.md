# blacklist_carnival — Carnival of the Damned

A staff-operated, roleplay-focused carnival event for **Blacklist RP** (QBX/Qbox · ox_lib · ox_target · ox_inventory · oxmysql · React/TypeScript NUI).

Players register at the ticket booth and receive one of six coloured tickets. Each colour is a travelling group that rotates through six attractions; **scores are individual**. Staff run the attractions from an in-game staff panel; owners/admins configure everything from an in-game configurator — no Lua edits for ordinary event setup.

| Attraction | Type | Highlights |
|---|---|---|
| The Shooting Gallery | automated + operator | Heats, server-validated hit reports, bullseyes, timed special targets, accuracy bonus. |
| The Wheel of Misfortune | automated | Weighted server-side outcomes, points ±, prizes, trick/treat, staff approval for special prizes. |
| The Fortune Teller's Curse | automated + staff-led | Riddles and multiple choice marked on the server, fortunes, roleplay awards. |
| The Puppet Master's Theatre | staff-judged | Scenario library/random/custom, casting with roles, timer, preview → commit once. |
| The Hall of Deception | staff-judged | Mysteries with secret answer key, performer briefs, clues, structured accusations + judged reasoning. |
| The House of Horrors | automated + controllers | Server timer with configurable warnings, bronze/silver/gold tokens, escape bonuses, performer scares. |

## Documentation

* [Installation & start order](docs/INSTALLATION.md)
* [Administrator manual](docs/ADMIN_MANUAL.md) · [Event staff manual](docs/STAFF_MANUAL.md)
* [Permissions](docs/PERMISSIONS.md) · [Commands](docs/COMMANDS.md) · [Exports](docs/EXPORTS.md)
* [Database reference](docs/DATABASE.md)
* [Testing checklist & results](docs/TESTING.md) · [Security checklist](docs/SECURITY.md)
* [Known limitations & unverified functionality](docs/KNOWN_LIMITATIONS.md)

## Quick start

1. Add the items from `../ox_inventory_additions/data/carnival_items.lua` to `ox_inventory/data/items.lua` and copy `../ox_inventory_additions/web/images/*.png` to `ox_inventory/web/images/`.
2. Put your license in `Config.Security.Allowlist` (config.lua) as `owner`.
3. `ensure blacklist_carnival` after its dependencies. Tables are created automatically.
4. In game: `/carnivaladmin` → set locations with **Use my position** → *Events & history* → *Create event* → open registration.

## Layout

```
config.lua                bootstrap security (roles, allowlists, webhooks via convars, logging) — server only
shared/                   constants, utils, config schema, factory defaults, validation
server/                   bootstrap, persistence, monitoring, audit, discord, identity, permissions,
                          api router, push, config manager, inventory, prizes, events, registration,
                          groups, tickets, scoring, rewards, leaderboard, rotation, attraction registry,
                          attractions/*, admin api, commands, exports
client/                   NUI bridge + focus, audio, interactions (NPCs/ox_target/blips), tickets,
                          participants/HUD, rotation, leaderboard, attractions/*
web/                      React + TypeScript (Vite) source; web/dist is the built UI
sql/                      migrations (applied automatically) + schema.sql
items/                    ox_inventory definitions + item manifest
images/inventory/         original 256×256 item images
locales/en.json           message strings used by the NUI
tools/                    generators for the item images and sounds
tests/                    static checks, integration harness + suite, NUI fixture exporter
docs/                     manuals and references
```

## Design notes

* **Server-authoritative**: state machine, timers, random outcomes, distance checks, scoring and rewards run on the server; clients render and request.
* **One scoring ledger** with idempotency keys, transactional summaries and a verification tool.
* **Versioned configuration** in the database with validation, preview, history and rollback; bootstrap security stays in `config.lua`.
* **Persistent history**: every event, participant, ticket, session, score, reward, judgement and results version is kept.
* **Owner content rule**: no clowns in any content, models or imagery (enforced by a static check).
