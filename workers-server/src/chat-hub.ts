/**
 * ChatHub - Durable Object managing WebSocket connections for
 *           1) ephemeral 1:1/group chat (no DB persistence)
 *           2) WebRTC voice call signaling (SDP offer/answer, ICE)
 *
 * Protocol (JSON text frames over WebSocket):
 *   Client → Server:
 *     { type: "join_room",   room_id, peer_nickname?, product_id? }
 *     { type: "leave_room",  room_id }
 *     { type: "message",     room_id, text, sender_nickname? }
 *     { type: "call_invite", to_user_id, call_id, caller_nickname? }
 *     { type: "call_response", to_user_id, call_id, accepted }
 *     { type: "webrtc_offer",  to_user_id, call_id, sdp }
 *     { type: "webrtc_answer", to_user_id, call_id, sdp }
 *     { type: "webrtc_ice",    to_user_id, call_id, candidate }
 *     { type: "call_end",      to_user_id, call_id }
 *     { type: "ping" }
 *
 *   Server → Client:
 *     { type: "connected",       user_id, nickname }
 *     { type: "system",          text }
 *     { type: "message",         id, room_id, sender_id, sender_nickname, text, type:"text", sent_at }
 *     { type: "call_incoming",   call_id, from_user_id, caller_nickname }
 *     { type: "call_response",   call_id, accepted, from_user_id }
 *     { type: "call_failed",     call_id, reason, message }
 *     { type: "webrtc_offer",    call_id, from_user_id, sdp }
 *     { type: "webrtc_answer",   call_id, from_user_id, sdp }
 *     { type: "webrtc_ice",      call_id, from_user_id, candidate }
 *     { type: "call_end",        call_id, from_user_id }
 *     { type: "pong" }
 *     { type: "error", message }
 */

import type { Env } from './types';

interface AttachedMeta {
  userId: string;
  nickname: string;
  rooms: string[];
}

type Binding = { JWT_SECRET: string } & Env;

export class ChatHub {
  private state: DurableObjectState;
  private env: Binding;

  // socketId (generated on attach) -> metadata
  // Durable Object hibernation: we also persist meta on ws via serializeAttachment
  // so after DO wakes up, we can recover without losing state.
  constructor(state: DurableObjectState, env: Binding) {
    this.state = state;
    this.env = env;
  }

  /** Entry point: handle upgrade + internal REST from worker. */
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // ---- Internal REST (called by the main worker, not by clients) ----
    if (url.pathname === '/internal/room-deleted' && request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as {
        room_id?: string;
        deleted_by?: string;
        peer_user_id?: string;
      };
      if (body.room_id && body.peer_user_id) {
        this.broadcastRoomDeleted(body.room_id, body.deleted_by || '', body.peer_user_id);
      }
      return new Response('ok');
    }

    if (url.pathname === '/internal/messages-cleared' && request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as {
        room_id?: string;
        cleared_by?: string;
        peer_user_id?: string;
      };
      if (body.room_id && body.peer_user_id) {
        this.broadcastMessagesCleared(body.room_id, body.cleared_by || '', body.peer_user_id);
      }
      return new Response('ok');
    }

    if (url.pathname === '/internal/read-receipt' && request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as {
        room_id?: string;
        reader_id?: string;
        peer_user_id?: string;
        read_at?: string;
      };
      if (body.room_id && body.peer_user_id && body.read_at) {
        // Tell the peer that their messages in this room got read.
        // Their UI flips "전송됨" → "읽음" and clears the unread badge for
        // that conversation locally.
        this.sendToUser(body.peer_user_id, {
          type: 'read_receipt',
          room_id: body.room_id,
          reader_id: body.reader_id || '',
          read_at: body.read_at,
        });
      }
      return new Response('ok');
    }

    // Generic broadcast to everyone joined to a room AND a direct push to a
    // peer who may not be in the room view. Used by REST routes that mutate
    // chat state (e.g. price offers) so both clients can update in realtime.
    if (url.pathname === '/internal/broadcast-room' && request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as {
        room_id?: string;
        peer_user_id?: string;
        payload?: Record<string, unknown>;
      };
      if (body.room_id && body.payload) {
        this.broadcastToRoom(body.room_id, null, body.payload);
        // Make sure the peer who's NOT currently in the room view also gets
        // the event (so chat-list previews / unread badges update).
        if (body.peer_user_id) {
          this.sendToUser(body.peer_user_id, body.payload);
        }
      }
      return new Response('ok');
    }

    if (request.headers.get('Upgrade') !== 'websocket') {
      return new Response('Expected WebSocket upgrade', { status: 426 });
    }

