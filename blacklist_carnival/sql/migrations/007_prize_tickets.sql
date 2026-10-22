-- Carnival of the Damned - migration 007: prize tickets per game
-- Prize tickets are earned per attraction (for playing and for points scored
-- there); the attraction is recorded so per-night caps can be enforced.

ALTER TABLE carnival_prize_ledger ADD COLUMN attraction_id VARCHAR(32) NULL AFTER event_id;
ALTER TABLE carnival_prize_ledger ADD KEY idx_prize_ledger_earning (citizenid, event_id, attraction_id, kind);
