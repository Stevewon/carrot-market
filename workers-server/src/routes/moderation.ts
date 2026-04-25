/**
 * Moderation endpoints — block (차단) + report (신고).
 *
 *   POST   /api/moderation/block    { user_id }              -> block a user
 *   DELETE /api/moderation/block/:userId                     -> unblock
 *   GET    /api/moderation/blocks                            -> my block list
 *   POST   /api/moderation/report   { user_id, reason, product_id?, detail? }
 *
 * All routes require authentication.
 */

import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { authMiddleware } from '../jwt';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use('*', authMiddleware);

const VALID_REASONS = new Set([
  'spam',
  'fraud',
  'abuse',
  'inappropriate',
  'fake',
  'other',
]);

// ── Block ────────────────────────────────────────────────────────────

app.post('/block', async (c) => {
  const me = c.get('user')!;
  let body: { user_id?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }
  const target = (body.user_id || '').trim();
  if (!target) return c.json({ error: 'user_id is required' }, 400);
  if (target === me.id) {
    return c.json({ error: '자기 자신을 차단할 수 없어요' }, 400);
  }

  // Confirm the target exists.
  const exists = await c.env.DB
    .prepare('SELECT id FROM users WHERE id = ?')
    .bind(target)
    .first<{ id: string }>();
  if (!exists) return c.json({ error: '대상을 찾을 수 없어요' }, 404);

  // INSERT OR IGNORE so a re-block is a no-op.
  await c.env.DB
    .prepare(
      `INSERT OR IGNORE INTO user_blocks (blocker_id, blocked_id)
       VALUES (?, ?)`
    )
    .bind(me.id, target)
    .run();

  return c.json({ ok: true, blocked: true });
});

app.delete('/block/:userId', async (c) => {
  const me = c.get('user')!;
  const target = c.req.param('userId');
  await c.env.DB
    .prepare(
      'DELETE FROM user_blocks WHERE blocker_id = ? AND blocked_id = ?'
    )
    .bind(me.id, target)
    .run();
  return c.json({ ok: true, blocked: false });
});

app.get('/blocks', async (c) => {
  const me = c.get('user')!;
  const rs = await c.env.DB
    .prepare(
      `SELECT b.blocked_id, b.created_at,
              u.nickname, u.region, u.manner_score
         FROM user_blocks b
         JOIN users u ON u.id = b.blocked_id
        WHERE b.blocker_id = ?
        ORDER BY b.created_at DESC`
    )
    .bind(me.id)
    .all();
  return c.json({ blocks: rs.results || [] });
});

// ── Report ───────────────────────────────────────────────────────────

app.post('/report', async (c) => {
  const me = c.get('user')!;
  let body: {
    user_id?: string;
    reason?: string;
    product_id?: string;
    detail?: string;
  } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const target = (body.user_id || '').trim();
  const reason = (body.reason || '').trim();
  const productId = (body.product_id || '').trim() || null;
  const detail = (body.detail || '').trim().slice(0, 500);

  if (!target) return c.json({ error: 'user_id is required' }, 400);
  if (target === me.id) {
    return c.json({ error: '자기 자신을 신고할 수 없어요' }, 400);
  }
  if (!VALID_REASONS.has(reason)) {
    return c.json({ error: '신고 사유가 올바르지 않아요' }, 400);
  }

  // Make sure target exists.
  const exists = await c.env.DB
    .prepare('SELECT id FROM users WHERE id = ?')
    .bind(target)
    .first<{ id: string }>();
  if (!exists) return c.json({ error: '대상을 찾을 수 없어요' }, 404);

  try {
    await c.env.DB
      .prepare(
        `INSERT INTO user_reports
           (reporter_id, reported_id, product_id, reason, detail)
         VALUES (?, ?, ?, ?, ?)`
      )
      .bind(me.id, target, productId, reason, detail)
      .run();
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    if (/UNIQUE constraint failed/.test(msg)) {
      // Same reporter+reported+reason is allowed only once — treat repeat as success.
      return c.json({ ok: true, duplicate: true });
    }
    console.error('[moderation/report] failed:', msg);
    return c.json({ error: '신고 접수 중 오류가 발생했어요' }, 500);
  }

  return c.json({ ok: true });
});

export default app;
