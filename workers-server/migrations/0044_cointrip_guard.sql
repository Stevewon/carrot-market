-- ============================================================
-- 0044_cointrip_guard.sql — 위치 조작 대책 (사장님 지시 2026-10-19)
-- ============================================================
-- 위치 조작은 완전히 막을 수 없으니 조작해도 많이 못 챙기게:
--   1) 하루 줍기 한도 (ct_settings.daily_pick_max, 0 = 한도 없음)
--   2) 출금은 원래 어드민이 직접 보낸다 — 출금 신청 줄에 의심 기록 수를 같이 보여 준다
--   3) 의심 회원 목록 — 순간이동·조작 앱·먼 곳 줍기 시도를 ct_flags 에 남기고,
--      어드민이 코인트립 정지 (ct_settings.blocked_ids) 할 수 있다
--
-- ct_positions: 지도를 보는 동안 앱이 10초마다 보내는 내 위치의 마지막 값 — 다음 위치와 비교해 순간이동을 찾는다.
-- ============================================================

INSERT OR IGNORE INTO ct_settings (key, value) VALUES
  ('daily_pick_max', '50'),     -- 한 사람이 하루(한국 시간 0시 기준)에 주울 수 있는 개수
  ('blocked_ids', '');          -- 코인트립 정지 회원 id (쉼표)

CREATE TABLE IF NOT EXISTS ct_positions (
  user_id  TEXT PRIMARY KEY,
  lat      REAL NOT NULL,
  lng      REAL NOT NULL,
  at       TEXT NOT NULL DEFAULT (datetime('now'))
);

-- kind: mocked (조작 앱 켜고 줍기) | jump (순간이동) | too_fast (줍기 사이 너무 빠름)
--       | too_far (아주 먼 곳에서 줍기 시도) | limit (하루 한도 닿음 — 참고용)
CREATE TABLE IF NOT EXISTS ct_flags (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  kind        TEXT NOT NULL,
  detail      TEXT,
  lat         REAL,
  lng         REAL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ct_flags_user ON ct_flags(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ct_flags_time ON ct_flags(created_at);
