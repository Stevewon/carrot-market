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
ALTER TABLE products ADD COLUMN buyer_id TEXT REFERENCES users(id) ON DELETE SET NULL;

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

-- ── 4. auto‑update manner_score on review insert ────────────────────
CREATE TRIGGER IF NOT EXISTS trg_reviews_update_manner
AFTER INSERT ON reviews
FOR EACH ROW
BEGIN
  UPDATE users
     SET manner_score = MIN(990, MAX(0,
           manner_score + CASE NEW.rating
             WHEN 'good' THEN 5   -- +0.5°
             WHEN 'bad'  THEN -5  -- -0.5°
             ELSE 0
           END
         )),
         updated_at = datetime('now')
   WHERE id = NEW.reviewee_id;
END;
