-- ======================================================================
-- Eggplant D1 마이그레이션 통합 SQL (0001 ~ 0022)
-- 이 파일을 Cloudflare Dashboard → D1 → eggplant-db → Console 에서
-- 통째로 붙여넣고 실행하면 22개 마이그레이션이 한 번에 적용됩니다.
-- 토큰/GitHub Actions 완전히 우회. 사장님 손은 SQL 붙여넣기 한 번뿐.
-- ======================================================================


-- ────────────────────────────────────────────────────────────────────
-- 0001_init.sql
-- ────────────────────────────────────────────────────────────────────
-- Eggplant 🍆 - Initial schema
-- Users, Products, Likes

CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  nickname      TEXT NOT NULL,
  device_uuid   TEXT NOT NULL UNIQUE,
  region        TEXT,
  manner_score  INTEGER NOT NULL DEFAULT 36,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_users_device_uuid ON users(device_uuid);

CREATE TABLE IF NOT EXISTS products (
  id           TEXT PRIMARY KEY,
  seller_id    TEXT NOT NULL,
  title        TEXT NOT NULL,
  description  TEXT NOT NULL,
  price        INTEGER NOT NULL DEFAULT 0,
  category     TEXT NOT NULL,
  region       TEXT NOT NULL,
  images       TEXT DEFAULT '',          -- comma-separated /uploads/<key> paths
  status       TEXT NOT NULL DEFAULT 'sale',  -- sale | reserved | sold
  view_count   INTEGER NOT NULL DEFAULT 0,
  like_count   INTEGER NOT NULL DEFAULT 0,
  chat_count   INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at   TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (seller_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_products_seller_id   ON products(seller_id);
CREATE INDEX IF NOT EXISTS idx_products_category    ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_region      ON products(region);
CREATE INDEX IF NOT EXISTS idx_products_created_at  ON products(created_at);
CREATE INDEX IF NOT EXISTS idx_products_status      ON products(status);

CREATE TABLE IF NOT EXISTS product_likes (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     TEXT NOT NULL,
  product_id  TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, product_id),
  FOREIGN KEY (user_id)    REFERENCES users(id)    ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_product_likes_user    ON product_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_product_likes_product ON product_likes(product_id);

-- ────────────────────────────────────────────────────────────────────
-- 0002_add_video_url.sql
-- ────────────────────────────────────────────────────────────────────
-- Eggplant 🍆 - Add video_url column to products
-- Allows sellers to attach a video (YouTube link OR uploaded video stored in R2)

ALTER TABLE products ADD COLUMN video_url TEXT DEFAULT '';

-- ────────────────────────────────────────────────────────────────────
-- 0003_chat_persistence.sql
-- ────────────────────────────────────────────────────────────────────
-- Chat persistence (당근 style). Everything is deletable by either party.
-- When a room is deleted, ALL messages cascade-delete on both users.

CREATE TABLE IF NOT EXISTS chat_rooms (
  id              TEXT PRIMARY KEY,               -- sorted(userA,userB)[_productId]
  user_a_id       TEXT NOT NULL,
  user_b_id       TEXT NOT NULL,
  product_id      TEXT,                            -- nullable: direct QR chat
  product_title   TEXT,
  product_thumb   TEXT,
  last_message    TEXT NOT NULL DEFAULT '',
  last_sender_id  TEXT,
  last_message_at TEXT NOT NULL DEFAULT (datetime('now')),
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_a_id)  REFERENCES users(id)    ON DELETE CASCADE,
  FOREIGN KEY (user_b_id)  REFERENCES users(id)    ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_user_a       ON chat_rooms(user_a_id);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_user_b       ON chat_rooms(user_b_id);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_last_msg_at  ON chat_rooms(last_message_at DESC);

CREATE TABLE IF NOT EXISTS chat_messages (
  id          TEXT PRIMARY KEY,
  room_id     TEXT NOT NULL,
  sender_id   TEXT NOT NULL,
  text        TEXT NOT NULL,
  msg_type    TEXT NOT NULL DEFAULT 'text',     -- text | image | system
  sent_at     TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (room_id)   REFERENCES chat_rooms(id) ON DELETE CASCADE,
  FOREIGN KEY (sender_id) REFERENCES users(id)      ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_room_id  ON chat_messages(room_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sent_at  ON chat_messages(sent_at);

-- ────────────────────────────────────────────────────────────────────
-- 0004_auth_wallet.sql
-- ────────────────────────────────────────────────────────────────────
-- Eggplant 🍆 - Wallet-based authentication
--
-- Replaces the device_uuid-only auth with wallet_address + password flow.
--
-- Notes:
--  - wallet_address is the permanent "ID" users log in with (Quantarium wallet).
--  - password_hash is PBKDF2-SHA256 (base64) + random salt (base64).
--  - token_version starts at 1 and is bumped whenever the user:
--      * changes their password (all old JWTs become invalid)
--      * logs in from a different device (old device's JWT invalid)
--    This is how we prevent "someone else logging in and staying in".
--  - We KEEP device_uuid on the row for the "currently bound" device, and
--    use UNIQUE(wallet_address) / UNIQUE(nickname) to stop duplicates.

-- 1) Add new columns (nullable first so existing rows don't break).
ALTER TABLE users ADD COLUMN wallet_address   TEXT;
ALTER TABLE users ADD COLUMN password_hash    TEXT;
ALTER TABLE users ADD COLUMN password_salt    TEXT;
ALTER TABLE users ADD COLUMN token_version    INTEGER NOT NULL DEFAULT 1;

-- 2) Unique indexes (case-insensitive for wallet, exact for nickname).
--    COLLATE NOCASE lets us treat "0xAbCd..." and "0xabcd..." as the same.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_wallet_unique
  ON users(wallet_address COLLATE NOCASE)
  WHERE wallet_address IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_nickname_unique
  ON users(nickname COLLATE NOCASE)
  WHERE nickname IS NOT NULL;

-- ────────────────────────────────────────────────────────────────────
-- 0005_device_uuid_not_unique.sql
-- ────────────────────────────────────────────────────────────────────
-- Eggplant 🍆 - Drop UNIQUE constraint on users.device_uuid
--
-- WHY:
--   Migration 0001 declared `device_uuid TEXT NOT NULL UNIQUE` because the
--   original auth model used device_uuid AS the identity. With wallet+password
--   auth (migration 0004), device_uuid is now just a "currently bound device"
--   marker — multiple wallets CAN legitimately share one phone (family,
--   dev/QA, re-signup after logout, etc.).
--
--   The UNIQUE constraint now causes `INSERT INTO users ...` to fail with
--   `UNIQUE constraint failed: users.device_uuid` whenever a second wallet
--   tries to register on the same device.
--
-- HOW:
--   SQLite can't ALTER TABLE DROP CONSTRAINT, so we rebuild the users table.
--   We preserve every row (id → updated_at) exactly as-is.
--
--   The FK in products(seller_id) points at users(id), which stays stable
--   through a rename-and-copy, so no CASCADE is triggered.
--
-- NOTE (D1):
--   Cloudflare D1 자동으로 statement 들을 atomic batch 로 실행하기 때문에
--   `BEGIN TRANSACTION`/`COMMIT`/`SAVEPOINT`/`PRAGMA foreign_keys` 같은
--   세션 제어 SQL 은 거부된다 (error code 7500). 따라서 raw 트랜잭션은
--   삭제하고 D1 batch 의 atomic 보장에 의존한다.

-- 1) Rename the old table out of the way.
ALTER TABLE users RENAME TO users_old;

-- 2) Create the new table with device_uuid as plain NOT NULL (no UNIQUE).
CREATE TABLE users (
  id              TEXT PRIMARY KEY,
  nickname        TEXT NOT NULL,
  device_uuid     TEXT NOT NULL,
  wallet_address  TEXT,
  password_hash   TEXT,
  password_salt   TEXT,
  token_version   INTEGER NOT NULL DEFAULT 1,
  region          TEXT,
  manner_score    INTEGER NOT NULL DEFAULT 36,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 3) Copy every row over unchanged.
INSERT INTO users (
  id, nickname, device_uuid,
  wallet_address, password_hash, password_salt, token_version,
  region, manner_score, created_at, updated_at
)
SELECT
  id, nickname, device_uuid,
  wallet_address, password_hash, password_salt, token_version,
  region, manner_score, created_at, updated_at
FROM users_old;

-- 4) Drop the old table.
DROP TABLE users_old;

-- 5) Re-create indexes that 0001 + 0004 created on the original table.
--    (Dropping the table also dropped its indexes.)
CREATE INDEX IF NOT EXISTS idx_users_device_uuid ON users(device_uuid);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_wallet_unique
  ON users(wallet_address COLLATE NOCASE)
  WHERE wallet_address IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_nickname_unique
  ON users(nickname COLLATE NOCASE)
  WHERE nickname IS NOT NULL;

