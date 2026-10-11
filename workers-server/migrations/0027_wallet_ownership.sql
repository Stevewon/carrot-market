-- ============================================================
-- 0027_wallet_ownership.sql — 지갑 소유 증명 (소액 송금 인증)
-- ============================================================
-- 문제: 가입 시 지갑주소를 입력만 받아서, 남의 지갑주소로 먼저 가입(선점)할 수
--       있었다. 지갑주소는 상품 상세 등에 공개되는 값이다.
--
-- 해결: 서버가 고유 소액(예: 0.0042 QTA)을 정해주면 사용자가 그 지갑에서
--       송금(본인 지갑으로 보내도 됨)하고, 서버가 Quantarium 익스플로러에서
--       "그 지갑이 보낸" 거래를 확인한다. 보낸 쪽(from)이 그 지갑이라는 것은
--       개인키를 가진 사람만 만들 수 있으므로 소유 증명이 된다.
--
--   purpose = 'register' : 신규 가입
--   purpose = 'reset'    : 비밀번호 재설정 (등록 기기 분실/재설치, 선점 계정 회수)
--   purpose = 'verify'   : 로그인한 회원의 지갑 확인 (출금 조건)
--
--   status: pending → verified (거래 확인) → used (가입/재설정에 1회 사용)
--   tx_hash UNIQUE — 같은 거래로 두 번 인증 불가.
-- ============================================================

CREATE TABLE IF NOT EXISTS wallet_challenges (
  id              TEXT PRIMARY KEY,
  wallet_address  TEXT NOT NULL,             -- lowercase 0x...
  purpose         TEXT NOT NULL CHECK (purpose IN ('register', 'reset', 'verify')),
  device_uuid     TEXT NOT NULL,
  amount_wei      TEXT NOT NULL,
  amount_display  TEXT NOT NULL,             -- '0.0042'
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'verified', 'used')),
  tx_hash         TEXT UNIQUE,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at      TEXT NOT NULL,
  verified_at     TEXT,
  used_at         TEXT,
  last_checked_at TEXT,
  client_ip       TEXT                       -- 발급 요청 IP (IP당 동시 발급 제한용)
);

CREATE INDEX IF NOT EXISTS idx_wallet_challenges_ip
  ON wallet_challenges(client_ip, status);

CREATE INDEX IF NOT EXISTS idx_wallet_challenges_wallet
  ON wallet_challenges(wallet_address, purpose, status);

-- 소유 증명을 거친 계정 표시. 이전 가입자는 NULL (운영 화면에서 구분용).
ALTER TABLE users ADD COLUMN wallet_verified_at TEXT;
