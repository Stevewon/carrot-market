-- 사생활 보호 정책: 채팅·가격제안은 절대 DB 에 저장하지 않는다.
--
-- 한 번 흘러간 메시지는 영구 소실되어야 하며, 양쪽 기기 어디에도 복원되지 않는다.
-- (telegram secret chat / signal 의 "휘발성 채팅" 모델)
--
-- 이 마이그레이션은 그 동안 잠시 운영했던 영구 채팅 테이블을 전부 제거한다.
-- 기존 데이터는 모두 삭제된다 — 의도된 동작이다.
--
-- 이후 채팅은:
--   - WebSocket Durable Object 메모리에서만 broadcast.
--   - DB 에 어떤 흔적도 남기지 않음.
--   - 앱 재실행 / 다른 기기 로그인 시 채팅 목록 빈 상태로 시작.
--
-- 통화는 원래부터 WebRTC P2P 라 미디어가 서버를 거치지 않았다 (변경 없음).

-- 자식 테이블부터 순서대로 (FK CASCADE 정의되어 있어도 명시적으로 처리)
DROP TABLE IF EXISTS price_offers;
DROP TABLE IF EXISTS chat_messages;
DROP TABLE IF EXISTS chat_rooms;

-- 관련 인덱스는 테이블과 함께 자동 삭제되지만 혹시 남아 있을 수 있는 잔재를 정리.
DROP INDEX IF EXISTS idx_chat_rooms_user_a;
DROP INDEX IF EXISTS idx_chat_rooms_user_b;
DROP INDEX IF EXISTS idx_chat_rooms_last_msg_at;
DROP INDEX IF EXISTS idx_chat_messages_room_id;
DROP INDEX IF EXISTS idx_chat_messages_sent_at;
DROP INDEX IF EXISTS idx_price_offers_room;
DROP INDEX IF EXISTS idx_price_offers_message;
DROP INDEX IF EXISTS idx_price_offers_status;
DROP INDEX IF EXISTS idx_price_offers_one_pending_per_room;