-- ────────────────────────────────────────────────────────────────────
-- 0006_chat_read_tracking.sql
-- ────────────────────────────────────────────────────────────────────
-- Eggplant 🍆 - Chat read tracking (당근식 unread badge)
--
-- Each room has TWO participants (user_a, user_b). We store a per-user
-- "last_read_at" timestamp on the room itself, and compute the unread
-- count at query time as:
--   COUNT(*) FROM chat_messages
--    WHERE room_id = ?
--      AND sender_id != me
--      AND sent_at > my_last_read_at
--
-- This is fast because chat_messages already has indexes on (room_id) and
-- (sent_at), and rooms are O(few hundred) per user worst case.
--
-- NULL last_read_at_* = "never read" — every existing message counts as unread.
-- We backfill with the room's created_at so existing rooms don't suddenly
-- show every old message as unread.

ALTER TABLE chat_rooms ADD COLUMN last_read_at_a TEXT;
ALTER TABLE chat_rooms ADD COLUMN last_read_at_b TEXT;

-- Backfill: treat existing rooms as fully read up to creation time, so old
-- conversations don't pop up with massive unread counts on first deploy.
UPDATE chat_rooms
   SET last_read_at_a = COALESCE(last_message_at, created_at),
       last_read_at_b = COALESCE(last_message_at, created_at)
 WHERE last_read_at_a IS NULL OR last_read_at_b IS NULL;

-- ────────────────────────────────────────────────────────────────────
-- 0007_product_bump.sql
-- ────────────────────────────────────────────────────────────────────
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

-- ────────────────────────────────────────────────────────────────────
-- 0008_reviews.sql
-- ────────────────────────────────────────────────────────────────────
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

