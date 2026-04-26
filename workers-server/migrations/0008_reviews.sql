-- 0008_reviews.sql
-- 거래후기(transaction reviews) + 매너온도(manner score) tracking — 당근식.
--
-- Flow
--  1. Seller marks a listing as 'sold' and picks the buyer (from chat partners).
--     • products.buyer_id is set so each side knows their counterpart.
--  2. Either side can leave one review per (product, reviewer) pair:
--       rating: 'good' | 'soso' | 'bad'
--       tags  : free-form CSV (예: '시간약속을 잘 지켜요,친절해요')
--  3. The reviewee's users.manner_score is auto-updated by a trigger on insert:
--       good  → +0.5
--       soso  → +0.0
--       bad   → −0.5
--     Clamped to 0..99 (당근의 매너온도는 36.5 시작, 0~99 범위).
--
-- Notes
--  • manner_score는 INTEGER이지만 실제로는 *10 스케일로 저장한다 (e.g. 365 = 36.5°).
--    클라이언트에서 표시할 때 / 10 으로 나눠서 보여준다.
--    기존 데이터는 36 → 365로 한 번에 백필.
--  • 한 번 남긴 후기는 수정/삭제 불가 (UNIQUE(product_id, reviewer_id)).

-- ── 1. products: track buyer when sold ──────────────────────────────
-- NOTE: SQLite ALTER TABLE ADD COLUMN 으로 추가하는 컬럼에는 일부 D1 환경에서
--       REFERENCES (FK) 를 거부하는 케이스가 있어 plain TEXT 로만 추가하고,
--       애플리케이션 레벨에서 정합성을 보장한다 (탈퇴 시 buyer_id NULL 처리).
ALTER TABLE products ADD COLUMN buyer_id TEXT;
CREATE INDEX IF NOT EXISTS idx_products_buyer ON products(buyer_id);

-- ── 2. reviews table ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS reviews (
  id           TEXT PRIMARY KEY,
  product_id   TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  reviewer_id  TEXT NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  reviewee_id  TEXT NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  rating       TEXT NOT NULL CHECK (rating IN ('good', 'soso', 'bad')),
  tags         TEXT NOT NULL DEFAULT '', -- CSV
  comment      TEXT NOT NULL DEFAULT '',
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (product_id, reviewer_id)
);

CREATE INDEX IF NOT EXISTS idx_reviews_reviewee ON reviews(reviewee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reviews_product  ON reviews(product_id);

-- ── 3. backfill manner_score to *10 scale (36 → 365) ────────────────
UPDATE users SET manner_score = manner_score * 10 WHERE manner_score < 100;

-- ── 4. manner_score 업데이트는 애플리케이션 레벨에서 수행 ──────────────
--
-- 원래는 AFTER INSERT 트리거로 자동 업데이트했지만, Cloudflare D1 의
-- migration 적용 단계에서 `CREATE TRIGGER ... BEGIN ... END;` 블록 안의
-- 세미콜론을 statement 종료로 오인해 `incomplete input: SQLITE_ERROR
-- [code: 7500]` 으로 실패한다.
--
-- 따라서 트리거는 정의하지 않고, POST /api/products/:id/review 핸들러
-- (workers-server/src/routes/products.ts) 안에서 INSERT review 다음에
-- 명시적으로 users.manner_score 를 +5 / -5 / 0 (clamped 0..990) 으로
-- 업데이트한다. 이 변경은 같은 batch 안에서 일어나므로 review 와
-- manner_score 가 나뉘어 적용될 위험은 없다.
