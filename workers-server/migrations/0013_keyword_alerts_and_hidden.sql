-- P2-3: 키워드 알림 + P2-4: 게시물 숨김
--
-- 1) keyword_alerts
--    사용자가 등록한 검색 키워드. 새 상품이 등록되면 키워드와 매칭되는 사용자에게
--    WebSocket 으로 알림(type:'keyword_alert') 을 발송한다. 알림 자체는 휘발성 —
--    DB 에 알림 이력은 남기지 않는다.
--
--    제약:
--      - 한 사용자당 최대 5개. (서버에서 INSERT 전에 체크)
--      - 키워드는 trim, 소문자(lower) 로 저장 — 매칭 시 product.title/description 의
--        lower 와 LIKE 비교.
--      - UNIQUE(user_id, keyword) 로 중복 방지.
--      - 사생활 보호: alerted 이력은 절대 저장하지 않음. 발송됐는지 추적 안 함.
--
-- 2) hidden_products
--    사용자가 "이 게시물 숨기기" 를 누르면 (user_id, product_id) 를 기록.
--    피드/검색 결과에서 자동 제외된다. 본인 외 누구도 알 수 없다.
--
--    제약:
--      - PRIMARY KEY(user_id, product_id) — idempotent.
--      - product 가 삭제되면 cascade.
--      - hidden_users 같은 "이 사용자 모든 게시물 숨김" 은 차단(blocks)과 비슷하지만
--        피드 필터에 적용된다는 점이 다름. 이번 마이그레이션에서는 단일 게시물
--        숨김만 다룸. 사용자 단위 숨김은 ModerationService 의 blocks 가 이미 같은
--        효과(차단 사용자의 글이 보이지 않음)를 내도록 products GET 에 join 만 추가.

-- ────────────────────────────────────────────────────────────────────────
-- 1) keyword_alerts
-- ────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS keyword_alerts (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  keyword     TEXT NOT NULL,                       -- 정규화된 lower 형태
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE (user_id, keyword)
);

CREATE INDEX IF NOT EXISTS idx_keyword_alerts_user
  ON keyword_alerts(user_id);

-- 새 상품 fanout 시 keyword 로 빠르게 후보 user_id 를 찾기 위함.
CREATE INDEX IF NOT EXISTS idx_keyword_alerts_keyword
  ON keyword_alerts(keyword);

-- ────────────────────────────────────────────────────────────────────────
-- 2) hidden_products
-- ────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS hidden_products (
  user_id     TEXT NOT NULL,
  product_id  TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, product_id),
  FOREIGN KEY (user_id)    REFERENCES users(id)    ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_hidden_products_user
  ON hidden_products(user_id);
