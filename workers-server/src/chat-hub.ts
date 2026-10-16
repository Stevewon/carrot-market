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
import { sendFcm } from './utils/fcm';
import { callIdentity, walletToAgoraUid } from './utils/agoraToken';
import { checkSession } from './jwt';
import { maskChatText } from './prohibited';
import { marketLang, normalizeMarket, trl, type Lang } from './market';

interface AttachedMeta {
  userId: string;
  nickname: string;
  rooms: string[];
  /**
   * ★ v1.0.158 (2026-05-11): 클라이언트 앱 lifecycle 상태.
   *   'foreground': 사용자가 앱 화면을 보고 있음 → Flutter UI 가 통화 수신 가능
   *   'background': 백그라운드/잠금/종료 → native heads-up/FSI 필요
   *
   *   default 'background' — 구버전 클라이언트(v1.0.157 이하) 가 presence_update
   *   를 보내지 않아도 안전한 쪽(FCM push 발송) 으로 fallback.
   *
   *   call_invite 핸들러가 이 값을 보고 FCM heads-up push 발송 여부 결정 →
   *   foreground 단말은 WebSocket call_incoming 만 받아 Flutter IncomingCallScreen
   *   표시, background 단말은 FCM heads-up 받아 native UI 표시.
   *   → 이중 표시 (Flutter 풀스크린 + native 헤드업 동시 노출) 원천 차단.
   */
  appState?: 'foreground' | 'background';
  /** 서버 안내 메시지 언어 (users.market 기준, 없으면 'ko'). */
  lang?: Lang;
}

type Binding = { JWT_SECRET: string } & Env;

