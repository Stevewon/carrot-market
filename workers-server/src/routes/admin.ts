/**
 * Eggplant 🍆 Admin API
 *
 * 모든 라우트는 requireAdminToken 미들웨어로 보호됨.
 * 헤더: Authorization: Admin <ADMIN_TOKEN>
 *
 * 6대 기능:
 *   ① 사용자 관리 (목록/차단/해제/검증)
 *   ② 상품 관리 (목록/숨김/해제/삭제)
 *   ③ QKEY 거래 원장 조회 (read-only)
 *   ④ 매출/통계 대시보드 (집계)
 *   ⑤ 공지/푸시 발송 (notices CRUD)
 *   ⑥ 신고 처리 (목록/처리)
 *
 * 모든 액션은 admin_audit 에 기록됨.
 */
import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { requireAdminToken } from '../jwt';

const admin = new Hono<{ Bindings: Env; Variables: Variables }>();

// 모든 어드민 라우트에 토큰 검증 적용
admin.use('*', requireAdminToken);

// ────────────────────────────────────────────────────────────────────
// 공통 헬퍼
// ────────────────────────────────────────────────────────────────────
async function audit(
  c: any,
  action: string,
  targetId: string | null,
  payload: any,
) {
  const ip =
    c.req.header('cf-connecting-ip') ||
    c.req.header('x-forwarded-for') ||
    '';
  const ua = c.req.header('user-agent') || '';
  try {
    await c.env.DB.prepare(
      `INSERT INTO admin_audit (action, target_id, payload_json, ip, user_agent)
       VALUES (?, ?, ?, ?, ?)`,
    )
      .bind(action, targetId, JSON.stringify(payload ?? {}), ip, ua)
      .run();
  } catch {
    // 감사 로그 기록 실패해도 원래 액션은 진행
  }
}

function clampLimit(v: any, def = 50, max = 200): number {
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) return def;
  return Math.min(Math.floor(n), max);
}

// ────────────────────────────────────────────────────────────────────
// Health (토큰 검증용)
// ────────────────────────────────────────────────────────────────────
admin.get('/health', (c) =>
  c.json({ ok: true, scope: 'admin', server_time: new Date().toISOString() }),
);

// ────────────────────────────────────────────────────────────────────
// ① 사용자 관리
// ────────────────────────────────────────────────────────────────────

// 사용자 목록 (검색/페이지네이션)
admin.get('/users', async (c) => {
  const q = (c.req.query('q') || '').trim();
  const blocked = c.req.query('blocked'); // '1' | '0' | undefined
  const limit = clampLimit(c.req.query('limit'));
  const offset = Number(c.req.query('offset')) || 0;

  let sql = `SELECT id, nickname, wallet_address, region, manner_score,
                    qta_balance, verification_level, is_blocked, blocked_at,
                    blocked_reason, created_at
             FROM users WHERE 1=1`;
  const params: any[] = [];
  if (q) {
    sql += ` AND (nickname LIKE ? OR wallet_address LIKE ?)`;
    params.push(`%${q}%`, `%${q}%`);
  }
  if (blocked === '1') sql += ` AND is_blocked = 1`;
  if (blocked === '0') sql += ` AND is_blocked = 0`;
  sql += ` ORDER BY created_at DESC LIMIT ? OFFSET ?`;
  params.push(limit, offset);

  const { results } = await c.env.DB.prepare(sql).bind(...params).all();
  return c.json({ items: results, limit, offset });
});

// 사용자 상세
admin.get('/users/:id', async (c) => {
  const id = c.req.param('id');
  const user = await c.env.DB.prepare(`SELECT * FROM users WHERE id = ?`)
    .bind(id)
    .first();
  if (!user) return c.json({ error: 'not found' }, 404);

  // 신고 받은 횟수
  const reportCount = await c.env.DB.prepare(
    `SELECT COUNT(*) as n FROM user_reports WHERE reported_id = ?`,
  )
    .bind(id)
    .first<{ n: number }>();

  // 등록 상품 수
  const productCount = await c.env.DB.prepare(
    `SELECT COUNT(*) as n FROM products WHERE seller_id = ?`,
  )
    .bind(id)
    .first<{ n: number }>();

  return c.json({
    user,
    stats: {
      reports_received: reportCount?.n ?? 0,
      products_count: productCount?.n ?? 0,
    },
  });
});

