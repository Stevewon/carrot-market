-- ============================================================
-- 0029_wallet_receive_phone.sql — 지갑 인증 방향 변경 + 휴대폰 인증
-- ============================================================
-- 1단계 지갑 인증: 회원이 지갑주소를 넣으면 본사 지갑이 소수점 6자리 임의
--   수량(예: 0.234567 QTA)을 그 지갑으로 보내고, 회원이 받은 수량을 입력하면 통과.
--   direction = 'to_user' 인 행이 이 방식. 기존 'from_user'(회원이 송금)는
--   비밀번호 재설정·예전 앱용으로 남는다.
--
--   send_status: queued → sending → sent  (실패 시 failed, 재시도는 queued 로)
--
-- 2단계 휴대폰 인증: Firebase 휴대폰 문자 인증. 전화번호 평문은 저장하지 않고
--   verified_ci_hash 에 해시만 둔다 (1인 1계정).
--
-- 인증 보너스: 2단계까지 끝나면 1,000 QTA. 사람 단위 1회 — signup_bonus_claims 에
--   'verify:...' 키로 남긴다 (예전 가입 보너스 키와 분리).
-- ============================================================

ALTER TABLE wallet_challenges ADD COLUMN direction TEXT NOT NULL DEFAULT 'from_user';
ALTER TABLE wallet_challenges ADD COLUMN user_id TEXT;
ALTER TABLE wallet_challenges ADD COLUMN send_status TEXT;
ALTER TABLE wallet_challenges ADD COLUMN send_tx_hash TEXT;
ALTER TABLE wallet_challenges ADD COLUMN send_started_at TEXT;
ALTER TABLE wallet_challenges ADD COLUMN send_error TEXT;
ALTER TABLE wallet_challenges ADD COLUMN send_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE wallet_challenges ADD COLUMN confirm_attempts INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_wallet_challenges_send
  ON wallet_challenges(send_status, created_at);

CREATE INDEX IF NOT EXISTS idx_wallet_challenges_user
  ON wallet_challenges(user_id, direction, created_at);
