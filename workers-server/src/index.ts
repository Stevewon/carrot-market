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
import authRoutes from './routes/auth';
import usersRoutes from './routes/users';
import productsRoutes from './routes/products';
import chatRoutes from './routes/chat';
import moderationRoutes from './routes/moderation';
import alertsRoutes from './routes/alerts';
import hiddenRoutes from './routes/hidden';
import withdrawalsRoutes from './routes/withdrawals';
import referralsRoutes from './routes/referrals';

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
app.get('/', (c) => c.json(HEALTH));
app.get('/api', (c) => c.json(HEALTH));
app.get('/api/health', (c) => c.json(HEALTH));

// ---------- REST routes ----------
app.route('/api/auth', authRoutes);
app.route('/api/users', usersRoutes);
app.route('/api/products', productsRoutes);
app.route('/api/chat', chatRoutes);
app.route('/api/moderation', moderationRoutes);
app.route('/api/alerts', alertsRoutes);
app.route('/api/hidden', hiddenRoutes);
app.route('/api/withdrawals', withdrawalsRoutes);
app.route('/api/referrals', referralsRoutes);

// ---------- R2 uploads passthrough ----------
// Serves /uploads/<key> from the R2 bucket with basic caching.
app.get('/uploads/:key{.+}', async (c) => {
  const key = c.req.param('key');
  if (!key) return c.json({ error: 'Not found' }, 404);

  // If a public R2 URL is configured, redirect there (CDN cheaper + faster).
  if (c.env.PUBLIC_UPLOAD_URL) {
    return c.redirect(`${c.env.PUBLIC_UPLOAD_URL.replace(/\/$/, '')}/${key}`, 302);
  }

  const obj = await c.env.UPLOADS.get(key);
  if (!obj) return c.json({ error: 'Not found' }, 404);

  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set('etag', obj.httpEtag);
  headers.set('cache-control', 'public, max-age=31536000, immutable');
  if (!headers.has('content-type')) {
    headers.set('content-type', 'application/octet-stream');
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

export default app;
