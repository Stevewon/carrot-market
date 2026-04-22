import { Hono } from 'hono';
import type { Env, UserRow, Variables } from '../types';
import { authMiddleware, signToken } from '../jwt';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

/**
 * POST /api/auth/register
 * Body: { nickname, device_uuid, region? }
 * If device_uuid already exists, treats as login.
 */
app.post('/register', async (c) => {
  let body: { nickname?: string; device_uuid?: string; region?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const { nickname, device_uuid, region } = body;
  if (!nickname || typeof nickname !== 'string' || nickname.trim().length < 2) {
    return c.json({ error: '닉네임은 2자 이상이어야 해요' }, 400);
  }
  if (!device_uuid || typeof device_uuid !== 'string') {
    return c.json({ error: '기기 UUID가 필요해요' }, 400);
  }
  const cleanNick = nickname.trim().slice(0, 12);

  const existing = await c.env.DB
    .prepare('SELECT * FROM users WHERE device_uuid = ?')
    .bind(device_uuid)
    .first<UserRow>();

  if (existing) {
    const token = await signToken(existing, c.env.JWT_SECRET);
    return c.json({ token, user: existing });
  }

  const id = crypto.randomUUID();
  await c.env.DB
    .prepare('INSERT INTO users (id, nickname, device_uuid, region) VALUES (?, ?, ?, ?)')
    .bind(id, cleanNick, device_uuid, region || null)
    .run();

  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(id)
    .first<UserRow>();

  if (!user) return c.json({ error: '사용자 생성 실패' }, 500);

  const token = await signToken(user, c.env.JWT_SECRET);
  return c.json({ token, user }, 201);
});

/**
 * POST /api/auth/login
 * Body: { device_uuid }
 */
app.post('/login', async (c) => {
  let body: { device_uuid?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const { device_uuid } = body;
  if (!device_uuid) return c.json({ error: '기기 UUID가 필요해요' }, 400);

  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE device_uuid = ?')
    .bind(device_uuid)
    .first<UserRow>();

  if (!user) return c.json({ error: '가입되지 않은 기기예요' }, 404);

  const token = await signToken(user, c.env.JWT_SECRET);
  return c.json({ token, user });
});

/** GET /api/auth/me */
app.get('/me', authMiddleware, async (c) => {
  const authUser = c.get('user');
  if (!authUser) return c.json({ error: 'Unauthorized' }, 401);

  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(authUser.id)
    .first<UserRow>();

  if (!user) return c.json({ error: 'User not found' }, 404);
  return c.json({ user });
});

export default app;
