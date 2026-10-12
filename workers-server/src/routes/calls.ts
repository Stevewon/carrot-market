/**
 * 통화 신호 REST — 네이티브 통화 화면 전용.
 *
 * 앱이 백그라운드·종료·잠금 상태일 때 받은 통화는 Android 네이티브 화면
 * (NativeIncomingCallActivity / AgoraCallActivity) 이 처리한다. 이때 Flutter 를
 * 깨워 WebSocket 으로 응답을 보내던 방식은 콜드 스타트에서 신호가 유실됐다.
 * 네이티브가 저장된 JWT 로 이 엔드포인트를 직접 호출한다.
 *
 * POST /api/calls/signal
 *   { type: 'response', call_id, to_user_id, accepted: boolean }   수락/거절
 *   { type: 'end',      call_id, to_user_id }                       종료
 */
import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { authMiddleware } from '../jwt';
import { tr } from '../market';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.post('/signal', authMiddleware, async (c) => {
  const me = c.get('user')!;
  let body: { type?: string; call_id?: string; to_user_id?: string; accepted?: boolean } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);
  }
  const type = body.type === 'response' || body.type === 'end' ? body.type : null;
  const callId = String(body.call_id || '').slice(0, 64);
  const to = String(body.to_user_id || '').slice(0, 64);
  if (!type || !callId || !to || to === me.id) return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);

  const stub = c.env.CHAT_HUB.get(c.env.CHAT_HUB.idFromName('global'));
  await stub.fetch('https://do/internal/call-signal', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      from_user_id: me.id,
      type,
      call_id: callId,
      to_user_id: to,
      accepted: body.accepted === true,
    }),
  });
  return c.json({ ok: true });
});

export default app;
