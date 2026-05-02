-- 0018_reset_all_data.sql
--
-- ⚠️ DESTRUCTIVE: 모든 사용자/상품/거래/QTA 데이터를 삭제한다.
--
-- 안전 패치:
--   기존 0018 은 price_offers / reviews 등이 반드시 존재한다고 가정했으나
--   0010 / 0008 이 과거 부분 실패로 일부 환경에서 테이블이 누락된 채로
--   d1_migrations 에 기록된 사례가 있다 → 누락된 테이블을 먼저 보강(CREATE
--   IF NOT EXISTS) 한 뒤 DELETE 한다. 이로써 어떤 환경에서도 0018 이 실패
--   하지 않는다.
--
-- 목적
--   QA/개발 단계에서 누적된 샘플 데이터(테스트 계정, 더미 상품, 가짜 채팅
--   기록, 잔여 QTA 잔액 등)를 한 번에 비우고 "회원가입부터 다시" 시작할
--   수 있도록 한다.
--
-- 멱등성
--   여러 번 실행해도 안전 (이미 비어 있어도 DELETE 는 0행 영향).

-- ── 누락 가능 테이블 보강 (방어적 CREATE IF NOT EXISTS) ───────────────
-- price_offers (0010 에서 만들어졌어야 함)
CREATE TABLE IF NOT EXISTS price_offers (
  id           TEXT PRIMARY KEY,
  room_id      TEXT NOT NULL,
  message_id   TEXT NOT NULL,
  product_id   TEXT,
  buyer_id     TEXT NOT NULL,
  seller_id    TEXT NOT NULL,
  price        INTEGER NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending',
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  responded_at TEXT
);

-- reviews (0008 에서 만들어졌어야 함)
CREATE TABLE IF NOT EXISTS reviews (
  id          TEXT PRIMARY KEY,
  product_id  TEXT,
  reviewer_id TEXT NOT NULL,
  reviewee_id TEXT NOT NULL,
  rating      INTEGER NOT NULL,
  text        TEXT,
  tags        TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- user_reports / user_blocks (0009 에서 만들어졌어야 함)
CREATE TABLE IF NOT EXISTS user_reports (
  id           TEXT PRIMARY KEY,
  reporter_id  TEXT NOT NULL,
  reported_id  TEXT NOT NULL,
  reason       TEXT,
  created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS user_blocks (
  blocker_id  TEXT NOT NULL,
  blocked_id  TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (blocker_id, blocked_id)
);

-- hidden_products / keyword_alerts (0013)
CREATE TABLE IF NOT EXISTS hidden_products (
  user_id     TEXT NOT NULL,
  product_id  TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, product_id)
);

CREATE TABLE IF NOT EXISTS keyword_alerts (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  keyword     TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- product_likes (0001)
CREATE TABLE IF NOT EXISTS product_likes (
  user_id     TEXT NOT NULL,
  product_id  TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, product_id)
);

-- qta_* (0014, 0015)
CREATE TABLE IF NOT EXISTS qta_withdrawals (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  amount      INTEGER NOT NULL,
  status      TEXT NOT NULL DEFAULT 'pending',
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS qta_daily_login (
  user_id     TEXT NOT NULL,
  yyyymmdd    TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, yyyymmdd)
);

CREATE TABLE IF NOT EXISTS qta_ledger (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  delta       INTEGER NOT NULL,
  reason      TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- referrals (0016)
CREATE TABLE IF NOT EXISTS referrals (
  id            TEXT PRIMARY KEY,
  referrer_id   TEXT NOT NULL,
  referee_id    TEXT NOT NULL,
  bonus_paid    INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ── 자식 테이블 먼저 ────────────────────────────────────────────────
DELETE FROM reviews;
DELETE FROM price_offers;
DELETE FROM user_reports;
DELETE FROM user_blocks;
DELETE FROM hidden_products;
DELETE FROM keyword_alerts;
DELETE FROM product_likes;
DELETE FROM qta_withdrawals;
DELETE FROM qta_daily_login;
DELETE FROM qta_ledger;
DELETE FROM referrals;

-- ── 부모 테이블 ─────────────────────────────────────────────────────
DELETE FROM products;
DELETE FROM users;
