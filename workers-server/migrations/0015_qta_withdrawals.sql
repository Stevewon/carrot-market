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
