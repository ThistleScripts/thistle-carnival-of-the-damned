# Permissions

All checks run on the server (`server/permissions.lua`). Hiding a button in the UI is never the security boundary: every API endpoint, command and export re-checks the permission.

## How a player's role is resolved

The highest-ranked of:

1. `Config.Security.Allowlist` — `license:`/`license2:` identifier → role.
2. ACE `carnival.role.<role>`.
3. An in-game staff assignment (`carnival_staff_assignments`) made by someone with `staff.manage` — capped at `Config.Security.MaxGrantableRank` (default 60 = Event Manager) and always below the granter's own rank. Owner/Administrator can therefore only come from config.lua or ACE.

Extra single permissions: ACE `carnival.perm.<permission>`.
Attraction scoping for operators/performers: ACE `carnival.attraction.<id>` or an in-game assignment with an attraction.

Resolved permissions are cached for `PermissionCacheSeconds` (30 s) and invalidated immediately when assignments change; clients receive their new permission list and open panels update.

## Roles (defaults in `config.lua`)

| Role | Rank | Purpose |
|---|---|---|
| `owner` | 100 | Everything (`*`). |
| `administrator` | 80 | Configurator, events, history, staff management, all attraction controls. |
| `event_manager` | 60 | Runs the live event: pause/resume, rotation overrides, participants, scores, rewards, all attractions (incl. deception secrets, horror control if allowlisted). No configurator. |
| `attraction_operator` | 40 | Staff panel + only the attractions they are assigned to. |
| `performer` | 30 | Staff panel + assigned attractions + custom theatre scenarios. Receives only their own Hall of Deception brief. |
| `observer` | 10 | Read-only staff panel and leaderboard. |

## Permission list

| Permission | Grants |
|---|---|
| `panel.admin` | Open `/carnivaladmin`. |
| `panel.staff` | Open `/carnivalstaff`. |
| `config.view` / `config.edit` | Read / change gameplay configuration (versioned). |
| `events.manage` | Create/duplicate/edit events, open/close registration, start, cancel, final results, complete, recovery tools. |
| `events.operate` | Pause/resume, extend/skip/delay/advance rotation, attraction availability. |
| `events.history` | Past events, results and their participants. |
| `participants.view` / `participants.manage` | See / register, transfer, remove, reinstate, replace tickets. |
| `scores.view` / `scores.adjust` | Ledger / manual adjustments, reversals, ledger verification. |
| `rewards.manage` | Approve, retry, reconcile, cancel reward deliveries. |
| `attractions.operate.<id>` | Operator console for one attraction (`shooting`, `wheel`, `fortune`, `puppets`, `deception`, `horror`). |
| `theatre.custom` | Create custom theatre scenarios. |
| `deception.secrets` | See the Hall of Deception answer key, briefs, preview/commit scoring. |
| `horror.control` | Start/pause/stop/reset House of Horrors runs (also requires the horror allowlist unless the role is in `HorrorAllowlistBypassRoles`). |
| `monitoring.view` / `audit.view` | Monitoring centre / audit trail. |
| `export.history` | Export frozen results (audited). |
| `staff.manage` | Grant/revoke in-game staff roles. |
| `leaderboard.staff` | Full staff leaderboard with breakdowns. |

## House of Horrors allowlist

`Config.Security.RequireHorrorAllowlist = true` means `horror.control` only applies to licenses in `Config.Security.HorrorControllers` (owners bypass by default). Performers assigned to the horror house can still trigger scares (`attractions.operate.horror`).
