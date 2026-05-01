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