    // Extract token from ?token=... (browsers cannot set WS headers on upgrade)
    const token = url.searchParams.get('token') || '';
    if (!token) {
      return new Response('Missing token', { status: 401 });
    }

    // Validate JWT
    const payload = await verifyJwt(token, this.env.JWT_SECRET);
    if (!payload) {
      return new Response('Invalid token', { status: 401 });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    // Attach metadata so we can recover after hibernation.
    const meta: AttachedMeta = {
      userId: payload.id,
      nickname: payload.nickname,
      rooms: [],
    };
    server.serializeAttachment(meta);

    // Hibernatable WebSocket: we don't keep JS refs; runtime wakes us on events.
    this.state.acceptWebSocket(server);

    // Greet on connect
    server.send(
      JSON.stringify({
        type: 'connected',
        user_id: meta.userId,
        nickname: meta.nickname,
      })
    );

    return new Response(null, { status: 101, webSocket: client });
  }

  // ---------------- WebSocket event handlers (hibernation-friendly) ----------------

  async webSocketMessage(ws: WebSocket, raw: string | ArrayBuffer): Promise<void> {
    const meta = ws.deserializeAttachment() as AttachedMeta | null;
    if (!meta) {
      ws.close(1011, 'No session');
      return;
    }

    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(typeof raw === 'string' ? raw : new TextDecoder().decode(raw));
    } catch {
      this.sendSafe(ws, { type: 'error', message: 'Invalid JSON' });
      return;
    }

    const t = String(msg.type || '');

