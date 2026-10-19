# Security review checklist

| # | Requirement | Implementation | Verified by |
|---|---|---|---|
| 1 | Every client request untrusted | Single router (`server/api.lua`); payload must be a table; every endpoint validates fields (`shared/validation.lua`). | static + integration tests |
| 2 | Server-side permission checks | Router enforces `perm`/`anyPerm` before handlers; commands and exports re-check; attraction operators scoped per attraction. | `unauthorised panel and privileged calls…`, `in-game grants…` |
| 3 | No client-side scoring | No participant endpoint accepts points; all awards are computed server-side and written by `Scoring.award` only. | `players cannot award themselves points` |
| 4 | Idempotent scoring | Deterministic keys (spin id, token id, performance id, request id…) + unique DB constraint. | wheel/theatre/deception/fortune/adjust tests |
| 5 | Authoritative timers | Single 1 Hz server ticker for rounds, horror runs, heats, theatre, deception. Clients only render `endsAt`. | `countdown warnings…`, `round timer…`, `pause freezes…` |
| 6 | Server RNG | Wheel outcome, token subsets, question selection use server `math.random`; the client animates to the server's result. | `wheel weights follow configured probabilities` |
| 7 | Distance validation | Server reads ped coordinates for registration, attractions, token collection, horror exit, shooting stand. | `players must be at the ticket booth`, horror/shooting tests |
| 8 | Event membership / stale IDs | Eligibility checks event id, participant status, colour session, completed attractions; run/heat/round ids must match the current one. | horror `stale run id`, deception `stale` |
| 9 | Forged / stale tickets | Random serial per ticket stored in DB; tickets valid only if serial + participant + event + item match the single active row; others logged as forged/stale/foreign. | `ticket replacement voids…` |
| 10 | Secret separation | Deception answer key/briefs/statements and fortune answers never in participant payloads; config redaction by permission; performers only get their own brief. | `secret answer key never reaches participants`, `secret fields are redacted` |
| 11 | Rate limits & abuse | Per-player buckets per endpoint group; repeated rejects raise one security alert; **no automatic bans**. | `rate limits reject floods…` |
| 12 | Duplicate submissions | Unique constraints + per-participant locks (wheel, fortune, deception, horror token, theatre/deception commit guards). | multiple tests |
| 13 | Idempotent rewards | Reward row with unique key created first; delivery claims the row with a guarded UPDATE; interrupted deliveries become `unknown`, never replayed. | `special prizes…`, `restart…` |
| 14 | Inventory input | Item names never come from clients; configured items are checked against `ox_inventory:Items()`; quantities bounded; tickets can never be rewards. | `reward items in config are validated…`, `item_not_permitted` |
| 15 | No unrestricted DB access from NUI | NUI can only call named endpoints; there is no generic query endpoint. | code review |
| 16 | Secrets never sent to clients | `config.lua` is a server script; webhooks from convars; licenses only shown to `participants.manage`/`staff.manage`. | manifest check |
| 17 | Bootstrap model cannot be bypassed | DB grants capped by `MaxGrantableRank` and the granter's rank; owner/admin only via config/ACE; gameplay config cannot change security settings. | `in-game grants cannot exceed…` |
| 18 | Audit | Append-only audit for config, state, tickets, groups, scores, rewards, staff, attraction controls, exports. | `audit log is append-only…` |
| 19 | Safe cleanup | `onResourceStop`: NUI focus released, props/peds/zones/blips removed, sounds stopped, monitoring flushed. | manual test M-NUI-4 |
| 20 | Discord safety | Rate-limited queue, failures never propagate, URLs only from convars. | code review |

## Residual risks (see KNOWN_LIMITATIONS.md)

* Shooting hit detection relies on client-reported impact points (validated, bounded, logged).
* Token positions are sent to runners during a run so the client can render them.
* `math.random` is not a cryptographic RNG; it is server-side and unpredictable to clients, which is sufficient for game outcomes.
