-- 한국/일본 시장 분리. 'kr' = 한국어·원화·한국 지역, 'jp' = 일본어·엔화·일본 지역.
-- 회원은 가입할 때 기기 언어로 정해지고, 상품은 올린 사람의 시장을 따른다.
-- 피드는 같은 시장 상품만 보여준다 (일본 사용자에게 한국 동네·원화 상품이 섞이지 않게).
ALTER TABLE users ADD COLUMN market TEXT NOT NULL DEFAULT 'kr';
ALTER TABLE products ADD COLUMN market TEXT NOT NULL DEFAULT 'kr';
CREATE INDEX IF NOT EXISTS idx_products_market ON products(market, created_at DESC);
