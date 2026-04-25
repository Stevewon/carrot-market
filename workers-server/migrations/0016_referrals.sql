-- 친구 초대 (referral) + 즉시 삭감형 탈퇴
--
-- 정책:
--   1) 신규 가입자가 추천인 닉네임을 입력하면, 가입 직후 추천인에게 +200 QTA 1회 지급
--      · 무제한 (한 사람이 몇 명을 초대해도 OK)
--      · 단, "동일한 신규 가입자(referee)" 가 두 번 트리거되지 않도록 멱등키 사용
--      · ledger.idem_key = 'referral:<referee_user_id>'
--      · reason = 'referral_inviter'
--   2) 추천인 자신을 추천하거나, 이미 다른 가입자가 같은 referee 로 처리되면 무시.
--   3) 신규 가입자(referee)에게는 이번에 보너스 X. (가입 +500 만 받음)
--
-- 탈퇴(account deletion) 정책 — "한 번 사라진 건 영구 보관 X" + 즉시 삭감:
--   · 사용자가 탈퇴하면 그 사람이 받았던/지급했던 referral 보너스를 즉시 회수.
--     - 탈퇴자가 추천인이었다면(reason='referral_inviter') → -200 QTA 차감 (clawback)
--     - 탈퇴자가 referee 로 처리됐다면 추천인의 보너스도 -200 회수
--   · users 행은 ON DELETE CASCADE 가 걸려 있어 ledger / referrals 등 자동 정리.
--   · referrals 테이블의 추천인/피추천인 행이 사라져도 idem_key 충돌은 발생하지 않도록
--     ledger.idem_key 만으로 중복 차단. (referrals 는 보조 인덱스성 테이블)

-- ──────────────────────────────────────────────────────
-- 1) referrals — 누가 누구를 초대했는지의 단방향 기록
-- ──────────────────────────────────────────────────────
--   inviter_id  : 추천인 (보너스 받는 사람)
--   referee_id  : 신규 가입자
--   bonus_ledger_id  : 추천인에게 지급된 ledger row id (FK)
--   clawback_ledger_id : 회수가 발생한 경우의 ledger row id
--   status      : 'granted' | 'clawed_back'
--
-- referee_id UNIQUE → 한 신규 가입자는 단 한 번만 누군가의 추천 보너스를 트리거.
CREATE TABLE IF NOT EXISTS referrals (
  id                  TEXT PRIMARY KEY,
  inviter_id          TEXT NOT NULL,
  referee_id          TEXT NOT NULL UNIQUE,
  status              TEXT NOT NULL DEFAULT 'granted'
                        CHECK (status IN ('granted','clawed_back')),
  bonus_ledger_id     TEXT,
  clawback_ledger_id  TEXT,
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (inviter_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (referee_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_referrals_inviter
  ON referrals(inviter_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_referrals_status
  ON referrals(status);

-- ──────────────────────────────────────────────────────
-- 2) ledger reason 확장 안내 (코드 레벨)
-- ──────────────────────────────────────────────────────
--   'referral_inviter'         : 추천인 +200 보너스
--   'referral_clawback'        : 탈퇴 시 -200 회수 (ledger amount = -200)
--   'account_deletion_balance' : 탈퇴 시 잔여 balance 폐기 ledger (amount = -balance)
--
--   ※ 탈퇴 시 users 행 DELETE 직전에 위 ledger 들을 한꺼번에 batch 로 기록한 뒤,
--     사용자 행을 지우면 ON DELETE CASCADE 로 ledger / referrals 가 모두 정리됨.
--     "한 번 사라진 건 영구 보관 X" 원칙: 탈퇴자에 대한 모든 흔적은 즉시 사라짐.
