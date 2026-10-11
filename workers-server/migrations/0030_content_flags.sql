-- ============================================================
-- 0030_content_flags.sql — 거래 금지 품목 / 금지어 검토 큐 (멱등)
-- ============================================================
-- src/prohibited.ts 가 감지한 이벤트를 적재한다.
--   action='review' → status='pending'  : 등록은 됐지만 운영자 검토 필요 (어드민 /api/admin/flags)
--   action='block'  → status='logged'   : 등록 거절된 시도 기록 (반복 시도자 파악용)
-- 채팅 내용은 저장하지 않는다 (채팅 비저장 정책).
-- ============================================================

CREATE TABLE IF NOT EXISTS content_flags (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id      TEXT,
  target_type  TEXT NOT NULL CHECK (target_type IN ('product', 'nickname', 'keyword')),
  target_id    TEXT,
  action       TEXT NOT NULL CHECK (action IN ('block', 'review')),
  rule_id      TEXT NOT NULL,
  label        TEXT NOT NULL,
  matched      TEXT NOT NULL DEFAULT '',
  field        TEXT,
  status       TEXT NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending', 'resolved', 'dismissed', 'logged')),
  resolved_at  TEXT,
  resolved_note TEXT,
  created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_content_flags_status ON content_flags(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_content_flags_user   ON content_flags(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_content_flags_target ON content_flags(target_type, target_id);
