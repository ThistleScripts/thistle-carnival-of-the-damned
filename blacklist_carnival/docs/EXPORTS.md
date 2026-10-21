# Server exports

Exports are server-side only (clients cannot call them). When an export changes state on behalf of a player pass that player's source as `actorSource` — the same permission check as the panel applies. `actorSource = 0` means *system* (the calling resource name is recorded as the actor in the ledger and audit log).

```lua
local event = exports.blacklist_carnival:getCurrentEvent()
```

| Export | Arguments | Returns | Permission |
|---|---|---|---|
| `getCurrentEvent()` | – | Public event state (`id, name, state, stateLabel, round, totalRounds, roundEndsAt, participantCount…`) or `nil`. | none |
| `isEligible(source, attractionId?)` | player source; optional attraction id | `boolean, reasonCode?` — without an attraction: registered and active; with one: the full attraction gate (group scheduled there, session active, valid ticket) except distance. | none |
| `getParticipant(source)` | player source | `{ id, name, colour, status, total, rank }` or `nil` | none |
| `getScore(source)` | player source | `total, breakdown` (`{ [attractionId] = points }`) or `nil` | none |
| `awardPoints(targetSource, delta, reason, idempotencyKey, actorSource?, attractionId?)` | `delta` integer (may be negative); `idempotencyKey` 4–100 chars, unique per award | `true, tx` (`tx.duplicate = true` when the key was already used) or `false, errorCode` | `actorSource == 0` or `scores.adjust` |
| `getAttractionState(attractionId)` | attraction id | `{ id, label, readiness, session, summary }` or `nil` | none |
| `registerExternalResult(targetSource, attractionId, points, resultKey, actorSource?)` | the participant must be eligible for that attraction right now | `true, tx` or `false, errorCode` | `actorSource == 0` or `scores.adjust (was attractions.operate.)<id>` |

Error codes include `not_registered`, `forbidden`, `bad_key`, `invalid_attraction`, `wrong_attraction`, `session_not_active`, `ticket_missing`, `event_not_live`, `event_closed`, `database_error`.

All awards go through the central scoring ledger: clamps, duplicate prevention and auditing apply exactly as for in-game awards.

## Item hooks (used by ox_inventory)

`useTicket`, `useToken`, `useTrickToken`, `useTreatToken`, `usePrizeBox` are registered for the item definitions' `server.export`. They are not intended to be called directly.
