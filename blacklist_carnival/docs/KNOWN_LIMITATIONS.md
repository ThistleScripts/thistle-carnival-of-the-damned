# Known limitations and unverified functionality

Honest list of what has **not** been proven in a live FiveM server, and the design limits.

## Not verified in game (no FiveM server was available while building)

The server logic was executed for real (integration tests run the actual server scripts against MariaDB), but everything that depends on the GTA client, CEF or the real versions of the dependencies has only been written against their documented APIs:

* **Client Lua** (`client/*`) — compiles and every API endpoint it calls exists on the server (static check), but NPC spawning, ox_target options, blips, prop spawning, `GetPedLastWeaponImpactCoord` hit detection, screen effects and NUI focus handling have not been run in game.
* **NUI in CEF** — rendered and exercised in jsdom tests (open/close, Escape, forms, validation errors, permission-gated navigation), not inside FiveM's CEF. Audio playback of the `.ogg` files is untested in CEF.
* **Dependency API assumptions** to confirm on your versions:
  * `qbx_core` triggers `QBCore:Server:PlayerLoaded` / `QBCore:Server:OnPlayerUnload` and `QBCore:Client:OnPlayerLoaded`; the client also announces itself on resource start (`LocalPlayer.state.isLoggedIn`), so binding still works if an event name differs.
  * `ox_inventory` item `server.export` hooks receive `(event, item, inventory, slot, data)` with `inventory.items[slot].metadata`, and returning `false` from `usingItem` cancels use.
  * `ox_inventory` `Search(src, 'slots', item)` returns slot tables with `metadata`; `RemoveItem` matches partial metadata.
  * `oxmysql` returns `TINYINT(1)` as booleans (handled either way) and `MySQL.transaction.await` returns `false` on rollback.
* **Discord webhooks** — code path not exercised against Discord.
* **Default coordinates/models** — placeholders around the Del Perro pier; GTA prop names for horror tokens (`prop_ld_case_01`, `prop_money_bag_01`, `prop_ld_gold_chest`) fall back to markers/zones if a model is invalid. Capture real positions with the coordinate tool before an event.

## Design limitations

* **Shooting Gallery (NUI aim game).** The server generates every target's spawn time, lane and kind, and accepts a hit only if that target was on screen at that moment by the server clock (±latency allowance), had not been hit, and the click rate is plausible. The bullseye ring is judged by the client (worth a small bonus). A modified client could still auto-click every target perfectly — like any aimbot for a 2D game — but cannot exceed the schedule; rejected shots are logged and visible to staff.
* **Theatre audience vote.** Self-service shows are judged by the group's vote; groups can collude. Use staff mode if you want a judge.
* **Token positions** are sent to runners so props can be rendered; a cheating client could reveal them. Collection still requires being physically within range inside the boundary.
* **One active event at a time.** Earlier events remain fully queryable; parallel live events are not supported.
* **Item registration** cannot be automated (ox_inventory has no runtime registration): items must be pasted into `ox_inventory/data/items.lua`.
* **Locale**: player-facing text is English; error-code fallbacks live in `locales/en.json`.
* **Score cap semantics**: attraction `maxScore` limits positive points per attraction; staff adjustments/corrections are not capped by it (they are capped by *maximum single manual adjustment*).
* **Wheel spins** are limited per participant per event (not per round visit).
* **Physical horror tokens** (optional keepsakes) carry no points; possession never grants points.
* **Background artwork** is supplied by the owner (slots are ready; none are shipped).
* **Audio** is procedurally generated placeholder-quality sound design; replace files in `web/public/sounds/` (same names) for higher production value.
