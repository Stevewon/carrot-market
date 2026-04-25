/**
 * Chat REST endpoints (persistent chat, 당근 style).
 *
 *   GET    /api/chat/rooms                       -> my chat rooms with last message
 *                                                   AND unread_count (per-user)
 *   GET    /api/chat/unread-count                -> total unread across all my rooms
 *   POST   /api/chat/rooms                       -> get-or-create a room
 *   POST   /api/chat/rooms/:roomId/read          -> mark this room as read up to now
 *   GET    /api/chat/rooms/:roomId/messages      -> paginated history
 *   DELETE /api/chat/rooms/:roomId               -> leave = delete the room AND all
 *                                                   messages for both users (CASCADE).
 *                                                   Also signals the peer via DO broadcast
 *                                                   so their client drops the room instantly.
 *   DELETE /api/chat/rooms/:roomId/messages      -> clear messages only; keep the room
 */

import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { authMiddleware } from '../jwt';

interface ChatRoomRow {
  id: string;
  user_a_id: string;
  user_b_id: string;
  product_id: string | null;
  product_title: string | null;
  product_thumb: string | null;
  last_message: string;
  last_sender_id: string | null;
  last_message_at: string;
  created_at: string;
  last_read_at_a: string | null;
  last_read_at_b: string | null;
}

interface ChatMessageRow {
  id: string;
  room_id: string;
  sender_id: string;
  text: string;
  msg_type: string;
  sent_at: string;
}

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use('*', authMiddleware);

/** Deterministic room id shared by both users. */
function makeRoomId(userA: string, userB: string, productId?: string | null): string {
  const [a, b] = [userA, userB].sort();
  return productId ? `${a}_${b}_${productId}` : `${a}_${b}`;
}

/** Verify the authenticated user is a member of the given room. */
async function getRoomIfMember(
  env: Env,
  roomId: string,
  userId: string
): Promise<ChatRoomRow | null> {
  const row = await env.DB.prepare(
    'SELECT * FROM chat_rooms WHERE id = ? AND (user_a_id = ? OR user_b_id = ?)'
  )
    .bind(roomId, userId, userId)
    .first<ChatRoomRow>();
  return row || null;
}

/** List my rooms, sorted by last activity. Includes unread_count per room. */
app.get('/rooms', async (c) => {
  const me = c.get('user')!;
  // The correlated sub-query computes unread count = messages from the OTHER
  // person sent after MY last_read_at. SQLite handles this efficiently with
  // the (room_id, sent_at) index.
  const rows = await c.env.DB.prepare(
    `SELECT r.*,
            CASE WHEN r.user_a_id = ? THEN r.user_b_id ELSE r.user_a_id END AS peer_id,
            u.nickname      AS peer_nickname,
            u.manner_score  AS peer_manner_score,
            (
              SELECT COUNT(*) FROM chat_messages m
               WHERE m.room_id = r.id
                 AND m.sender_id != ?
                 AND m.sent_at > COALESCE(
                       CASE WHEN r.user_a_id = ?
                            THEN r.last_read_at_a
                            ELSE r.last_read_at_b END,
                       r.created_at
                     )
            ) AS unread_count,
            CASE WHEN r.user_a_id = ?
                 THEN r.last_read_at_b
                 ELSE r.last_read_at_a END AS peer_last_read_at
       FROM chat_rooms r
       JOIN users u
         ON u.id = CASE WHEN r.user_a_id = ? THEN r.user_b_id ELSE r.user_a_id END
      WHERE (r.user_a_id = ? OR r.user_b_id = ?)
        AND (CASE WHEN r.user_a_id = ? THEN r.user_b_id ELSE r.user_a_id END)
            NOT IN (SELECT blocked_id FROM user_blocks WHERE blocker_id = ?)
      ORDER BY r.last_message_at DESC`
  )
    .bind(me.id, me.id, me.id, me.id, me.id, me.id, me.id, me.id, me.id)
    .all();

  return c.json({ rooms: rows.results || [] });
});

