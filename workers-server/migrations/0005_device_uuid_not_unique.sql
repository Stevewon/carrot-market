-- Eggplant 🍆 - Drop UNIQUE constraint on users.device_uuid
--
-- WHY:
--   Migration 0001 declared `device_uuid TEXT NOT NULL UNIQUE` because the
--   original auth model used device_uuid AS the identity. With wallet+password
--   auth (migration 0004), device_uuid is now just a "currently bound device"
--   marker — multiple wallets CAN legitimately share one phone (family,
--   dev/QA, re-signup after logout, etc.).
--
--   The UNIQUE constraint now causes `INSERT INTO users ...` to fail with
--   `UNIQUE constraint failed: users.device_uuid` whenever a second wallet
--   tries to register on the same device.
--
-- HOW:
--   SQLite can't ALTER TABLE DROP CONSTRAINT, so we rebuild the users table.
--   We preserve every row (id → updated_at) exactly as-is.
--
--   The FK in products(seller_id) points at users(id), which stays stable
--   through a rename-and-copy, so no CASCADE is triggered.
--
-- NOTE (D1):
--   Cloudflare D1 자동으로 statement 들을 atomic batch 로 실행하기 때문에
--   `BEGIN TRANSACTION`/`COMMIT`/`SAVEPOINT`/`PRAGMA foreign_keys` 같은
--   세션 제어 SQL 은 거부된다 (error code 7500). 따라서 raw 트랜잭션은
--   삭제하고 D1 batch 의 atomic 보장에 의존한다.

-- 1) Rename the old table out of the way.
ALTER TABLE users RENAME TO users_old;

-- 2) Create the new table with device_uuid as plain NOT NULL (no UNIQUE).
CREATE TABLE users (
  id              TEXT PRIMARY KEY,
  nickname        TEXT NOT NULL,
  device_uuid     TEXT NOT NULL,
  wallet_address  TEXT,
  password_hash   TEXT,
  password_salt   TEXT,
  token_version   INTEGER NOT NULL DEFAULT 1,
  region          TEXT,
  manner_score    INTEGER NOT NULL DEFAULT 36,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 3) Copy every row over unchanged.
INSERT INTO users (
  id, nickname, device_uuid,
  wallet_address, password_hash, password_salt, token_version,
  region, manner_score, created_at, updated_at
)
SELECT
  id, nickname, device_uuid,
  wallet_address, password_hash, password_salt, token_version,
  region, manner_score, created_at, updated_at
FROM users_old;

-- 4) Drop the old table.
DROP TABLE users_old;

-- 5) Re-create indexes that 0001 + 0004 created on the original table.
--    (Dropping the table also dropped its indexes.)
CREATE INDEX IF NOT EXISTS idx_users_device_uuid ON users(device_uuid);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_wallet_unique
  ON users(wallet_address COLLATE NOCASE)
  WHERE wallet_address IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_nickname_unique
  ON users(nickname COLLATE NOCASE)
  WHERE nickname IS NOT NULL;
