-- Eggplant 🍆 - Chat read tracking (당근식 unread badge)
--
-- Each room has TWO participants (user_a, user_b). We store a per-user
-- "last_read_at" timestamp on the room itself, and compute the unread
-- count at query time as:
--   COUNT(*) FROM chat_messages
--    WHERE room_id = ?
--      AND sender_id != me
--      AND sent_at > my_last_read_at
--
-- This is fast because chat_messages already has indexes on (room_id) and
-- (sent_at), and rooms are O(few hundred) per user worst case.
--
-- NULL last_read_at_* = "never read" — every existing message counts as unread.
-- We backfill with the room's created_at so existing rooms don't suddenly
-- show every old message as unread.

ALTER TABLE chat_rooms ADD COLUMN last_read_at_a TEXT;
ALTER TABLE chat_rooms ADD COLUMN last_read_at_b TEXT;

-- Backfill: treat existing rooms as fully read up to creation time, so old
-- conversations don't pop up with massive unread counts on first deploy.
UPDATE chat_rooms
   SET last_read_at_a = COALESCE(last_message_at, created_at),
       last_read_at_b = COALESCE(last_message_at, created_at)
 WHERE last_read_at_a IS NULL OR last_read_at_b IS NULL;