/** DO 저장소의 통화 기록 — 응답·종료 신호를 보낸 사람이 그 통화의 당사자인지 확인. */
interface CallRecord {
  caller: string;
  callee: string;
  at: number;
}

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

    // 계정 정지 시 열려 있는 소켓을 즉시 끊는다 (checkSession 은 접속 때만 검사하므로
    // 이미 연결된 소켓은 정지 후에도 채팅·통화를 계속할 수 있었다).
    if (url.pathname === '/internal/kick-user' && request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as { user_id?: string };
      if (body.user_id) {
        for (const ws of this.state.getWebSockets()) {
          const meta = ws.deserializeAttachment() as AttachedMeta | null;
          if (meta && meta.userId === body.user_id) {
            try { ws.close(4003, 'banned'); } catch { /* ignore */ }
          }
        }
      }
      return new Response('ok');
    }

    // 네이티브 통화 화면(앱 백그라운드·종료·잠금 상태에서 받은 통화)의
    // 수락/거절/종료 신호. routes/calls.ts 가 JWT 로 보낸 사람을 확인한 뒤 호출.
    // body: { from_user_id, type: 'response'|'end', call_id, to_user_id, accepted? }
    if (url.pathname === '/internal/call-signal' && request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
      const from = String(body.from_user_id || '');
      if (from) {
        if (body.type === 'response') await this.handleCallResponse(from, null, body);
        else if (body.type === 'end') await this.handleCallEnd(from, null, body);
      }
      return new Response('ok');
    }

    // 키워드 알림 fanout: products.ts 가 새 상품 등록 직후 호출.
    // body: { user_ids: string[], payload: object }
    // 알림 이력은 DB 에 남기지 않는다 — 사생활 보호.
    if (url.pathname === '/internal/fanout-users' && request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as {
        user_ids?: string[];
        payload?: Record<string, unknown>;
      };
      const users = Array.isArray(body.user_ids) ? body.user_ids : [];
      if (users.length && body.payload) {
        for (const uid of users) {
          if (typeof uid === 'string' && uid) {
            this.sendToUser(uid, body.payload);
          }
        }
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
    // REST 와 같은 DB 기준 검사 — 로그아웃/비밀번호 재설정/다른 기기 로그인으로
    // 무효화된 토큰, 정지된 계정은 채팅·통화 소켓도 열 수 없다.
    const failure = await checkSession(this.env.DB, payload);
    if (failure) {
      return new Response(failure === 'banned' ? 'Banned' : 'Session expired', {
        status: failure === 'banned' ? 403 : 401,
      });
    }

    // 안내 메시지 언어 — ?market= / X-Market / Accept-Language, 없으면 회원 시장(users.market).
    let lang: Lang = 'ko';
    const hinted = normalizeMarket((url.searchParams.get('market') || request.headers.get('x-market') || '').trim().toLowerCase());
    if (hinted) {
      lang = marketLang(hinted);
    } else if ((request.headers.get('accept-language') || '').trim().toLowerCase().startsWith('ja')) {
      lang = 'ja';
    } else if ((request.headers.get('accept-language') || '').trim().toLowerCase().startsWith('en')) {
      lang = 'en';
    } else {
      try {
        const row = await this.env.DB.prepare('SELECT market FROM users WHERE id = ?').bind(payload.id).first<{ market: string | null }>();
        lang = marketLang(normalizeMarket(row?.market ?? '') ?? 'kr');
      } catch { /* market 컬럼 미적용 — 한국어 */ }
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    // Attach metadata so we can recover after hibernation.
    // ★ v1.0.158: appState default = 'background' — 클라이언트가 presence_update
    //   를 명시적으로 보내기 전까지는 안전한 쪽(FCM push 발송) 으로 fallback.
    //   v1.0.158+ 클라이언트는 connect 직후 즉시 'foreground' 송신.
    const meta: AttachedMeta = {
      userId: payload.id,
      nickname: payload.nickname,
      rooms: [],
      appState: 'background',
      lang,
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

      // ★ v1.0.158 (2026-05-11): 클라이언트 lifecycle 상태 업데이트.
      //   Flutter didChangeAppLifecycleState 가 resumed → 'foreground',
      //   paused/inactive/hidden/detached → 'background' 송신.
      //   call_invite 핸들러가 이 값 보고 FCM heads-up push 발송 여부 결정.
      //   foreground 단말은 WebSocket call_incoming + Flutter UI 로 처리 →
      //   FCM push 생략 → 이중 표시 0건.
      //   background 단말은 FCM heads-up 발송 → native UI 표시.
      case 'presence_update': {
        const rawState = String(msg.state || '').toLowerCase();
        if (rawState === 'foreground' || rawState === 'background') {
          if (meta.appState !== rawState) {
            meta.appState = rawState;
            ws.serializeAttachment(meta);
          }
        }
        return;
      }

      // 클라이언트가 방을 읽었음을 알림 — peer 에게 그대로 forward.
      // 휘발성: 서버는 read 상태를 저장하지 않는다.
      case 'read_receipt': {
        const room_id = String(msg.room_id || '');
        const read_at = String(msg.read_at || new Date().toISOString());
        if (!room_id) return;
        const tokens = room_id.split('_');
        if (!isRoomMember(room_id, meta.userId)) return;
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
        // 방 참여자(roomId 앞 두 토큰)만 입장 가능. 예전엔 검사가 없어
        // 아무 roomId 로 join 해서 남의 대화를 broadcast 로 받을 수 있었다.
        if (!isRoomMember(room_id, meta.userId)) {
          this.sendSafe(ws, { type: 'error', message: trl(meta.lang ?? 'ko', '이 채팅방에 참여할 수 없어요', 'このチャットルームには参加できません', "You can't join this chat room") });
          return;
        }

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
        // 욕설·혐오 표현만 *** 마스킹 (저장 없음 — 릴레이 직전 변환).
        const text = maskChatText(String(msg.text || '').slice(0, 2000));
        if (!room_id || !text.trim()) return;

        // 휘발성: 멤버십 검증을 DB 로 하지 않는다 (chat_rooms 자체가 없음).
        // 대신 roomId 형식이 'a_b' / 'a_b_productId' 이므로 sender 의 ID 가
        // roomId 토큰 안에 있어야 한다. 이게 spoof 방지의 1차 게이트.
        const tokens = room_id.split('_');
        if (!isRoomMember(room_id, meta.userId)) {
          this.sendSafe(ws, { type: 'error', message: trl(meta.lang ?? 'ko', '이 채팅방에 참여할 수 없어요', 'このチャットルームには参加できません', "You can't join this chat room") });
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
          // 클라이언트가 보낸 닉네임은 신뢰하지 않는다 (사칭 방지).
          sender_nickname: meta.nickname || '익명',
          text,
          msg_type: 'text',
          sent_at: sentAt,
        };
        // 같은 방의 모든 소켓 (자신 포함) 에게 broadcast.
        this.broadcastToRoom(room_id, null, payload);

        // peer 가 방 화면에 없을 수도 있으니 chat-list 뱃지/미리보기용 푸시도 발송.
        const peerId = tokens.find((t) => t.length >= 30 && t !== meta.userId);
        if (peerId) {
          // 처음 말을 건 경우 상대는 아직 이 방에 join 하지 않았다 → 위 broadcast 를 못 받는다.
          // 서버엔 기록이 없으므로 본문을 직접 보내야 상대 앱이 방을 만들고 메시지를 담는다.
          this.sendToUserOutsideRoom(peerId, room_id, payload);
          const delivered = this.sendToUser(peerId, {
            type: 'room_updated',
            room_id,
            last_message: text,
            last_sender_id: meta.userId,
            last_sender_nickname: meta.nickname || '익명',
            last_message_at: sentAt,
          });
          // ★★★ 3차 푸시: WebSocket 으로 전달 못 함 (앱 종료/백그라운드/네트워크 끊김)
          //  → FCM 으로 시스템 푸시 발송. peer 가 폰을 켜고 있으면 트레이에 표시.
          //  익명성: 메시지 본문/닉네임은 push body 에 절대 포함 안 함.
          //  Firebase 키 미등록(placeholder) 환경에서는 sendFcm 이 silent skip.
          if (!delivered) {
            // ignore: discarded_futures - DO 응답 지연 방지 (fire-and-forget)
            // ★ v1.0.110 (이슈 3): FCM data 필드에 text/sender 정보 포함.
            //  data 영역은 OS 알림 트레이에 노출되지 않는 메타데이터(클라이언트만
            //  읽음) → 익명성 정책 위반 X. 클라이언트 applyIncomingPushMessage
            //  가 이 text 를 합성 ChatMessage 로 채팅방에 추가 → 푸시 받은
            //  사용자가 채팅방 진입 시 첫 메시지 정상 표시.
            //  (title/body 는 그대로 generic 유지 — 익명성 보존)
            this.sendOfflinePush(peerId, {
              title: (l) => trl(l, '새 메시지', '新着メッセージ', 'New message'),
              body: (l) => trl(l, '새 메시지가 도착했어요', '新しいメッセージが届きました', 'You have a new message'),
              data: {
                type: 'message',
                room_id,
                text,
                sender_id: meta.userId,
                sender_nickname: meta.nickname || '익명',
                sent_at: sentAt,
              },
              isCall: false,
            });
          }
        }
        return;
      }

      // ---------- 사진 · 약속 (휘발성) ----------
      // 사진: { type:'image', room_id, media_id, key, w?, h? }
      //   media_id = /api/chat/media 에 올린 암호문, key = 그 암호문을 여는 열쇠(base64).
      //   서버는 열쇠를 저장하지 않고 상대에게 전달만 한다.
      // 약속: { type:'appointment', room_id, at(ISO8601), place? }
      case 'image':
      case 'appointment': {
        const room_id = String(msg.room_id || '');
        if (!room_id) return;
        if (!isRoomMember(room_id, meta.userId)) {
          this.sendSafe(ws, { type: 'error', message: trl(meta.lang ?? 'ko', '이 채팅방에 참여할 수 없어요', 'このチャットルームには参加できません', "You can't join this chat room") });
          return;
        }
        const lang = meta.lang ?? 'ko';
        let extra: Record<string, unknown>;
        let text: string;
        let pushData: Record<string, string>;
        if (t === 'image') {
          const media_id = String(msg.media_id || '');
          const key = String(msg.key || '');
          if (!/^[0-9a-f-]{36}$/.test(media_id) || !/^[A-Za-z0-9+/=]{40,64}$/.test(key)) return;
          const w = Math.max(0, Math.min(10000, Number(msg.w) || 0));
          const h = Math.max(0, Math.min(10000, Number(msg.h) || 0));
          extra = { image: { media_id, key, w, h } };
          text = trl(lang, '📷 사진', '📷 写真', '📷 Photo');
          pushData = { image: JSON.stringify({ media_id, key, w, h }) };
        } else {
          const at = new Date(String(msg.at || ''));
          if (Number.isNaN(at.getTime())) return;
          // 지난 시각이나 1년 뒤보다 먼 약속은 받지 않는다.
          if (at.getTime() < Date.now() - 60_000 || at.getTime() > Date.now() + 366 * 86_400_000) return;
          const place = maskChatText(String(msg.place || '').slice(0, 60)).trim();
          const atIso = at.toISOString();
          const action = msg.action === 'cancel' ? 'cancel' : 'set';
          extra = { appointment: { at: atIso, place, action } };
          text = action === 'cancel'
            ? trl(lang, '📅 약속을 취소했어요', '📅 約束をキャンセルしました', '📅 Meetup cancelled')
            : trl(lang, '📅 거래 약속을 잡았어요', '📅 取引の約束を決めました', '📅 Meetup scheduled');
          pushData = { appointment: JSON.stringify({ at: atIso, place, action }) };
        }
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
          sender_nickname: meta.nickname || '익명',
          text,
          msg_type: t,
          sent_at: sentAt,
          ...extra,
        };
        this.broadcastToRoom(room_id, null, payload);
        const peerId = room_id.split('_').find((x) => x.length >= 30 && x !== meta.userId);
        if (peerId) {
          this.sendToUserOutsideRoom(peerId, room_id, payload);
          const delivered = this.sendToUser(peerId, {
            type: 'room_updated',
            room_id,
            last_message: text,
            last_sender_id: meta.userId,
            last_sender_nickname: meta.nickname || '익명',
            last_message_at: sentAt,
          });
          if (!delivered) {
            this.sendOfflinePush(peerId, {
              title: (l) => trl(l, '새 메시지', '新着メッセージ', 'New message'),
              body: (l) => trl(l, '새 메시지가 도착했어요', '新しいメッセージが届きました', 'You have a new message'),
              data: {
                type: 'message',
                room_id,
                text,
                msg_type: t,
                sender_id: meta.userId,
                sender_nickname: meta.nickname || '익명',
                sent_at: sentAt,
                ...pushData,
              },
              isCall: false,
            });
          }
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
        if (!isRoomMember(room_id, meta.userId)) {
          this.sendSafe(ws, { type: 'error', message: trl(meta.lang ?? 'ko', '이 채팅방에 참여할 수 없어요', 'このチャットルームには参加できません', "You can't join this chat room") });
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
          // 가격 제안 문구 — 보낸 사람 시장 기준 (같은 시장끼리만 거래)
          text: trl(
            meta.lang ?? 'ko',
            `${price.toLocaleString('ko-KR')}원에 어떠세요?`,
            `${price.toLocaleString('ja-JP')}円でいかがですか？`,
            `How about ₱${price.toLocaleString('en-US')}?`,
          ),
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
        if (!isRoomMember(room_id, meta.userId)) return;
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
        // ★ P1-#7 (v1.0.127): 닉네임 spoof 방지 — 클라이언트가 보낸 값을 그대로
        //   쓰지 않고, JWT 의 meta.nickname 을 우선 사용. 발신자가 임의로 다른
        //   사람 닉네임으로 가장하는 것을 서버에서 차단.
        const caller_nickname = meta.nickname || (msg.caller_nickname as string) || '익명';
        // ★ v1.0.136: caller_wallet 도 push data 에 포함시켜야 background isolate 의
        //   CallKit 가 wallet 까지 들고 main isolate 로 전달 → CallScreen 이 채널명
        //   산정 가능. 클라이언트가 보내준 값 신뢰 (서버는 wallet 검증 안 함 — Agora
        //   채널명 산정용 단순 페어 키이고, 토큰은 별도 인증으로 발급되므로 위·변조해도
        //   실효성 0).
        //   → 보안 핫픽스: 클라이언트 값 대신 DB 의 발신자 지갑을 쓴다. 채널명이
        //     토큰 발급 시 참여자 검증 기준이 되므로 위조된 지갑으로 남의 채널을
        //     만들 수 없게 한다. 조회 실패 시에만 클라이언트 값으로 fallback.
        let caller_wallet = String(msg.caller_wallet || '').trim().toLowerCase();
        try {
          const me = await this.env.DB.prepare('SELECT wallet_address FROM users WHERE id = ?')
            .bind(meta.userId)
            .first<{ wallet_address: string | null }>();
          // 지갑 없는 회원은 'u_<id>' (callIdentity)
          if (me) caller_wallet = callIdentity(me.wallet_address, meta.userId);
        } catch (e) {
          console.log('[call_invite] caller wallet lookup failed:', e);
        }
        // ★ v1.0.142: callType 도 페이로드에 포함시켜야 native FCM 서비스가
        //   audio/video 분기 가능. 기본 'audio'.
        const call_type_raw = String(msg.callType || msg.call_type || 'audio');
        const call_type = call_type_raw === 'video' ? 'video' : 'audio';
        if (!to_user_id || !call_id) return;

        // ★ P1-#7 (v1.0.127): block 검증 — 수신자가 발신자를 차단했으면 invite
        //   자체를 차단. 차단된 사용자도 전화 받을 수 있던 보안 구멍 수정.
        //   양방향 모두 체크: 발신자가 수신자를 차단했어도 invite 차단 (UX 일관성).
        try {
          const blockRow = await this.env.DB.prepare(
            `SELECT 1 FROM user_blocks
             WHERE (blocker_id = ? AND blocked_id = ?)
                OR (blocker_id = ? AND blocked_id = ?)
             LIMIT 1`,
          )
            .bind(to_user_id, meta.userId, meta.userId, to_user_id)
            .first();
          if (blockRow) {
            // 차단 관계 — 발신자에게 일반 거절 신호.
            this.sendSafe(ws, {
              type: 'call_failed',
              call_id,
              reason: 'blocked',
              message: trl(meta.lang ?? 'ko', '연결할 수 없는 상대에요', 'この相手とは通話できません', "You can't call this user"),
            });
            return;
          }
        } catch (e) {
          // DB 일시 오류 — 차단 검증 실패해도 통화는 허용 (가용성 우선).
          console.log('[call_invite] block check failed:', e);
        }

        // ★ v1.0.142 (Eggplant native call port): peer 의 wallet_address 조회.
        //   Agora 채널명은 caller_wallet + peer_wallet 의 sorted lowercase pair 로
        //   산정한다 → `eggplant_call_<min>_<max>`. 양쪽 단말이 동일 채널명을
        //   합의해야 join 후 서로 들리므로 서버에서 결정해서 push/WS 에 같이 실어
        //   보내는 게 가장 안전 (클라이언트가 wallet 모를 가능성 차단).
        //   조회 실패 시 channel 은 빈 문자열 — 클라이언트가 fallback (call_id 기반)
        //   으로 처리하지만 native 측에선 cross-side mismatch 위험 있음.
        let peer_wallet = '';
        let channel_name = '';
        try {
          const peerRow = await this.env.DB.prepare(
            'SELECT wallet_address FROM users WHERE id = ?',
          )
            .bind(to_user_id)
            .first<{ wallet_address: string | null }>();
          peer_wallet = peerRow ? callIdentity(peerRow.wallet_address, to_user_id) : '';
          if (caller_wallet && peer_wallet) {
            // ★ v1.0.143 (2026-05-09): raw wallet 두 개 join 시 99자 → 서버
            //   `/api/users/agora/token` 의 64자 한도 초과 (HTTP 400 'channel too long').
            //   해결: 양쪽 wallet 을 walletToAgoraUid (Dart AgoraUid.fromWalletAddress
            //   / Kotlin AgoraConfig.walletToUid 와 동일 SHA-256 앞 4바이트 u32) 로
            //   변환 후 수치 오름차순 join → 최대 35자.
            const uidCaller = await walletToAgoraUid(caller_wallet);
            const uidPeer = await walletToAgoraUid(peer_wallet);
            const lo = Math.min(uidCaller, uidPeer);
            const hi = Math.max(uidCaller, uidPeer);
            channel_name = `eggplant_call_${lo}_${hi}`;
          }
        } catch (e) {
          console.log('[call_invite] peer wallet lookup failed:', e);
        }

        // 통화 기록 (응답·종료 신호의 당사자 확인용). 다른 사람의 통화 id 를 덮어쓰지 않는다.
        {
          const key = `call:${call_id}`;
          const prev = await this.state.storage.get<CallRecord>(key);
          if (prev && prev.caller !== meta.userId) return;
          await this.state.storage.put(key, { caller: meta.userId, callee: to_user_id, at: Date.now() });
          if (Math.random() < 0.02) await this.pruneCallRecords();
        }

        const delivered = this.sendToUser(to_user_id, {
          type: 'call_incoming',
          call_id,
          from_user_id: meta.userId,
          caller_nickname,
          caller_wallet,
          // ★ v1.0.142: foreground 수신 클라이언트도 동일 채널명을 사용해야
          //   양쪽이 같은 Agora 채널에 join 됨.
          channel: channel_name,
          call_type,
        });

        // ★ v1.0.158 (2026-05-11) presence-aware hybrid push.
        //
        // 배경 (v1.0.157 사장님 2폰 검증 결과):
        //   - 두 폰 모두 foreground 일 때 헤드업(native) + 풀스크린(Flutter)
        //     이중 표시 발생 + 한쪽 수락 후 다른 쪽 벨소리 잔존 + 잠금화면 빈
        //     푸쉬 알림 — v1.0.157 의 무조건 push 가 너무 강했음
        //
        // 해결 (옵션 A — 정확한 백그라운드 감지):
        //   1) 클라이언트가 didChangeAppLifecycleState 에서 'presence_update'
        //      WebSocket 메시지로 foreground/background 상태 송신
        //   2) 서버는 AttachedMeta.appState 에 저장
        //   3) call_invite 핸들러는 수신자의 foreground 단말 보유 여부 판별 →
        //      foreground 단말 있으면 FCM push 생략 (Flutter UI 가 처리)
        //      foreground 단말 없으면 FCM push 발송 (native heads-up/FSI 가 처리)
        //
        // 하위 호환 (v1.0.157 이하 클라이언트):
        //   - presence_update 안 보냄 → meta.appState 가 default 'background'
        //   - hasForegroundDevice 는 false 반환 → FCM push 발송
        //   - 즉, 구버전은 v1.0.157 과 동일하게 동작 (이중 표시 가능성 있으나
        //     기존 사용자 통화 가능성 유지)
        const hasForeground = this.hasForegroundDevice(to_user_id);
        const needPush = !hasForeground;

        if (needPush) {
          // 수신자가 background/offline → FCM heads-up/FSI 로 알림
          const pushPayload = {
            // ★ v1.0.124: 닉네임을 알림 제목/본문에 노출.
            //   native FCM 서비스가 data-only 로 받지만 generic 푸시 fallback
            //   시 표시되도록.
            title: caller_nickname,
            body: (l: Lang) => trl(l, '전화가 와요', '着信があります', 'Incoming call'),
            data: {
              // ★ v1.0.142 (Eggplant native call port — QRChat v4.0.270 형식):
              //   EggplantFirebaseMessagingService.onMessageReceived 가 읽는 키 셋.
              //   type='incoming_call' 이어야 native 서비스가 통화 분기로 라우팅.
              type: 'incoming_call',
              sessionId: call_id,
              callerId: meta.userId,
              callerNickname: caller_nickname,
              callType: call_type,
              callerProfilePhoto: '',
              channel: channel_name,
              agora: '1',
              // ★ v1.0.159 (2026-05-11): callerWallet 명시 필드 추가.
              //   v1.0.158 까지 native 측은 callerId(user_id) 만 받았고 wallet 전달
              //   채널이 없어서 NativeIncomingCallActivity 수락 → Flutter
              //   bootstrapIncomingFromPush(peerWalletAddress=user_id) → CallService
              //   _joinAgoraChannel 이 user_id 를 wallet 으로 오인 → Agora 채널 산정
              //   불일치 → 'wallet missing (my=ok, peer=empty)' 토스트.
              //   해결: FCM data 에 callerWallet 명시 + native 가 intent extras 로 전파.
              callerWallet: caller_wallet,
              // ★ Legacy 필드 병행 (v1.0.141 이하 클라이언트 호환).
              call_id,
              from_user_id: meta.userId,
              caller_nickname,
              caller_wallet,
            },
            isCall: true,
          };
          this.sendOfflinePush(to_user_id, pushPayload);
        }

        // ★ v1.0.162 (2026-05-12) ★★★ 진짜 근본 원인 수정 ★★★
        //   사장님 v1.0.157~v1.0.161 검증 결과 시나리오 3, 4 에서 발신자 즉시 끊김
        //   + 채팅방 잔재 + 수신자 벨소리만 죽어라 울림 — 본 분기가 원인.
        //
        //   기존 버그:
        //     - 수신자가 앱 모두 닫음/잠금화면 → WebSocket 끊김 → delivered=false
        //     - presence_update 못 보낸 상태 → hasForegroundDevice=false → needPush=true
        //     - 서버가 FCM 푸시는 정상 발사 (수신자 헤드업/벨소리 OK)
        //     - 동시에 발신자에게 call_failed('상대방이 접속 중이 아니에요') 발사
        //     - 발신자 call_service.dart 의 chat.on('call_failed') 핸들러가
        //       _setError + _teardown(ended) → 발신자 즉시 끊김 + 채팅방 잔재
        //     - 수신자는 이미 발신자 끊긴 후라 응답해도 합류 못 함 → 벨소리만 울림
        //
        //   주석은 "발신자는 ringback 계속 듣다가" 라고 적혀있었으나 실제 코드는
        //   정반대로 즉시 끊는 메시지를 보내고 있었음. v1.0.157 부터 잠재된 버그.
        //
        //   해결:
        //     - !delivered && needPush 인 경우는 정상 동선 (FCM 으로 깨움) → call_failed 발사 금지
        //     - !delivered && !needPush 는 이론상 도달 불가 (foreground 인데 WS 없음 모순)
        //       → 안전망으로 발신자에게 fail 알리되 message 는 부드럽게
        //     - 발신자는 ringback 계속 듣다가 수신자 응답(call_response) 받거나
        //       outgoing timer (call_service 측 30s timeout) 자체 만료로 종료
        if (!delivered && !needPush) {
          // 이론상 도달 어려운 분기 (foreground 라고 표시됐는데 WS 미연결).
          //   안전망: 발신자에게 fail 안내. 부드러운 한국어.
          this.sendSafe(ws, {
            type: 'call_failed',
            call_id,
            reason: 'offline',
            message: trl(meta.lang ?? 'ko', '연결할 수 없어요. 잠시 후 다시 걸어주세요.', '接続できませんでした。しばらくしてからもう一度おかけください。', "Couldn't connect. Please try calling again in a moment."),
          });
        }
        // ★ v1.0.162: !delivered && needPush 분기는 call_failed 발사 금지!!
        //   FCM push 만으로 정상 깨우기 동선 — 발신자는 ringback 계속.
        return;
      }

      case 'call_response': {
        // 실제 처리는 handleCallResponse — 네이티브 수신 화면이 REST
        // (/api/calls/signal → /internal/call-signal) 로 보내는 응답과 같은 경로.
        await this.handleCallResponse(meta.userId, ws, msg);
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
        await this.handleCallEnd(meta.userId, ws, msg);
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
  /** user_id 의 소켓 중 room_id 에 join 하지 않은 소켓에만 보낸다 (join 한 소켓은 broadcast 로 받음). */
  private sendToUserOutsideRoom(user_id: string, room_id: string, payload: unknown): void {
    const data = JSON.stringify(payload);
    for (const ws of this.state.getWebSockets()) {
      const meta = ws.deserializeAttachment() as AttachedMeta | null;
      if (meta && meta.userId === user_id && !meta.rooms.includes(room_id)) {
        try { ws.send(data); } catch { /* ignore */ }
      }
    }
  }

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

  /**
   * ★ v1.0.158 (2026-05-11): 수신자가 foreground 단말을 하나라도 보유하고
   *   있는지 판별. presence_update 로 갱신된 meta.appState='foreground' 인
   *   소켓이 한 개 이상이면 true.
   *
   *   call_invite 핸들러가 이 값으로 FCM heads-up push 발송 여부 결정:
   *     true  → Flutter UI 가 처리 → FCM push 생략 (이중 표시 0건)
   *     false → background/offline → FCM heads-up/FSI 로 native UI 표시
   *
   *   하위 호환: v1.0.157 이하 클라이언트는 presence_update 안 보내므로
   *   meta.appState 가 default 'background' → false 반환 → 기존 v1.0.157
   *   동작과 동일하게 FCM push 발송.
   */
  private hasForegroundDevice(user_id: string): boolean {
    for (const ws of this.state.getWebSockets()) {
      const meta = ws.deserializeAttachment() as AttachedMeta | null;
      if (meta && meta.userId === user_id && meta.appState === 'foreground') {
        return true;
      }
    }
    return false;
  }

  /** Send directly to a user (first socket we find for them). Returns true if delivered. */
  /**
   * 수신자의 통화 응답(수락/거절) 처리. WS(call_response) 와 네이티브 REST
   * (/internal/call-signal) 가 같이 쓴다. origin = 요청을 보낸 소켓 (REST 면 null).
   */
  private async handleCallResponse(fromUserId: string, origin: WebSocket | null, msg: Record<string, unknown>): Promise<void> {
    const cid = String(msg.call_id || '');
    const peer = String(msg.to_user_id || '');
    if (!cid || !peer) return;
    const accepted = msg.accepted === true;
    // 이 통화의 수신자만 응답할 수 있다 (아무나 남의 통화를 거절·수락 처리하지 못하게).
    const rec = await this.state.storage.get<CallRecord>(`call:${cid}`);
    if (!rec || rec.callee !== fromUserId || rec.caller !== peer) return;
    if (!accepted) await this.state.storage.delete(`call:${cid}`);

    // 발신자에게 응답 전달.
    this.sendToUser(peer, { type: 'call_response', call_id: cid, from_user_id: fromUserId, accepted });

    // 응답한 사람의 다른 소켓에 "이미 처리됨" 통보 — 네이티브 화면에서 받거나
    // 거절했을 때, 백그라운드에 살아 있던 Flutter 쪽 수신 상태·벨소리를 정리.
    this.sendToUserExcept(fromUserId, origin, { type: 'call_answered_elsewhere', call_id: cid, accepted });

    if (!accepted) {
      // 발신자가 백그라운드에서 신호음만 듣고 있었다면 즉시 종료되도록.
      this.sendToUser(peer, { type: 'call_cancel', call_id: cid, from_user_id: fromUserId, reason: 'rejected' });
      // 거절한 사람 본인 단말의 네이티브 벨·수신 화면도 닫는다. 예: Flutter 로 통화 중인
      // 사람이 백그라운드에서 새 전화를 "통화 중" 자동 거절 → FCM 으로 이미 울리기
      // 시작한 네이티브 벨이 계속 울리던 문제. (앱이 화면에 있으면 네이티브는 안 울림)
      if (!this.isUserForeground(fromUserId)) {
        this.sendOfflinePush(fromUserId, {
          title: '',
          body: '',
          data: { type: 'call_cancel', call_id: cid, from_user_id: fromUserId, reason: 'rejected' },
          isCall: true,
        });
      }
    }
  }

  /**
   * 통화 종료/취소 처리 (발신 취소, 무응답 타임아웃, 통화 중 끊기).
   * 상대가 앱을 화면에 띄워 두지 않았으면(백그라운드·종료·잠금) WS 가 살아
   * 있어도 FCM 취소를 같이 보낸다 — 네이티브 벨소리·수신 화면은 FCM 으로만 닫힌다.
   */
  private async handleCallEnd(fromUserId: string, origin: WebSocket | null, msg: Record<string, unknown>): Promise<void> {
    const cid = String(msg.call_id || '');
    const peer = String(msg.to_user_id || '');
    if (!cid || !peer) return;
    // 이 통화의 두 당사자만 종료 신호를 보낼 수 있다 — 아무 사용자에게나 high-priority
    // FCM 취소를 보내는 스팸·배터리 소모를 막는다.
    const rec = await this.state.storage.get<CallRecord>(`call:${cid}`);
    if (!rec) return;
    const isParty = (rec.caller === fromUserId && rec.callee === peer) || (rec.callee === fromUserId && rec.caller === peer);
    if (!isParty) return;
    await this.state.storage.delete(`call:${cid}`);
    const cancel = { type: 'call_cancel', call_id: cid, from_user_id: fromUserId, reason: 'caller_ended' };

    const onlineDelivered = this.sendToUser(peer, cancel);
    if (!onlineDelivered || !this.isUserForeground(peer)) {
      this.sendOfflinePush(peer, {
        // data-only (notification 비움) — OS 가 새 알림을 띄우지 않게.
        title: '',
        body: '',
        data: cancel,
        isCall: true, // high priority — 잠든 단말도 즉시 깨움
      });
    }
    // 끊은 사람의 다른 단말/소켓도 정리.
    this.sendToUserExcept(fromUserId, origin, cancel);
  }

  /** 2시간 지난 통화 기록 정리 (종료 신호가 없던 통화). 가끔(초대의 2%)만 실행. */
  private async pruneCallRecords(): Promise<void> {
    const cutoff = Date.now() - 2 * 60 * 60 * 1000;
    const all = await this.state.storage.list<CallRecord>({ prefix: 'call:', limit: 500 });
    const stale: string[] = [];
    for (const [k, v] of all) if (!v || v.at < cutoff) stale.push(k);
    if (stale.length) await this.state.storage.delete(stale);
  }

  /** origin 소켓을 뺀 같은 사용자의 소켓들에 전송. */
  private sendToUserExcept(user_id: string, except: WebSocket | null, payload: unknown): boolean {
    const data = JSON.stringify(payload);
    let delivered = false;
    for (const ws of this.state.getWebSockets()) {
      if (except && ws === except) continue;
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

  /** 이 사용자의 소켓 중 앱이 화면에 떠 있는(presence=foreground) 것이 있는지. */
  private isUserForeground(user_id: string): boolean {
    for (const ws of this.state.getWebSockets()) {
      const meta = ws.deserializeAttachment() as AttachedMeta | null;
      if (meta && meta.userId === user_id && meta.appState === 'foreground') return true;
    }
    return false;
  }

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

  /**
   * 오프라인 peer 에게 FCM 시스템 푸시 발송.
   *
   * 정책:
   *  - 익명성: title/body 에 닉네임/메시지 본문 포함 0건 (generic 만).
   *  - 휘발성: 푸시 이력 D1 저장 0건. 토큰 invalid 시 NULL 처리.
   *  - placeholder: Firebase 키 미등록 시 sendFcm 이 silent skip → return false.
   *  - fire-and-forget: WebSocket 응답 지연 안 시키도록 await 안 함.
   */
  private sendOfflinePush(
    peerUserId: string,
    opts: {
      /** 수신자 언어(users.market)별 문구를 고르려면 함수로 넘긴다. */
      title: string | ((lang: Lang) => string);
      body: string | ((lang: Lang) => string);
      data: Record<string, string>;
      isCall: boolean;
    },
  ): void {
    // ignore: discarded_futures - 의도적 fire-and-forget.
    void (async () => {
      try {
        let row: { fcm_token: string | null; market?: string | null } | null;
        try {
          row = await this.env.DB.prepare(
            'SELECT fcm_token, market FROM users WHERE id = ?',
          )
            .bind(peerUserId)
            .first<{ fcm_token: string | null; market: string | null }>();
        } catch {
          // market 컬럼 미적용 — 한국어
          row = await this.env.DB.prepare(
            'SELECT fcm_token FROM users WHERE id = ?',
          )
            .bind(peerUserId)
            .first<{ fcm_token: string | null }>();
        }
        const token = row?.fcm_token;
        if (!token) return; // 미등록 디바이스 — skip.
        const lang = marketLang(normalizeMarket(row?.market ?? '') ?? 'kr');

        const ok = await sendFcm(this.env, {
          fcmToken: token,
          title: typeof opts.title === 'function' ? opts.title(lang) : opts.title,
          body: typeof opts.body === 'function' ? opts.body(lang) : opts.body,
          data: opts.data,
          isCall: opts.isCall,
        });
        if (!ok) {
          // 발송 실패 (placeholder 모드 OR 토큰 invalid). 토큰 무효 처리는
          // 너무 공격적으로 하면 정상 토큰까지 지울 수 있어, sendFcm 내부에서
          // UNREGISTERED 만 로그로 남기는 수준으로 유지.
        }
      } catch (e) {
        // 0024 마이그레이션 미적용 / DB 일시 오류 → silent skip.
        console.log('[push] offline send skipped:', e);
      }
    })();
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
/**
 * roomId 형식은 'userA_userB' 또는 'userA_userB_productId' (클라이언트
 * ChatService._makeRoomId). 참여자는 앞 두 토큰뿐이다. productId 자리에
 * 자기 id 를 넣은 roomId 로 남의 방에 끼어들지 못하도록 앞 두 토큰만 본다.
 */
function isRoomMember(roomId: string, userId: string): boolean {
  const parts = roomId.split('_');
  return parts.length >= 2 && (parts[0] === userId || parts[1] === userId);
}

async function verifyJwt(
  token: string,
  secret: string,
): Promise<{ id: string; nickname: string; device_uuid: string; tv: number } | null> {
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
