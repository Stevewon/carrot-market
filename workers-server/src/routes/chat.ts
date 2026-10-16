/**
 * 채팅 REST 엔드포인트 (휘발성 / 사생활 보호 모드).
 *
 * 정책: 채팅·메시지·가격제안은 절대 DB 에 저장하지 않는다.
 *       모든 상태는 WebSocket Durable Object 메모리에만 잠시 머무른다.
 *       앱 재실행 / 서버 재시작 / DO hibernation 만료 시 모두 사라진다.
 *
 * 그 결과 chat.ts 가 제공하는 REST 는 거의 비어 있다:
 *
 *   POST /api/chat/rooms       -> 클라이언트가 임의로 부르면 deterministic roomId
 *                                 만 계산해서 돌려줌. DB 흔적 없음.
 *   GET  /api/chat/rooms       -> 빈 배열. (서버는 누가 누구와 채팅 중인지 모름)
 *   GET  /api/chat/unread-count -> { unread: 0 }. (서버는 unread 를 모름)
 *   GET  /api/chat/rooms/:roomId/messages -> 빈 배열. (히스토리 없음)
 *   POST /api/chat/rooms/:roomId/read     -> 200 ok (no-op).
 *   DELETE /api/chat/rooms/:roomId         -> 200 ok (no-op). 휘발성이라 삭제할 게 없음.
 *   DELETE /api/chat/rooms/:roomId/messages -> 200 ok (no-op).
 *
 * 가격 제안(price offer)도 일반 메시지처럼 WebSocket 으로만 흘러가고 DB 에 저장되지 않는다.
 * 따라서 별도 REST 엔드포인트 없이 chat-hub.ts 의 'price_offer' / 'offer_response' 이벤트로 처리.
 *
 * 신원 노출은 닉네임만. wallet_address / device_uuid / 비밀번호 / id 같은 식별자는
 * 응답 어디에도 포함되지 않는다 (peer 정보는 닉네임 + 매너온도만).
 */

import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { authMiddleware } from '../jwt';
import { tr } from '../market';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use('*', authMiddleware);

/** 결정적 roomId — 양쪽 사용자가 같은 ID 를 산출하도록. */
function makeRoomId(userA: string, userB: string, productId?: string | null): string {
  const [a, b] = [userA, userB].sort();
  return productId ? `${a}_${b}_${productId}` : `${a}_${b}`;
}

/**
 * GET /api/chat/rooms
 *   서버는 채팅을 저장하지 않으므로 항상 빈 배열을 돌려준다.
 *   채팅 목록은 클라이언트가 메모리에서만 유지한다 (앱 종료 시 소실).
 */
app.get('/rooms', async (c) => {
  return c.json({ rooms: [] });
});

/**
 * GET /api/chat/unread-count
 *   서버는 메시지를 저장하지 않으므로 항상 0.
 *   읽음/안 읽음 뱃지도 클라이언트 메모리에서만 관리.
 */
app.get('/unread-count', async (c) => {
  return c.json({ unread: 0 });
});

/**
 * POST /api/chat/rooms
 *   Body: { peer_user_id, product_id?, product_title?, product_thumb? }
 *
 *   상대방이 실재하는 사용자인지만 검증하고, deterministic roomId 와
 *   상대방의 *공개* 정보(닉네임 + 매너온도)만 돌려준다.
 *   DB 에 어떤 행도 만들지 않는다 — 휘발성.
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
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);
  }

  const peerUserId = (body.peer_user_id || '').trim();
  if (!peerUserId) {
    return c.json({ error: tr(c, 'peer_user_id 가 필요해요', 'peer_user_id が必要です', 'peer_user_id is required') }, 400);
  }
  if (peerUserId === me.id) {
    return c.json({ error: tr(c, '자기 자신과는 채팅할 수 없어요', 'ご自身とはチャットできません', "You can't chat with yourself") }, 400);
  }

  // 상대방 닉네임/매너온도만 조회 — wallet, device_uuid 같은 식별자는 절대 노출하지 않음.
  const peer = await c.env.DB
    .prepare('SELECT id, nickname, manner_score FROM users WHERE id = ?')
    .bind(peerUserId)
    .first<{ id: string; nickname: string; manner_score: number }>();
  if (!peer) {
    return c.json({ error: tr(c, '상대방을 찾을 수 없어요', 'お相手が見つかりません', "We couldn't find this user") }, 404);
  }

  const roomId = makeRoomId(me.id, peer.id, body.product_id);
  const nowIso = new Date().toISOString();

  return c.json({
    room: {
      id: roomId,
      peer_id: peer.id,
      peer_nickname: peer.nickname,
      peer_manner_score: peer.manner_score,
      product_id: body.product_id || null,
      product_title: body.product_title || null,
      product_thumb: body.product_thumb || null,
      last_message: '',
      last_sender_id: null,
      last_message_at: nowIso,
      created_at: nowIso,
      // 휘발성이므로 unread / peer_last_read_at 은 항상 0/null 로 시작.
      unread_count: 0,
      peer_last_read_at: null,
    },
  });
});

/**
 * POST /api/chat/rooms/:roomId/read
 *   no-op. 휘발성이라 서버에 read 상태가 없음.
 *   읽음 표시(read receipt) 는 WebSocket 으로 직접 peer 에게만 전달된다.
 */
