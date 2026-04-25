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
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const peerUserId = (body.peer_user_id || '').trim();
  if (!peerUserId) {
    return c.json({ error: 'peer_user_id 가 필요해요' }, 400);
  }
  if (peerUserId === me.id) {
    return c.json({ error: '자기 자신과는 채팅할 수 없어요' }, 400);
  }

  // 상대방 닉네임/매너온도만 조회 — wallet, device_uuid 같은 식별자는 절대 노출하지 않음.
  const peer = await c.env.DB
    .prepare('SELECT id, nickname, manner_score FROM users WHERE id = ?')
    .bind(peerUserId)
    .first<{ id: string; nickname: string; manner_score: number }>();
  if (!peer) {
    return c.json({ error: '상대방을 찾을 수 없어요' }, 404);
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
