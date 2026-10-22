-- Carnival of the Damned - full schema (equivalent to sql/migrations/001-006).
-- Optional: the resource applies migrations automatically on start. Importing this
-- file manually is safe and repeatable (IF NOT EXISTS / INSERT IGNORE); on first
-- start the resource records the migrations as applied (the columns added by 003/004
-- are already present here, which the migration runner accepts).

-- Carnival of the Damned - migration 001: initial schema
-- All timestamps are UTC unix epoch seconds (BIGINT).
-- Statements are idempotent (IF NOT EXISTS) so the migration may be re-run safely.

CREATE TABLE IF NOT EXISTS carnival_schema_migrations (
    version INT UNSIGNED NOT NULL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    checksum VARCHAR(64) NULL,
    applied_at BIGINT UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_events (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(96) NOT NULL,
    description TEXT NULL,
    state VARCHAR(32) NOT NULL DEFAULT 'configuring',
    mode VARCHAR(16) NOT NULL DEFAULT 'scheduled',
    resume_state VARCHAR(32) NULL,
    current_round TINYINT UNSIGNED NOT NULL DEFAULT 0,
    template_of INT UNSIGNED NULL,
    registration_opens_at BIGINT UNSIGNED NULL,
    registration_closes_at BIGINT UNSIGNED NULL,
    scheduled_start BIGINT UNSIGNED NULL,
    scheduled_end BIGINT UNSIGNED NULL,
    started_at BIGINT UNSIGNED NULL,
    ended_at BIGINT UNSIGNED NULL,
    end_reason VARCHAR(500) NULL,
    created_by VARCHAR(80) NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    updated_at BIGINT UNSIGNED NOT NULL,
    KEY idx_events_state (state),
    KEY idx_events_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_event_transitions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    from_state VARCHAR(32) NOT NULL,
    to_state VARCHAR(32) NOT NULL,
    actor VARCHAR(80) NULL,
    actor_name VARCHAR(96) NULL,
    reason VARCHAR(500) NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    KEY idx_transitions_event (event_id, created_at),
    CONSTRAINT fk_transitions_event FOREIGN KEY (event_id) REFERENCES carnival_events (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Versioned configuration. scope = 'global' (event_id NULL) or 'event'.
CREATE TABLE IF NOT EXISTS carnival_config_versions (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    scope VARCHAR(16) NOT NULL,
    event_id INT UNSIGNED NULL,
    version INT UNSIGNED NOT NULL,
    data LONGTEXT NOT NULL,
    checksum VARCHAR(64) NOT NULL,
    note VARCHAR(500) NULL,
    rollback_of INT UNSIGNED NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 0,
    created_by VARCHAR(80) NULL,
    created_by_name VARCHAR(96) NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_config_scope_version (scope, event_id, version),
    KEY idx_config_active (scope, event_id, is_active),
    CONSTRAINT fk_config_event FOREIGN KEY (event_id) REFERENCES carnival_events (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Frozen effective settings for an event (taken at start, completion, cancel).
CREATE TABLE IF NOT EXISTS carnival_event_settings (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    reason VARCHAR(32) NOT NULL,
    global_version INT UNSIGNED NULL,
    event_version INT UNSIGNED NULL,
    data LONGTEXT NOT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    KEY idx_event_settings_event (event_id, created_at),
    CONSTRAINT fk_event_settings_event FOREIGN KEY (event_id) REFERENCES carnival_events (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_attractions (
    id VARCHAR(32) NOT NULL PRIMARY KEY,
    label VARCHAR(96) NOT NULL,
    staff_judged TINYINT(1) NOT NULL DEFAULT 0,
    created_at BIGINT UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Per-event attraction availability overrides set by staff.
CREATE TABLE IF NOT EXISTS carnival_attraction_status (
    event_id INT UNSIGNED NOT NULL,
    attraction_id VARCHAR(32) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'available',
    note VARCHAR(500) NULL,
    updated_by VARCHAR(80) NULL,
    updated_at BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (event_id, attraction_id),
    CONSTRAINT fk_attr_status_event FOREIGN KEY (event_id) REFERENCES carnival_events (id),
    CONSTRAINT fk_attr_status_attr FOREIGN KEY (attraction_id) REFERENCES carnival_attractions (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_participants (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    citizenid VARCHAR(64) NOT NULL,
    license VARCHAR(80) NULL,
    display_name VARCHAR(96) NOT NULL,
    colour VARCHAR(16) NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'active',
    total_score INT NOT NULL DEFAULT 0,
    first_score_at BIGINT UNSIGNED NULL,
    last_score_at BIGINT UNSIGNED NULL,
    replacements TINYINT UNSIGNED NOT NULL DEFAULT 0,
    last_replacement_at BIGINT UNSIGNED NULL,
    registered_by VARCHAR(80) NULL,
    registered_round TINYINT UNSIGNED NOT NULL DEFAULT 0,
    status_reason VARCHAR(500) NULL,
    registered_at BIGINT UNSIGNED NOT NULL,
    last_seen_at BIGINT UNSIGNED NULL,
    UNIQUE KEY uq_participant_event_citizen (event_id, citizenid),
    KEY idx_participant_event_colour (event_id, colour, status),
    KEY idx_participant_event_score (event_id, total_score),
    KEY idx_participant_name (display_name),
    CONSTRAINT fk_participant_event FOREIGN KEY (event_id) REFERENCES carnival_events (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_tickets (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    colour VARCHAR(16) NOT NULL,
    item_name VARCHAR(64) NULL,
    serial VARCHAR(32) NOT NULL,
    is_virtual TINYINT(1) NOT NULL DEFAULT 0,
    status VARCHAR(16) NOT NULL DEFAULT 'issuing',
    delivery_error VARCHAR(255) NULL,
    issued_by VARCHAR(80) NULL,
    issue_reason VARCHAR(500) NULL,
    issued_at BIGINT UNSIGNED NOT NULL,
    invalidated_at BIGINT UNSIGNED NULL,
    invalidated_reason VARCHAR(500) NULL,
    UNIQUE KEY uq_ticket_serial (serial),
    KEY idx_ticket_participant (participant_id, status),
    KEY idx_ticket_event (event_id, status),
    CONSTRAINT fk_ticket_event FOREIGN KEY (event_id) REFERENCES carnival_events (id),
    CONSTRAINT fk_ticket_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_group_assignments (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    from_colour VARCHAR(16) NULL,
    to_colour VARCHAR(16) NULL,
    method VARCHAR(16) NOT NULL,
    actor VARCHAR(80) NULL,
    reason VARCHAR(500) NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    KEY idx_group_assign_participant (participant_id, created_at),
    KEY idx_group_assign_event (event_id, created_at),
    CONSTRAINT fk_group_assign_event FOREIGN KEY (event_id) REFERENCES carnival_events (id),
    CONSTRAINT fk_group_assign_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_rounds (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    round_number TINYINT UNSIGNED NOT NULL,
    state VARCHAR(16) NOT NULL DEFAULT 'active',
    duration_seconds INT UNSIGNED NOT NULL,
    started_at BIGINT UNSIGNED NULL,
    ends_at BIGINT UNSIGNED NULL,
    paused_remaining INT NULL,
    extended_seconds INT NOT NULL DEFAULT 0,
    overtime TINYINT(1) NOT NULL DEFAULT 0,
    completed_at BIGINT UNSIGNED NULL,
    next_round_at BIGINT UNSIGNED NULL,
    UNIQUE KEY uq_round_event_number (event_id, round_number),
    CONSTRAINT fk_round_event FOREIGN KEY (event_id) REFERENCES carnival_events (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per (round, colour group): the group's visit to an attraction.
CREATE TABLE IF NOT EXISTS carnival_attraction_sessions (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    kind VARCHAR(16) NOT NULL DEFAULT 'round',
    round_id INT UNSIGNED NULL,
    round_number TINYINT UNSIGNED NULL,
    colour VARCHAR(16) NULL,
    attraction_id VARCHAR(32) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending',
    delayed_until BIGINT UNSIGNED NULL,
    started_at BIGINT UNSIGNED NULL,
    completed_at BIGINT UNSIGNED NULL,
    completed_by VARCHAR(80) NULL,
    note VARCHAR(500) NULL,
    UNIQUE KEY uq_session_round_colour (event_id, round_number, colour),
    UNIQUE KEY uq_session_round_attraction (event_id, round_number, attraction_id),
    KEY idx_session_status (event_id, status),
    CONSTRAINT fk_session_event FOREIGN KEY (event_id) REFERENCES carnival_events (id),
    CONSTRAINT fk_session_round FOREIGN KEY (round_id) REFERENCES carnival_rounds (id),
    CONSTRAINT fk_session_attraction FOREIGN KEY (attraction_id) REFERENCES carnival_attractions (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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

CREATE TABLE IF NOT EXISTS carnival_attraction_participation (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    attraction_id VARCHAR(32) NOT NULL,
    session_id INT UNSIGNED NOT NULL,
    status VARCHAR(16) NOT NULL,
    completed_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_participation (event_id, participant_id, attraction_id),
    KEY idx_participation_session (session_id),
    CONSTRAINT fk_participation_event FOREIGN KEY (event_id) REFERENCES carnival_events (id),
    CONSTRAINT fk_participation_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id),
    CONSTRAINT fk_participation_session FOREIGN KEY (session_id) REFERENCES carnival_attraction_sessions (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Append-only scoring ledger.
CREATE TABLE IF NOT EXISTS carnival_score_transactions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    citizenid VARCHAR(64) NOT NULL,
    attraction_id VARCHAR(32) NULL,
    round_number TINYINT UNSIGNED NULL,
    session_id INT UNSIGNED NULL,
    requested_delta INT NOT NULL,
    delta INT NOT NULL,
    previous_total INT NOT NULL,
    resulting_total INT NOT NULL,
    tx_type VARCHAR(24) NOT NULL,
    source VARCHAR(48) NOT NULL,
    reason VARCHAR(500) NULL,
    staff_license VARCHAR(80) NULL,
    staff_name VARCHAR(96) NULL,
    reverses_tx BIGINT UNSIGNED NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_score_idempotency (event_id, idempotency_key),
    KEY idx_score_participant (participant_id, id),
    KEY idx_score_event_created (event_id, created_at),
    KEY idx_score_attraction (event_id, attraction_id),
    CONSTRAINT fk_score_event FOREIGN KEY (event_id) REFERENCES carnival_events (id),
    CONSTRAINT fk_score_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cached per-attraction totals; always written in the same DB transaction as the ledger row.
CREATE TABLE IF NOT EXISTS carnival_score_summaries (
    event_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    attraction_id VARCHAR(32) NOT NULL,
    points INT NOT NULL DEFAULT 0,
    positive INT NOT NULL DEFAULT 0,
    negative INT NOT NULL DEFAULT 0,
    tx_count INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (event_id, participant_id, attraction_id),
    CONSTRAINT fk_summary_event FOREIGN KEY (event_id) REFERENCES carnival_events (id),
    CONSTRAINT fk_summary_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_rewards (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    citizenid VARCHAR(64) NOT NULL,
    source VARCHAR(48) NOT NULL,
    item VARCHAR(64) NOT NULL,
    count INT UNSIGNED NOT NULL,
    metadata TEXT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'pending',
    requires_approval TINYINT(1) NOT NULL DEFAULT 0,
    approved_by VARCHAR(80) NULL,
    attempts INT UNSIGNED NOT NULL DEFAULT 0,
    last_error VARCHAR(255) NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    note VARCHAR(500) NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    updated_at BIGINT UNSIGNED NOT NULL,
    delivered_at BIGINT UNSIGNED NULL,
    UNIQUE KEY uq_reward_idempotency (event_id, idempotency_key),
    KEY idx_reward_status (event_id, status),
    KEY idx_reward_participant (participant_id),
    KEY idx_reward_citizen (citizenid, status),
    CONSTRAINT fk_reward_event FOREIGN KEY (event_id) REFERENCES carnival_events (id),
    CONSTRAINT fk_reward_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_reward_attempts (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    reward_id INT UNSIGNED NOT NULL,
    attempt INT UNSIGNED NOT NULL,
    result VARCHAR(24) NOT NULL,
    error VARCHAR(255) NULL,
    actor VARCHAR(80) NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    KEY idx_reward_attempt_reward (reward_id),
    CONSTRAINT fk_reward_attempt_reward FOREIGN KEY (reward_id) REFERENCES carnival_rewards (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Wheel of Misfortune
CREATE TABLE IF NOT EXISTS carnival_wheel_spins (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    session_id INT UNSIGNED NULL,
    spin_number TINYINT UNSIGNED NOT NULL,
    outcome_id VARCHAR(32) NOT NULL,
    outcome_label VARCHAR(48) NOT NULL,
    outcome_type VARCHAR(24) NOT NULL,
    points INT NOT NULL DEFAULT 0,
    item VARCHAR(64) NULL,
    item_count INT UNSIGNED NOT NULL DEFAULT 0,
    reward_id INT UNSIGNED NULL,
    roll DOUBLE NOT NULL,
    total_weight INT UNSIGNED NOT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_wheel_spin (event_id, participant_id, spin_number),
    KEY idx_wheel_session (session_id),
    CONSTRAINT fk_wheel_event FOREIGN KEY (event_id) REFERENCES carnival_events (id),
    CONSTRAINT fk_wheel_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Fortune Teller
CREATE TABLE IF NOT EXISTS carnival_fortune_visits (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    session_id INT UNSIGNED NULL,
    visit_number TINYINT UNSIGNED NOT NULL,
    mode VARCHAR(16) NOT NULL,
    fortune TEXT NULL,
    question_ids TEXT NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'active',
    staff_license VARCHAR(80) NULL,
    started_at BIGINT UNSIGNED NOT NULL,
    finished_at BIGINT UNSIGNED NULL,
    UNIQUE KEY uq_fortune_visit (event_id, participant_id, visit_number),
    CONSTRAINT fk_fortune_visit_event FOREIGN KEY (event_id) REFERENCES carnival_events (id),
    CONSTRAINT fk_fortune_visit_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_fortune_answers (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    visit_id INT UNSIGNED NOT NULL,
    question_id VARCHAR(32) NOT NULL,
    question_snapshot TEXT NOT NULL,
    answer VARCHAR(255) NULL,
    correct TINYINT(1) NOT NULL,
    timed_out TINYINT(1) NOT NULL DEFAULT 0,
    points INT NOT NULL DEFAULT 0,
    created_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_fortune_answer (event_id, participant_id, question_id),
    KEY idx_fortune_answer_visit (visit_id),
    CONSTRAINT fk_fortune_answer_visit FOREIGN KEY (visit_id) REFERENCES carnival_fortune_visits (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Puppet Master's Theatre
CREATE TABLE IF NOT EXISTS carnival_theatre_performances (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    session_id INT UNSIGNED NULL,
    scenario_id VARCHAR(32) NULL,
    scenario_snapshot TEXT NOT NULL,
    is_custom TINYINT(1) NOT NULL DEFAULT 0,
    status VARCHAR(16) NOT NULL DEFAULT 'draft',
    duration_seconds INT UNSIGNED NOT NULL,
    operator_license VARCHAR(80) NULL,
    operator_name VARCHAR(96) NULL,
    judging_note TEXT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    started_at BIGINT UNSIGNED NULL,
    ends_at BIGINT UNSIGNED NULL,
    paused_remaining INT NULL,
    ended_at BIGINT UNSIGNED NULL,
    committed_at BIGINT UNSIGNED NULL,
    KEY idx_theatre_event (event_id, created_at),
    KEY idx_theatre_session (session_id),
    CONSTRAINT fk_theatre_event FOREIGN KEY (event_id) REFERENCES carnival_events (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_theatre_performers (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    performance_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    role_name VARCHAR(64) NULL,
    is_winner TINYINT(1) NOT NULL DEFAULT 0,
    points INT NOT NULL DEFAULT 0,
    participation_bonus INT NOT NULL DEFAULT 0,
    UNIQUE KEY uq_theatre_performer (performance_id, participant_id),
    CONSTRAINT fk_theatre_performer_perf FOREIGN KEY (performance_id) REFERENCES carnival_theatre_performances (id),
    CONSTRAINT fk_theatre_performer_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Hall of Deception. answer_key is never sent to participant clients before reveal.
CREATE TABLE IF NOT EXISTS carnival_deception_rounds (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    session_id INT UNSIGNED NULL,
    mystery_id VARCHAR(32) NOT NULL,
    mystery_snapshot LONGTEXT NOT NULL,
    answer_key TEXT NOT NULL,
    performer_assignments TEXT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'setup',
    operator_license VARCHAR(80) NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    questioning_started_at BIGINT UNSIGNED NULL,
    questioning_ends_at BIGINT UNSIGNED NULL,
    questioning_ended_at BIGINT UNSIGNED NULL,
    revealed_at BIGINT UNSIGNED NULL,
    committed_at BIGINT UNSIGNED NULL,
    judging_note TEXT NULL,
    KEY idx_deception_event (event_id),
    KEY idx_deception_session (session_id),
    CONSTRAINT fk_deception_event FOREIGN KEY (event_id) REFERENCES carnival_events (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_deception_clues (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    round_id INT UNSIGNED NOT NULL,
    clue_id VARCHAR(32) NOT NULL,
    clue_text TEXT NOT NULL,
    released_by VARCHAR(80) NULL,
    released_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_deception_clue (round_id, clue_id),
    CONSTRAINT fk_deception_clue_round FOREIGN KEY (round_id) REFERENCES carnival_deception_rounds (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_deception_submissions (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    round_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    submission_number TINYINT UNSIGNED NOT NULL,
    selections TEXT NOT NULL,
    explanation TEXT NULL,
    recorded_by VARCHAR(80) NULL,
    correct_count TINYINT UNSIGNED NULL,
    incorrect_count TINYINT UNSIGNED NULL,
    auto_points INT NULL,
    judge_points INT NULL,
    judge_note TEXT NULL,
    judged_by VARCHAR(80) NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_deception_submission (round_id, participant_id, submission_number),
    CONSTRAINT fk_deception_sub_round FOREIGN KEY (round_id) REFERENCES carnival_deception_rounds (id),
    CONSTRAINT fk_deception_sub_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- House of Horrors
CREATE TABLE IF NOT EXISTS carnival_horror_runs (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    session_id INT UNSIGNED NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'running',
    duration_seconds INT UNSIGNED NOT NULL,
    settings_snapshot TEXT NOT NULL,
    started_by VARCHAR(80) NULL,
    started_at BIGINT UNSIGNED NOT NULL,
    ends_at BIGINT UNSIGNED NULL,
    paused_remaining INT NULL,
    ended_at BIGINT UNSIGNED NULL,
    end_reason VARCHAR(64) NULL,
    KEY idx_horror_event (event_id, status),
    CONSTRAINT fk_horror_event FOREIGN KEY (event_id) REFERENCES carnival_events (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_horror_runners (
    run_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'inside',
    exited_at BIGINT UNSIGNED NULL,
    seconds_remaining INT NULL,
    boundary_penalised TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (run_id, participant_id),
    CONSTRAINT fk_horror_runner_run FOREIGN KEY (run_id) REFERENCES carnival_horror_runs (id),
    CONSTRAINT fk_horror_runner_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_horror_tokens (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    run_id INT UNSIGNED NOT NULL,
    token_key VARCHAR(32) NOT NULL,
    token_type VARCHAR(16) NOT NULL,
    x DOUBLE NOT NULL,
    y DOUBLE NOT NULL,
    z DOUBLE NOT NULL,
    points INT NOT NULL,
    UNIQUE KEY uq_horror_token (run_id, token_key),
    CONSTRAINT fk_horror_token_run FOREIGN KEY (run_id) REFERENCES carnival_horror_runs (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_horror_collections (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    run_id INT UNSIGNED NOT NULL,
    token_id INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    token_type VARCHAR(16) NOT NULL,
    points INT NOT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_horror_collection (run_id, token_id, participant_id),
    KEY idx_horror_collection_participant (participant_id),
    CONSTRAINT fk_horror_collection_run FOREIGN KEY (run_id) REFERENCES carnival_horror_runs (id),
    CONSTRAINT fk_horror_collection_token FOREIGN KEY (token_id) REFERENCES carnival_horror_tokens (id),
    CONSTRAINT fk_horror_collection_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Shooting Gallery
CREATE TABLE IF NOT EXISTS carnival_shooting_heats (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    session_id INT UNSIGNED NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'running',
    duration_seconds INT UNSIGNED NOT NULL,
    started_by VARCHAR(80) NULL,
    started_at BIGINT UNSIGNED NOT NULL,
    ended_at BIGINT UNSIGNED NULL,
    end_reason VARCHAR(64) NULL,
    KEY idx_shooting_heat_event (event_id),
    CONSTRAINT fk_shooting_heat_event FOREIGN KEY (event_id) REFERENCES carnival_events (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_shooting_results (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    heat_id INT UNSIGNED NOT NULL,
    session_id INT UNSIGNED NULL,
    participant_id INT UNSIGNED NOT NULL,
    hits INT UNSIGNED NOT NULL DEFAULT 0,
    shots INT UNSIGNED NOT NULL DEFAULT 0,
    bullseyes INT UNSIGNED NOT NULL DEFAULT 0,
    specials INT UNSIGNED NOT NULL DEFAULT 0,
    target_points INT NOT NULL DEFAULT 0,
    accuracy_bonus INT NOT NULL DEFAULT 0,
    miss_penalty INT NOT NULL DEFAULT 0,
    points INT NOT NULL DEFAULT 0,
    rejected_hits INT UNSIGNED NOT NULL DEFAULT 0,
    created_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_shooting_result (heat_id, participant_id),
    KEY idx_shooting_result_participant (event_id, participant_id),
    CONSTRAINT fk_shooting_result_heat FOREIGN KEY (heat_id) REFERENCES carnival_shooting_heats (id),
    CONSTRAINT fk_shooting_result_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Staff role grants made in game (bounded by config.lua bootstrap rules).
CREATE TABLE IF NOT EXISTS carnival_staff_assignments (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    license VARCHAR(80) NOT NULL,
    display_name VARCHAR(96) NULL,
    role VARCHAR(32) NOT NULL,
    attraction_id VARCHAR(32) NULL,
    event_id INT UNSIGNED NULL,
    granted_by VARCHAR(80) NOT NULL,
    reason VARCHAR(500) NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    revoked_at BIGINT UNSIGNED NULL,
    revoked_by VARCHAR(80) NULL,
    revoke_reason VARCHAR(500) NULL,
    KEY idx_staff_license (license, revoked_at),
    KEY idx_staff_event (event_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Frozen final results. Each freeze writes a new version; history is never rewritten.
CREATE TABLE IF NOT EXISTS carnival_event_results (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NOT NULL,
    version INT UNSIGNED NOT NULL,
    reason VARCHAR(500) NULL,
    tie_break TEXT NOT NULL,
    data LONGTEXT NOT NULL,
    frozen_by VARCHAR(80) NULL,
    frozen_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_event_results_version (event_id, version),
    CONSTRAINT fk_event_results_event FOREIGN KEY (event_id) REFERENCES carnival_events (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_event_result_rows (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    result_id INT UNSIGNED NOT NULL,
    rank_position INT UNSIGNED NOT NULL,
    participant_id INT UNSIGNED NOT NULL,
    display_name VARCHAR(96) NOT NULL,
    colour VARCHAR(16) NULL,
    total INT NOT NULL,
    breakdown TEXT NOT NULL,
    prize_tier VARCHAR(64) NULL,
    UNIQUE KEY uq_result_row (result_id, participant_id),
    KEY idx_result_rank (result_id, rank_position),
    CONSTRAINT fk_result_row_result FOREIGN KEY (result_id) REFERENCES carnival_event_results (id),
    CONSTRAINT fk_result_row_participant FOREIGN KEY (participant_id) REFERENCES carnival_participants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Administrative audit trail. The application only ever INSERTs into this table.
CREATE TABLE IF NOT EXISTS carnival_audit_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_id INT UNSIGNED NULL,
    actor_license VARCHAR(80) NULL,
    actor_name VARCHAR(96) NULL,
    action VARCHAR(64) NOT NULL,
    target_type VARCHAR(32) NULL,
    target_id VARCHAR(64) NULL,
    reason VARCHAR(500) NULL,
    details TEXT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    KEY idx_audit_event (event_id, created_at),
    KEY idx_audit_actor (actor_license, created_at),
    KEY idx_audit_action (action, created_at),
    KEY idx_audit_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Operational + security monitoring. High volume; pruned by retention settings.
CREATE TABLE IF NOT EXISTS carnival_monitor_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    severity VARCHAR(10) NOT NULL,
    category VARCHAR(32) NOT NULL,
    event_id INT UNSIGNED NULL,
    attraction_id VARCHAR(32) NULL,
    participant_id INT UNSIGNED NULL,
    actor VARCHAR(80) NULL,
    actor_name VARCHAR(96) NULL,
    action VARCHAR(64) NOT NULL,
    result VARCHAR(32) NULL,
    details TEXT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    KEY idx_monitor_created (created_at),
    KEY idx_monitor_category (category, created_at),
    KEY idx_monitor_severity (severity, created_at),
    KEY idx_monitor_event (event_id, created_at),
    KEY idx_monitor_participant (participant_id),
    KEY idx_monitor_actor (actor)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Carnival of the Damned - migration 002: attraction registry seed
-- INSERT IGNORE keeps this idempotent.

INSERT IGNORE INTO carnival_attractions (id, label, staff_judged, created_at) VALUES
    ('shooting', 'The Shooting Gallery', 0, UNIX_TIMESTAMP()),
    ('wheel', 'The Wheel of Misfortune', 0, UNIX_TIMESTAMP()),
    ('fortune', 'The Fortune Teller''s Curse', 0, UNIX_TIMESTAMP()),
    ('puppets', 'The Puppet Master''s Theatre', 1, UNIX_TIMESTAMP()),
    ('deception', 'The Hall of Deception', 1, UNIX_TIMESTAMP()),
    ('horror', 'The House of Horrors', 0, UNIX_TIMESTAMP());

CREATE TABLE IF NOT EXISTS carnival_props (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    model VARCHAR(64) NOT NULL,
    label VARCHAR(64) NULL,
    x DOUBLE NOT NULL,
    y DOUBLE NOT NULL,
    z DOUBLE NOT NULL,
    rot_x DOUBLE NOT NULL DEFAULT 0,
    rot_y DOUBLE NOT NULL DEFAULT 0,
    rot_z DOUBLE NOT NULL DEFAULT 0,
    collision TINYINT(1) NOT NULL DEFAULT 1,
    created_by VARCHAR(80) NULL,
    created_by_name VARCHAR(96) NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    updated_by VARCHAR(80) NULL,
    updated_at BIGINT UNSIGNED NULL,
    deleted_by VARCHAR(80) NULL,
    deleted_at BIGINT UNSIGNED NULL,
    KEY idx_props_active (deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Carnival of the Damned - migration 006: prize counter

CREATE TABLE IF NOT EXISTS carnival_prize_wallets (
    citizenid VARCHAR(64) NOT NULL PRIMARY KEY,
    display_name VARCHAR(96) NULL,
    balance INT NOT NULL DEFAULT 0,
    earned_total INT NOT NULL DEFAULT 0,
    spent_total INT NOT NULL DEFAULT 0,
    created_at BIGINT UNSIGNED NOT NULL,
    updated_at BIGINT UNSIGNED NOT NULL,
    KEY idx_wallet_balance (balance)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS carnival_prize_ledger (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(64) NOT NULL,
    kind VARCHAR(16) NOT NULL,
    delta INT NOT NULL,
    balance_after INT NOT NULL,
    event_id INT UNSIGNED NULL,
    score_tx_id INT UNSIGNED NULL,
    item VARCHAR(64) NULL,
    item_count INT NULL,
    unit_price INT NULL,
    reason VARCHAR(500) NULL,
    staff_license VARCHAR(80) NULL,
    staff_name VARCHAR(96) NULL,
    idempotency_key VARCHAR(160) NOT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_prize_ledger_key (idempotency_key),
    KEY idx_prize_ledger_citizen (citizenid, created_at),
    KEY idx_prize_ledger_kind (kind, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