app.post('/rooms/:roomId/read', async (c) => {
  return c.json({ ok: true });
});

/**
 * GET /api/chat/rooms/:roomId/messages
 *   휘발성: 히스토리가 없으므로 항상 빈 배열.
 */
app.get('/rooms/:roomId/messages', async (c) => {
  return c.json({ messages: [] });
});

/**
 * DELETE /api/chat/rooms/:roomId
 *   no-op. 휘발성이라 삭제할 DB 행이 없다.
 *   클라이언트가 호출하면 200 만 돌려주고, WebSocket 으로 peer 에게도 'room_deleted'
 *   broadcast 해서 양쪽 메모리 캐시에서 제거되도록 한다.
 */
app.delete('/rooms/:roomId', async (c) => {
  const me = c.get('user')!;
  const roomId = c.req.param('roomId');

  // peer 식별: roomId 형식이 'a_b' 또는 'a_b_productId' 라서 내가 아닌 ID 가 peer.
  // 단, productId 가 36자 UUID 가 아닐 수도 있으니 단순히 토큰 중 길이 ≥ 30 인 것 중
  // 내 ID 가 아닌 것을 뽑는다.
  let peerId = '';
  for (const tok of roomId.split('_')) {
    if (tok.length >= 30 && tok !== me.id) { peerId = tok; break; }
  }

  if (peerId) {
    try {
      const id = c.env.CHAT_HUB.idFromName('global');
      const stub = c.env.CHAT_HUB.get(id);
      await stub.fetch('https://do/internal/room-deleted', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ room_id: roomId, deleted_by: me.id, peer_user_id: peerId }),
      });
    } catch (e) {
      console.error('[chat] broadcast delete failed', e);
    }
  }
  return c.json({ ok: true });
});

/**
 * DELETE /api/chat/rooms/:roomId/messages
 *   no-op (휘발성). peer 에게 'messages_cleared' broadcast 만.
 */
app.delete('/rooms/:roomId/messages', async (c) => {
  const me = c.get('user')!;
  const roomId = c.req.param('roomId');

  let peerId = '';
  for (const tok of roomId.split('_')) {
    if (tok.length >= 30 && tok !== me.id) { peerId = tok; break; }
  }
  if (peerId) {
    try {
      const id = c.env.CHAT_HUB.idFromName('global');
      const stub = c.env.CHAT_HUB.get(id);
      await stub.fetch('https://do/internal/messages-cleared', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ room_id: roomId, cleared_by: me.id, peer_user_id: peerId }),
      });
    } catch (e) {
      console.error('[chat] broadcast clear failed', e);
    }
  }
  return c.json({ ok: true });
});

export default app;

// ---------- 채팅 사진 (암호화본, 잠시 보관 후 삭제) ----------
//
// 사진은 보내는 폰에서 AES-256-GCM 으로 암호화한 뒤 올린다. 열쇠는 메시지(WebSocket)
// 로만 상대에게 가고 서버는 열쇠를 저장하지 않는다 → 서버에 남는 것은 읽을 수 없는 암호문뿐.
// 받는 사람이 내려받으면 바로 지우고, 못 받아도 24시간 뒤 cron 이 지운다.
//
//   POST   /api/chat/media?room_id=...   body: 암호문 바이트 → { id }
//   GET    /api/chat/media/:id           → 암호문 바이트 (같은 방 참여자만)
//   DELETE /api/chat/media/:id           → 삭제 (같은 방 참여자만)

