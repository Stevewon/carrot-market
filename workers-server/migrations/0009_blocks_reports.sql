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
