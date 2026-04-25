-- 동네 인증 + 거리 기반 검색 (당근식)
--
-- 1) users 에 lat/lng + 인증시각 추가:
--    - GPS 좌표는 region 중심점에서 일정 반경 안일 때만 저장.
--    - 좌표는 정확한 위치가 아니라 "내 동네 중심점에 가까운지" 검증용.
--    - 사생활: 정확한 GPS 는 클라이언트가 보낸 즉시 검증만 하고
--      DB에는 region 중심 좌표만 저장(즉, 모든 같은 동네 사용자는 같은 점을 갖는다).
--
-- 2) products 에 lat/lng 추가:
--    - 상품 등록 시 작성자의 region 중심 좌표를 그대로 복사.
--    - 거리 필터를 빠르게 수행하기 위함.
--
-- 3) 거리 계산은 Haversine 을 서버 코드에서 수행 (D1 은 함수가 제한적).
--    - 인덱스는 lat 단일 인덱스만 두고, range_km 을 조잡한 bbox prefilter 로 줄인 뒤
--      Haversine 으로 정확도를 맞춘다.

ALTER TABLE users ADD COLUMN lat REAL;
ALTER TABLE users ADD COLUMN lng REAL;
ALTER TABLE users ADD COLUMN region_verified_at TEXT;

ALTER TABLE products ADD COLUMN lat REAL;
ALTER TABLE products ADD COLUMN lng REAL;

CREATE INDEX IF NOT EXISTS idx_products_lat ON products(lat);
CREATE INDEX IF NOT EXISTS idx_products_lng ON products(lng);
