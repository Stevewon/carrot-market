-- 프로필 인증 (Verification) 시스템
--
-- 정책:
--   1) 가입 직후 verification_level = 0 (익명, 둘러보기·채팅·통화·상품등록 가능)
--   2) 본인인증 후 verification_level = 1 (KRW/QTA 결제 가능)
--   3) 계좌 등록 후 verification_level = 2 (QTA 출금 가능)
--
-- 저장 정책:
--   - 휴대폰 번호 자체는 절대 저장하지 않음
--   - 본인인증 토큰(CI, Connecting Information)의 SHA-256 해시만 저장
--   - 같은 사람이 여러 계정 만드는지 검증할 때만 사용
--
-- 채팅·통화는 익명성 그대로 유지 (verification_level 무관, 닉네임만 사용).
-- 거래/결제/출금 단계에서만 verification_level 체크.

-- ───────────────────────────────────────────
-- 1) users 테이블에 인증 컬럼 추가
-- ───────────────────────────────────────────
ALTER TABLE users ADD COLUMN verification_level INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN verified_ci_hash TEXT;        -- SHA-256(CI), 미인증 시 NULL
ALTER TABLE users ADD COLUMN verified_at TEXT;             -- ISO-8601, 미인증 시 NULL
ALTER TABLE users ADD COLUMN bank_account_hash TEXT;       -- SHA-256(bank+account), 미등록 시 NULL
ALTER TABLE users ADD COLUMN bank_registered_at TEXT;      -- ISO-8601, 미등록 시 NULL

-- ───────────────────────────────────────────
-- 2) 같은 CI(같은 사람)가 여러 계정 못 만들도록 UNIQUE
--    (NULL은 UNIQUE 제약 무시되므로 미인증 계정은 영향 없음)
-- ───────────────────────────────────────────
CREATE UNIQUE INDEX idx_users_ci_unique ON users(verified_ci_hash)
WHERE verified_ci_hash IS NOT NULL;
