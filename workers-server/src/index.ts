/**
 * Eggplant 🍆 API - Cloudflare Workers entrypoint
 *
 * Routes:
 *   GET  /                      -> health
 *   GET  /api                   -> health
 *   GET  /api/health            -> health
 *   *    /api/auth/*            -> auth routes
 *   *    /api/users/*           -> user routes
 *   *    /api/products/*        -> product routes
 *   GET  /uploads/:key          -> R2 image passthrough
 *   GET  /socket                -> WebSocket upgrade -> ChatHub Durable Object
 *
 * The Flutter client connects to:
 *   - REST : https://api.eggplant.life
 *   - WS   : wss://api.eggplant.life/socket?token=<jwt>
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import type { Env, Variables } from './types';
import { ipCountry, ipMarket } from './market';
import authRoutes from './routes/auth';
import callsRoutes from './routes/calls';
import shareRoutes from './routes/share';
import userLinkRoutes from './routes/userLink';
import inviteRoutes from './routes/invite';
import unionInviteRoutes from './routes/unionInvite';
import usersRoutes from './routes/users';
import productsRoutes from './routes/products';
import chatRoutes, { purgeExpiredChatMedia } from './routes/chat';
import moderationRoutes from './routes/moderation';
import alertsRoutes from './routes/alerts';
import notificationsRoutes from './routes/notifications';
import { purgeOldInbox } from './utils/inbox';
import hiddenRoutes from './routes/hidden';
import withdrawalsRoutes from './routes/withdrawals';
import referralsRoutes from './routes/referrals';
import adminRoutes from './routes/admin';
import cointripRoutes, { sweepCointrip } from './routes/cointrip';
import cointripSsvRoutes from './routes/cointripSsv';
import { processReceiveSends } from './walletReceive';

// Re-export the Durable Object class so Wrangler can bind it
export { ChatHub } from './chat-hub';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

// ---------- CORS ----------
// Allow the Flutter app (native) + browser dev tools to hit the API.
app.use(
  '*',
  cors({
    origin: (origin) => origin ?? '*',
    allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization'],
    exposeHeaders: ['Content-Length'],
    maxAge: 600,
    credentials: false,
  })
);

// ---------- Health ----------
const HEALTH = {
  ok: true,
  name: 'eggplant-api',
  runtime: 'cloudflare-workers',
  message: '🍆 Eggplant API is running',
};
app.get('/api', (c) => c.json(HEALTH));
app.get('/api/health', (c) => c.json(HEALTH));

// ---------- Root ----------
app.get('/', (c) => c.json(HEALTH));

// 접속 IP 의 나라로 언어·시장을 정한다 (일본 IP → 일본어·일본 지역·엔화, 그 외 한국어).
// 앱이 처음 실행할 때 한 번 부르고 기억한다.
app.get('/api/geo', (c) => {
  const country = ipCountry(c);
  return c.json({ country, market: ipMarket(c) });
});

// ---------- REST routes ----------
app.route('/api/auth', authRoutes);
app.route('/api/users', usersRoutes);
app.route('/api/products', productsRoutes);
app.route('/api/chat', chatRoutes);
app.route('/api/moderation', moderationRoutes);
app.route('/api/alerts', alertsRoutes);
app.route('/api/notifications', notificationsRoutes);
app.route('/api/hidden', hiddenRoutes);
app.route('/api/withdrawals', withdrawalsRoutes);
app.route('/api/referrals', referralsRoutes);
app.route('/api/admin', adminRoutes);
app.route('/api/cointrip', cointripRoutes);
// AdMob 보상형 광고 서버 확인 콜백 (로그인 없음 — 구글 서명으로 확인)
app.route('/api/cointrip-ssv', cointripSsvRoutes);
app.route('/api/calls', callsRoutes);
// 공유 링크 웹 미리보기 (https://api.eggplant.life/p/<상품id>)
app.route('/p', shareRoutes);
// 내 QR 링크 웹 페이지 (https://api.eggplant.life/u/<회원id>)
app.route('/u', userLinkRoutes);
// 친구 초대 링크 웹 페이지 (https://api.eggplant.life/i/<닉네임>)
app.route('/i', inviteRoutes);
// 코인트립 친구 연합 초대 링크 웹 페이지 (https://api.eggplant.life/c/<초대 코드>)
app.route('/c', unionInviteRoutes);

// ---------- R2 uploads passthrough ----------
// Serves /uploads/<key> from the R2 bucket with basic caching.
app.get('/uploads/:key{.+}', async (c) => {
  const key = c.req.param('key');
  if (!key) return c.json({ error: 'Not found' }, 404);
  // 채팅 사진(암호화본)은 공개 경로로 내주지 않는다 — /api/chat/media 로만 (방 참여자 확인).
  if (key.startsWith('chat-media/')) return c.json({ error: 'Not found' }, 404);

  // If a public R2 URL is configured, redirect there (CDN cheaper + faster).
  if (c.env.PUBLIC_UPLOAD_URL) {
    return c.redirect(`${c.env.PUBLIC_UPLOAD_URL.replace(/\/$/, '')}/${key}`, 302);
  }

  // 영상 플레이어(ExoPlayer/AVPlayer)는 Range 로 조각 요청한다. 206 을 못 주면
  // moov 가 파일 끝에 있는 mp4 는 전체를 다 받아야 재생이 시작된다.
  const rangeHeader = c.req.header('range');
  const obj = await c.env.UPLOADS.get(key, rangeHeader ? { range: c.req.raw.headers } : undefined);
  if (!obj) return c.json({ error: 'Not found' }, 404);

  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set('etag', obj.httpEtag);
  headers.set('cache-control', 'public, max-age=31536000, immutable');
  headers.set('accept-ranges', 'bytes');
  if (!headers.has('content-type')) {
    headers.set('content-type', 'application/octet-stream');
  }
  const r = obj.range as { offset?: number; length?: number; suffix?: number } | undefined;
  if (rangeHeader && r) {
    let start = 0;
    let len = obj.size;
    if (r.suffix !== undefined) {
      len = Math.min(r.suffix, obj.size);
      start = obj.size - len;
    } else {
      start = r.offset ?? 0;
      len = r.length ?? obj.size - start;
    }
    headers.set('content-range', `bytes ${start}-${start + len - 1}/${obj.size}`);
    headers.set('content-length', String(len));
    return new Response(obj.body, { status: 206, headers });
  }
  return new Response(obj.body, { headers });
});

// ---------- WebSocket upgrade -> Durable Object ----------
// The client connects to wss://<host>/socket?token=<jwt>
// All WS sessions are routed to a single global ChatHub instance
// (id derived from a fixed name), so every user can reach every other user.
app.get('/socket', async (c) => {
  const upgrade = c.req.header('upgrade') || '';
  if (upgrade.toLowerCase() !== 'websocket') {
    return c.text('Expected WebSocket upgrade', 426);
  }

  const id = c.env.CHAT_HUB.idFromName('global');
  const stub = c.env.CHAT_HUB.get(id);
  return stub.fetch(c.req.raw);
});

// Legacy socket.io path (during migration) -> same DO
app.get('/socket.io/*', async (c) => {
  const upgrade = c.req.header('upgrade') || '';
  if (upgrade.toLowerCase() !== 'websocket') {
    return c.json({ error: 'Socket.IO is no longer supported; use /socket (raw WebSocket)' }, 410);
  }
  const id = c.env.CHAT_HUB.idFromName('global');
  const stub = c.env.CHAT_HUB.get(id);
  return stub.fetch(c.req.raw);
});

// ---------- 404 ----------
app.notFound((c) => c.json({ error: 'Not found', path: c.req.path }, 404));

// ---------- Error handler ----------
app.onError((err, c) => {
  console.error('[error]', err?.stack || err);
  return c.json(
    {
      error: 'Internal Server Error',
      message: c.env.ENVIRONMENT === 'production' ? undefined : String(err?.message || err),
    },
    500
  );
});

// 1분 cron — 1단계 지갑 인증 송금 대기열 처리 (요청 직후 처리가 실패했을 때의 재시도).
export default {
  fetch: app.fetch,
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    // 30분마다: 24시간 지난 채팅 사진 암호문 삭제.
    if (new Date(event.scheduledTime).getUTCMinutes() % 30 === 0) {
      ctx.waitUntil(
        purgeExpiredChatMedia(env)
          .then((n) => { if (n) console.log('[cron] chat-media purged', n); })
          .catch((e) => console.error('[cron] chat-media purge failed', e)),
      );
    }
    // 하루 한 번(UTC 18:00 = 한국 새벽 3시): 30일 지난 알림·검색어 집계 삭제.
    const at = new Date(event.scheduledTime);
    if (at.getUTCHours() === 18 && at.getUTCMinutes() === 0) {
      ctx.waitUntil(purgeOldInbox(env).catch((e) => console.error('[cron] inbox purge failed', e)));
    }
    // 코인트립: 10분 지난 블랙코인 열기(지도에 되돌림)·벌칙(QTA 차감) 정리.
    ctx.waitUntil(sweepCointrip(env).catch((e) => console.error('[cron] cointrip sweep failed', e)));
    ctx.waitUntil(
      processReceiveSends(env)
        .then((r) => { if (r.picked) console.log('[cron] wallet-receive', JSON.stringify(r)); })
        .catch((e) => console.error('[cron] wallet-receive failed', e)),
    );
  },
};