-- ────────────────────────────────────────────────────────────────────
-- 0009_blocks_reports.sql
-- ────────────────────────────────────────────────────────────────────
-- 0009_blocks_reports.sql
-- 차단 (block) + 신고 (report) — 당근식.
--
-- Block:
--   • blocker_id 가 blocked_id 를 차단하면, 양방향 격리:
--       - blocker 의 피드/검색 결과에서 blocked 의 상품이 사라진다.
--       - blocked 가 blocker 에게 새 채팅을 걸 수 없다 (채팅 생성 시 막음).
--       - 기존 채팅방은 유지하지만, 메시지가 들어오면 받지 않고 폐기 가능 (앱쪽 필터).
--   • UNIQUE(blocker_id, blocked_id) — 같은 사람을 두 번 차단할 수 없다.
--   • 차단 해제 = 행 삭제.
--
-- Report:
--   • 누구나 한 사람을 신고할 수 있다 (스팸, 사기, 부적절한 게시물 등).
--   • 신고 사유는 reason 컬럼에 enum 으로 저장.
--   • 같은 사람을 같은 사유로 여러 번 신고하지 못하게 UNIQUE(reporter_id, reported_id, reason).
--   • product_id 는 옵션 — 특정 게시물 신고 시 같이 저장.
--   • 운영자는 D1 콘솔에서 reports 테이블 직접 조회.

CREATE TABLE IF NOT EXISTS user_blocks (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  blocker_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON user_blocks(blocker_id);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON user_blocks(blocked_id);

CREATE TABLE IF NOT EXISTS user_reports (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  reporter_id   TEXT NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  reported_id   TEXT NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  product_id    TEXT          REFERENCES products(id) ON DELETE SET NULL,
  reason        TEXT NOT NULL CHECK (reason IN
                  ('spam', 'fraud', 'abuse', 'inappropriate', 'fake', 'other')),
  detail        TEXT NOT NULL DEFAULT '',
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (reporter_id, reported_id, reason),
  CHECK (reporter_id <> reported_id)
);

CREATE INDEX IF NOT EXISTS idx_user_reports_reported ON user_reports(reported_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_reports_reporter ON user_reports(reporter_id);

-- ────────────────────────────────────────────────────────────────────
-- 0010_price_offers.sql
-- ────────────────────────────────────────────────────────────────────
-- Sprint 4 — 가격 제안 / 네고 (당근식)
--
-- 채팅방에서 사용자가 상품 가격을 흥정할 수 있도록 별도 메시지 타입과 상태 테이블을 둔다.
--
-- 흐름:
--   1) 구매자가 채팅방(상품 첨부된 방)에서 "5,000원에 살래요" 같은 제안 메시지를 보낸다.
--   2) 제안은 chat_messages 에 msg_type='price_offer' 로 저장되고, 동시에
--      price_offers 테이블에 pending 상태로 한 줄이 들어간다. text 필드에는 클라이언트 표시용 요약 ("5,000원 가격 제안") 이 들어간다.
--   3) 판매자가 그 메시지의 [수락]/[거절] 버튼을 누르면 price_offers.status 가
--      accepted / rejected 로 바뀐다. 클라이언트는 status 를 보고 메시지 카드의 모양을 갱신.
--   4) 한 채팅방에는 동시에 1건의 pending 제안만 존재 (UNIQUE partial index).
--      새 제안을 보내면 직전 pending 은 자동으로 cancelled 로 만든다(서버 라우트가 처리).
--
-- 메시지 자체가 chat_messages 에 들어가므로 채팅 히스토리 / 마지막 메시지 / 안 읽음 카운트
-- 같은 기존 로직과 그대로 호환된다. 제안의 "상태"만 별도로 가져오면 된다.
--
-- chat_messages 의 msg_type CHECK 제약은 두지 않았기 때문에(기존 0003 참고) 별도
-- 마이그레이션 없이 바로 'price_offer' 값을 사용할 수 있다.

CREATE TABLE IF NOT EXISTS price_offers (
  id          TEXT PRIMARY KEY,
  room_id     TEXT NOT NULL,
  message_id  TEXT NOT NULL,                  -- chat_messages.id 와 1:1 매핑
  product_id  TEXT,                           -- 방의 product_id (편의를 위한 비정규화)
  buyer_id    TEXT NOT NULL,                  -- 제안한 사람 (구매자)
  seller_id   TEXT NOT NULL,                  -- 받은 사람 (판매자)
  price       INTEGER NOT NULL,               -- 제안 금액 (원 단위)
  status      TEXT NOT NULL DEFAULT 'pending',-- pending | accepted | rejected | cancelled
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  responded_at TEXT,                          -- 수락/거절 시각
  FOREIGN KEY (room_id)    REFERENCES chat_rooms(id)    ON DELETE CASCADE,
  FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id)      ON DELETE SET NULL,
  FOREIGN KEY (buyer_id)   REFERENCES users(id)         ON DELETE CASCADE,
  FOREIGN KEY (seller_id)  REFERENCES users(id)         ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_price_offers_room    ON price_offers(room_id);
CREATE INDEX IF NOT EXISTS idx_price_offers_message ON price_offers(message_id);
CREATE INDEX IF NOT EXISTS idx_price_offers_status  ON price_offers(status);

-- 한 방에 동시에 pending 제안은 최대 1건 — partial unique index.
CREATE UNIQUE INDEX IF NOT EXISTS idx_price_offers_one_pending_per_room
  ON price_offers(room_id) WHERE status = 'pending';

