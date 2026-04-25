-- Eggplant 🍆 - "Bump" (끌어올리기) for products
--
-- 당근 style: sellers can re-promote a stale listing to the top of the feed
-- once every 24 hours. We track the last bump timestamp on the product row
-- and sort the feed by COALESCE(bumped_at, created_at) DESC.
--
-- Why a separate column (and not just touching created_at)?
--   created_at is referenced by analytics, the seller's own listing history,
--   and product_likes ordering. Mutating it would corrupt all of those.
--   bumped_at is purely a presentational hint for the feed.

ALTER TABLE products ADD COLUMN bumped_at TEXT;

-- Index for the feed ORDER BY. Most rows will have bumped_at = NULL initially,
-- so the COALESCE(bumped_at, created_at) expression in the query benefits more
-- from the existing idx_products_created_at; we add a secondary index for
-- products that HAVE been bumped to keep that hot path fast.
CREATE INDEX IF NOT EXISTS idx_products_bumped_at ON products(bumped_at DESC)
  WHERE bumped_at IS NOT NULL;