const CHAT_MEDIA_PREFIX = 'chat-media/';
const CHAT_MEDIA_MAX = 3 * 1024 * 1024; // 압축한 사진 1장 — 3MB 면 넉넉하다
export const CHAT_MEDIA_TTL_MS = 24 * 60 * 60 * 1000;

function isRoomMember(roomId: string, userId: string): boolean {
  const parts = roomId.split('_');
  return parts.length >= 2 && (parts[0] === userId || parts[1] === userId);
}

app.post('/media', async (c) => {
  const me = c.get('user')!;
  const roomId = c.req.query('room_id') || '';
  if (!roomId || !isRoomMember(roomId, me.id)) {
    return c.json({ error: tr(c, '이 채팅방에 참여할 수 없어요', 'このチャットルームには参加できません', "You can't join this chat room") }, 403);
  }
  const len = parseInt(c.req.header('content-length') || '0', 10);
  if (len > CHAT_MEDIA_MAX) {
    return c.json({ error: tr(c, '사진이 너무 커요', '写真のサイズが大きすぎます', 'This photo is too large') }, 413);
  }
  const body = await c.req.arrayBuffer();
  if (body.byteLength === 0 || body.byteLength > CHAT_MEDIA_MAX) {
    return c.json({ error: tr(c, '사진이 너무 커요', '写真のサイズが大きすぎます', 'This photo is too large') }, 413);
  }
  const id = crypto.randomUUID();
  await c.env.UPLOADS.put(`${CHAT_MEDIA_PREFIX}${id}`, body, {
    httpMetadata: { contentType: 'application/octet-stream' },
    customMetadata: { room: roomId, sender: me.id },
  });
  return c.json({ id });
});

async function mediaForMember(c: { env: Env }, id: string, userId: string) {
  if (!/^[0-9a-f-]{36}$/.test(id)) return null;
  const head = await c.env.UPLOADS.head(`${CHAT_MEDIA_PREFIX}${id}`);
  if (!head) return null;
  const room = head.customMetadata?.room || '';
  if (!isRoomMember(room, userId)) return null;
  // 24시간이 지난 것은 cron 이 지우기 전이라도 내주지 않는다.
  if (Date.now() - head.uploaded.getTime() > CHAT_MEDIA_TTL_MS) return null;
  return head;
}

app.get('/media/:id', async (c) => {
  const me = c.get('user')!;
  const id = c.req.param('id');
  const head = await mediaForMember(c, id, me.id);
  if (!head) return c.json({ error: tr(c, '사진을 찾을 수 없어요', '写真が見つかりません', 'Photo not found') }, 404);
  const obj = await c.env.UPLOADS.get(`${CHAT_MEDIA_PREFIX}${id}`);
  if (!obj) return c.json({ error: tr(c, '사진을 찾을 수 없어요', '写真が見つかりません', 'Photo not found') }, 404);
  return new Response(obj.body, {
    headers: { 'content-type': 'application/octet-stream', 'cache-control': 'no-store' },
  });
});

app.delete('/media/:id', async (c) => {
  const me = c.get('user')!;
  const id = c.req.param('id');
  const head = await mediaForMember(c, id, me.id);
  if (head) await c.env.UPLOADS.delete(`${CHAT_MEDIA_PREFIX}${id}`);
  return c.json({ ok: true });
});

/** cron: 24시간 넘은 채팅 사진 암호문 삭제. */
export async function purgeExpiredChatMedia(env: Env): Promise<number> {
  let cursor: string | undefined;
  let removed = 0;
  const cutoff = Date.now() - CHAT_MEDIA_TTL_MS;
  for (let page = 0; page < 10; page++) {
    const list = await env.UPLOADS.list({ prefix: CHAT_MEDIA_PREFIX, cursor, limit: 1000 });
    const old = list.objects.filter((o) => o.uploaded.getTime() < cutoff).map((o) => o.key);
    if (old.length) {
      await env.UPLOADS.delete(old);
      removed += old.length;
    }
    if (!list.truncated) break;
    cursor = list.cursor;
  }
  return removed;
}