-- ────────────────────────────────────────────────────────────────────
-- 0011_drop_chat_persistence.sql
-- ────────────────────────────────────────────────────────────────────
-- 사생활 보호 정책: 채팅·가격제안은 절대 DB 에 저장하지 않는다.
--
-- 한 번 흘러간 메시지는 영구 소실되어야 하며, 양쪽 기기 어디에도 복원되지 않는다.
-- (telegram secret chat / signal 의 "휘발성 채팅" 모델)
--
-- 이 마이그레이션은 그 동안 잠시 운영했던 영구 채팅 테이블을 전부 제거한다.
-- 기존 데이터는 모두 삭제된다 — 의도된 동작이다.
--
-- 이후 채팅은:
--   - WebSocket Durable Object 메모리에서만 broadcast.
--   - DB 에 어떤 흔적도 남기지 않음.
--   - 앱 재실행 / 다른 기기 로그인 시 채팅 목록 빈 상태로 시작.
--
-- 통화는 원래부터 WebRTC P2P 라 미디어가 서버를 거치지 않았다 (변경 없음).

-- 자식 테이블부터 순서대로 (FK CASCADE 정의되어 있어도 명시적으로 처리)
DROP TABLE IF EXISTS price_offers;
DROP TABLE IF EXISTS chat_messages;
DROP TABLE IF EXISTS chat_rooms;

-- 관련 인덱스는 테이블과 함께 자동 삭제되지만 혹시 남아 있을 수 있는 잔재를 정리.
DROP INDEX IF EXISTS idx_chat_rooms_user_a;
DROP INDEX IF EXISTS idx_chat_rooms_user_b;
DROP INDEX IF EXISTS idx_chat_rooms_last_msg_at;
DROP INDEX IF EXISTS idx_chat_messages_room_id;
DROP INDEX IF EXISTS idx_chat_messages_sent_at;
DROP INDEX IF EXISTS idx_price_offers_room;
DROP INDEX IF EXISTS idx_price_offers_message;
DROP INDEX IF EXISTS idx_price_offers_status;
DROP INDEX IF EXISTS idx_price_offers_one_pending_per_room;

-- ────────────────────────────────────────────────────────────────────
-- 0012_geo_location.sql
-- ────────────────────────────────────────────────────────────────────
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

-- ────────────────────────────────────────────────────────────────────
-- 0013_keyword_alerts_and_hidden.sql
-- ────────────────────────────────────────────────────────────────────
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

-- ────────────────────────────────────────────────────────────────────
-- 0014_qta_economy.sql
-- ────────────────────────────────────────────────────────────────────
-- QTA 토큰 경제 (회원가입 +500, 로그인 +10×3/day, 거래완료 +10 each)
--
-- 정책:
--   1) 회원가입 시 +500 QTA 1회 (멱등: ledger.idem_key = 'signup:<user_id>')
--   2) 로그인 시 +10 QTA, 하루 3회까지 (qta_daily_login 카운터)
--   3) 거래완료(status -> 'sold') 시 판매자·구매자 각 +10 QTA
--      (멱등: ledger.idem_key = 'trade:<product_id>:<role>')
--
-- 모든 적립/차감은 qta_ledger 한 줄로 기록되며 users.qta_balance 는 그 합계.
-- 음수 amount 도 허용 (향후 수수료/이체용). 잔액은 절대 음수가 되지 않도록 서버 코드에서 가드.

-- ───────────────────────────────────────────
-- 1) users.qta_balance 컬럼
-- ───────────────────────────────────────────
ALTER TABLE users ADD COLUMN qta_balance INTEGER NOT NULL DEFAULT 0;

-- ───────────────────────────────────────────
-- 2) qta_ledger — 모든 변동 한 줄씩
-- ───────────────────────────────────────────
--   reason 분류:
--     'signup'         : 가입 보너스
--     'login_daily'    : 로그인 일일 보너스
--     'trade_seller'   : 거래완료 판매자 보너스
--     'trade_buyer'    : 거래완료 구매자 보너스
--     (앞으로 'transfer','fee','refund' 등 자유 확장)
--
--   idem_key (UNIQUE) — 중복 지급 차단:
--     signup:<user_id>
--     login_daily:<user_id>:<ymd>:<n>      (n = 1,2,3)
--     trade:<product_id>:seller
--     trade:<product_id>:buyer
CREATE TABLE IF NOT EXISTS qta_ledger (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  amount      INTEGER NOT NULL,                       -- + 입금 / - 출금
  reason      TEXT NOT NULL,
  idem_key    TEXT NOT NULL,
  meta        TEXT,                                   -- JSON 문자열, 자유. (예: {"product_id":"..."})
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE (idem_key)
);

CREATE INDEX IF NOT EXISTS idx_qta_ledger_user_created
  ON qta_ledger(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_qta_ledger_reason
  ON qta_ledger(reason);

-- ───────────────────────────────────────────
-- 3) qta_daily_login — 일일 로그인 카운터 (하루 3회 제한)
-- ───────────────────────────────────────────
--   ymd: 'YYYY-MM-DD' (UTC). 클라이언트의 timezone 다양성 + 서버 일관성 유지를 위해 UTC.
CREATE TABLE IF NOT EXISTS qta_daily_login (
  user_id     TEXT NOT NULL,
  ymd         TEXT NOT NULL,
  count       INTEGER NOT NULL DEFAULT 0,
  updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, ymd),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_qta_daily_login_ymd
  ON qta_daily_login(ymd);

