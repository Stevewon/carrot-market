-- ============================================================
-- 0042_cointrip_dud.sql — 블랙코인 꽝 + 광고 (사장님 지시 2026-10-18)
-- ============================================================
-- 블랙코인은 모험 (무조건 덥석 줍지 말라는 것): 대부분 좋은 코인, 가끔 꽝이나 벌칙.
--   ct_drops.is_dud = 0 : 좋은 코인 · 1 : 꽝 (아무것도 없음) · 2 : 벌칙 (is_black = 1 인 것만, 지급 없음)
-- 벌칙이면 구글 보상형 광고를 보면 그냥 넘어가고, 안 보면 갖고 있는 QTA 에서 10개(설정값)를 내놓는다.
--   ct_dud_penalties     : 벌칙 한 번 = 한 줄. pending → ad (광고 봄) | paid (QTA 냄)
--     10분 안에 정하지 않으면 paid 로 처리한다 (광고를 안 본 것).
-- ============================================================

ALTER TABLE ct_drops ADD COLUMN is_dud INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS ct_dud_penalties (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL,
  drop_id      TEXT NOT NULL UNIQUE,
  qta          INTEGER NOT NULL,              -- 안 보면 낼 QTA
  status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'ad', 'paid')),
  deducted     INTEGER NOT NULL DEFAULT 0,    -- 실제로 뺀 QTA (잔액이 모자라면 있는 만큼)
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at   TEXT NOT NULL,
  resolved_at  TEXT
);

CREATE INDEX IF NOT EXISTS idx_ct_dud_user ON ct_dud_penalties(user_id, status);
CREATE INDEX IF NOT EXISTS idx_ct_dud_pending ON ct_dud_penalties(status, expires_at);

INSERT OR IGNORE INTO ct_settings (key, value) VALUES
  ('dud_penalty_qta', '10'),
  -- client: 앱이 "광고 끝까지 봄"을 알려 주면 인정 / ssv: AdMob 서버 확인 콜백이 와야 인정
  ('ad_verify', 'client'),
  -- 보상형 광고 단위 (처음은 구글 테스트 광고). 실제 광고 단위 ID 를 받으면 어드민에서 바꾼다.
  ('rewarded_ad_unit', 'ca-app-pub-3940256099942544/5224354917');
