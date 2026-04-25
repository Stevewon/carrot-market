-- QTA 토큰 경제 (회원가입 +500, 로그인 +10×3/day, 거래완료 +10 each)
--
-- 정책:
--   1) 회원가입 시 +500 QTA 1회 (멱등: ledger.idem_key = 'signup:<user_id>')
--   2) 로그인 시 +10 QTA, 하루 3회까지 (qta_daily_login 카운터)
--   3) 거래완료(status -> 'sold') 시 판매자·구매자 각 +10 QTA
--      (멱등: ledger.idem_key = 'trade:<product_id>:<role>')
--
-- 모든 적립/차감은 qta_ledger 한 줄로 기록되며 users.qta_balance 는 그 합계.
-- 음수 amount 도 허용 (향후 수수료/이체용). 잔액은 절대 음수가 되지 않도록 서버 코드에서 가드.

-- ───────────────────────────────────────────
-- 1) users.qta_balance 컬럼
-- ───────────────────────────────────────────
ALTER TABLE users ADD COLUMN qta_balance INTEGER NOT NULL DEFAULT 0;

-- ───────────────────────────────────────────
-- 2) qta_ledger — 모든 변동 한 줄씩
-- ───────────────────────────────────────────
--   reason 분류:
--     'signup'         : 가입 보너스
--     'login_daily'    : 로그인 일일 보너스
--     'trade_seller'   : 거래완료 판매자 보너스
--     'trade_buyer'    : 거래완료 구매자 보너스
--     (앞으로 'transfer','fee','refund' 등 자유 확장)
--
--   idem_key (UNIQUE) — 중복 지급 차단:
--     signup:<user_id>
--     login_daily:<user_id>:<ymd>:<n>      (n = 1,2,3)
--     trade:<product_id>:seller
--     trade:<product_id>:buyer
CREATE TABLE IF NOT EXISTS qta_ledger (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  amount      INTEGER NOT NULL,                       -- + 입금 / - 출금
  reason      TEXT NOT NULL,
  idem_key    TEXT NOT NULL,
  meta        TEXT,                                   -- JSON 문자열, 자유. (예: {"product_id":"..."})
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE (idem_key)
);

CREATE INDEX IF NOT EXISTS idx_qta_ledger_user_created
  ON qta_ledger(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_qta_ledger_reason
  ON qta_ledger(reason);

-- ───────────────────────────────────────────
-- 3) qta_daily_login — 일일 로그인 카운터 (하루 3회 제한)
-- ───────────────────────────────────────────
--   ymd: 'YYYY-MM-DD' (UTC). 클라이언트의 timezone 다양성 + 서버 일관성 유지를 위해 UTC.
CREATE TABLE IF NOT EXISTS qta_daily_login (
  user_id     TEXT NOT NULL,
  ymd         TEXT NOT NULL,
  count       INTEGER NOT NULL DEFAULT 0,
  updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, ymd),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_qta_daily_login_ymd
  ON qta_daily_login(ymd);
