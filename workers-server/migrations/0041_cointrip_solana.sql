-- ============================================================
-- 0041_cointrip_solana.sql — 코인트립 체인: Quantarium · Ethereum · BNB · Polygon · Solana
-- ============================================================
-- 사장님 지시 (2026-10-18): 체인을 이더리움·BNB·솔라나·폴리곤·퀀타리움 다섯 개에서 고른다.
--   Quantarium              → users.wallet_address (퀀타리움 월렛)
--   Ethereum · BNB · Polygon → users.ext_wallet_address (0x 주소 하나로 셋 다 받음)
--   Solana                  → users.sol_wallet_address (솔라나 주소, 0x 아님)
-- 어느 주소로 받는지는 ct_coins.network 로 정한다 (src/cointrip.ts walletKeyOf).
-- ============================================================

ALTER TABLE users ADD COLUMN sol_wallet_address TEXT;
ALTER TABLE users ADD COLUMN sol_wallet_set_at TEXT;
