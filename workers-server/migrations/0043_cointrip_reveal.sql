-- ============================================================
-- 0043_cointrip_reveal.sql — 블랙코인 "광고 보고 열기" (사장님 지시 2026-10-18)
-- ============================================================
-- 블랙코인 결과 하나 더: ct_drops.is_dud = 3 → 광고를 끝까지 봐야 어떤 코인이 몇 개인지 보이고 받는다.
-- 광고를 안 보면(그만두기 또는 10분 지남) 못 받고, 그 코인은 지도에 다시 놓인다.
--   status: pending → verified (AdMob 서버 확인 왔음, ssv 모드) → opened (지급) | lost (안 봄)
-- ============================================================

CREATE TABLE IF NOT EXISTS ct_reveals (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL,
  drop_id      TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'opened', 'lost')),
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at   TEXT NOT NULL,
  resolved_at  TEXT
);

CREATE INDEX IF NOT EXISTS idx_ct_reveals_user ON ct_reveals(user_id, status);
CREATE INDEX IF NOT EXISTS idx_ct_reveals_pending ON ct_reveals(status, expires_at);
