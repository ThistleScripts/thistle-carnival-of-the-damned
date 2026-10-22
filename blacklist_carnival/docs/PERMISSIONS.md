# Permissions

All checks run on the server (`server/permissions.lua`). Hiding a button in the UI is never the security boundary: every API endpoint, command and export re-checks the permission.

The games run themselves. Staff at the carnival are actors and need **no role at all**. Roles are only for people who manage the carnival from `/carnivaladmin`.

## How a player's role is resolved

The highest-ranked of:

1. `Config.Security.Allowlist` — `license:`/`license2:` identifier → role.
2. ACE `carnival.role.<role>`.
3. An in-game assignment (`carnival_staff_assignments`) made by someone with `staff.manage` — capped at `Config.Security.MaxGrantableRank` (default 60 = Event Manager) and always below the granter's own rank. Owner/Administrator can therefore only come from config.lua or ACE.

Extra single permissions: ACE `carnival.perm.<permission>`. A role name that is not defined in `config.lua` (for example one left over from an older version) is ignored.

Resolved permissions are cached for `PermissionCacheSeconds` (30 s) and invalidated immediately when assignments change; clients receive their new permission list and open panels update.

## Roles (defaults in `config.lua`)

| Role | Rank | Purpose |
|---|---|---|
| `owner` | 100 | Everything (`*`). |
| `administrator` | 80 | Everything in the admin panel: settings, props, the prize counter, nights & results, players, prizes, roles, logs. |
| `event_manager` | 60 | Runs the night from the admin panel: pause/resume, end the night, close/reopen attractions, players, scores, prize deliveries. Cannot change settings. |
| `observer` | 10 | Read-only admin panel: overview, players and the full leaderboard. |

## Permission list

| Permission | Grants |
|---|---|
| `panel.admin` | Open `/carnivaladmin`. |
| `config.view` / `config.edit` | Read / change settings (versioned). |
| `events.manage` | Create/duplicate/edit nights, open/close registration, start, cancel, final results, complete, recovery tools. |
| `events.operate` | Pause/resume, close/reopen attractions, timed-round overrides, complete a stuck visit. |
| `events.history` | Past nights, results and their participants. |
| `participants.view` / `participants.manage` | See / register, transfer, remove, reinstate, replace tickets. |
| `scores.view` / `scores.adjust` | Ledger / manual adjustments, reversals, ledger verification, results from other resources (`registerExternalResult`). |
| `rewards.manage` | Retry, reconcile and cancel prize deliveries. |
| `deception.secrets` | See and edit the Hall of Deception answer keys and clues in settings. |
| `monitoring.view` / `audit.view` | Monitoring log / audit trail. |
| `export.history` | Export frozen results (audited). |
| `staff.manage` | Grant/revoke in-game roles. |
| `leaderboard.staff` | Full leaderboard with per-attraction breakdowns. |
| `props.manage` | Place, move and remove world props (prop placer). |
| `shop.manage` | Prize counter page: purchases, wallets and point adjustments. Prices and items are settings (`config.edit`). |
