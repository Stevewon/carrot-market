import { Hono } from 'hono';
import type { Env, UserRow, UserPublic, Variables } from '../types';
import { authMiddleware } from '../jwt';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

function sanitize(u: UserRow): UserPublic {
  return {
    id: u.id,
    nickname: u.nickname,
    device_uuid: u.device_uuid,
    wallet_address: u.wallet_address,
    region: u.region,
    manner_score: u.manner_score,
    created_at: u.created_at,
    updated_at: u.updated_at,
  };
}

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

  if (body.nickname !== undefined) {
    const nick = body.nickname.trim();
    if (nick.length < 2 || nick.length > 12) {
      return c.json({ error: '닉네임은 2~12자여야 해요' }, 400);
    }
    // Block nickname collisions (excluding ourselves).
    const collision = await c.env.DB
      .prepare('SELECT id FROM users WHERE nickname = ? COLLATE NOCASE AND id != ?')
      .bind(nick, authUser.id)
      .first<{ id: string }>();
    if (collision) {
      return c.json({ error: '이미 사용 중인 닉네임이에요' }, 409);
    }
    updates.push('nickname = ?');
    values.push(nick);
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
  if (!user) return c.json({ error: 'User not found' }, 404);

  return c.json({ user: sanitize(user) });
});

/**
 * GET /api/users/:id/profile
 *
 * Public profile of any user — used by the seller-profile screen.
 * Returns nickname, region, manner_score (×10 scale), join date, and
 * lightweight aggregates: total reviews, good/soso/bad breakdown,
 * top 3 review tags.
 */
app.get('/:id/profile', async (c) => {
  const id = c.req.param('id');
  const u = await c.env.DB
    .prepare(
      'SELECT id, nickname, region, manner_score, created_at FROM users WHERE id = ?'
    )
    .bind(id)
    .first<{
      id: string;
      nickname: string;
      region: string | null;
      manner_score: number;
      created_at: string;
    }>();
  if (!u) return c.json({ error: 'Not found' }, 404);

  const stats = await c.env.DB
    .prepare(
      `SELECT
         COUNT(*) AS total,
         SUM(CASE WHEN rating='good' THEN 1 ELSE 0 END) AS good,
         SUM(CASE WHEN rating='soso' THEN 1 ELSE 0 END) AS soso,
         SUM(CASE WHEN rating='bad'  THEN 1 ELSE 0 END) AS bad
       FROM reviews WHERE reviewee_id = ?`
    )
    .bind(id)
    .first<{ total: number; good: number; soso: number; bad: number }>();

  const sellingCount = await c.env.DB
    .prepare(
      "SELECT COUNT(*) AS n FROM products WHERE seller_id = ? AND status = 'sale'"
    )
    .bind(id)
    .first<{ n: number }>();

  return c.json({
    profile: u,
    stats: {
      total: stats?.total ?? 0,
      good: stats?.good ?? 0,
      soso: stats?.soso ?? 0,
      bad: stats?.bad ?? 0,
      selling: sellingCount?.n ?? 0,
    },
  });
});

/**
 * GET /api/users/:id/reviews
 *
 * Paginated list of reviews received by a user, newest first.
 *   ?limit=20&before=<iso>
 */
app.get('/:id/reviews', async (c) => {
  const id = c.req.param('id');
  const limit = Math.min(parseInt(c.req.query('limit') || '20', 10) || 20, 50);
  const before = c.req.query('before');

  const sql = before
    ? `SELECT r.id, r.rating, r.tags, r.comment, r.created_at,
              r.reviewer_id, ru.nickname AS reviewer_nickname,
              p.id AS product_id, p.title AS product_title
         FROM reviews r
         JOIN users    ru ON ru.id = r.reviewer_id
         JOIN products p  ON p.id  = r.product_id
        WHERE r.reviewee_id = ? AND r.created_at < ?
        ORDER BY r.created_at DESC LIMIT ?`
    : `SELECT r.id, r.rating, r.tags, r.comment, r.created_at,
              r.reviewer_id, ru.nickname AS reviewer_nickname,
              p.id AS product_id, p.title AS product_title
         FROM reviews r
         JOIN users    ru ON ru.id = r.reviewer_id
         JOIN products p  ON p.id  = r.product_id
        WHERE r.reviewee_id = ?
        ORDER BY r.created_at DESC LIMIT ?`;

  const stmt = before
    ? c.env.DB.prepare(sql).bind(id, before, limit)
    : c.env.DB.prepare(sql).bind(id, limit);
  const { results } = await stmt.all();
  return c.json({ reviews: results || [] });
});

export default app;
