-- 0035_reviews_best.sql
-- 거래 후기에 '최고예요'(best) 평가 추가 — 당근식 3단계 (별로예요 / 좋아요 / 최고예요).
--
--  • reviews.rating CHECK 를 ('best','good','soso','bad') 로 넓힌다.
--    'soso'(보통이에요)는 예전 데이터·구버전 앱 호환용으로 남긴다.
--  • tags 는 이제 안정적인 코드 CSV ('kind,punctual' …) — 예전 자유 입력 한국어 태그는 그대로 둔다
--    (앱이 모르는 값은 문구 그대로 보여준다).
--  • 매너온도 변화량은 workers-server/src/reviews.ts MANNER_DELTA 참고.
--
-- SQLite 는 CHECK 제약을 ALTER 로 바꿀 수 없어 테이블을 다시 만든다:
--   새 테이블 CREATE → INSERT SELECT → 옛 테이블 DROP → RENAME → 인덱스 재생성.
--  • reviews 를 참조하는 FK 는 없다 (reviews 는 products/users 를 참조하는 자식 테이블일 뿐)
--    → DROP TABLE reviews 가 다른 테이블의 FK 에 걸리지 않는다.
--  • D1 은 외래키 검사가 항상 켜져 있고 마이그레이션 안에서 세션 제어 구문(트랜잭션·pragma)을 쓰지
--    않는다 (0005 참고 — 거부됨). 위 이유로 끌 필요도 없다. 이미 사라진 상품·회원을 가리키는
--    고아 행(원래 ON DELETE CASCADE 로 지워졌어야 할 행)은 INSERT 가 외래키에 걸리지 않도록
--    복사하지 않는다.
--  • 트리거는 없다 (0008 참고) → 재생성할 것 없음.

CREATE TABLE reviews_new (
  id           TEXT PRIMARY KEY,
  product_id   TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  reviewer_id  TEXT NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  reviewee_id  TEXT NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  rating       TEXT NOT NULL CHECK (rating IN ('best', 'good', 'soso', 'bad')),
  tags         TEXT NOT NULL DEFAULT '', -- CSV (코드)
  comment      TEXT NOT NULL DEFAULT '',
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (product_id, reviewer_id)
);

INSERT INTO reviews_new (id, product_id, reviewer_id, reviewee_id, rating, tags, comment, created_at)
SELECT id, product_id, reviewer_id, reviewee_id, rating, tags, comment, created_at
  FROM reviews
 WHERE product_id  IN (SELECT id FROM products)
   AND reviewer_id IN (SELECT id FROM users)
   AND reviewee_id IN (SELECT id FROM users);

DROP TABLE reviews;

ALTER TABLE reviews_new RENAME TO reviews;

CREATE INDEX IF NOT EXISTS idx_reviews_reviewee ON reviews(reviewee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reviews_product  ON reviews(product_id);

-- 예전 가입 회원 중 ×1 스케일(36)로 남은 매너온도를 36.5° (365) 로 맞춘다. 새 가입은 365 로 넣는다.
UPDATE users SET manner_score = manner_score * 10 + 5 WHERE manner_score > 0 AND manner_score < 100;
