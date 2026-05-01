-- 채팅 내역 = QRChat 정책 100%% 위임
--
-- 결정사항:
--   채팅·통화는 QRChat 을 만든 회사가 SDK 를 제공한다.
--   채팅 내역의 저장 기간/암호화/내보내기/삭제 정책은 무조건 QRChat 정책을 따른다.
--   가지(Eggplant) 백엔드는 채팅 메시지를 절대 저장·중계·복제하지 않는다.
--
-- 따라서:
--   - 가지 D1 에는 채팅 메시지 테이블이 없어야 한다.
--   - 과거 임시 보존되던 chat_* 테이블이 있다면 정리 (있어도 / 없어도 안전).
--   - 채팅방 메타(룸 ID, 참여자 매핑)도 가지에서는 보관하지 않는다.
--   - 가격 제안·읽음 처리 등 가지 고유 이벤트는 QRChat 의 generic event 채널로
--     실시간 송수신만 하고 영속화는 안 함.
--
-- 본 마이그레이션은 D1 의 chat 관련 잔여 테이블/인덱스를 정리한다.
-- 0011_drop_chat_persistence.sql 에서 이미 한 차례 정리된 적이 있으나
-- 어떤 환경(시드 DB, 백업 복원 등)에서는 재생성됐을 수 있어 IF EXISTS 로 안전 정리.

DROP TABLE IF EXISTS chat_messages;
DROP TABLE IF EXISTS chat_room_members;
DROP TABLE IF EXISTS chat_rooms;
DROP TABLE IF EXISTS chat_message_reads;
DROP TABLE IF EXISTS chat_offers;

-- 정책 메모를 D1 안에 흔적으로 남긴다(운영자 점검용).
CREATE TABLE IF NOT EXISTS chat_policy (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  note  TEXT
);

INSERT OR REPLACE INTO chat_policy (key, value, note) VALUES
  ('storage_owner', 'qrchat_sdk',
   '채팅 내역의 저장·암호화·삭제 정책은 QRChat SDK 가 단독 책임. 가지 백엔드는 미보관.'),
  ('eggplant_persists', 'false',
   '가지(Eggplant) D1 에는 채팅 메시지를 어떤 형태로도 저장하지 않는다.'),
  ('voice_call_media', 'webrtc_p2p',
   '음성통화는 WebRTC P2P 로만 흐르며 서버는 시그널링도 휘발성으로 중계.');