    switch (t) {
      case 'ping':
        this.sendSafe(ws, { type: 'pong' });
        return;

      // 클라이언트가 방을 읽었음을 알림 — peer 에게 그대로 forward.
      // 휘발성: 서버는 read 상태를 저장하지 않는다.
      case 'read_receipt': {
        const room_id = String(msg.room_id || '');
        const read_at = String(msg.read_at || new Date().toISOString());
        if (!room_id) return;
        const tokens = room_id.split('_');
        if (!tokens.includes(meta.userId)) return;
        const peerId = tokens.find((t) => t.length >= 30 && t !== meta.userId);
        if (peerId) {
          this.sendToUser(peerId, {
            type: 'read_receipt',
            room_id,
            reader_id: meta.userId,
            read_at,
          });
        }
        return;
      }

      case 'join_room': {
        const room_id = String(msg.room_id || '');
        if (!room_id) return;

        if (!meta.rooms.includes(room_id)) {
          meta.rooms.push(room_id);
          ws.serializeAttachment(meta);
        }

        // Notify others in the same room
        this.broadcastToRoom(room_id, ws, {
          type: 'system',
          text: `${meta.nickname} 님이 대화에 참여했어요`,
        });
        // 휘발성 정책: chat_count / 채팅방 통계 등 어떠한 DB 업데이트도 하지 않는다.
        return;
      }

      case 'leave_room': {
        const room_id = String(msg.room_id || '');
        if (!room_id) return;
        meta.rooms = meta.rooms.filter((r) => r !== room_id);
        ws.serializeAttachment(meta);
        this.broadcastToRoom(room_id, ws, {
          type: 'system',
          text: `${meta.nickname} 님이 대화를 떠났어요`,
        });
        return;
      }

      case 'message': {
        const room_id = String(msg.room_id || '');
        const text = String(msg.text || '').slice(0, 2000);
        if (!room_id || !text.trim()) return;

        // 휘발성: 멤버십 검증을 DB 로 하지 않는다 (chat_rooms 자체가 없음).
        // 대신 roomId 형식이 'a_b' / 'a_b_productId' 이므로 sender 의 ID 가
        // roomId 토큰 안에 있어야 한다. 이게 spoof 방지의 1차 게이트.
        const tokens = room_id.split('_');
        if (!tokens.includes(meta.userId)) {
          this.sendSafe(ws, { type: 'error', message: '이 채팅방에 참여할 수 없어요' });
          return;
        }
        // 자동으로 join 처리 (peer 가 먼저 메시지를 보낸 경우에도 broadcast 받도록)
        if (!meta.rooms.includes(room_id)) {
          meta.rooms.push(room_id);
          ws.serializeAttachment(meta);
        }

        const msgId = crypto.randomUUID();
        const sentAt = new Date().toISOString();

        const payload = {
          type: 'message',
          id: msgId,
          room_id,
          sender_id: meta.userId,
          sender_nickname:
            (msg.sender_nickname as string | undefined) || meta.nickname || '익명',
          text,
          msg_type: 'text',
          sent_at: sentAt,
        };
        // 같은 방의 모든 소켓 (자신 포함) 에게 broadcast.
        this.broadcastToRoom(room_id, null, payload);

        // peer 가 방 화면에 없을 수도 있으니 chat-list 뱃지/미리보기용 푸시도 발송.
        const peerId = tokens.find((t) => t.length >= 30 && t !== meta.userId);
        if (peerId) {
          this.sendToUser(peerId, {
            type: 'room_updated',
            room_id,
            last_message: text,
            last_sender_id: meta.userId,
            last_sender_nickname: meta.nickname || '익명',
            last_message_at: sentAt,
          });
        }
        return;
      }

      // ---------- 가격 제안 (휘발성) ----------
      // 클라이언트가 보내는 형식:
      //   { type: 'price_offer', room_id, price, currency? }
      //   { type: 'offer_response', room_id, offer_id, action: 'accept'|'reject'|'cancel' }
      // 서버는 어떠한 DB 도 건드리지 않고 그대로 broadcast 만 한다.
      case 'price_offer': {
        const room_id = String(msg.room_id || '');
        const price = Number(msg.price);
        if (!room_id || !Number.isFinite(price) || price < 0 || price > 1_000_000_000) return;
        const tokens = room_id.split('_');
        if (!tokens.includes(meta.userId)) {
          this.sendSafe(ws, { type: 'error', message: '이 채팅방에 참여할 수 없어요' });
          return;
        }
        if (!meta.rooms.includes(room_id)) {
          meta.rooms.push(room_id);
          ws.serializeAttachment(meta);
        }
        const offerId = crypto.randomUUID();
        const sentAt = new Date().toISOString();
        const payload = {
          type: 'message',
          id: offerId,
          room_id,
          sender_id: meta.userId,
          sender_nickname: meta.nickname || '익명',
          text: `${price.toLocaleString('ko-KR')}원에 어떠세요?`,
          msg_type: 'price_offer',
          sent_at: sentAt,
          offer: {
            id: offerId,
            price,
            status: 'pending',
            buyer_id: meta.userId,
          },
        };
        this.broadcastToRoom(room_id, null, payload);
        const peerId = tokens.find((t) => t.length >= 30 && t !== meta.userId);
        if (peerId) {
          this.sendToUser(peerId, {
            type: 'room_updated',
            room_id,
            last_message: payload.text,
            last_sender_id: meta.userId,
            last_sender_nickname: meta.nickname || '익명',
            last_message_at: sentAt,
          });
        }
        return;
      }

      case 'offer_response': {
        const room_id = String(msg.room_id || '');
        const offer_id = String(msg.offer_id || '');
        const action = String(msg.action || '');
        if (!room_id || !offer_id) return;
        if (!['accept', 'reject', 'cancel'].includes(action)) return;
        const tokens = room_id.split('_');
        if (!tokens.includes(meta.userId)) return;
        const status =
          action === 'accept' ? 'accepted' : action === 'reject' ? 'rejected' : 'cancelled';
        const updatedAt = new Date().toISOString();
        this.broadcastToRoom(room_id, null, {
          type: 'offer_updated',
          room_id,
          offer_id,
          status,
          responder_id: meta.userId,
          updated_at: updatedAt,
        });
        return;
      }

      // ---------- WebRTC signaling ----------
      case 'call_invite': {
        const to_user_id = String(msg.to_user_id || '');
        const call_id = String(msg.call_id || '');
        const caller_nickname = (msg.caller_nickname as string) || meta.nickname;
        if (!to_user_id || !call_id) return;
        const delivered = this.sendToUser(to_user_id, {
          type: 'call_incoming',
          call_id,
          from_user_id: meta.userId,
          caller_nickname,
        });
        if (!delivered) {
          this.sendSafe(ws, {
            type: 'call_failed',
            call_id,
            reason: 'offline',
            message: '상대방이 접속 중이 아니에요',
          });
        }
        return;
      }

      case 'call_response': {
        this.relayTo(msg, meta, 'call_response', ['accepted']);
        return;
      }
      case 'webrtc_offer': {
        this.relayTo(msg, meta, 'webrtc_offer', ['sdp']);
        return;
      }
      case 'webrtc_answer': {
        this.relayTo(msg, meta, 'webrtc_answer', ['sdp']);
        return;
      }
      case 'webrtc_ice': {
        this.relayTo(msg, meta, 'webrtc_ice', ['candidate']);
        return;
      }
      case 'call_end': {
        this.relayTo(msg, meta, 'call_end', []);
        return;
      }

      default:
        this.sendSafe(ws, { type: 'error', message: `Unknown type: ${t}` });
    }
  }

  async webSocketClose(ws: WebSocket, _code: number, _reason: string, _wasClean: boolean): Promise<void> {
    await this.cleanup(ws);
  }

  async webSocketError(ws: WebSocket, _err: unknown): Promise<void> {
    await this.cleanup(ws);
  }

  // ------------------ helpers ------------------

  private async cleanup(ws: WebSocket): Promise<void> {
    const meta = ws.deserializeAttachment() as AttachedMeta | null;
    if (!meta) return;
    for (const room_id of meta.rooms) {
      this.broadcastToRoom(room_id, ws, {
        type: 'system',
        text: `${meta.nickname} 님이 연결을 종료했어요`,
      });
    }
  }

  private sendSafe(ws: WebSocket, payload: unknown): void {
    try {
      ws.send(JSON.stringify(payload));
    } catch {
      /* ignore */
    }
  }

  /** Broadcast to every socket whose attachment includes the room_id (except optionally excluded). */
  private broadcastToRoom(room_id: string, except: WebSocket | null, payload: unknown): void {
    const data = JSON.stringify(payload);
    for (const ws of this.state.getWebSockets()) {
      if (except && ws === except) continue;
      const meta = ws.deserializeAttachment() as AttachedMeta | null;
      if (meta && meta.rooms.includes(room_id)) {
        try { ws.send(data); } catch { /* ignore */ }
      }
    }
  }

  /** Send directly to a user (first socket we find for them). Returns true if delivered. */
  private sendToUser(user_id: string, payload: unknown): boolean {
    const data = JSON.stringify(payload);
    let delivered = false;
    for (const ws of this.state.getWebSockets()) {
      const meta = ws.deserializeAttachment() as AttachedMeta | null;
      if (meta && meta.userId === user_id) {
        try {
          ws.send(data);
          delivered = true;
        } catch { /* ignore */ }
      }
    }
    return delivered;
  }

  /** Tell all sockets (caller + peer) that a room has been permanently deleted. */
  private broadcastRoomDeleted(roomId: string, deletedBy: string, peerUserId: string): void {
    const payload = JSON.stringify({
      type: 'room_deleted',
      room_id: roomId,
      deleted_by: deletedBy,
    });
    for (const ws of this.state.getWebSockets()) {
      const meta = ws.deserializeAttachment() as AttachedMeta | null;
      if (!meta) continue;
      // Notify both parties (the peer for sure, and the deleter's other devices).
      if (meta.userId === peerUserId || meta.userId === deletedBy) {
        try { ws.send(payload); } catch { /* ignore */ }
        // Also drop the room from their attachment so future broadcasts skip them.
        meta.rooms = meta.rooms.filter((r) => r !== roomId);
        try { ws.serializeAttachment(meta); } catch { /* ignore */ }
      }
    }
  }

  /** Tell the peer that messages were cleared but the room stays. */
  private broadcastMessagesCleared(roomId: string, clearedBy: string, peerUserId: string): void {
    const payload = JSON.stringify({
      type: 'messages_cleared',
      room_id: roomId,
      cleared_by: clearedBy,
    });
    for (const ws of this.state.getWebSockets()) {
      const meta = ws.deserializeAttachment() as AttachedMeta | null;
      if (!meta) continue;
      if (meta.userId === peerUserId || meta.userId === clearedBy) {
        try { ws.send(payload); } catch { /* ignore */ }
      }
    }
  }

  /** Generic relay of signaling messages to target user. */
  private relayTo(
    msg: Record<string, unknown>,
    meta: AttachedMeta,
    outType: string,
    forwardKeys: string[]
  ): void {
    const to_user_id = String(msg.to_user_id || '');
    const call_id = String(msg.call_id || '');
    if (!to_user_id || !call_id) return;
    const payload: Record<string, unknown> = {
      type: outType,
      call_id,
      from_user_id: meta.userId,
    };
    for (const k of forwardKeys) payload[k] = msg[k];
    this.sendToUser(to_user_id, payload);
  }
}

// --- Minimal inline JWT verification (no external import to keep DO slim) ---
// The main worker already uses @tsndr/cloudflare-worker-jwt, but that package
// doesn't work inside DO stub fetch handshake path, so we replicate HS256 here.
async function verifyJwt(token: string, secret: string): Promise<{ id: string; nickname: string } | null> {
  try {
    const [h, p, s] = token.split('.');
    if (!h || !p || !s) return null;
    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify']
    );
    const sig = base64UrlDecode(s);
    const data = new TextEncoder().encode(`${h}.${p}`);
    const ok = await crypto.subtle.verify('HMAC', key, sig, data);
    if (!ok) return null;

    const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(p)));
    if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) return null;
    if (!payload.id || !payload.nickname) return null;
    return payload;
  } catch {
    return null;
  }
}

function base64UrlDecode(s: string): Uint8Array {
  const pad = s.length % 4 === 2 ? '==' : s.length % 4 === 3 ? '=' : '';
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + pad;
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
