-- Chat persistence (당근 style). Everything is deletable by either party.
-- When a room is deleted, ALL messages cascade-delete on both users.

CREATE TABLE IF NOT EXISTS chat_rooms (
  id              TEXT PRIMARY KEY,               -- sorted(userA,userB)[_productId]
  user_a_id       TEXT NOT NULL,
  user_b_id       TEXT NOT NULL,
  product_id      TEXT,                            -- nullable: direct QR chat
  product_title   TEXT,
  product_thumb   TEXT,
  last_message    TEXT NOT NULL DEFAULT '',
  last_sender_id  TEXT,
  last_message_at TEXT NOT NULL DEFAULT (datetime('now')),
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_a_id)  REFERENCES users(id)    ON DELETE CASCADE,
  FOREIGN KEY (user_b_id)  REFERENCES users(id)    ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_user_a       ON chat_rooms(user_a_id);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_user_b       ON chat_rooms(user_b_id);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_last_msg_at  ON chat_rooms(last_message_at DESC);

CREATE TABLE IF NOT EXISTS chat_messages (
  id          TEXT PRIMARY KEY,
  room_id     TEXT NOT NULL,
  sender_id   TEXT NOT NULL,
  text        TEXT NOT NULL,
  msg_type    TEXT NOT NULL DEFAULT 'text',     -- text | image | system
  sent_at     TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (room_id)   REFERENCES chat_rooms(id) ON DELETE CASCADE,
  FOREIGN KEY (sender_id) REFERENCES users(id)      ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_room_id  ON chat_messages(room_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sent_at  ON chat_messages(sent_at);