// 사용자 차단
admin.post('/users/:id/block', async (c) => {
  const id = c.req.param('id');
  const body = await c.req.json<{ reason?: string }>().catch(() => ({}));
  const reason = (body.reason || '').slice(0, 200);

  const r = await c.env.DB.prepare(
    `UPDATE users
     SET is_blocked = 1, blocked_at = datetime('now'), blocked_reason = ?,
         token_version = token_version + 1
     WHERE id = ?`,
  )
    .bind(reason, id)
    .run();

  if (r.meta.changes === 0) return c.json({ error: 'not found' }, 404);
  await audit(c, 'user.block', id, { reason });
  return c.json({ ok: true });
});

// 사용자 차단 해제
admin.post('/users/:id/unblock', async (c) => {
  const id = c.req.param('id');
  const r = await c.env.DB.prepare(
    `UPDATE users SET is_blocked = 0, blocked_at = NULL, blocked_reason = NULL
     WHERE id = ?`,
  )
    .bind(id)
    .run();
  if (r.meta.changes === 0) return c.json({ error: 'not found' }, 404);
  await audit(c, 'user.unblock', id, {});
  return c.json({ ok: true });
});

// 사용자 검증 단계 강제 변경 (운영자 수동 검증)
admin.post('/users/:id/verify', async (c) => {
  const id = c.req.param('id');
  const body = await c.req.json<{ level: number }>().catch(() => ({ level: 0 }));
  const lv = Math.max(0, Math.min(2, Math.floor(Number(body.level) || 0)));

  const r = await c.env.DB.prepare(
    `UPDATE users SET verification_level = ?, verified_at = datetime('now')
     WHERE id = ?`,
  )
    .bind(lv, id)
    .run();
  if (r.meta.changes === 0) return c.json({ error: 'not found' }, 404);
  await audit(c, 'user.verify', id, { level: lv });
  return c.json({ ok: true, level: lv });
});

// ────────────────────────────────────────────────────────────────────
// ② 상품 관리
// ────────────────────────────────────────────────────────────────────

admin.get('/products', async (c) => {
  const q = (c.req.query('q') || '').trim();
  const hidden = c.req.query('hidden'); // '1' | '0' | undefined
  const limit = clampLimit(c.req.query('limit'));
  const offset = Number(c.req.query('offset')) || 0;

  let sql = `SELECT p.id, p.title, p.price, p.qta_amount, p.status,
                    p.hidden_by_admin, p.hidden_reason, p.seller_id,
                    p.region, p.created_at,
                    u.nickname as seller_nickname
             FROM products p
             LEFT JOIN users u ON u.id = p.seller_id
             WHERE 1=1`;
  const params: any[] = [];
  if (q) {
    sql += ` AND p.title LIKE ?`;
    params.push(`%${q}%`);
  }
  if (hidden === '1') sql += ` AND p.hidden_by_admin = 1`;
  if (hidden === '0') sql += ` AND p.hidden_by_admin = 0`;
  sql += ` ORDER BY p.created_at DESC LIMIT ? OFFSET ?`;
  params.push(limit, offset);

  const { results } = await c.env.DB.prepare(sql).bind(...params).all();
  return c.json({ items: results, limit, offset });
});

admin.post('/products/:id/hide', async (c) => {
  const id = c.req.param('id');
  const body = await c.req.json<{ reason?: string }>().catch(() => ({}));
  const reason = (body.reason || '').slice(0, 200);
  const r = await c.env.DB.prepare(
    `UPDATE products
     SET hidden_by_admin = 1, hidden_at = datetime('now'), hidden_reason = ?
     WHERE id = ?`,
  )
    .bind(reason, id)
    .run();
  if (r.meta.changes === 0) return c.json({ error: 'not found' }, 404);
  await audit(c, 'product.hide', id, { reason });
  return c.json({ ok: true });
});

admin.post('/products/:id/unhide', async (c) => {
  const id = c.req.param('id');
  const r = await c.env.DB.prepare(
    `UPDATE products SET hidden_by_admin = 0, hidden_at = NULL, hidden_reason = NULL
     WHERE id = ?`,
  )
    .bind(id)
    .run();
  if (r.meta.changes === 0) return c.json({ error: 'not found' }, 404);
  await audit(c, 'product.unhide', id, {});
  return c.json({ ok: true });
});

admin.delete('/products/:id', async (c) => {
  const id = c.req.param('id');
  const r = await c.env.DB.prepare(`DELETE FROM products WHERE id = ?`)
    .bind(id)
    .run();
  if (r.meta.changes === 0) return c.json({ error: 'not found' }, 404);
  await audit(c, 'product.delete', id, {});
  return c.json({ ok: true });
});

// ────────────────────────────────────────────────────────────────────
// ③ QKEY 거래 원장 조회 (read-only) — D1 의 qta_transactions 활용
// ────────────────────────────────────────────────────────────────────

