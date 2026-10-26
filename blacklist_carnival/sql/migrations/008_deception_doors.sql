-- Carnival of the Damned - migration 008: Hall of Deception door maze
-- The Hall of Deception is now a maze of doors: each player's run is recorded
-- here (the old mystery tables are kept for history but no longer written).

CREATE TABLE IF NOT EXISTS carnival_deception_runs (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    session_id INT UNSIGNED NULL,
    participant_id INT UNSIGNED NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'running',
    started_at BIGINT UNSIGNED NOT NULL,
    ends_at BIGINT UNSIGNED NOT NULL,
    ended_at BIGINT UNSIGNED NULL,
    end_reason VARCHAR(32) NULL,
    doors_used INT UNSIGNED NOT NULL DEFAULT 0,
    resets INT UNSIGNED NOT NULL DEFAULT 0,
    points INT NOT NULL DEFAULT 0,
    KEY idx_deception_runs_event (event_id, status),
    KEY idx_deception_runs_participant (participant_id, session_id),
    CONSTRAINT fk_deception_runs_event FOREIGN KEY (event_id) REFERENCES carnival_events (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
