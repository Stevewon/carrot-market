import { Hono } from 'hono';
import type { Env, UserRow, Variables } from '../types';
import { authMiddleware } from '../jwt';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

/** PUT /api/users/me - update region / nickname */
app.put('/me', authMiddleware, async (c) => {
  const authUser = c.get('user');
  if (!authUser) return c.json({ error: 'Unauthorized' }, 401);

  let body: { region?: string; nickname?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const updates: string[] = [];
  const values: (string | null)[] = [];

  if (body.region !== undefined) {
    updates.push('region = ?');
    values.push(body.region);
  }
  if (body.nickname !== undefined && body.nickname.trim().length >= 2) {
    updates.push('nickname = ?');
    values.push(body.nickname.trim().slice(0, 12));
  }

  if (updates.length === 0) return c.json({ ok: true });

  updates.push("updated_at = datetime('now')");
  values.push(authUser.id);

  await c.env.DB
    .prepare(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`)
    .bind(...values)
    .run();

  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(authUser.id)
    .first<UserRow>();

  return c.json({ user });
});

export default app;
