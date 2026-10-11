-- 휴대폰 인증 번호 보관함 — 불법 사용자 추적 전용.
-- 번호는 AES-256-GCM 암호문으로만 저장 (키는 Worker secret PHONE_ENC_KEY, DB 에 없음).
-- 회원 화면·API 어디에도 내보내지 않고, super_admin 이 사유를 남기고 조회할 때만 복호화한다.
-- 탈퇴 후에도 추적할 수 있도록 users 에 FK/CASCADE 를 걸지 않는다.
CREATE TABLE IF NOT EXISTS phone_vault (
  user_id     TEXT PRIMARY KEY,
  phone_enc   TEXT NOT NULL,
  phone_hash  TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_phone_vault_hash ON phone_vault(phone_hash);
