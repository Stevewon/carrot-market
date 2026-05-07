-- ============================================================
-- 0025_admin.sql — 어드민 웹 콘솔 인프라
-- ============================================================
-- 목적:
--   1) 사장님 전용 어드민 웹 (https://eggplant.life/admin/) 인증/감사 기반.
--   2) 사용자 정지(ban) 컬럼 추가 — 영구 삭제 대신 비활성화 정책.
--   3) 신고 처리 상태 컬럼 추가 — 운영자가 처리 큐로 관리.
--   4) 모든 어드민 액션을 admin_audit_log 에 기록 (감사 추적).
--
-- 정책:
--   - 어드민 인증은 Workers Secret ADMIN_TOKEN (/api/admin/login → 발급)
--     또는 admins 테이블의 username/password_hash 매칭 방식.
--   - QKEY 잔액 조작 컬럼/엔드포인트는 만들지 않음 (사장님 보호 정책).
--   - 사용자 영구 삭제 없음 — is_banned = 1 로 비활성화.
-- ============================================================

-- 어드민 계정 테이블 (앱 사용자와 완전 분리)
CREATE TABLE IF NOT EXISTS admins (
  id              TEXT PRIMARY KEY,                 -- uuid
  username        TEXT NOT NULL UNIQUE,             -- 로그인 ID
  password_hash   TEXT NOT NULL,                    -- PBKDF2(salt$hash) 형식 (crypto.ts 와 호환)
  email           TEXT,
  role            TEXT NOT NULL DEFAULT 'admin'     -- 'admin' | 'super_admin'
                  CHECK (role IN ('admin', 'super_admin')),
  is_active       INTEGER NOT NULL DEFAULT 1,
  must_change_pw  INTEGER NOT NULL DEFAULT 1,       -- 첫 로그인 시 강제 변경
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  last_login_at   TEXT
);

CREATE INDEX IF NOT EXISTS idx_admins_username ON admins(username);

-- 어드민 세션 (JWT 와 별도 — 짧은 TTL, 강제 종료 가능)
CREATE TABLE IF NOT EXISTS admin_sessions (
  id           TEXT PRIMARY KEY,                    -- 세션 토큰 (랜덤 hex)
  admin_id     TEXT NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
  ip           TEXT,
  user_agent   TEXT,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at   TEXT NOT NULL,
  revoked_at   TEXT
);

CREATE INDEX IF NOT EXISTS idx_admin_sessions_admin   ON admin_sessions(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_sessions_expires ON admin_sessions(expires_at);

-- 어드민 감사 로그 (모든 admin 액션 기록)
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  admin_id    TEXT NOT NULL,                        -- admins.id (FK 없음 = 어드민 삭제돼도 로그 보존)
  action      TEXT NOT NULL,                        -- 'login', 'ban_user', 'reject_withdrawal', etc.
  target_type TEXT,                                 -- 'user', 'product', 'withdrawal', 'report'
  target_id   TEXT,
  detail      TEXT,                                 -- JSON 또는 짧은 메모
  ip          TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_admin   ON admin_audit_log(admin_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_action  ON admin_audit_log(action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_target  ON admin_audit_log(target_type, target_id);

-- 사용자 정지 컬럼 추가 (영구 삭제 대신 비활성화)
ALTER TABLE users ADD COLUMN is_banned INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN banned_at TEXT;
ALTER TABLE users ADD COLUMN ban_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_users_banned ON users(is_banned);

-- 신고 처리 상태 컬럼 추가
ALTER TABLE user_reports ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'
  CHECK (status IN ('pending', 'reviewing', 'resolved', 'dismissed'));
ALTER TABLE user_reports ADD COLUMN handled_by TEXT;     -- admins.id
ALTER TABLE user_reports ADD COLUMN handled_at TEXT;
ALTER TABLE user_reports ADD COLUMN admin_note TEXT;

CREATE INDEX IF NOT EXISTS idx_user_reports_status ON user_reports(status, created_at DESC);
