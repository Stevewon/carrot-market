-- 내 동네 여러 곳 (최대 10곳). JSON 배열 문자열, 예: ["서울 강남구","서울 서초구"].
-- users.region 은 그중 지금 보고 있는 동네 (피드·상품 등록 기준).
ALTER TABLE users ADD COLUMN regions TEXT;
