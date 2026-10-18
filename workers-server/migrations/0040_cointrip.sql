-- ============================================================
-- 0040_cointrip.sql — 코인트립 (지도 코인 찾기) 1단계
-- ============================================================
-- 사장님 결정 (2026-10-17, 계획서 7장):
--   - 코인 종류·수량은 어드민이 정한다 (기본 코인 없음).
--   - 받는 지갑: 퀀타리움 소속 코인 → 퀀타리움 월렛(users.wallet_address),
--               일반 코인 → 회원이 따로 등록한 기존 지갑 주소(users.ext_wallet_address).
--     그 지갑이 없는 회원에게는 그 코인이 지도에 아예 안 보인다 (서버가 안 보냄).
--   - 주운 코인은 앱 지갑(ct_balances)에 쌓이고, 어드민이 코인별로 정한 최소 수량
--     이상일 때만 출금 신청.
--   - 친구 연합 최대 50명 (설정값), 주운 사람이 배수만큼 더 (처음 2배).
--   - 잘못 넣은 주소로 지급된 코인은 회원 책임 — 확인 버튼을 누른 기록을 남긴다.
--   - 법률 검토 전에는 켜지 않는다: enabled 기본 0, 테스터만 미리 볼 수 있다.
--
-- 수량은 모두 정수 micro 단위 (1 코인 = 1,000,000) — 소수점 오차 없이 나눈다.
-- ============================================================

CREATE TABLE IF NOT EXISTS ct_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT OR IGNORE INTO ct_settings (key, value) VALUES
  ('enabled', '0'),             -- 1 이면 모든 회원에게 탭이 보인다
  ('tester_ids', ''),           -- 꺼져 있어도 미리 볼 회원 id (쉼표)
  ('pick_radius_m', '30'),      -- 이 거리 안이어야 줍기
  ('precise_radius_m', '300'),  -- 이 거리 안에서만 정확한 위치
  ('finder_multiplier', '2'),   -- 연합 나눔에서 주운 사람 몫 배수
  ('union_max', '50');          -- 연합 최대 인원

-- 코인 종류 (어드민 등록).
CREATE TABLE IF NOT EXISTS ct_coins (
  id               TEXT PRIMARY KEY,
  symbol           TEXT NOT NULL,              -- 'QKEY'
  name             TEXT NOT NULL,              -- '큐키'
  wallet_kind      TEXT NOT NULL CHECK (wallet_kind IN ('quantarium', 'general')),
  network          TEXT NOT NULL DEFAULT '',   -- 출금 안내용 ('Quantarium', 'BNB Smart Chain' 등)
  color            TEXT NOT NULL DEFAULT '#7C3AED',
  withdraw_min_micro INTEGER NOT NULL DEFAULT 0,
  budget_micro     INTEGER,                    -- NULL = 한도 없음
  active           INTEGER NOT NULL DEFAULT 1,
  created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 지도에 뿌린 코인.
CREATE TABLE IF NOT EXISTS ct_drops (
  id           TEXT PRIMARY KEY,
  coin_id      TEXT NOT NULL REFERENCES ct_coins(id),
  amount_micro INTEGER NOT NULL CHECK (amount_micro > 0),
  lat          REAL NOT NULL,
  lng          REAL NOT NULL,
  is_black     INTEGER NOT NULL DEFAULT 0,     -- 1 = 열어봐야 아는 블랙코인
  status       TEXT NOT NULL DEFAULT 'active'
               CHECK (status IN ('active', 'picked', 'cancelled')),
  batch_id     TEXT,                           -- 한 번에 뿌린 묶음
  created_by   TEXT,                           -- 어드민 id
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at   TEXT,                           -- NULL = 기한 없음
  picked_by    TEXT,
  picked_at    TEXT,
  pick_lat     REAL,
  pick_lng     REAL
);

CREATE INDEX IF NOT EXISTS idx_ct_drops_active ON ct_drops(status, lat, lng);
CREATE INDEX IF NOT EXISTS idx_ct_drops_coin ON ct_drops(coin_id, status);
CREATE INDEX IF NOT EXISTS idx_ct_drops_picker ON ct_drops(picked_by, picked_at);

-- 친구 연합.
CREATE TABLE IF NOT EXISTS ct_unions (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  code        TEXT NOT NULL UNIQUE,            -- 초대 코드 (8자)
  owner_id    TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS ct_union_members (
  union_id   TEXT NOT NULL REFERENCES ct_unions(id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL UNIQUE,             -- 한 사람은 한 연합에만
  joined_at  TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (union_id, user_id)
);

-- 앱 지갑 잔액 (코인별).
CREATE TABLE IF NOT EXISTS ct_balances (
  user_id       TEXT NOT NULL,
  coin_id       TEXT NOT NULL,
  amount_micro  INTEGER NOT NULL DEFAULT 0 CHECK (amount_micro >= 0),
  updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, coin_id)
);

-- 앱 지갑 내역.
--   reason: pick (내가 주움) | share (연합원이 주운 몫) | withdrawal | withdrawal_refund
CREATE TABLE IF NOT EXISTS ct_ledger (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL,
  coin_id       TEXT NOT NULL,
  amount_micro  INTEGER NOT NULL,
  reason        TEXT NOT NULL,
  drop_id       TEXT,
  withdrawal_id TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (user_id, drop_id, reason)
);

CREATE INDEX IF NOT EXISTS idx_ct_ledger_user ON ct_ledger(user_id, created_at DESC);

-- 출금 신청 (코인별, 어드민이 직접 보내고 tx 해시 기록).
CREATE TABLE IF NOT EXISTS ct_withdrawals (
  id             TEXT PRIMARY KEY,
  user_id        TEXT NOT NULL,
  coin_id        TEXT NOT NULL,
  amount_micro   INTEGER NOT NULL CHECK (amount_micro > 0),
  wallet_kind    TEXT NOT NULL,
  wallet_address TEXT NOT NULL,                -- 신청 당시 주소 스냅샷
  status         TEXT NOT NULL DEFAULT 'requested'
                 CHECK (status IN ('requested', 'processing', 'completed', 'rejected')),
  requested_at   TEXT NOT NULL DEFAULT (datetime('now')),
  processed_at   TEXT,
  tx_hash        TEXT,
  reject_reason  TEXT
);

CREATE INDEX IF NOT EXISTS idx_ct_withdrawals_status ON ct_withdrawals(status, requested_at);
CREATE INDEX IF NOT EXISTS idx_ct_withdrawals_user ON ct_withdrawals(user_id, requested_at DESC);

-- 일반 코인 받을 기존 지갑 주소 (BNB 등 0x 주소).
ALTER TABLE users ADD COLUMN ext_wallet_address TEXT;
ALTER TABLE users ADD COLUMN ext_wallet_set_at TEXT;

-- "잘못 넣은 주소로 지급된 코인은 회원 책임" 확인 기록.
--   context: ext_wallet (주소 입력) | withdraw (출금 신청) | cointrip_intro (첫 안내)
--   탈퇴해도 지우지 않는다 (분쟁 대비 — 회원 id 와 시각만, 개인정보 없음).
CREATE TABLE IF NOT EXISTS wallet_notice_acks (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     TEXT NOT NULL,
  context     TEXT NOT NULL,
  detail      TEXT,                            -- 확인한 주소 등
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_wallet_notice_acks_user ON wallet_notice_acks(user_id, context);