-- ────────────────────────────────────────────────────────────────────
-- 0015_qta_withdrawals.sql
-- ────────────────────────────────────────────────────────────────────
-- QTA 출금 시스템
--
-- 정책:
--   - 최소 출금액: 5,000 QTA
--   - 단위: 5,000 의 배수만 (5,000 / 10,000 / 15,000 …)
--   - 출금 주소: 본인 가입 시 등록된 wallet_address 로만. 타 주소 송금 불가.
--   - 신청 즉시 잔액에서 차감 (qta_ledger reason='withdrawal', amount = -N).
--   - 상태:
--       'requested'  : 사용자 신청 (잔액 차감 완료, 운영자 처리 대기)
--       'processing' : 운영자가 송금 진행 중
--       'completed'  : 송금 완료 (트랜잭션 해시 기록)
--       'rejected'   : 거부됨 → 자동으로 ledger reason='withdrawal_refund' +N 환불
--   - 한 사용자당 'requested'/'processing' 상태 출금은 동시에 1건만.
--     (UNIQUE partial index 로 강제)

CREATE TABLE IF NOT EXISTS qta_withdrawals (
  id              TEXT PRIMARY KEY,
  user_id         TEXT NOT NULL,
  wallet_address  TEXT NOT NULL,        -- 신청 당시 사용자 지갑 (변경에 영향 안 받게 스냅샷)
  amount          INTEGER NOT NULL,     -- 양수, 5000 의 배수, ≥ 5000
  status          TEXT NOT NULL DEFAULT 'requested'
    CHECK (status IN ('requested', 'processing', 'completed', 'rejected')),
  requested_at    TEXT NOT NULL DEFAULT (datetime('now')),
  processed_at    TEXT,                 -- processing/completed/rejected 로 바뀐 시각
  tx_hash         TEXT,                 -- completed 시 송금 트랜잭션 해시
  reject_reason   TEXT,                 -- rejected 시 사유
  ledger_id       TEXT NOT NULL,        -- 차감 ledger 행 id (참조)
  refund_ledger_id TEXT,                -- rejected 환불 ledger 행 id
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_qta_withdrawals_user
  ON qta_withdrawals(user_id, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_qta_withdrawals_status
  ON qta_withdrawals(status, requested_at);

-- 한 사용자당 'requested' 또는 'processing' 상태 출금은 최대 1건.
-- (D1 SQLite 부분 UNIQUE 인덱스 지원)
CREATE UNIQUE INDEX IF NOT EXISTS idx_qta_withdrawals_one_pending_per_user
  ON qta_withdrawals(user_id)
  WHERE status IN ('requested', 'processing');

-- ────────────────────────────────────────────────────────────────────
-- 0016_referrals.sql
-- ────────────────────────────────────────────────────────────────────
-- 친구 초대 (referral) + 즉시 삭감형 탈퇴
--
-- 정책:
--   1) 신규 가입자가 추천인 닉네임을 입력하면, 가입 직후 추천인에게 +200 QTA 1회 지급
--      · 무제한 (한 사람이 몇 명을 초대해도 OK)
--      · 단, "동일한 신규 가입자(referee)" 가 두 번 트리거되지 않도록 멱등키 사용
--      · ledger.idem_key = 'referral:<referee_user_id>'
--      · reason = 'referral_inviter'
--   2) 추천인 자신을 추천하거나, 이미 다른 가입자가 같은 referee 로 처리되면 무시.
--   3) 신규 가입자(referee)에게는 이번에 보너스 X. (가입 +500 만 받음)
--
-- 탈퇴(account deletion) 정책 — "한 번 사라진 건 영구 보관 X" + 즉시 삭감:
--   · 사용자가 탈퇴하면 그 사람이 받았던/지급했던 referral 보너스를 즉시 회수.
--     - 탈퇴자가 추천인이었다면(reason='referral_inviter') → -200 QTA 차감 (clawback)
--     - 탈퇴자가 referee 로 처리됐다면 추천인의 보너스도 -200 회수
--   · users 행은 ON DELETE CASCADE 가 걸려 있어 ledger / referrals 등 자동 정리.
--   · referrals 테이블의 추천인/피추천인 행이 사라져도 idem_key 충돌은 발생하지 않도록
--     ledger.idem_key 만으로 중복 차단. (referrals 는 보조 인덱스성 테이블)

