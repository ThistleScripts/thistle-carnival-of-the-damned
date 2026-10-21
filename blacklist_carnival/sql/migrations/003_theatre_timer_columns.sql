-- Carnival of the Damned - migration 003: theatre performance timer columns
-- The theatre timer (pause/resume) stores its end time and frozen remainder.
-- Re-running is safe: the migration runner treats "duplicate column" as applied.

ALTER TABLE carnival_theatre_performances
    ADD COLUMN ends_at BIGINT UNSIGNED NULL AFTER started_at,
    ADD COLUMN paused_remaining INT NULL AFTER ends_at;