admin.get('/qkey/transactions', async (c) => {
  const userId = c.req.query('user_id');
  const limit = clampLimit(c.req.query('limit'), 100);
  const offset = Number(c.req.query('offset')) || 0;

  // qta_transactions 가 0014 마이그레이션에 있다고 가정
  let sql = `SELECT * FROM qta_transactions WHERE 1=1`;
  const params: any[] = [];
  if (userId) {
    sql += ` AND (from_user_id = ? OR to_user_id = ?)`;
    params.push(userId, userId);
  }
  sql += ` ORDER BY created_at DESC LIMIT ? OFFSET ?`;
  params.push(limit, offset);

  try {
    const { results } = await c.env.DB.prepare(sql).bind(...params).all();
    return c.json({ items: results, limit, offset });
  } catch (e: any) {
    // 테이블 없으면 빈 결과 (마이그레이션 차이 대비)
    return c.json({ items: [], limit, offset, note: 'qta_transactions not available' });
  }
});

// 출금 요청 목록
admin.get('/qkey/withdrawals', async (c) => {
  const status = c.req.query('status');
  const limit = clampLimit(c.req.query('limit'), 100);
  const offset = Number(c.req.query('offset')) || 0;

  let sql = `SELECT w.*, u.nickname FROM withdrawals w
             LEFT JOIN users u ON u.id = w.user_id
             WHERE 1=1`;
  const params: any[] = [];
  if (status) {
    sql += ` AND w.status = ?`;
    params.push(status);
  }
  sql += ` ORDER BY w.created_at DESC LIMIT ? OFFSET ?`;
  params.push(limit, offset);

  try {
    const { results } = await c.env.DB.prepare(sql).bind(...params).all();
    return c.json({ items: results, limit, offset });
  } catch {
    return c.json({ items: [], limit, offset, note: 'withdrawals not available' });
  }
});

// ────────────────────────────────────────────────────────────────────
// ④ 매출/통계 대시보드
// ────────────────────────────────────────────────────────────────────

admin.get('/stats/overview', async (c) => {
  // 단일 응답에 핵심 KPI 모두 포함 (대시보드 첫 화면용)
  const [users, products, blockedUsers, hiddenProducts, pendingReports] =
    await Promise.all([
      c.env.DB.prepare(`SELECT COUNT(*) as n FROM users`).first<{ n: number }>(),
      c.env.DB.prepare(`SELECT COUNT(*) as n FROM products`).first<{ n: number }>(),
      c.env.DB.prepare(
        `SELECT COUNT(*) as n FROM users WHERE is_blocked = 1`,
      ).first<{ n: number }>(),
      c.env.DB.prepare(
        `SELECT COUNT(*) as n FROM products WHERE hidden_by_admin = 1`,
      ).first<{ n: number }>(),
      c.env.DB.prepare(
        `SELECT COUNT(*) as n FROM user_reports WHERE status = 'pending'`,
      ).first<{ n: number }>(),
    ]);

  // 최근 7일 가입자 / 등록 상품
  const recentUsers = await c.env.DB.prepare(
    `SELECT date(created_at) as day, COUNT(*) as n
     FROM users
     WHERE created_at >= date('now', '-7 days')
     GROUP BY date(created_at)
     ORDER BY day DESC`,
  ).all();
  const recentProducts = await c.env.DB.prepare(
    `SELECT date(created_at) as day, COUNT(*) as n
     FROM products
     WHERE created_at >= date('now', '-7 days')
     GROUP BY date(created_at)
     ORDER BY day DESC`,
  ).all();

  return c.json({
    totals: {
      users: users?.n ?? 0,
      products: products?.n ?? 0,
      blocked_users: blockedUsers?.n ?? 0,
      hidden_products: hiddenProducts?.n ?? 0,
      pending_reports: pendingReports?.n ?? 0,
    },
    recent_users_7d: recentUsers.results,
    recent_products_7d: recentProducts.results,
  });
});

// ────────────────────────────────────────────────────────────────────
// ⑤ 공지/푸시 발송
// ────────────────────────────────────────────────────────────────────

admin.get('/notices', async (c) => {
  const active = c.req.query('active'); // '1' | '0' | undefined
  let sql = `SELECT * FROM notices WHERE 1=1`;
  const params: any[] = [];
  if (active === '1') sql += ` AND active = 1`;
  if (active === '0') sql += ` AND active = 0`;
  sql += ` ORDER BY created_at DESC LIMIT 100`;
  const { results } = await c.env.DB.prepare(sql).bind(...params).all();
  return c.json({ items: results });
});