-- ──────────────────────────────────────────────────────
-- 1) referrals — 누가 누구를 초대했는지의 단방향 기록
-- ──────────────────────────────────────────────────────
--   inviter_id  : 추천인 (보너스 받는 사람)
--   referee_id  : 신규 가입자
--   bonus_ledger_id  : 추천인에게 지급된 ledger row id (FK)
--   clawback_ledger_id : 회수가 발생한 경우의 ledger row id
--   status      : 'granted' | 'clawed_back'
--
-- referee_id UNIQUE → 한 신규 가입자는 단 한 번만 누군가의 추천 보너스를 트리거.
CREATE TABLE IF NOT EXISTS referrals (
  id                  TEXT PRIMARY KEY,
  inviter_id          TEXT NOT NULL,
  referee_id          TEXT NOT NULL UNIQUE,
  status              TEXT NOT NULL DEFAULT 'granted'
                        CHECK (status IN ('granted','clawed_back')),
  bonus_ledger_id     TEXT,
  clawback_ledger_id  TEXT,
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (inviter_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (referee_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_referrals_inviter
  ON referrals(inviter_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_referrals_status
  ON referrals(status);

-- ──────────────────────────────────────────────────────
-- 2) ledger reason 확장 안내 (코드 레벨)
-- ──────────────────────────────────────────────────────
--   'referral_inviter'         : 추천인 +200 보너스
--   'referral_clawback'        : 탈퇴 시 -200 회수 (ledger amount = -200)
--   'account_deletion_balance' : 탈퇴 시 잔여 balance 폐기 ledger (amount = -balance)
--
--   ※ 탈퇴 시 users 행 DELETE 직전에 위 ledger 들을 한꺼번에 batch 로 기록한 뒤,
--     사용자 행을 지우면 ON DELETE CASCADE 로 ledger / referrals 가 모두 정리됨.
--     "한 번 사라진 건 영구 보관 X" 원칙: 탈퇴자에 대한 모든 흔적은 즉시 사라짐.

-- ────────────────────────────────────────────────────────────────────
-- 0017_qta_product_payment.sql
-- ────────────────────────────────────────────────────────────────────
-- 0017_qta_product_payment.sql
--
-- 상품 거래에 QTA 결제 기능 추가.
--
-- 판매자가 상품을 등록할 때 선택적으로 'qta_price' (정수 QTA) 를 매길 수 있다.
--   - qta_price = NULL 또는 0 → KRW 거래 (현장 송금/계좌이체 등 외부 처리)
--   - qta_price > 0          → QTA 거래. 거래 완료 시점에 자동으로 buyer→seller
--                              잔액 이체 (멱등 키: trade_payment:<product_id>).
--
-- 가격 단위는 정수만 허용한다 (소수 QTA 없음).

ALTER TABLE products ADD COLUMN qta_price INTEGER NOT NULL DEFAULT 0;

-- qta_price 가 0 보다 큰 상품만 빠르게 골라 보기 위한 인덱스 (선택).
CREATE INDEX IF NOT EXISTS idx_products_qta_price
  ON products(qta_price) WHERE qta_price > 0;

-- ────────────────────────────────────────────────────────────────────
-- 0018_reset_all_data.sql
-- ────────────────────────────────────────────────────────────────────
-- 0018_reset_all_data.sql
--
-- ⚠️ DESTRUCTIVE: 모든 사용자/상품/거래/QTA 데이터를 삭제한다.
--
-- 목적
--   QA/개발 단계에서 누적된 샘플 데이터(테스트 계정, 더미 상품, 가짜 채팅
--   기록, 잔여 QTA 잔액 등)를 한 번에 비우고 "회원가입부터 다시" 시작할
--   수 있도록 한다.
--
-- 방식
--   - 스키마(테이블/인덱스)는 보존, 데이터만 DELETE.
--   - 외래키 의존 순서를 고려해 자식 → 부모 순으로 지운다.
--   - SQLite/D1 은 sqlite_sequence 가 있는 경우만 AUTOINCREMENT 카운터를
--     리셋하지만, 이 프로젝트는 모두 TEXT(UUID) PK 라 sqlite_sequence 를
--     쓰지 않는다. 따라서 별도 시퀀스 리셋은 불필요.
--   - 채팅(chat_messages, chat_rooms) 은 0011 에서 이미 DROP 됐고, 현재
--     채팅은 Durable Object 메모리에서만 살아있다 → DB 에서 지울 게 없음.
--
-- 실행 후
--   - 모든 사용자가 로그아웃된 것과 동일한 상태가 된다 (서버에 row 가 없음).
--   - 클라이언트에 남아있던 JWT 는 다음 인증 요청 시 401 → 자동 로그아웃.
--   - R2 업로드 (이미지/비디오) 는 별도 정리가 필요하다 (이 마이그레이션
--     으로는 안 지워짐). 필요시:
--       npx wrangler r2 bucket delete eggplant-uploads --recursive
--       npx wrangler r2 bucket create eggplant-uploads
--
-- 멱등성
--   여러 번 실행해도 안전 (이미 비어 있어도 DELETE 는 0행 영향).

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

-- ────────────────────────────────────────────────────────────────────
-- 0019_verification.sql
-- ────────────────────────────────────────────────────────────────────
-- 프로필 인증 (Verification) 시스템
--
-- 정책:
--   1) 가입 직후 verification_level = 0 (익명, 둘러보기·채팅·통화·상품등록 가능)
--   2) 본인인증 후 verification_level = 1 (KRW/QTA 결제 가능)
--   3) 계좌 등록 후 verification_level = 2 (QTA 출금 가능)
--
-- 저장 정책:
--   - 휴대폰 번호 자체는 절대 저장하지 않음
--   - 본인인증 토큰(CI, Connecting Information)의 SHA-256 해시만 저장
--   - 같은 사람이 여러 계정 만드는지 검증할 때만 사용
--
-- 채팅·통화는 익명성 그대로 유지 (verification_level 무관, 닉네임만 사용).
-- 거래/결제/출금 단계에서만 verification_level 체크.

-- ───────────────────────────────────────────
-- 1) users 테이블에 인증 컬럼 추가
-- ───────────────────────────────────────────
ALTER TABLE users ADD COLUMN verification_level INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN verified_ci_hash TEXT;        -- SHA-256(CI), 미인증 시 NULL
ALTER TABLE users ADD COLUMN verified_at TEXT;             -- ISO-8601, 미인증 시 NULL
ALTER TABLE users ADD COLUMN bank_account_hash TEXT;       -- SHA-256(bank+account), 미등록 시 NULL
ALTER TABLE users ADD COLUMN bank_registered_at TEXT;      -- ISO-8601, 미등록 시 NULL

