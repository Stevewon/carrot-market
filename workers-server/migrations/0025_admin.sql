-- ============================================================
-- 0025_admin.sql — 어드민 웹 콘솔 인프라 (멱등/중복 안전)
-- ============================================================
-- 정책:
--   - 기존 admin_audit (단순 구조) 보존, 어드민 콘솔용 admin_audit_log 신규 생성
--   - 기존 user_reports.status / resolved_at / resolved_note 컬럼 재사용 (중복 ALTER 금지)
--   - users.is_banned / banned_at / ban_reason 만 추가
--   - QKEY 잔액 조작 컬럼/엔드포인트는 만들지 않음 (사장님 보호 정책)
-- ============================================================

-- 어드민 계정 테이블
CREATE TABLE IF NOT EXISTS admins (
  id              TEXT PRIMARY KEY,
  username        TEXT NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,
  email           TEXT,
  role            TEXT NOT NULL DEFAULT 'admin'
                  CHECK (role IN ('admin', 'super_admin')),
  is_active       INTEGER NOT NULL DEFAULT 1,
  must_change_pw  INTEGER NOT NULL DEFAULT 1,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  last_login_at   TEXT
);

CREATE INDEX IF NOT EXISTS idx_admins_username ON admins(username);

-- 어드민 세션
CREATE TABLE IF NOT EXISTS admin_sessions (
  id           TEXT PRIMARY KEY,
  admin_id     TEXT NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
  ip           TEXT,
  user_agent   TEXT,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at   TEXT NOT NULL,
  revoked_at   TEXT
);

CREATE INDEX IF NOT EXISTS idx_admin_sessions_admin   ON admin_sessions(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_sessions_expires ON admin_sessions(expires_at);

-- 어드민 감사 로그 (기존 admin_audit 과 별개)
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  admin_id    TEXT NOT NULL,
  action      TEXT NOT NULL,
  target_type TEXT,
  target_id   TEXT,
  detail      TEXT,
  ip          TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin   ON admin_audit_log(admin_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_action  ON admin_audit_log(action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_target  ON admin_audit_log(target_type, target_id);
