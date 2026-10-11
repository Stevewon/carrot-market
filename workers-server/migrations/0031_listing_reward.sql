-- 상품 등록 채굴: 등록 가격의 10% 를 QTA(1 QTA = 10원 고정)로 지급.
-- 이 상품으로 현재 지급돼 있는 QTA. 가격을 내리면 차액, 삭제하면 전액을 회수한다.
ALTER TABLE products ADD COLUMN listing_reward INTEGER NOT NULL DEFAULT 0;
