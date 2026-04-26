-- 0018_reset_all_data.sql
--
-- ⚠️ DESTRUCTIVE: 모든 사용자/상품/거래/QTA 데이터를 삭제한다.
--
-- 목적
--   QA/개발 단계에서 누적된 샘플 데이터(테스트 계정, 더미 상품, 가짜 채팅
--   기록, 잔여 QTA 잔액 등)를 한 번에 비우고 "회원가입부터 다시" 시작할
--   수 있도록 한다.
--
-- 방식
--   - 스키마(테이블/인덱스)는 보존, 데이터만 DELETE.
--   - 외래키 의존 순서를 고려해 자식 → 부모 순으로 지운다.
--   - SQLite/D1 은 sqlite_sequence 가 있는 경우만 AUTOINCREMENT 카운터를
--     리셋하지만, 이 프로젝트는 모두 TEXT(UUID) PK 라 sqlite_sequence 를
--     쓰지 않는다. 따라서 별도 시퀀스 리셋은 불필요.
--   - 채팅(chat_messages, chat_rooms) 은 0011 에서 이미 DROP 됐고, 현재
--     채팅은 Durable Object 메모리에서만 살아있다 → DB 에서 지울 게 없음.
--
-- 실행 후
--   - 모든 사용자가 로그아웃된 것과 동일한 상태가 된다 (서버에 row 가 없음).
--   - 클라이언트에 남아있던 JWT 는 다음 인증 요청 시 401 → 자동 로그아웃.
--   - R2 업로드 (이미지/비디오) 는 별도 정리가 필요하다 (이 마이그레이션
--     으로는 안 지워짐). 필요시:
--       npx wrangler r2 bucket delete eggplant-uploads --recursive
--       npx wrangler r2 bucket create eggplant-uploads
--
-- 멱등성
--   여러 번 실행해도 안전 (이미 비어 있어도 DELETE 는 0행 영향).

-- ── 자식 테이블 먼저 ────────────────────────────────────────────────
DELETE FROM reviews;
DELETE FROM price_offers;
DELETE FROM user_reports;
DELETE FROM user_blocks;
DELETE FROM hidden_products;
DELETE FROM keyword_alerts;
DELETE FROM product_likes;
DELETE FROM qta_withdrawals;
DELETE FROM qta_daily_login;
DELETE FROM qta_ledger;
DELETE FROM referrals;

-- ── 부모 테이블 ─────────────────────────────────────────────────────
DELETE FROM products;
DELETE FROM users;