admin.post('/notices', async (c) => {
  const body = await c.req.json<{
    type?: string;
    target?: string;
    target_value?: string;
    title?: string;
    body?: string;
    link_url?: string;
    starts_at?: string;
    ends_at?: string;
  }>().catch(() => ({}));

  const type = body.type || 'notice';
  const target = body.target || 'all';
  const title = (body.title || '').trim();
  if (!title) return c.json({ error: 'title required' }, 400);
  if (!['notice', 'push', 'banner'].includes(type)) {
    return c.json({ error: 'invalid type' }, 400);
  }
  if (!['all', 'region', 'user'].includes(target)) {
    return c.json({ error: 'invalid target' }, 400);
  }

  const r = await c.env.DB.prepare(
    `INSERT INTO notices (type, target, target_value, title, body, link_url,
                          starts_at, ends_at, active)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)`,
  )
    .bind(
      type,
      target,
      body.target_value || null,
      title,
      body.body || '',
      body.link_url || null,
      body.starts_at || null,
      body.ends_at || null,
    )
    .run();

  const newId = r.meta.last_row_id as number | undefined;
  await audit(c, 'notice.create', String(newId ?? ''), { type, target, title });
  return c.json({ ok: true, id: newId });
});

admin.delete('/notices/:id', async (c) => {
  const id = c.req.param('id');
  const r = await c.env.DB.prepare(`DELETE FROM notices WHERE id = ?`)
    .bind(id)
    .run();
  if (r.meta.changes === 0) return c.json({ error: 'not found' }, 404);
  await audit(c, 'notice.delete', id, {});
  return c.json({ ok: true });
});

// 활성/비활성 토글
admin.post('/notices/:id/toggle', async (c) => {
  const id = c.req.param('id');
  const r = await c.env.DB.prepare(
    `UPDATE notices SET active = 1 - active WHERE id = ?`,
  )
    .bind(id)
    .run();
  if (r.meta.changes === 0) return c.json({ error: 'not found' }, 404);
  await audit(c, 'notice.toggle', id, {});
  return c.json({ ok: true });
});

// ────────────────────────────────────────────────────────────────────
// ⑥ 신고 처리
// ────────────────────────────────────────────────────────────────────

admin.get('/reports', async (c) => {
  const status = c.req.query('status') || 'pending';
  const limit = clampLimit(c.req.query('limit'), 100);
  const offset = Number(c.req.query('offset')) || 0;

  const { results } = await c.env.DB.prepare(
    `SELECT r.*,
            ur.nickname as reporter_nickname,
            ud.nickname as reported_nickname
     FROM user_reports r
     LEFT JOIN users ur ON ur.id = r.reporter_id
     LEFT JOIN users ud ON ud.id = r.reported_id
     WHERE r.status = ?
     ORDER BY r.created_at DESC
     LIMIT ? OFFSET ?`,
  )
    .bind(status, limit, offset)
    .all();
  return c.json({ items: results, limit, offset });
});

admin.post('/reports/:id/resolve', async (c) => {
  const id = c.req.param('id');
  const body = await c.req.json<{ note?: string }>().catch(() => ({}));
  const r = await c.env.DB.prepare(
    `UPDATE user_reports
     SET status = 'resolved', resolved_at = datetime('now'), resolved_note = ?
     WHERE id = ?`,
  )
    .bind((body.note || '').slice(0, 500), id)
    .run();
  if (r.meta.changes === 0) return c.json({ error: 'not found' }, 404);
  await audit(c, 'report.resolve', id, { note: body.note });
  return c.json({ ok: true });
});

admin.post('/reports/:id/dismiss', async (c) => {
  const id = c.req.param('id');
  const body = await c.req.json<{ note?: string }>().catch(() => ({}));
  const r = await c.env.DB.prepare(
    `UPDATE user_reports
     SET status = 'dismissed', resolved_at = datetime('now'), resolved_note = ?
     WHERE id = ?`,
  )
    .bind((body.note || '').slice(0, 500), id)
    .run();
  if (r.meta.changes === 0) return c.json({ error: 'not found' }, 404);
  await audit(c, 'report.dismiss', id, { note: body.note });
  return c.json({ ok: true });
});

// ────────────────────────────────────────────────────────────────────
// 감사 로그 조회 (어드민이 자신의 액션 기록 확인)
// ────────────────────────────────────────────────────────────────────

admin.get('/audit', async (c) => {
  const limit = clampLimit(c.req.query('limit'), 100);
  const offset = Number(c.req.query('offset')) || 0;
  const { results } = await c.env.DB.prepare(
    `SELECT * FROM admin_audit ORDER BY created_at DESC LIMIT ? OFFSET ?`,
  )
    .bind(limit, offset)
    .all();
  return c.json({ items: results, limit, offset });
});

export default admin;
