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

  /** Entry point: handle upgrade + REST from worker. */
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

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

      case 'join_room': {
        const room_id = String(msg.room_id || '');
        const product_id = msg.product_id ? String(msg.product_id) : undefined;
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

        // Bump chat_count (fire-and-forget)
        if (product_id) {
          this.env.DB
            .prepare('UPDATE products SET chat_count = chat_count + 1 WHERE id = ?')
            .bind(product_id)
            .run()
            .catch(() => {});
        }
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
        const payload = {
          type: 'message',
          id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
          room_id,
          sender_id: meta.userId,
          sender_nickname:
            (msg.sender_nickname as string | undefined) || meta.nickname || '익명',
          text,
          msg_type: 'text',
          sent_at: new Date().toISOString(),
        };
        // Send to ALL in room including sender (so UI shows own message consistently)
        this.broadcastToRoom(room_id, null, payload);
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
