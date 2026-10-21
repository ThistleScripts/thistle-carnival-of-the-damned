-- Carnival of the Damned - migration 005: world props
-- Props placed in the world with the admin prop placer. Every player spawns
-- them locally; removing one keeps the row (deleted_at) for history.

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