-- ───────────────────────────────────────────
-- 2) 같은 CI(같은 사람)가 여러 계정 못 만들도록 UNIQUE
--    (NULL은 UNIQUE 제약 무시되므로 미인증 계정은 영향 없음)
-- ───────────────────────────────────────────
CREATE UNIQUE INDEX idx_users_ci_unique ON users(verified_ci_hash)
WHERE verified_ci_hash IS NOT NULL;

-- ────────────────────────────────────────────────────────────────────
-- 0020_escrow_and_mining.sql
-- ────────────────────────────────────────────────────────────────────
-- 에스크로우 + QTA 채굴 시스템
--
-- 정책:
--   1) 에스크로우 (KRW 전용, 소액만 회사 개입)
--      - 거래금액 < 30,000 KRW : 회사통장으로 임시예치 → 거래완료 후 판매자 송금
--      - 거래금액 >= 30,000 KRW : 당사자 직거래, 회사 미개입 (사고 시 자기책임)
--      - QTA 거래 : 즉시 자동 송금, 에스크로우 없음
--
--   2) QTA 채굴 시스템
--      A. 상품 유지 보너스
--         - 등록 후 7일 이상 미판매·미삭제 상태로 유지 → +10 QTA (상품당 1회)
--         - 멱등 키: 'mining_listing:<product_id>'
--
--      B. 둘러보기 보너스
--         - 상품 상세보기를 KST 자정 기준 하루 10개 이상 → +10 QTA (1회/일)
--         - 자기 상품 보기는 카운트 X
--         - 같은 상품 중복 조회는 1회만 카운트 (UNIQUE)
--         - 멱등 키: 'mining_browse:<user_id>:<ymd_kst>'

-- ───────────────────────────────────────────
-- 1) 에스크로우 거래 테이블
-- ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS escrow_transactions (
  id            TEXT PRIMARY KEY,
  product_id    TEXT NOT NULL,
  buyer_id      TEXT NOT NULL,
  seller_id     TEXT NOT NULL,
  amount_krw    INTEGER NOT NULL,           -- KRW 정수
  status        TEXT NOT NULL DEFAULT 'pending',
  --   pending   : 구매자가 입금 대기
  --   held      : 회사통장 입금 확인 (예치 중)
  --   released  : 거래완료 → 판매자 송금 완료
  --   refunded  : 환불 완료 (분쟁 해결)
  --   cancelled : 거래 취소 (입금 전)
  deposit_memo  TEXT,                       -- 입금자 식별용 메모 (랜덤 4-6자리)
  admin_note    TEXT,                       -- 운영자 메모
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
  released_at   TEXT,
  refunded_at   TEXT,
  FOREIGN KEY (product_id) REFERENCES products(id),
  FOREIGN KEY (buyer_id)   REFERENCES users(id),
  FOREIGN KEY (seller_id)  REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_escrow_status     ON escrow_transactions(status);
CREATE INDEX IF NOT EXISTS idx_escrow_buyer      ON escrow_transactions(buyer_id);
CREATE INDEX IF NOT EXISTS idx_escrow_seller     ON escrow_transactions(seller_id);
CREATE INDEX IF NOT EXISTS idx_escrow_product    ON escrow_transactions(product_id);
CREATE INDEX IF NOT EXISTS idx_escrow_memo       ON escrow_transactions(deposit_memo);

-- ───────────────────────────────────────────
-- 2) 둘러보기 채굴 — 상품 조회 로그
--    같은 사용자가 같은 상품을 봐도 1회만 카운트하기 위한 UNIQUE 키.
--    KST 일자별로 분리 (ymd_kst).
-- ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS product_view_log (
  user_id    TEXT NOT NULL,
  product_id TEXT NOT NULL,
  ymd_kst    TEXT NOT NULL,                 -- 'YYYY-MM-DD' (KST 자정 기준)
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, product_id, ymd_kst)
);
CREATE INDEX IF NOT EXISTS idx_view_log_user_day ON product_view_log(user_id, ymd_kst);

-- ───────────────────────────────────────────
-- 3) 채굴 진행 상태 캐시 (조회 최적화)
--    오늘 둘러보기 카운트를 빠르게 보여주기 위해.
--    products.created_at 기반의 7일 유지 채굴은 ledger.idem_key 만으로 충분하니
--    별도 테이블 X.
-- ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS qta_browse_mining_daily (
  user_id    TEXT NOT NULL,
  ymd_kst    TEXT NOT NULL,
  view_count INTEGER NOT NULL DEFAULT 0,
  credited   INTEGER NOT NULL DEFAULT 0,    -- 0/1, 오늘 보너스 받았는지
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, ymd_kst)
);

-- ───────────────────────────────────────────
-- 4) qta_ledger.reason 확장 (참고용 주석)
--    'mining_listing'  : 상품 7일 유지 보너스
--    'mining_browse'   : 둘러보기 일일 보너스
--    'escrow_release'  : (KRW 거래는 ledger 안 씀, 미사용 예약)
-- ───────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────
-- 0021_sso_and_pass.sql
-- ────────────────────────────────────────────────────────────────────
-- SSO 통합 + PASS 본인인증 연계
--
-- 정책:
--   1) "퀀타리움 지갑주소 = Universal User ID"
--      QRChat 과 가지(Eggplant)는 같은 회사 자매 앱.
--      한쪽에서 가입/로그인하면 반대쪽이 자동으로 같은 계정 인식.
--      식별 키는 오직 wallet_address.
--
--   2) /api/auth/sso/exchange 가 QRChat 토큰 + wallet_address 를 받아
--      자동으로 가지 계정을 생성/조회하고 가지 JWT 를 돌려준다.
--
--   3) 본인인증은 PASS(통합본인인증) 사용 가정. 휴대폰 번호 자체는 저장 X,
--      CI(Connecting Information) 의 SHA-256 해시만 저장.

