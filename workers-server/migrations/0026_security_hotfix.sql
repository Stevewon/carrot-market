-- ============================================================
-- 0026_security_hotfix.sql — 보안 핫픽스 (거래 구매자 확인 + 계정 정지)
-- ============================================================
-- 1) products.buyer_confirmed_at
--    판매자가 거래완료 + 구매자 지정만으로 구매자 QTA 가 차감되던 문제 수정.
--    이제 구매자가 직접 "거래 확인" 을 눌러야 QTA 결제 + 거래 보너스가 실행되고,
--    그 시각을 여기에 기록한다. 확인된 거래는 판매자가 상태를 되돌릴 수 없다.
--
-- 2) user_bans
--    0025 주석에는 users.is_banned 추가가 적혀 있지만 실제 ALTER 가 없어서
--    정지 기능이 동작하지 않았다. 운영 DB 에 컬럼이 수동으로 추가됐는지 여부를
--    알 수 없어 ALTER 대신 멱등한 별도 테이블로 관리한다.
--    (행 존재 = 정지 상태. 해제 시 행 삭제.)
-- ============================================================

ALTER TABLE products ADD COLUMN buyer_confirmed_at TEXT;

CREATE TABLE IF NOT EXISTS user_bans (
  user_id    TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  reason     TEXT,
  banned_by  TEXT,
  banned_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 0026 이전에 이미 QTA 결제까지 끝난 거래는 "구매자 확인 완료" 로 채워 둔다.
-- 안 그러면 판매자가 상태를 되돌려 다른 구매자를 지정할 수 있고, 그 구매자는
-- "이미 다른 구매자와 결제가 끝난 상품" 오류에 영구히 걸린다.
UPDATE products
   SET buyer_confirmed_at = updated_at
 WHERE status = 'sold'
   AND buyer_id IS NOT NULL
   AND buyer_confirmed_at IS NULL
   AND EXISTS (SELECT 1 FROM qta_ledger WHERE idem_key = 'trade_payment:' || products.id || ':debit');
