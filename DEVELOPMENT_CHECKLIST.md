# Carnival of the Damned — Development Checklist

Persistent tracker so work can resume across sessions.

| Phase | Scope | Status |
|---|---|---|
| 1 | Architecture, module interfaces, schema & permission design | done |
| 2 | SQL migrations, persistence, event lifecycle, config versioning, permissions, audit/monitoring, Discord | done |
| 3 | Registration, tickets, groups, rotation, scoring ledger, leaderboard | done |
| 4 | Six attractions (server + client) | done |
| 5 | ox_inventory items, original images, ticket metadata, rewards, prize item behaviour | done |
| 6 | Admin configurator NUI (schema-driven editor, monitoring, audit, rewards, staff, history) | done |
| 7 | Staff panel NUI (operations + six attraction consoles) | done |
| 8 | Hardening, recovery, cleanup | done |
| 9 | Tests (static 468 / integration 51 / NUI 14 — all passing), documentation | done |

## Outstanding (requires a live FiveM server)
- Execute the manual in-game test plan in `blacklist_carnival/docs/TESTING.md` (M-* items).
- Capture real coordinates for every location with the admin coordinate tool.
- Confirm dependency API assumptions listed in `blacklist_carnival/docs/KNOWN_LIMITATIONS.md`.
- Optional: add background artwork to `blacklist_carnival/web/public/backgrounds/` and rebuild the NUI.

## How to resume
- Run `blacklist_carnival/tests/run_all.sh` (see `tests/README.md` for the test database).
- NUI: `cd blacklist_carnival/web && npm ci && npm run build` (commit `web/dist`).
- Assets: `python3 tools/generate_item_images.py`, `python3 tools/generate_audio.py`.
- New DB changes: add `sql/migrations/00N_*.sql`, list it in `Db.MIGRATIONS`, regenerate `sql/schema.sql`.

## Requirements added by the project owner during development
- Player-facing game NUIs for every attraction (not just staff/admin panels). ✔
- Every main NUI screen exposes a background image slot (`web/public/backgrounds/<screen>.png|jpg`) so the owner can supply artwork; a CSS fallback is used when no file is present. ✔
- No clowns anywhere: NPC models, characters, roles, fortunes, scenario text, item images or UI artwork. ✔ (enforced by `tests/static_checks.lua`)
