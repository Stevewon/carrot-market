-- ────────────────────────────────────────────────────────────────────
-- 0021_admin.sql
-- 운영자(어드민) 전용 테이블 + 기존 테이블 컬럼 확장.
--
-- 6대 어드민 기능 매핑:
--   ① 사용자 관리(차단/검증) → users.is_blocked, users.blocked_at, users.blocked_reason
--   ② 상품 관리(삭제/숨김/신고처리) → products.hidden_by_admin, products.hidden_reason
--   ③ QKEY 거래 원장 조회 → 기존 qta_transactions / withdrawals 테이블 활용 (read-only)
--   ④ 매출/통계 대시보드 → 집계 쿼리 (별도 테이블 X, 비용 절감)
--   ⑤ 공지/푸시 발송 → notices (신규)
--   ⑥ 신고 처리 → user_reports (기존) + reports.status 컬럼 추가
--
-- 모든 어드민 액션 → admin_audit 에 기록 (감사 로그).
-- ────────────────────────────────────────────────────────────────────

-- ① 사용자 차단 컬럼
ALTER TABLE users ADD COLUMN is_blocked INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN blocked_at TEXT;
ALTER TABLE users ADD COLUMN blocked_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_users_is_blocked ON users(is_blocked);

-- ② 상품 숨김(어드민) 컬럼
ALTER TABLE products ADD COLUMN hidden_by_admin INTEGER NOT NULL DEFAULT 0;
ALTER TABLE products ADD COLUMN hidden_reason TEXT;
ALTER TABLE products ADD COLUMN hidden_at TEXT;

CREATE INDEX IF NOT EXISTS idx_products_hidden_by_admin ON products(hidden_by_admin);

-- ⑥ 신고 처리 상태 컬럼
ALTER TABLE user_reports ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'
  CHECK (status IN ('pending', 'resolved', 'dismissed'));
ALTER TABLE user_reports ADD COLUMN resolved_at TEXT;
ALTER TABLE user_reports ADD COLUMN resolved_note TEXT;

CREATE INDEX IF NOT EXISTS idx_user_reports_status ON user_reports(status, created_at DESC);

-- ⑤ 공지/푸시 발송 테이블
-- type:
--   'notice'  : 앱 내 공지 (배너/팝업)
--   'push'    : 푸시 알림 발송 (FCM 연동 별도)
--   'banner'  : 메인 화면 배너
-- target:
--   'all'     : 전체 사용자
--   'region'  : 특정 지역 (target_value = region 명)
--   'user'    : 특정 user_id (target_value = user_id)
CREATE TABLE IF NOT EXISTS notices (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  type          TEXT NOT NULL CHECK (type IN ('notice', 'push', 'banner')),
  target        TEXT NOT NULL CHECK (target IN ('all', 'region', 'user')),
  target_value  TEXT,
  title         TEXT NOT NULL,
  body          TEXT NOT NULL DEFAULT '',
  link_url      TEXT,
  active        INTEGER NOT NULL DEFAULT 1,
  starts_at     TEXT,
  ends_at       TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  created_by    TEXT
);

CREATE INDEX IF NOT EXISTS idx_notices_active ON notices(active, ends_at);
CREATE INDEX IF NOT EXISTS idx_notices_type ON notices(type);

-- 어드민 감사 로그 (모든 어드민 액션 기록)
-- action:
--   'user.block', 'user.unblock', 'user.verify',
--   'product.hide', 'product.unhide', 'product.delete',
--   'report.resolve', 'report.dismiss',
--   'notice.create', 'notice.delete',
--   'admin.login'
CREATE TABLE IF NOT EXISTS admin_audit (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  action        TEXT NOT NULL,
  target_id     TEXT,
  payload_json  TEXT,
  ip            TEXT,
  user_agent    TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_action ON admin_audit(action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_target ON admin_audit(target_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit(created_at DESC);
