-- ============================================================
-- 0028_qrchat_login.sql — 큐알쳇 닉네임·비밀번호로 가지 로그인
-- ============================================================
-- 큐알쳇 회원이 가지 로그인 화면에 큐알쳇 닉네임·비밀번호를 넣으면, 가지 서버가
-- 큐알쳇 함수(eggplantVerifyHttp)로 확인한 뒤 연결된 가지 계정으로 로그인시킨다
-- (없으면 자동 생성). 연결 기록은 기존 sso_links 에 provider='qrchat_pw',
-- external_id=큐알쳇 uid 로 남긴다.
--
-- 예전 /sso/exchange 가 쓰던 provider='qrchat' 행과 섞이지 않도록 새 provider
-- 이름을 쓰고, 그 provider 에만 (provider, external_id) 유일 인덱스를 건다.
-- (큐알쳇 계정 1개 ↔ 가지 계정 1개, 동시 로그인 경쟁에도 중복 생성 없음)
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_sso_links_qrchat_pw_external
  ON sso_links(provider, external_id)
  WHERE provider = 'qrchat_pw';

-- ------------------------------------------------------------
-- 가입 보너스 1회 보장 (탈퇴 → 재가입 반복 지급 차단)
-- ------------------------------------------------------------
-- 가입 보너스의 멱등 키(qta_ledger.idem_key='signup:<user_id>')는 탈퇴 시 CASCADE 로
-- 같이 지워지고 user_id 도 새로 생겨서, 탈퇴 후 같은 지갑/같은 큐알쳇 계정으로 다시
-- 가입하면 500 QTA 를 또 받을 수 있었다. 사람 단위 키를 탈퇴와 무관하게 보관한다.
--   claim_key: SHA-256('wallet:<lowercase wallet>') | SHA-256('qrchat:<큐알쳇 uid>') (hex)
-- 탈퇴 시 "모든 흔적 삭제" 원칙에 맞춰 지갑·uid 원문은 저장하지 않고 해시만 남긴다.
-- (users FK 없음 — 탈퇴해도 남아야 한다.)
CREATE TABLE IF NOT EXISTS signup_bonus_claims (
  claim_key   TEXT PRIMARY KEY,
  claimed_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
