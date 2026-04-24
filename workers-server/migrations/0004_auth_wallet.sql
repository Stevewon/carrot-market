-- Eggplant 🍆 - Wallet-based authentication
--
-- Replaces the device_uuid-only auth with wallet_address + password flow.
--
-- Notes:
--  - wallet_address is the permanent "ID" users log in with (Quantarium wallet).
--  - password_hash is PBKDF2-SHA256 (base64) + random salt (base64).
--  - token_version starts at 1 and is bumped whenever the user:
--      * changes their password (all old JWTs become invalid)
--      * logs in from a different device (old device's JWT invalid)
--    This is how we prevent "someone else logging in and staying in".
--  - We KEEP device_uuid on the row for the "currently bound" device, and
--    use UNIQUE(wallet_address) / UNIQUE(nickname) to stop duplicates.

-- 1) Add new columns (nullable first so existing rows don't break).
ALTER TABLE users ADD COLUMN wallet_address   TEXT;
ALTER TABLE users ADD COLUMN password_hash    TEXT;
ALTER TABLE users ADD COLUMN password_salt    TEXT;
ALTER TABLE users ADD COLUMN token_version    INTEGER NOT NULL DEFAULT 1;

-- 2) Unique indexes (case-insensitive for wallet, exact for nickname).
--    COLLATE NOCASE lets us treat "0xAbCd..." and "0xabcd..." as the same.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_wallet_unique
  ON users(wallet_address COLLATE NOCASE)
  WHERE wallet_address IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_nickname_unique
  ON users(nickname COLLATE NOCASE)
  WHERE nickname IS NOT NULL;
