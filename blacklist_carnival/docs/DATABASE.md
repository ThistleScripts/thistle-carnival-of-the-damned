# Database reference

* Engine InnoDB, charset utf8mb4. All tables are prefixed `carnival_`.
* **Timestamps are UTC unix epoch seconds** (`BIGINT UNSIGNED`) — unambiguous regardless of server/database time zone; the NUI formats them in the viewer's local time.
* Migrations: `sql/migrations/NNN_name.sql`, applied in order at start and recorded in `carnival_schema_migrations` (with a checksum; edited migrations raise a warning). Statements are idempotent. Add new migrations as new files and list them in `Db.MIGRATIONS` (`server/persistence.lua`). Current migrations: 001 initial schema, 002 attraction seed, 003 theatre timer columns, 004 walk-up mode (`carnival_events.mode`, session `kind`, optional round/colour, `carnival_session_members`), 005 world props (`carnival_props`), 006 prize counter (`carnival_prize_wallets`, `carnival_prize_ledger`), 007 prize tickets per game (`carnival_prize_ledger.attraction_id`).
* All queries are parameterised. Related writes (score ledger + summary + total, state change + transition row, config deactivate + insert, group change + history) use `MySQL.transaction`.
* Nothing is deleted except monitoring records past their retention (`Config.Retention`). The audit log is insert-only.

## Tables

| Table | Purpose / key constraints |
|---|---|
| `carnival_schema_migrations` | Applied migrations. |
| `carnival_events` | One row per event; `state`, `mode` (`walkup`/`scheduled`), `resume_state` (when paused), `current_round`, schedule fields, `end_reason`. |
| `carnival_event_transitions` | Every state change with actor and reason. |
| `carnival_config_versions` | Versioned settings documents (`scope` global/event, `version`, `data` JSON, `is_active`, `rollback_of`, author). Unique (scope, event_id, version). |
| `carnival_event_settings` | Frozen effective settings per event at start / completion / cancellation, with the config versions in force. |
| `carnival_attractions` | Attraction registry (seeded). |
| `carnival_attraction_status` | Per-event close/reopen overrides set from the admin Overview. |
| `carnival_participants` | Registration per (event, **citizenid**) — unique; colour, status, cached `total_score`, first/last score time, replacements. |
| `carnival_tickets` | Every ticket ever issued: unique random `serial`, item, virtual flag, status (`active`, `pending_delivery`, `replaced`), issue/invalidation reasons. |
| `carnival_group_assignments` | History of colour assignments/transfers with actor and reason. |
| `carnival_rounds` | Rounds with timer (`ends_at`, `paused_remaining`, `extended_seconds`, `overtime`, `next_round_at`). Unique (event, round). |
| `carnival_attraction_sessions` | `kind = 'round'`: one row per (round, colour): attraction, status (`pending/active/completed/skipped/interrupted`), delay, notes. Unique (event, round, colour) **and** (event, round, attraction) — a round can never send two groups to one attraction. `kind = 'walkup'`: one row per attraction visit in a walk-up event (round and colour are NULL). |
| `carnival_session_members` | Who joined each walk-up visit, with `status` (`joined`/`completed`/`interrupted`) and join/leave times. Unique (session, participant). |
| `carnival_attraction_participation` | Per participant completion of each attraction. Unique (event, participant, attraction). |
| `carnival_score_transactions` | **The scoring ledger.** Requested and applied delta, previous/resulting total, type, source, reason, admin who made it (if any), reversal link, idempotency key. Unique (event, idempotency_key). |
| `carnival_score_summaries` | Per participant per attraction totals (written in the same transaction as the ledger row). |
| `carnival_rewards` | Item rewards: item, count, status, approval, attempts, last error, unique idempotency key. |
| `carnival_reward_attempts` | Every delivery attempt / admin reconciliation. |
| `carnival_wheel_spins` | Each spin with server roll, total weight, outcome, reward link. Unique (event, participant, spin_number). |
| `carnival_fortune_visits` / `carnival_fortune_answers` | Readings (question list, fortune) and answers with question snapshot. Answers unique (event, participant, question). |
| `carnival_theatre_performances` / `carnival_theatre_performers` | Scenario snapshot, status, timings, judging note (how the vote went); performers with role, winner flag, points, bonus. |
| `carnival_deception_rounds` | Mystery snapshot, **answer key**, status, timings, judging note. |
| `carnival_deception_clues` | Released clues. Unique (round, clue). |
| `carnival_deception_submissions` | Structured selections + free-text reasoning; auto/judge points after commit. Unique (round, participant, number). |
| `carnival_horror_runs` / `carnival_horror_runners` / `carnival_horror_tokens` / `carnival_horror_collections` | Runs with settings snapshot and timer; runners (inside/escaped/trapped); token instances per run; collections unique (run, token, participant). |
| `carnival_shooting_heats` / `carnival_shooting_results` | Heats and per-shooter results (hits, shots, bonuses, rejected hits). Results unique (heat, participant). |
| `carnival_staff_assignments` | In-game role grants (license, role, event scope, granted/revoked by + reasons). `attraction_id` is unused since games have no staff. |
| `carnival_event_results` / `carnival_event_result_rows` | Frozen results, versioned per event, with tie-break order and prize tiers. |
| `carnival_props` | World props from the prop placer: model, name, position, rotation, solid flag, who placed/moved it; `deleted_at` marks removed props (rows are kept). |
| `carnival_prize_wallets` | Prize tickets per character (**citizenid** primary key): balance, earned and spent totals. Kept between nights. |
| `carnival_prize_ledger` | Every prize-ticket change: `kind` (`earned` for finishing a game or scoring in it, with `attraction_id` for the per-night cap; `purchase`, `refund`, `adjust`), delta, balance after, item/count/unit price, staff and reason. Unique `idempotency_key` (`score:<tx>`, `play:<session>:<participant>`, `buy:<citizenid>:<request>`, `refund:<row>`, `adjust:<request>`). Written in one transaction with the wallet. |
| `carnival_audit_log` | Administrative audit trail (insert-only). |
| `carnival_monitor_log` | Operational + security monitoring (pruned by retention). |

## Where content lives

Attraction content (wheel outcomes, fortune questions, theatre scenarios, deception mysteries incl. answer keys, horror token positions) is part of the **versioned configuration** so it gets validation, preview, history and rollback. Whenever content is used it is snapshotted into the per-use tables above (`mystery_snapshot` + `answer_key`, `scenario_snapshot`, `question_snapshot`, horror `settings_snapshot` + token rows), so history remains interpretable after the configuration changes.

## Integrity check

`/carnivalverify` or *Score ledger → Verify ledger* checks: participant totals = SUM(ledger), per-attraction summaries = ledger, and every row's `previous_total` = the previous row's `resulting_total`.