/** Total unread across all my rooms (for tab-bar badge on home). */
app.get('/unread-count', async (c) => {
  const me = c.get('user')!;
  const row = await c.env.DB.prepare(
    `SELECT COALESCE(SUM(cnt), 0) AS total
       FROM (
         SELECT (
           SELECT COUNT(*) FROM chat_messages m
            WHERE m.room_id = r.id
              AND m.sender_id != ?
              AND m.sent_at > COALESCE(
                    CASE WHEN r.user_a_id = ?
                         THEN r.last_read_at_a
                         ELSE r.last_read_at_b END,
                    r.created_at
                  )
         ) AS cnt
           FROM chat_rooms r
          WHERE r.user_a_id = ? OR r.user_b_id = ?
       )`
  )
    .bind(me.id, me.id, me.id, me.id)
    .first<{ total: number }>();

  return c.json({ unread: row?.total ?? 0 });
});

/**
 * POST /api/chat/rooms/:roomId/read
 * Marks the room as read for the authenticated user, updating their per-user
 * `last_read_at_*` to now(). Also broadcasts a `read_receipt` to the peer so
 * their UI can show "읽음" on the messages they sent.
 */
app.post('/rooms/:roomId/read', async (c) => {
  const me = c.get('user')!;
  const roomId = c.req.param('roomId');
  const room = await getRoomIfMember(c.env, roomId, me.id);
  if (!room) return c.json({ error: 'Not found' }, 404);

  const now = new Date().toISOString();
  const isA = room.user_a_id === me.id;
  const sql = isA
    ? "UPDATE chat_rooms SET last_read_at_a = ? WHERE id = ?"
    : "UPDATE chat_rooms SET last_read_at_b = ? WHERE id = ?";
  await c.env.DB.prepare(sql).bind(now, roomId).run();

  // Tell the peer in real-time that their messages are now read.
  try {
    const peerId = isA ? room.user_b_id : room.user_a_id;
    const id = c.env.CHAT_HUB.idFromName('global');
    const stub = c.env.CHAT_HUB.get(id);
    await stub.fetch('https://do/internal/read-receipt', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        room_id: roomId,
        reader_id: me.id,
        peer_user_id: peerId,
        read_at: now,
      }),
    });
  } catch (e) {
    console.error('[chat] broadcast read failed', e);
  }

  return c.json({ ok: true, read_at: now });
});

/**
 * Get-or-create a room between me and a peer.
 * Body: { peer_user_id, product_id?, product_title?, product_thumb? }
 */
app.post('/rooms', async (c) => {
  const me = c.get('user')!;
  let body: {
    peer_user_id?: string;
    product_id?: string;
    product_title?: string;
    product_thumb?: string;
  } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const peerUserId = (body.peer_user_id || '').trim();
  if (!peerUserId) return c.json({ error: 'peer_user_id is required' }, 400);
  if (peerUserId === me.id) return c.json({ error: '자기 자신과는 대화할 수 없어요' }, 400);

  const peer = await c.env.DB.prepare('SELECT id, nickname, manner_score FROM users WHERE id = ?')
    .bind(peerUserId)
    .first<{ id: string; nickname: string; manner_score: number }>();
  if (!peer) return c.json({ error: '상대방을 찾을 수 없어요' }, 404);

  // Block check: if EITHER side has blocked the other, refuse to (re)create
  // a room. We check both directions so a blocker can't be cold-DMed by their
  // blockee, AND a blockee can't keep talking to someone who blocked them.
  const block = await c.env.DB
    .prepare(
      `SELECT 1 FROM user_blocks
        WHERE (blocker_id = ? AND blocked_id = ?)
           OR (blocker_id = ? AND blocked_id = ?)
        LIMIT 1`
    )
    .bind(me.id, peerUserId, peerUserId, me.id)
    .first();
  if (block) {
    return c.json({ error: '대화할 수 없는 상대예요' }, 403);
  }

  const roomId = makeRoomId(me.id, peerUserId, body.product_id);
  const [userA, userB] = [me.id, peerUserId].sort();

  const existing = await c.env.DB.prepare('SELECT * FROM chat_rooms WHERE id = ?')
    .bind(roomId)
    .first<ChatRoomRow>();

  if (!existing) {
    await c.env.DB.prepare(
      `INSERT INTO chat_rooms
        (id, user_a_id, user_b_id, product_id, product_title, product_thumb,
         last_message, last_sender_id, last_message_at, created_at)
       VALUES (?, ?, ?, ?, ?, ?, '', NULL, datetime('now'), datetime('now'))`
    )
      .bind(
        roomId,
        userA,
        userB,
        body.product_id || null,
        body.product_title || null,
        body.product_thumb || null
      )
      .run();
  }

  return c.json({
    room: {
      id: roomId,
      peer_id: peer.id,
      peer_nickname: peer.nickname,
      peer_manner_score: peer.manner_score,
      product_id: body.product_id || existing?.product_id || null,
      product_title: body.product_title || existing?.product_title || null,
      product_thumb: body.product_thumb || existing?.product_thumb || null,
    },
  });
});