-- ───────────────────────────────────────────
-- 1) sso_links — 어느 외부 앱(QRChat 등)에서 어느 시각에 SSO 로 들어왔는지
--                기록. 같은 wallet_address 로 여러 외부 앱이 로그인할 수 있다.
-- ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sso_links (
  id              TEXT PRIMARY KEY,
  user_id         TEXT NOT NULL,
  provider        TEXT NOT NULL,                  -- 'qrchat', 'eggplant_self', ...
  external_id     TEXT,                           -- 외부 앱이 부여한 ID (옵션)
  wallet_address  TEXT NOT NULL,
  device_uuid     TEXT,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at    TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sso_links_provider_user
  ON sso_links(provider, user_id);
CREATE INDEX IF NOT EXISTS idx_sso_links_wallet
  ON sso_links(wallet_address);

-- ───────────────────────────────────────────
-- 2) PASS 본인인증 트랜잭션 로그
--    - tx_id : PASS 가 발급한 거래 식별자 (멱등키)
--    - ci_hash : SHA-256(CI). 사용자 동일성 검증에만 사용.
--    - status : pending / verified / failed / expired
-- ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pass_verifications (
  tx_id        TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL,
  ci_hash      TEXT,                              -- SHA-256(CI). 성공 시에만 채움.
  status       TEXT NOT NULL DEFAULT 'pending',
  provider     TEXT NOT NULL DEFAULT 'pass',      -- 'pass' / 'sms' / 'kisa'
  requested_at TEXT NOT NULL DEFAULT (datetime('now')),
  verified_at  TEXT,
  fail_reason  TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_pass_user_status
  ON pass_verifications(user_id, status);

-- ───────────────────────────────────────────
-- 3) verification_audit — 본인인증 시도/성공 감사 로그
--    실제 운영에서 어느 provider 로 어떤 트랜잭션이 성공했는지 추적용.
--    개인정보(휴대폰 번호 평문)는 절대 저장하지 않고, 클라이언트가
--    보낸 phone_hash(SHA-256) 만 옵션으로 보관.
-- ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS verification_audit (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  provider    TEXT NOT NULL,                      -- 'pass' / 'sms' / 'kisa' / 'dummy'
  tx_id       TEXT,                               -- provider 가 발급한 트랜잭션 ID
  phone_hash  TEXT,                               -- SHA-256(phone). 평문 절대 X
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_verif_audit_user
  ON verification_audit(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_verif_audit_provider
  ON verification_audit(provider, created_at DESC);

-- ────────────────────────────────────────────────────────────────────
-- 0022_chat_qrchat_only.sql
-- ────────────────────────────────────────────────────────────────────
-- 채팅 내역 = QRChat 정책 100%% 위임
--
-- 결정사항:
--   채팅·통화는 QRChat 을 만든 회사가 SDK 를 제공한다.
--   채팅 내역의 저장 기간/암호화/내보내기/삭제 정책은 무조건 QRChat 정책을 따른다.
--   가지(Eggplant) 백엔드는 채팅 메시지를 절대 저장·중계·복제하지 않는다.
--
-- 따라서:
--   - 가지 D1 에는 채팅 메시지 테이블이 없어야 한다.
--   - 과거 임시 보존되던 chat_* 테이블이 있다면 정리 (있어도 / 없어도 안전).
--   - 채팅방 메타(룸 ID, 참여자 매핑)도 가지에서는 보관하지 않는다.
--   - 가격 제안·읽음 처리 등 가지 고유 이벤트는 QRChat 의 generic event 채널로
--     실시간 송수신만 하고 영속화는 안 함.
--
-- 본 마이그레이션은 D1 의 chat 관련 잔여 테이블/인덱스를 정리한다.
-- 0011_drop_chat_persistence.sql 에서 이미 한 차례 정리된 적이 있으나
-- 어떤 환경(시드 DB, 백업 복원 등)에서는 재생성됐을 수 있어 IF EXISTS 로 안전 정리.

DROP TABLE IF EXISTS chat_messages;
DROP TABLE IF EXISTS chat_room_members;
DROP TABLE IF EXISTS chat_rooms;
DROP TABLE IF EXISTS chat_message_reads;
DROP TABLE IF EXISTS chat_offers;

-- 정책 메모를 D1 안에 흔적으로 남긴다(운영자 점검용).
CREATE TABLE IF NOT EXISTS chat_policy (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  note  TEXT
);

INSERT OR REPLACE INTO chat_policy (key, value, note) VALUES
  ('storage_owner', 'qrchat_sdk',
   '채팅 내역의 저장·암호화·삭제 정책은 QRChat SDK 가 단독 책임. 가지 백엔드는 미보관.'),
  ('eggplant_persists', 'false',
   '가지(Eggplant) D1 에는 채팅 메시지를 어떤 형태로도 저장하지 않는다.'),
  ('voice_call_media', 'webrtc_p2p',
   '음성통화는 WebRTC P2P 로만 흐르며 서버는 시그널링도 휘발성으로 중계.');
