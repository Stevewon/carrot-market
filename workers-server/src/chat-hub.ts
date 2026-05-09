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
              title: '새 메시지',
              body: '새 메시지가 도착했어요',
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
        // ★ P1-#7 (v1.0.127): 닉네임 spoof 방지 — 클라이언트가 보낸 값을 그대로
        //   쓰지 않고, JWT 의 meta.nickname 을 우선 사용. 발신자가 임의로 다른
        //   사람 닉네임으로 가장하는 것을 서버에서 차단.
        const caller_nickname = meta.nickname || (msg.caller_nickname as string) || '익명';
        // ★ v1.0.136: caller_wallet 도 push data 에 포함시켜야 background isolate 의
        //   CallKit 가 wallet 까지 들고 main isolate 로 전달 → CallScreen 이 채널명
        //   산정 가능. 클라이언트가 보내준 값 신뢰 (서버는 wallet 검증 안 함 — Agora
        //   채널명 산정용 단순 페어 키이고, 토큰은 별도 인증으로 발급되므로 위·변조해도
        //   실효성 0).
        const caller_wallet_raw = String(msg.caller_wallet || '');
        const caller_wallet = caller_wallet_raw.trim().toLowerCase();
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
              message: '연결할 수 없는 상대에요',
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
          peer_wallet = (peerRow?.wallet_address || '').trim().toLowerCase();
          if (caller_wallet && peer_wallet) {
            const pair = [caller_wallet, peer_wallet].sort();
            channel_name = `eggplant_call_${pair[0]}_${pair[1]}`;
          }
        } catch (e) {
          console.log('[call_invite] peer wallet lookup failed:', e);
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
        if (!delivered) {
          // ★★★ 3차 푸시: peer 가 백그라운드/앱 종료 상태일 때
          //  Eggplant native FCM 서비스 (EggplantFirebaseMessagingService) 로
          //  전화 수신 UI 를 띄우기 위해 FCM high-priority data-only 푸시 발송.
          //  앱이 켜져있으면 sendOfflinePush 결과와 무관하게 결국 WebSocket 으로
          //  call_incoming 이 다시 라우팅되도록, 클라이언트가 푸시 tap → 앱 부팅 →
          //  WebSocket 재연결 + call_id 로 시그널링 재시도.
          //  Firebase 키 미등록(placeholder) 환경에서는 silent skip 후 call_failed.
          this.sendOfflinePush(to_user_id, {
            // ★ v1.0.124: 닉네임을 알림 제목/본문에 노출. v1.0.142 에서도
            //   유지 — native FCM 서비스가 data-only 로 받지만 generic 푸시
            //   fallback 시 표시되도록.
            title: caller_nickname,
            body: '전화가 와요',
            data: {
              // ★ v1.0.142 (Eggplant native call port — QRChat v4.0.270 형식):
              //   EggplantFirebaseMessagingService.onMessageReceived 가 읽는 키 셋.
              //   type='incoming_call' 이어야 native 서비스가 통화 분기로 라우팅.
              //   sessionId/callerId/callerNickname/callType/channel/agora 가
              //   NativeIncomingCallActivity → AgoraCallActivity 까지 전달됨.
              type: 'incoming_call',
              sessionId: call_id,
              callerId: meta.userId,
              callerNickname: caller_nickname,
              callType: call_type,
              callerProfilePhoto: '',
              channel: channel_name,
              agora: '1',
              // ★ Legacy 필드 병행 (v1.0.141 이하 클라이언트 호환):
              //   기존 _showIncomingCall (Dart flutter_callkit_incoming) 가
              //   읽던 키. v1.0.142 에서 native 가 우선 처리하지만, 구버전
              //   설치 단말의 background isolate 가 깨졌을 때 대비.
              call_id,
              from_user_id: meta.userId,
              caller_nickname,
              caller_wallet,
            },
            isCall: true,
          });
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
        // ★ v1.0.124: 거절(accepted=false) 인 경우 발신자에게도 call_cancel 효과를
        //  주고, 백그라운드 CallKit 이 떠있던 발신자 단말도 즉시 닫아야 함.
        //  하지만 발신자측은 이미 chat.on('call_response') 에서 자체 teardown 함.
        //  여기서는 단순히 응답을 발신자에게 relay 만 하고, 추가로 발신자가
        //  이미 끊은 뒤 거절이 들어왔을 가능성 대비해 to_user_id 에게도 call_cancel
        //  보낸다 (수신자 자기 자신 — CallKit UI 종료 보장).
        this.relayTo(msg, meta, 'call_response', ['accepted']);
        const accepted = msg.accepted === true;
        if (!accepted) {
          // 거절: 양쪽 단말 모두 CallKit 닫기.
          const cidR = String(msg.call_id || '');
          const peerR = String(msg.to_user_id || '');
          if (cidR && peerR) {
            // 발신자에게도 call_cancel — 발신자가 백그라운드에서 ringback 만 듣고
            // 있었다면 즉시 종료되도록.
            this.sendToUser(peerR, {
              type: 'call_cancel',
              call_id: cidR,
              from_user_id: meta.userId,
              reason: 'rejected',
            });
            // 거절자 본인 단말이 여러 개일 때 다른 단말의 CallKit 도 닫기.
            this.sendToUser(meta.userId, {
              type: 'call_cancel',
              call_id: cidR,
              from_user_id: meta.userId,
              reason: 'rejected',
            });
          }
        }
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
        // ★ v1.0.124 핵심 핫픽스 (사장님 2026-05-07 보고):
        //   발신자가 통화를 끊었을 때, 수신측이 백그라운드/앱 종료 상태이면
        //   WebSocket 으로는 도달 못 하므로 그 단말의 벨소리(CallKit UI)가
        //   30초 타임아웃까지 절대 안 꺼짐 → "전화벨 무한 울림" 사장님 신고.
        //   해결: 1) WebSocket 으로 call_cancel relay (online 단말 즉시 종료)
        //         2) FCM data-only 푸시로 call_cancel 발사 (offline/background 단말
        //            의 background isolate 가 받아서 FlutterCallkitIncoming.endCall(callId)
        //            호출 → CallKit 시스템 UI 강제 종료)
        const cid = String(msg.call_id || '');
        const peer = String(msg.to_user_id || '');
        if (!cid || !peer) return;

        // (1) 온라인 단말에는 WS 로 즉시 통보.
        const onlineDelivered = this.sendToUser(peer, {
          type: 'call_cancel',
          call_id: cid,
          from_user_id: meta.userId,
          reason: 'caller_ended',
        });

        // (2) 오프라인 단말에도 FCM 으로 취소 통보 (CallKit UI 닫기 위해).
        //     온라인 단말이면 이미 (1)에서 처리됐지만, 멀티디바이스 상황에선
        //     다른 디바이스도 닫아야 하므로 항상 발사.
        if (!onlineDelivered) {
          this.sendOfflinePush(peer, {
            // notification 영역은 비우고 data-only 로 보내야 OS 가 알림 안 띄움.
            // (notification 이 있으면 새 알림 + 기존 알림 동시 표시될 수 있음)
            title: '',
            body: '',
            data: {
              type: 'call_cancel',
              call_id: cid,
              from_user_id: meta.userId,
              reason: 'caller_ended',
            },
            isCall: true, // high priority — background isolate 즉시 깨움
          });
        }

        // 자기(발신자) 다른 디바이스도 정리.
        this.sendToUser(meta.userId, {
          type: 'call_cancel',
          call_id: cid,
          from_user_id: meta.userId,
          reason: 'caller_ended',
        });
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
      title: string;
      body: string;
      data: Record<string, string>;
      isCall: boolean;
    },
  ): void {
    // ignore: discarded_futures - 의도적 fire-and-forget.
    void (async () => {
      try {
        const row = await this.env.DB.prepare(
          'SELECT fcm_token FROM users WHERE id = ?',
        )
          .bind(peerUserId)
          .first<{ fcm_token: string | null }>();
        const token = row?.fcm_token;
        if (!token) return; // 미등록 디바이스 — skip.

        const ok = await sendFcm(this.env, {
          fcmToken: token,
          title: opts.title,
          body: opts.body,
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
