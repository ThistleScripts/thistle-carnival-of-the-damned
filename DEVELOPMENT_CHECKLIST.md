# Carnival of the Damned — Development Checklist

Persistent tracker so work can resume across sessions. Update the status column as phases complete.

| Phase | Scope | Status |
|---|---|---|
| 1 | Architecture, module interfaces, schema & permission design | in progress |
| 2 | SQL migrations, persistence, event lifecycle, config versioning, permissions, audit/monitoring | pending |
| 3 | Registration, tickets, groups, rotation, scoring ledger, leaderboard | pending |
| 4 | Six attractions (server + client) | pending |
| 5 | ox_inventory items, images, ticket metadata, rewards | pending |
| 6 | Admin configurator NUI | pending |
| 7 | Staff panel NUI | pending |
| 8 | Hardening, recovery, Discord, cleanup | pending |
| 9 | Tests, docs | pending |

## Requirements added by the project owner during development
- Player-facing game NUIs for every attraction (not just staff/admin panels).
- Every NUI screen exposes a background image slot (`web/public/backgrounds/<screen>.jpg|png`) so the owner can supply artwork; a CSS fallback is used when no file is present.
- **No clowns** anywhere: NPC models, characters, roles, fortunes, scenario text, item images or UI artwork.
