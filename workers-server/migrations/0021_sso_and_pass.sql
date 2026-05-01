-- SSO 통합 + PASS 본인인증 연계
--
-- 정책:
--   1) "퀀타리움 지갑주소 = Universal User ID"
--      QRChat 과 가지(Eggplant)는 같은 회사 자매 앱.
--      한쪽에서 가입/로그인하면 반대쪽이 자동으로 같은 계정 인식.
--      식별 키는 오직 wallet_address.
--
--   2) /api/auth/sso/exchange 가 QRChat 토큰 + wallet_address 를 받아
--      자동으로 가지 계정을 생성/조회하고 가지 JWT 를 돌려준다.
--
--   3) 본인인증은 PASS(통합본인인증) 사용 가정. 휴대폰 번호 자체는 저장 X,
--      CI(Connecting Information) 의 SHA-256 해시만 저장.

-- ───────────────────────────────────────────
-- 1) sso_links — 어느 외부 앱(QRChat 등)에서 어느 시각에 SSO 로 들어왔는지
--                기록. 같은 wallet_address 로 여러 외부 앱이 로그인할 수 있다.
-- ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sso_links (
  id              TEXT PRIMARY KEY,
  user_id         TEXT NOT NULL,
  provider        TEXT NOT NULL,                  -- 'qrchat', 'eggplant_self', ...
  external_id     TEXT,                           -- 외부 앱이 부여한 ID (옵션)
  wallet_address  TEXT NOT NULL,
  device_uuid     TEXT,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at    TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sso_links_provider_user
  ON sso_links(provider, user_id);
CREATE INDEX IF NOT EXISTS idx_sso_links_wallet
  ON sso_links(wallet_address);

-- ───────────────────────────────────────────
-- 2) PASS 본인인증 트랜잭션 로그
--    - tx_id : PASS 가 발급한 거래 식별자 (멱등키)
--    - ci_hash : SHA-256(CI). 사용자 동일성 검증에만 사용.
--    - status : pending / verified / failed / expired
-- ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pass_verifications (
  tx_id        TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL,
  ci_hash      TEXT,                              -- SHA-256(CI). 성공 시에만 채움.
  status       TEXT NOT NULL DEFAULT 'pending',
  provider     TEXT NOT NULL DEFAULT 'pass',      -- 'pass' / 'sms' / 'kisa'
  requested_at TEXT NOT NULL DEFAULT (datetime('now')),
  verified_at  TEXT,
  fail_reason  TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_pass_user_status
  ON pass_verifications(user_id, status);

-- ───────────────────────────────────────────
-- 3) verification_audit — 본인인증 시도/성공 감사 로그
--    실제 운영에서 어느 provider 로 어떤 트랜잭션이 성공했는지 추적용.
--    개인정보(휴대폰 번호 평문)는 절대 저장하지 않고, 클라이언트가
--    보낸 phone_hash(SHA-256) 만 옵션으로 보관.
-- ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS verification_audit (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  provider    TEXT NOT NULL,                      -- 'pass' / 'sms' / 'kisa' / 'dummy'
  tx_id       TEXT,                               -- provider 가 발급한 트랜잭션 ID
  phone_hash  TEXT,                               -- SHA-256(phone). 평문 절대 X
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_verif_audit_user
  ON verification_audit(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_verif_audit_provider
  ON verification_audit(provider, created_at DESC);
