-- ============================================================
-- 0036_wallet_return.sql — 지갑 인증: 본사 5.xxxxxx 송금 → 회원이 1.xxxxxx 를 돌려보냄
-- ============================================================
-- 본사가 보낸 수량은 scan 에 공개돼 소유 증명이 안 된다 (남도 볼 수 있음).
-- 지갑 주인만 할 수 있는 "그 지갑에서 본사로 송금"을 증명으로 쓴다.
--   return_amount_*: 회원이 돌려보낼 수량 (요청한 회원에게만 알려줌)
--   tx_hash(UNIQUE): 돌려보낸 거래 — 같은 거래로 두 번 인증 불가
-- ============================================================

ALTER TABLE wallet_challenges ADD COLUMN return_amount_wei TEXT;
ALTER TABLE wallet_challenges ADD COLUMN return_amount_display TEXT;

-- 예전 방식(받은 수량 입력)으로 열려 있던 요청은 모두 닫는다.
UPDATE wallet_challenges SET status = 'used', used_at = datetime('now')
 WHERE direction = 'to_user' AND status IN ('pending', 'verified');
