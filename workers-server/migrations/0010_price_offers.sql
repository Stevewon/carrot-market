-- Sprint 4 — 가격 제안 / 네고 (당근식)
--
-- 채팅방에서 사용자가 상품 가격을 흥정할 수 있도록 별도 메시지 타입과 상태 테이블을 둔다.
--
-- 흐름:
--   1) 구매자가 채팅방(상품 첨부된 방)에서 "5,000원에 살래요" 같은 제안 메시지를 보낸다.
--   2) 제안은 chat_messages 에 msg_type='price_offer' 로 저장되고, 동시에
--      price_offers 테이블에 pending 상태로 한 줄이 들어간다. text 필드에는 클라이언트 표시용 요약 ("5,000원 가격 제안") 이 들어간다.
--   3) 판매자가 그 메시지의 [수락]/[거절] 버튼을 누르면 price_offers.status 가
--      accepted / rejected 로 바뀐다. 클라이언트는 status 를 보고 메시지 카드의 모양을 갱신.
--   4) 한 채팅방에는 동시에 1건의 pending 제안만 존재 (UNIQUE partial index).
--      새 제안을 보내면 직전 pending 은 자동으로 cancelled 로 만든다(서버 라우트가 처리).
--
-- 메시지 자체가 chat_messages 에 들어가므로 채팅 히스토리 / 마지막 메시지 / 안 읽음 카운트
-- 같은 기존 로직과 그대로 호환된다. 제안의 "상태"만 별도로 가져오면 된다.
--
-- chat_messages 의 msg_type CHECK 제약은 두지 않았기 때문에(기존 0003 참고) 별도
-- 마이그레이션 없이 바로 'price_offer' 값을 사용할 수 있다.

CREATE TABLE IF NOT EXISTS price_offers (
  id          TEXT PRIMARY KEY,
  room_id     TEXT NOT NULL,
  message_id  TEXT NOT NULL,                  -- chat_messages.id 와 1:1 매핑
  product_id  TEXT,                           -- 방의 product_id (편의를 위한 비정규화)
  buyer_id    TEXT NOT NULL,                  -- 제안한 사람 (구매자)
  seller_id   TEXT NOT NULL,                  -- 받은 사람 (판매자)
  price       INTEGER NOT NULL,               -- 제안 금액 (원 단위)
  status      TEXT NOT NULL DEFAULT 'pending',-- pending | accepted | rejected | cancelled
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  responded_at TEXT,                          -- 수락/거절 시각
  FOREIGN KEY (room_id)    REFERENCES chat_rooms(id)    ON DELETE CASCADE,
  FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id)      ON DELETE SET NULL,
  FOREIGN KEY (buyer_id)   REFERENCES users(id)         ON DELETE CASCADE,
  FOREIGN KEY (seller_id)  REFERENCES users(id)         ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_price_offers_room    ON price_offers(room_id);
CREATE INDEX IF NOT EXISTS idx_price_offers_message ON price_offers(message_id);
CREATE INDEX IF NOT EXISTS idx_price_offers_status  ON price_offers(status);

-- 한 방에 동시에 pending 제안은 최대 1건 — partial unique index.
CREATE UNIQUE INDEX IF NOT EXISTS idx_price_offers_one_pending_per_room
  ON price_offers(room_id) WHERE status = 'pending';
