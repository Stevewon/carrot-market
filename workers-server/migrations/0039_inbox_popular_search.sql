-- 0039: 알림함 (당근식) — 푸시가 사라져도 앱에서 다시 볼 수 있게 서버에 30일 보관.
--   키워드 알림은 사생활 보호로 서버에 남기지 않는다 (앱 안에만 저장).
--   type: price_drop | purchase_confirm | review_request | review_received
CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  product_id TEXT,
  target_user_id TEXT,
  thumb TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  read_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, created_at DESC);

-- 인기 검색어 — 시장·날짜별 검색 횟수 (검색한 사람은 남기지 않는다).
CREATE TABLE IF NOT EXISTS search_terms (
  market TEXT NOT NULL,
  term TEXT NOT NULL,
  day TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (market, term, day)
);
CREATE INDEX IF NOT EXISTS idx_search_terms_day ON search_terms(market, day);
