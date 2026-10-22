# Installation guide

## 1. Requirements

| Dependency | Notes |
|---|---|
| FiveM server (OneSync) | `GetSelectedPedWeapon`, `GetEntityCoords(GetPlayerPed())` are used server-side, which need OneSync. |
| `oxmysql` | Any recent version with `MySQL.*.await` and `MySQL.transaction.await`. |
| `ox_lib` | Callbacks, notify, points, dialogs. |
| `qbx_core` | Uses `exports.qbx_core:GetPlayer`, `GetPlayerByCitizenId`, `PlayerData.citizenid/charinfo`. |
| `ox_target` | `addLocalEntity`, `addSphereZone`, `removeZone`, `removeLocalEntity`. |
| `ox_inventory` | `Items`, `AddItem`, `RemoveItem`, `CanCarryItem`, `Search`, `GetItemCount`, item `server.export` hooks. |
| MySQL 5.7+/MariaDB 10.3+ | InnoDB, utf8mb4. |

No ESX/QBCore bridge is used or required.

## 2. Start order (`server.cfg`)

```cfg
ensure oxmysql
ensure ox_lib
ensure qbx_core
ensure ox_target
ensure ox_inventory
ensure blacklist_carnival
```

## 3. Files

1. Copy the `blacklist_carnival` folder into your resources directory.
2. The built NUI (`web/dist`) is committed, so Node is **not** needed on the server. To rebuild after changing the UI or adding background art: `cd web && npm ci && npm run build`.

## 4. Database

Nothing to import by hand: on start the resource applies `sql/migrations/*.sql` (all statements are `CREATE TABLE IF NOT EXISTS` / `INSERT IGNORE`) and records them in `carnival_schema_migrations`. If your database user cannot create tables, import `sql/schema.sql` once with an account that can; it is safe to import repeatedly.

Existing data is never dropped or recreated on start.

## 5. Inventory items (required for physical tickets)

ox_inventory cannot register items at runtime, so:

1. Open `ox_inventory/data/items.lua`.
2. Paste the contents of `ox_inventory_additions/data/carnival_items.lua` (repository root) **inside** the returned table — for example just before the final `}`. Do not replace the file.
3. Copy every PNG from `ox_inventory_additions/web/images/` to `ox_inventory/web/images/`.
4. Restart ox_inventory (or the server), then run `/carnivalitems` (or the *Items & health* page in `/carnivaladmin`). It must report all items registered.

The twenty-two items are: `carnival_ticket_{red,blue,green,yellow,purple,orange}`, `carnival_token_{bronze,silver,gold}`, `carnival_trick_token`, `carnival_treat_token`, `carnival_prize_box`, and the ten foods sold at the prize counter: `carnival_bloodfloss`, `carnival_poison_apple`, `carnival_finger_dog`, `carnival_grave_popcorn`, `carnival_bone_pretzel`, `carnival_web_cake`, `carnival_eyeball_pop`, `carnival_witch_brew`, `carnival_blood_slushie`, `carnival_grave_shake`. If you pasted an earlier version of the snippet, paste the food entries at the end of it too. The image manifest is `items/item-manifest.json`.

Registration refuses to open while the ticket items are missing (unless virtual tickets are enabled in the configurator, or you set `Config.Inventory.RequireItemDefinitions = false`).

To use your own server items as wheel or prize-tier rewards, just enter their names in the configurator; the server checks every configured item name against `exports.ox_inventory:Items()` before saving.

### House of Horrors coins

The three coin props are streamed by this resource (`stream/props/carnivalcoin{bronze,silver,gold}.ydr/.ytd/.ytyp`). Every `.ytyp` in `stream/props/` is loaded by `data_file 'DLC_ITYP_REQUEST' 'stream/props/*.ytyp'` in `fxmanifest.lua`, so props you add for the prop placer only need their files dropped into that folder. Nothing else to install.

Actors at the carnival need no role or setup: every game runs itself.

## 6. Permissions

Edit `config.lua` (server only, never sent to clients):

```lua
Config.Security.Allowlist = {
    ['license:0123456789abcdef0123456789abcdef01234567'] = 'owner',
}
```

Or use ACE in `server.cfg`:

```cfg
add_ace group.admin carnival.role.administrator allow
add_ace identifier.license:xxxx carnival.role.event_manager allow   # runs the night, cannot change settings
add_ace identifier.license:yyyy carnival.role.observer allow        # read-only admin panel
add_ace identifier.license:zzzz carnival.perm.scores.adjust allow   # one extra permission
```

Full details: [PERMISSIONS.md](PERMISSIONS.md).

## 7. Optional convars

```cfg
set carnival_log_level "info"            # debug | info | warning | error | critical
set carnival_discord "true"
set carnival_webhook_event    "https://discord.com/api/webhooks/..."
set carnival_webhook_security "https://discord.com/api/webhooks/..."
set carnival_webhook_admin    "https://discord.com/api/webhooks/..."
set carnival_webhook_error    "https://discord.com/api/webhooks/..."
```

Webhook URLs live only in convars; they are never written to the database or sent to clients.

## 8. First run checklist

1. Start the server and watch the console for `resource_ready`.
2. `/carnivalitems` → all items registered.
3. `/carnivaladmin` → *System → Health & items*: database healthy, ox_inventory/ox_target/qbx_core running.
4. Walk to each location and use **Use my position** on the configuration pages (entrance, each attraction, horror entry/exit/boundary and coin positions). The shipped coordinates are placeholders around the Del Perro pier.
5. Create an event on *Events & history* and follow the [Administrator manual](ADMIN_MANUAL.md).

## 9. Backgrounds (optional artwork)

Put `admin`, `hub`, `ticket`, `leaderboard`, `wheel`, `fortune`, `deception` or `results` (`.png` or `.jpg`) in `web/public/backgrounds/`, then rebuild the NUI. See `web/public/backgrounds/README.md`. Missing files fall back to the built-in gradient.
