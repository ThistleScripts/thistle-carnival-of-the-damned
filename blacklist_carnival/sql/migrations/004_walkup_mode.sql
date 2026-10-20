-- Carnival of the Damned - migration 004: walk-up mode
-- Walk-up events have no rounds: each attraction keeps an open session that
-- players join when they arrive, so the round/colour columns become optional
-- and session membership is stored explicitly.
-- Re-running is safe: MODIFY is idempotent and the runner treats "duplicate
-- column" as applied.

ALTER TABLE carnival_events
    ADD COLUMN mode VARCHAR(16) NOT NULL DEFAULT 'scheduled' AFTER state;

ALTER TABLE carnival_attraction_sessions
    ADD COLUMN kind VARCHAR(16) NOT NULL DEFAULT 'round' AFTER event_id;

ALTER TABLE carnival_attraction_sessions
    MODIFY round_id INT UNSIGNED NULL,
    MODIFY round_number TINYINT UNSIGNED NULL,
    MODIFY colour VARCHAR(16) NULL;

CREATE TABLE IF NOT EXISTS carnival_session_members (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    session_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'joined',
    joined_at BIGINT UNSIGNED NOT NULL,
    left_at BIGINT UNSIGNED NULL,
    UNIQUE KEY uq_session_member (session_id, participant_id),
    KEY idx_session_member_participant (participant_id),
    CONSTRAINT fk_session_member_session FOREIGN KEY (session_id) REFERENCES carnival_attraction_sessions (id),
    CONSTRAINT fk_session_member_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