/** Paginated message history. Query: ?limit=50&before=<iso ts> */
app.get('/rooms/:roomId/messages', async (c) => {
  const me = c.get('user')!;
  const roomId = c.req.param('roomId');
  const room = await getRoomIfMember(c.env, roomId, me.id);
  if (!room) return c.json({ error: 'Not found' }, 404);

  const limit = Math.min(parseInt(c.req.query('limit') || '50', 10) || 50, 200);
  const before = c.req.query('before'); // optional ISO timestamp

  let rows;
  if (before) {
    rows = await c.env.DB.prepare(
      `SELECT id, room_id, sender_id, text, msg_type, sent_at
         FROM chat_messages
        WHERE room_id = ? AND sent_at < ?
        ORDER BY sent_at DESC
        LIMIT ?`
    )
      .bind(roomId, before, limit)
      .all<ChatMessageRow>();
  } else {
    rows = await c.env.DB.prepare(
      `SELECT id, room_id, sender_id, text, msg_type, sent_at
         FROM chat_messages
        WHERE room_id = ?
        ORDER BY sent_at DESC
        LIMIT ?`
    )
      .bind(roomId, limit)
      .all<ChatMessageRow>();
  }

  // Return in chronological (ascending) order for the client.
  const messages = (rows.results || []).slice().reverse();
  return c.json({ messages });
});

/**
 * DELETE /api/chat/rooms/:roomId
 *   "Leave room" = wipe the room AND all messages for BOTH users (CASCADE).
 *   Also notify the peer via the ChatHub DO so their UI drops the room instantly.
 */
app.delete('/rooms/:roomId', async (c) => {
  const me = c.get('user')!;
  const roomId = c.req.param('roomId');
  const room = await getRoomIfMember(c.env, roomId, me.id);
  if (!room) return c.json({ error: 'Not found' }, 404);

  // CASCADE deletes all chat_messages for this room.
  await c.env.DB.prepare('DELETE FROM chat_rooms WHERE id = ?').bind(roomId).run();

  // Fire-and-forget broadcast to the DO so any connected peer gets an instant drop.
  try {
    const peerId = room.user_a_id === me.id ? room.user_b_id : room.user_a_id;
    const id = c.env.CHAT_HUB.idFromName('global');
    const stub = c.env.CHAT_HUB.get(id);
    // Using DO RPC via fetch with a well-known internal path.
    await stub.fetch('https://do/internal/room-deleted', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        room_id: roomId,
        deleted_by: me.id,
        peer_user_id: peerId,
      }),
    });
  } catch (e) {
    console.error('[chat] broadcast delete failed', e);
  }

  return c.json({ ok: true });
});

/**
 * DELETE /api/chat/rooms/:roomId/messages
 *   Clear just the messages; keep the room itself.
 */
app.delete('/rooms/:roomId/messages', async (c) => {
  const me = c.get('user')!;
  const roomId = c.req.param('roomId');
  const room = await getRoomIfMember(c.env, roomId, me.id);
  if (!room) return c.json({ error: 'Not found' }, 404);

  await c.env.DB.prepare('DELETE FROM chat_messages WHERE room_id = ?').bind(roomId).run();
  await c.env.DB.prepare(
    `UPDATE chat_rooms
        SET last_message = '', last_sender_id = NULL, last_message_at = datetime('now')
      WHERE id = ?`
  )
    .bind(roomId)
    .run();

  // Tell peer to refresh their message list (but keep the room).
  try {
    const peerId = room.user_a_id === me.id ? room.user_b_id : room.user_a_id;
    const id = c.env.CHAT_HUB.idFromName('global');
    const stub = c.env.CHAT_HUB.get(id);
    await stub.fetch('https://do/internal/messages-cleared', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        room_id: roomId,
        cleared_by: me.id,
        peer_user_id: peerId,
      }),
    });
  } catch (e) {
    console.error('[chat] broadcast clear failed', e);
  }

  return c.json({ ok: true });
});

export default app;
