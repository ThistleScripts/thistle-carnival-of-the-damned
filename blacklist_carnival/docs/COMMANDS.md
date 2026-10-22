# Commands

All commands are checked on the server with the same permission as the equivalent panel action. The server console can run the event commands.

| Command | Arguments | Permission | Effect |
|---|---|---|---|
| `/carnival` | – | anyone | Opens the player hub (ticket, route, points, leaderboard). |
| `/carnivaladmin` | – | `panel.admin` | Admin panel (overview, players, nights & results, settings, system). |
| `/carnivalboard` | – | anyone | Live leaderboard (or the last completed event's final results). |
| `/carnivalstatus` | – | anyone | Prints event, state, round and participant count. |
| `/carnivalstart` | `[note]` | `events.manage` | From *registration open/closed/ready*: closes registration, marks ready and starts the event. |
| `/carnivalpause` | `[reason]` | `events.operate` | Pauses the event. |
| `/carnivalresume` | `[reason]` | `events.operate` | Resumes into the state it was paused from. |
| `/carnivalstop` | `<reason>` | `events.manage` | Cancels the event (reason required). During final results it completes the event instead. |
| `/carnivalitems` | – | `panel.admin` | Checks every carnival + configured reward item in ox_inventory. |
| `/carnivalverify` | – | `scores.adjust` | Verifies the active event's score ledger. |
| `/carnivalcoords` | – | `config.edit` | Copies your position + heading to the clipboard. |
| `/carnivalwhere` | – | participant | Waypoint to your current attraction. |
| `/carnivalhud` | – | participant | Toggle the participant HUD. |
| `/carnivalpreview` | `[screen]` | `panel.admin` | Opens a game screen with labelled demo data (no server calls, no points): `wheel`, `fortune`, `deception`, `puppets`, `horror`, `shooting`, `ticket`, `leaderboard`, `hub`. Also on every attraction ped as *Admin: preview game screen*. |
| `/carnivalprop` | `<model> [name]` | `props.manage` | Starts the prop placer with that model (see the admin manual's *World props*). |
| `/prizetickets` | – | anyone | Shows your prize tickets (spent at the prize counter). `/prizepoints` still works. |
| `/carnivalambience` | – | anyone | Turns the carnival ambient sounds off or on, just for you (remembered). |
| `/carnivalclose` | – | anyone | Closes every carnival interface and releases NUI focus (safety valve). |
