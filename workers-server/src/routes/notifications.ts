/**
 * 알림함 (당근식).
 *
 *   GET    /api/notifications            - 내 알림 최근 100개 + 안 읽은 수
 *   GET    /api/notifications/unread     - 안 읽은 수만 (홈 종 아이콘 빨간 점)
 *   POST   /api/notifications/read-all   - 모두 읽음
 *   DELETE /api/notifications/:id        - 하나 지우기
 *   DELETE /api/notifications            - 모두 지우기
 */
import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { authMiddleware } from '../jwt';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use('*', authMiddleware);

async function unreadCount(env: Env, userId: string): Promise<number> {
  const r = await env.DB
    .prepare('SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND read_at IS NULL')
    .bind(userId)
    .first<{ n: number }>();
  return r?.n ?? 0;
}

app.get('/', async (c) => {
  const me = c.get('user')!;
  const rs = await c.env.DB
    .prepare(
      `SELECT id, type, title, body, product_id, target_user_id, thumb, created_at, read_at
         FROM notifications WHERE user_id = ?
        ORDER BY created_at DESC LIMIT 100`,
    )
    .bind(me.id)
    .all();
  return c.json({ notifications: rs.results || [], unread: await unreadCount(c.env, me.id) });
});

app.get('/unread', async (c) => {
  const me = c.get('user')!;
  return c.json({ unread: await unreadCount(c.env, me.id) });
});

app.post('/read-all', async (c) => {
  const me = c.get('user')!;
  await c.env.DB
    .prepare("UPDATE notifications SET read_at = datetime('now') WHERE user_id = ? AND read_at IS NULL")
    .bind(me.id)
    .run();
  return c.json({ ok: true, unread: 0 });
});

app.delete('/:id', async (c) => {
  const me = c.get('user')!;
  await c.env.DB
    .prepare('DELETE FROM notifications WHERE id = ? AND user_id = ?')
    .bind(c.req.param('id'), me.id)
    .run();
  return c.json({ ok: true });
});

app.delete('/', async (c) => {
  const me = c.get('user')!;
  await c.env.DB.prepare('DELETE FROM notifications WHERE user_id = ?').bind(me.id).run();
  return c.json({ ok: true, unread: 0 });
});

export default app;
