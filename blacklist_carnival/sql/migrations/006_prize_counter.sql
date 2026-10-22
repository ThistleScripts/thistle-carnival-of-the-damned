-- Carnival of the Damned - migration 006: prize counter
-- Prize-point wallets per character. Points are earned from game scores (never
-- from staff adjustments) and spent at the prize counter. Every change is a
-- ledger row; the unique idempotency key makes credits and purchases replay-safe.

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
