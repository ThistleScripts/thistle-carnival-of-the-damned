# Known limitations and unverified functionality

Honest list of what has **not** been proven in a live FiveM server, and the design limits.

## Not verified in game (no FiveM server was available while building)

The server logic was executed for real (integration tests run the actual server scripts against MariaDB), but everything that depends on the GTA client, CEF or the real versions of the dependencies has only been written against their documented APIs:

* **Client Lua** (`client/*`) — compiles and every API endpoint it calls exists on the server (static check), but NPC spawning, ox_target options, blips, prop spawning (including the floating coins), screen effects and NUI focus handling have not been run in game.
* **NUI in CEF** — rendered and exercised in jsdom tests (open/close, Escape, forms, validation errors, permission-gated navigation), not inside FiveM's CEF. Audio playback of the `.ogg` files is untested in CEF.
* **Dependency API assumptions** to confirm on your versions:
  * `qbx_core` triggers `QBCore:Server:PlayerLoaded` / `QBCore:Server:OnPlayerUnload` and `QBCore:Client:OnPlayerLoaded`; the client also announces itself on resource start (`LocalPlayer.state.isLoggedIn`), so binding still works if an event name differs.
  * `ox_inventory` item `server.export` hooks receive `(event, item, inventory, slot, data)` with `inventory.items[slot].metadata`, and returning `false` from `usingItem` cancels use.
  * `ox_inventory` `Search(src, 'slots', item)` returns slot tables with `metadata`; `RemoveItem` matches partial metadata.
  * `oxmysql` returns `TINYINT(1)` as booleans (handled either way) and `MySQL.transaction.await` returns `false` on rollback.
* **Discord webhooks** — code path not exercised against Discord.
* **Default coordinates** are placeholders around the Del Perro pier, including the horror token positions. Capture real positions with the coordinate tool before an event; tokens left at the defaults appear at the pier, not in your maze.
* **Horror coins** are the bundled `stream/props/carnivalcoin*` props (about 8 MB each, mostly textures — players download them once). The float/spin/glow is client-side animation of a local prop (`DrawLightWithRange` for the glow); it has not been checked in game yet.
* **Prop placer** — placement mode (raycast, controls, ghost preview) and local prop spawning have not been run in game. The manifest loads archetypes with a wildcard (`stream/props/*.ytyp`); if your server build does not expand wildcards in `data_file`, list each `.ytyp` on its own line. Props are spawned by every client within ~150 m: keep heavy props (large textures) few in number.
* **Prize counter and food** — buying, refunds, points and the eating flow (tokens, item removal, hunger/thirst/stress written to QBX metadata and state bags) are covered by the server tests; the counter NPC, the shop screen's item pictures (loaded from `nui://ox_inventory/web/images/`), the `lib.progressBar` animations and hand props, armour/health on the ped, and whether your HUD picks up the new hunger/thirst straight away (the server also sends `hud:client:UpdateNeeds`) have not been run in game. Tune animations and props in `consumables.lua`.
* **Ambient sound zones** — volume falloff and the NUI mixer (looping `<audio>` with fades) are untested in CEF. Some CEF builds block audio until the NUI has been interacted with once; if the ambience is silent until a menu is opened, that is why.
* **NUI look** was reviewed in headless Chromium (`tools/ui-screens.mjs`), not in FiveM's CEF; fonts are bundled so rendering should match.

## Design limitations

* **Shooting Gallery (NUI aim game).** The server generates every target's spawn time, lane and kind, and accepts a hit only if that target was on screen at that moment by the server clock (±latency allowance), had not been hit, and the click rate is plausible. The bullseye ring is judged by the client (worth a small bonus). A modified client could still auto-click every target perfectly — like any aimbot for a 2D game — but cannot exceed the schedule; rejected shots are logged in the monitoring log.
* **Walk-up group games.** The theatre, Hall of Deception and House of Horrors gather only players for whom it is the next game and who arrive during the short lobby. On a quiet server these are often solo: a solo show earns the configured solo points, and a solo mystery or maze run works as normal. Anyone arriving mid-run waits for the next one.
* **Walk-up idle visits** close after *idle seconds* without credit; the player can start that game again.
* **Theatre audience vote.** Shows are judged by the audience's vote; players can collude. There is no judge.
* **Token positions** are sent to runners so props can be rendered; a cheating client could reveal them. Collection still requires being physically within range inside the boundary.
* **One active event at a time.** Earlier events remain fully queryable; parallel live events are not supported.
* **Item registration** cannot be automated (ox_inventory has no runtime registration): items must be pasted into `ox_inventory/data/items.lua`.
* **Locale**: player-facing text is English; error-code fallbacks live in `locales/en.json`.
* **Score cap semantics**: attraction `maxScore` limits positive points per attraction; admin adjustments/corrections are not capped by it (they are capped by *maximum single manual adjustment*).
* **Wheel spins** are limited per participant per event (not per round visit).
* **Physical horror tokens** (optional keepsakes) carry no points; possession never grants points.
* **Background artwork** is supplied by the owner (slots are ready; none are shipped).
* **Audio** is procedurally generated placeholder-quality sound design; replace files in `web/public/sounds/` (same names) for higher production value.
