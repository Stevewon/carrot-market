/**
 * Admin Web Console Routes — https://eggplant.life/admin/
 *
 * 인증:
 *   POST /api/admin/login            { username, password }  -> { token, must_change_pw }
 *   POST /api/admin/logout                                    -> { ok }
 *   POST /api/admin/change-password  { old, new }            -> { ok }
 *   GET  /api/admin/me                                        -> 어드민 본인 정보
 *
 * 대시보드:
 *   GET  /api/admin/stats                                     -> 통계 요약
 *
 * 사용자:
 *   GET  /api/admin/users?q=...&banned=0&limit=50&offset=0   -> 사용자 목록
 *   GET  /api/admin/users/:id                                -> 사용자 상세
 *   POST /api/admin/users/:id/ban     { reason }             -> 정지
 *   POST /api/admin/users/:id/unban                          -> 정지 해제
 *
 * 상품:
 *   GET  /api/admin/products?q=...&status=...                -> 상품 목록
 *   POST /api/admin/products/:id/hide  { reason }            -> 강제 숨김 (status=sold 처리)
 *
 * 신고:
 *   GET  /api/admin/reports?status=pending                   -> 신고 큐
 *   POST /api/admin/reports/:id/resolve { note }             -> 처리 완료
 *   POST /api/admin/reports/:id/dismiss { note }             -> 반려
 *
 * 출금 (기존 /api/withdrawals/admin/* 라우트와 별도 — 어드민 콘솔 통합용):
 *   GET  /api/admin/withdrawals/pending                      -> 대기 큐
 *
 * 감사 로그:
 *   GET  /api/admin/audit?limit=100&offset=0                 -> 최근 액션 기록
 *
 * 인증 방식:
 *   - login 시 admin_sessions 테이블에 토큰 발급 (12시간 TTL)
 *   - 이후 요청은 Authorization: Bearer <admin_token> 헤더로 전달
 *   - adminAuth 미들웨어가 매 요청마다 세션·만료 확인
 *   - 모든 mutating 액션은 admin_audit_log 에 기록
 */

import { Hono } from 'hono';
import type { Context, MiddlewareHandler } from 'hono';
import type { Env, Variables } from '../types';
import { hashPassword, verifyPassword } from '../crypto';

// ────────────────────────────────────────────────────────────────────
// Admin Variables (추가 컨텍스트)
// ────────────────────────────────────────────────────────────────────
type AdminVariables = Variables & {
  admin?: {
    id: string;
    username: string;
    role: string;
  };
};

const app = new Hono<{ Bindings: Env; Variables: AdminVariables }>();

// ────────────────────────────────────────────────────────────────────
// 유틸리티
// ────────────────────────────────────────────────────────────────────

const SESSION_TTL_HOURS = 12;

function genToken(): string {
  // 32 bytes hex = 64 chars
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function genId(): string {
  // uuid v4
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function clientIp(c: Context): string {
  return (
    c.req.header('cf-connecting-ip') ||
    c.req.header('x-forwarded-for')?.split(',')[0].trim() ||
    ''
  );
}

async function audit(
  c: Context<{ Bindings: Env; Variables: AdminVariables }>,
  action: string,
  targetType: string | null,
  targetId: string | null,
  detail: string | null,
): Promise<void> {
  const admin = c.get('admin');
  if (!admin) return;
  try {
    await c.env.DB
      .prepare(
        `INSERT INTO admin_audit_log (admin_id, action, target_type, target_id, detail, ip)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .bind(admin.id, action, targetType, targetId, detail, clientIp(c))
      .run();
  } catch {
    // 감사 로그 실패는 무시 (메인 액션은 이미 성공)
  }
}

// ────────────────────────────────────────────────────────────────────
// 미들웨어: 어드민 세션 검증
// ────────────────────────────────────────────────────────────────────

const adminAuth: MiddlewareHandler<{
  Bindings: Env;
  Variables: AdminVariables;
}> = async (c, next) => {
  const header = c.req.header('authorization') || c.req.header('Authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!token) return c.json({ error: 'admin token required' }, 401);

  const row = await c.env.DB
    .prepare(
      `SELECT s.admin_id, s.expires_at, s.revoked_at,
              a.username, a.role, a.is_active
         FROM admin_sessions s
         JOIN admins a ON a.id = s.admin_id
        WHERE s.id = ?`,
    )
    .bind(token)
    .first<{
      admin_id: string;
      expires_at: string;
      revoked_at: string | null;
      username: string;
      role: string;
      is_active: number;
    }>();

  if (!row) return c.json({ error: 'invalid session' }, 401);
  if (row.revoked_at) return c.json({ error: 'session revoked' }, 401);
  if (!row.is_active) return c.json({ error: 'admin disabled' }, 403);
  if (new Date(row.expires_at + 'Z').getTime() < Date.now()) {
    return c.json({ error: 'session expired' }, 401);
  }

  c.set('admin', { id: row.admin_id, username: row.username, role: row.role });
  await next();
};

// ────────────────────────────────────────────────────────────────────
// 인증 라우트 (미들웨어 없음)
// ────────────────────────────────────────────────────────────────────

/** POST /api/admin/login */
app.post('/login', async (c) => {
  let body: { username?: string; password?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }
  const username = (body.username || '').trim().toLowerCase();
  const password = body.password || '';
  if (!username || !password) {
    return c.json({ error: '아이디와 비밀번호를 입력해주세요' }, 400);
  }

  const admin = await c.env.DB
    .prepare(
      `SELECT id, username, password_hash, role, is_active, must_change_pw
         FROM admins WHERE username = ?`,
    )
    .bind(username)
    .first<{
      id: string;
      username: string;
      password_hash: string;
      role: string;
      is_active: number;
      must_change_pw: number;
    }>();

  if (!admin || !admin.is_active) {
    return c.json({ error: '아이디 또는 비밀번호가 일치하지 않아요' }, 401);
  }

  const ok = await verifyPassword(password, admin.password_hash);
  if (!ok) {
    return c.json({ error: '아이디 또는 비밀번호가 일치하지 않아요' }, 401);
  }

  const token = genToken();
  const expiresAt = new Date(Date.now() + SESSION_TTL_HOURS * 3600 * 1000)
    .toISOString()
    .replace('T', ' ')
    .slice(0, 19);

  await c.env.DB
    .prepare(
      `INSERT INTO admin_sessions (id, admin_id, ip, user_agent, expires_at)
       VALUES (?, ?, ?, ?, ?)`,
    )
    .bind(token, admin.id, clientIp(c), c.req.header('user-agent') || '', expiresAt)
    .run();

  await c.env.DB
    .prepare(`UPDATE admins SET last_login_at = datetime('now') WHERE id = ?`)
    .bind(admin.id)
    .run();

  // 감사 로그 (별도 — admin context 가 아직 set 안됨)
  await c.env.DB
    .prepare(
      `INSERT INTO admin_audit_log (admin_id, action, target_type, target_id, detail, ip)
       VALUES (?, 'login', 'admin', ?, NULL, ?)`,
    )
    .bind(admin.id, admin.id, clientIp(c))
    .run();

  return c.json({
    token,
    expires_at: expiresAt,
    must_change_pw: admin.must_change_pw === 1,
    admin: { id: admin.id, username: admin.username, role: admin.role },
  });
});

// 이하 모든 라우트는 admin 인증 필요
app.use('*', adminAuth);

/** GET /api/admin/me */
app.get('/me', async (c) => {
  const admin = c.get('admin')!;
  const row = await c.env.DB
    .prepare(
      `SELECT id, username, email, role, must_change_pw, last_login_at, created_at
         FROM admins WHERE id = ?`,
    )
    .bind(admin.id)
    .first();
  return c.json({ admin: row });
});

/** POST /api/admin/logout */
app.post('/logout', async (c) => {
  const header = c.req.header('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (token) {
    await c.env.DB
      .prepare(`UPDATE admin_sessions SET revoked_at = datetime('now') WHERE id = ?`)
      .bind(token)
      .run();
  }
  await audit(c, 'logout', 'admin', c.get('admin')!.id, null);
  return c.json({ ok: true });
});

/** POST /api/admin/change-password */
app.post('/change-password', async (c) => {
  const me = c.get('admin')!;
  let body: { old?: string; new?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }
  const oldPw = body.old || '';
  const newPw = body.new || '';
  if (newPw.length < 8 || newPw.length > 64) {
    return c.json({ error: '새 비밀번호는 8~64자' }, 400);
  }
  if (oldPw === newPw) {
    return c.json({ error: '새 비밀번호가 기존과 같아요' }, 400);
  }

  const row = await c.env.DB
    .prepare(`SELECT password_hash FROM admins WHERE id = ?`)
    .bind(me.id)
    .first<{ password_hash: string }>();
  if (!row || !(await verifyPassword(oldPw, row.password_hash))) {
    return c.json({ error: '기존 비밀번호가 일치하지 않아요' }, 401);
  }

  const newHash = await hashPassword(newPw);
  await c.env.DB
    .prepare(
      `UPDATE admins SET password_hash = ?, must_change_pw = 0 WHERE id = ?`,
    )
    .bind(newHash, me.id)
    .run();

  await audit(c, 'change_password', 'admin', me.id, null);
  return c.json({ ok: true });
});

// ────────────────────────────────────────────────────────────────────
// 대시보드 통계
// ────────────────────────────────────────────────────────────────────

/** GET /api/admin/stats */
app.get('/stats', async (c) => {
  const [
    users, usersToday, usersBanned,
    products, productsActive, productsSold,
    withdrawalsPending, withdrawalsCompleted,
    reportsPending, reportsTotal,
    qtaTotal,
  ] = await Promise.all([
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM users`).first<{ n: number }>(),
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM users WHERE created_at >= datetime('now', '-1 day')`).first<{ n: number }>(),
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM users WHERE is_banned = 1`).first<{ n: number }>(),
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM products`).first<{ n: number }>(),
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM products WHERE status = 'sale'`).first<{ n: number }>(),
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM products WHERE status = 'sold'`).first<{ n: number }>(),
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM qta_withdrawals WHERE status IN ('requested','processing')`).first<{ n: number }>(),
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM qta_withdrawals WHERE status = 'completed'`).first<{ n: number }>(),
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM user_reports WHERE status = 'pending'`).first<{ n: number }>(),
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM user_reports`).first<{ n: number }>(),
    // 잔액 합계 (조회 전용 — 절대 수정 X)
    c.env.DB.prepare(`SELECT COALESCE(SUM(qta_balance), 0) AS n FROM users`).first<{ n: number }>(),
  ]);

  return c.json({
    users: {
      total: users?.n ?? 0,
      new_today: usersToday?.n ?? 0,
      banned: usersBanned?.n ?? 0,
    },
    products: {
      total: products?.n ?? 0,
      active: productsActive?.n ?? 0,
      sold: productsSold?.n ?? 0,
    },
    withdrawals: {
      pending: withdrawalsPending?.n ?? 0,
      completed: withdrawalsCompleted?.n ?? 0,
    },
    reports: {
      pending: reportsPending?.n ?? 0,
      total: reportsTotal?.n ?? 0,
    },
    qta: {
      total_balance: qtaTotal?.n ?? 0,
    },
  });
});

// ────────────────────────────────────────────────────────────────────
// 사용자 관리 (조회 + 정지/해제만 — 영구 삭제 없음)
// ────────────────────────────────────────────────────────────────────

/** GET /api/admin/users */
app.get('/users', async (c) => {
  const q = (c.req.query('q') || '').trim();
  const banned = c.req.query('banned'); // '1' | '0' | undefined
  const limit = Math.min(parseInt(c.req.query('limit') || '50', 10) || 50, 200);
  const offset = Math.max(parseInt(c.req.query('offset') || '0', 10) || 0, 0);

  const where: string[] = [];
  const args: (string | number)[] = [];
  if (q) {
    where.push(`(nickname LIKE ? OR id LIKE ? OR wallet_address LIKE ?)`);
    args.push(`%${q}%`, `%${q}%`, `%${q}%`);
  }
  if (banned === '1') where.push(`is_banned = 1`);
  if (banned === '0') where.push(`is_banned = 0`);

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const sql =
    `SELECT id, nickname, wallet_address, region, manner_score,
            qta_balance, verification_level, is_banned, banned_at, ban_reason,
            created_at
       FROM users
       ${whereSql}
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?`;

  const rs = await c.env.DB.prepare(sql).bind(...args, limit, offset).all();
  const totalRow = await c.env.DB
    .prepare(`SELECT COUNT(*) AS n FROM users ${whereSql}`)
    .bind(...args)
    .first<{ n: number }>();

  return c.json({
    users: rs.results || [],
    total: totalRow?.n ?? 0,
    limit,
    offset,
  });
});

/** GET /api/admin/users/:id */
app.get('/users/:id', async (c) => {
  const id = c.req.param('id');
  const user = await c.env.DB
    .prepare(
      `SELECT id, nickname, wallet_address, region, manner_score,
              qta_balance, verification_level, verified_at,
              bank_registered_at, is_banned, banned_at, ban_reason,
              created_at, updated_at
         FROM users WHERE id = ?`,
    )
    .bind(id)
    .first();
  if (!user) return c.json({ error: 'not found' }, 404);

  // 추가 정보: 상품 수, 신고 받은 횟수
  const [productCount, reportCount] = await Promise.all([
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM products WHERE seller_id = ?`).bind(id).first<{ n: number }>(),
    c.env.DB.prepare(`SELECT COUNT(*) AS n FROM user_reports WHERE reported_id = ?`).bind(id).first<{ n: number }>(),
  ]);

  return c.json({
    user,
    product_count: productCount?.n ?? 0,
    report_count: reportCount?.n ?? 0,
  });
});

/** POST /api/admin/users/:id/ban */
app.post('/users/:id/ban', async (c) => {
  const id = c.req.param('id');
  let body: { reason?: string } = {};
  try { body = await c.req.json(); } catch { /* empty body ok */ }
  const reason = (body.reason || '운영자 정지').slice(0, 200);

  const u = await c.env.DB
    .prepare(`SELECT id, is_banned FROM users WHERE id = ?`)
    .bind(id)
    .first<{ id: string; is_banned: number }>();
  if (!u) return c.json({ error: 'not found' }, 404);
  if (u.is_banned) return c.json({ error: '이미 정지된 사용자에요' }, 409);

  // token_version bump 로 즉시 로그아웃 효과
  await c.env.DB
    .prepare(
      `UPDATE users
          SET is_banned = 1,
              banned_at = datetime('now'),
              ban_reason = ?,
              token_version = token_version + 1,
              updated_at = datetime('now')
        WHERE id = ?`,
    )
    .bind(reason, id)
    .run();

  await audit(c, 'ban_user', 'user', id, reason);
  return c.json({ ok: true });
});

/** POST /api/admin/users/:id/unban */
app.post('/users/:id/unban', async (c) => {
  const id = c.req.param('id');
  await c.env.DB
    .prepare(
      `UPDATE users
          SET is_banned = 0, banned_at = NULL, ban_reason = NULL,
              updated_at = datetime('now')
        WHERE id = ?`,
    )
    .bind(id)
    .run();
  await audit(c, 'unban_user', 'user', id, null);
  return c.json({ ok: true });
});

// ────────────────────────────────────────────────────────────────────
// 상품 관리 (조회 + 강제 숨김)
// ────────────────────────────────────────────────────────────────────

/** GET /api/admin/products */
app.get('/products', async (c) => {
  const q = (c.req.query('q') || '').trim();
  const status = c.req.query('status') || '';
  const limit = Math.min(parseInt(c.req.query('limit') || '50', 10) || 50, 200);
  const offset = Math.max(parseInt(c.req.query('offset') || '0', 10) || 0, 0);

  const where: string[] = [];
  const args: (string | number)[] = [];
  if (q) {
    where.push(`(p.title LIKE ? OR p.id LIKE ?)`);
    args.push(`%${q}%`, `%${q}%`);
  }
  if (status && ['sale', 'reserved', 'sold'].includes(status)) {
    where.push(`p.status = ?`);
    args.push(status);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const rs = await c.env.DB
    .prepare(
      `SELECT p.id, p.title, p.price, p.qta_price, p.category, p.region,
              p.status, p.view_count, p.like_count, p.chat_count,
              p.created_at, p.seller_id,
              u.nickname AS seller_nickname
         FROM products p
    LEFT JOIN users u ON u.id = p.seller_id
         ${whereSql}
        ORDER BY p.created_at DESC
        LIMIT ? OFFSET ?`,
    )
    .bind(...args, limit, offset)
    .all();

  const totalRow = await c.env.DB
    .prepare(`SELECT COUNT(*) AS n FROM products p ${whereSql}`)
    .bind(...args)
    .first<{ n: number }>();

  return c.json({
    products: rs.results || [],
    total: totalRow?.n ?? 0,
    limit,
    offset,
  });
});

/** POST /api/admin/products/:id/hide  — status='sold' 로 강제 처리 (영구삭제 X) */
app.post('/products/:id/hide', async (c) => {
  const id = c.req.param('id');
  let body: { reason?: string } = {};
  try { body = await c.req.json(); } catch { /* ok */ }
  const reason = (body.reason || '운영자 강제 숨김').slice(0, 200);

  const p = await c.env.DB
    .prepare(`SELECT id, status FROM products WHERE id = ?`)
    .bind(id)
    .first<{ id: string; status: string }>();
  if (!p) return c.json({ error: 'not found' }, 404);

  await c.env.DB
    .prepare(
      `UPDATE products SET status = 'sold', updated_at = datetime('now') WHERE id = ?`,
    )
    .bind(id)
    .run();

  await audit(c, 'hide_product', 'product', id, reason);
  return c.json({ ok: true });
});

// ────────────────────────────────────────────────────────────────────
// 신고 관리
// ────────────────────────────────────────────────────────────────────

/** GET /api/admin/reports */
app.get('/reports', async (c) => {
  const status = c.req.query('status') || 'pending';
  const limit = Math.min(parseInt(c.req.query('limit') || '50', 10) || 50, 200);
  const offset = Math.max(parseInt(c.req.query('offset') || '0', 10) || 0, 0);

  const validStatus = ['pending', 'reviewing', 'resolved', 'dismissed', 'all'];
  if (!validStatus.includes(status)) {
    return c.json({ error: 'invalid status' }, 400);
  }
  const where = status === 'all' ? '' : `WHERE r.status = ?`;
  const args: string[] = status === 'all' ? [] : [status];

  const rs = await c.env.DB
    .prepare(
      `SELECT r.id, r.reporter_id, r.reported_id, r.product_id, r.reason,
              r.detail, r.status,
              NULL AS handled_by,
              r.resolved_at AS handled_at,
              r.resolved_note AS admin_note,
              r.created_at,
              ur.nickname AS reporter_nickname,
              ud.nickname AS reported_nickname
         FROM user_reports r
    LEFT JOIN users ur ON ur.id = r.reporter_id
    LEFT JOIN users ud ON ud.id = r.reported_id
         ${where}
        ORDER BY r.created_at DESC
        LIMIT ? OFFSET ?`,
    )
    .bind(...args, limit, offset)
    .all();

  const totalRow = await c.env.DB
    .prepare(`SELECT COUNT(*) AS n FROM user_reports r ${where}`)
    .bind(...args)
    .first<{ n: number }>();

  return c.json({
    reports: rs.results || [],
    total: totalRow?.n ?? 0,
    limit,
    offset,
  });
});

async function handleReport(
  c: Context<{ Bindings: Env; Variables: AdminVariables }>,
  id: string,
  newStatus: 'resolved' | 'dismissed',
): Promise<Response> {
  const me = c.get('admin')!;
  let body: { note?: string } = {};
  try { body = await c.req.json(); } catch { /* ok */ }
  const note = (body.note || '').slice(0, 500);

  const r = await c.env.DB
    .prepare(`SELECT id, status FROM user_reports WHERE id = ?`)
    .bind(id)
    .first<{ id: number; status: string }>();
  if (!r) return c.json({ error: 'not found' }, 404);
  if (r.status === 'resolved' || r.status === 'dismissed') {
    return c.json({ error: `이미 처리됐어요 (${r.status})` }, 409);
  }

  await c.env.DB
    .prepare(
      `UPDATE user_reports
          SET status = ?, resolved_at = datetime('now'), resolved_note = ?
        WHERE id = ?`,
    )
    .bind(newStatus, note, id)
    .run();

  await audit(c, `report_${newStatus}`, 'report', String(id), note);
  return c.json({ ok: true });
}

/** POST /api/admin/reports/:id/resolve */
app.post('/reports/:id/resolve', (c) => handleReport(c, c.req.param('id'), 'resolved'));

/** POST /api/admin/reports/:id/dismiss */
app.post('/reports/:id/dismiss', (c) => handleReport(c, c.req.param('id'), 'dismissed'));

// ────────────────────────────────────────────────────────────────────
// 출금 (어드민 콘솔 통합용 — 기존 /api/withdrawals/admin/* 와 별도 노출)
// ────────────────────────────────────────────────────────────────────

/** GET /api/admin/withdrawals/pending */
app.get('/withdrawals/pending', async (c) => {
  const rs = await c.env.DB
    .prepare(
      `SELECT w.id, w.user_id, w.wallet_address, w.amount, w.status,
              w.requested_at, w.processed_at, w.tx_hash, w.reject_reason,
              u.nickname AS user_nickname
         FROM qta_withdrawals w
    LEFT JOIN users u ON u.id = w.user_id
        WHERE w.status IN ('requested', 'processing')
     ORDER BY w.requested_at ASC
        LIMIT 200`,
    )
    .all();
  return c.json({ rows: rs.results || [] });
});

// ────────────────────────────────────────────────────────────────────
// 감사 로그
// ────────────────────────────────────────────────────────────────────

/** GET /api/admin/audit */
app.get('/audit', async (c) => {
  const limit = Math.min(parseInt(c.req.query('limit') || '100', 10) || 100, 500);
  const offset = Math.max(parseInt(c.req.query('offset') || '0', 10) || 0, 0);

  const rs = await c.env.DB
    .prepare(
      `SELECT l.id, l.admin_id, l.action, l.target_type, l.target_id,
              l.detail, l.ip, l.created_at,
              a.username AS admin_username
         FROM admin_audit_log l
    LEFT JOIN admins a ON a.id = l.admin_id
        ORDER BY l.created_at DESC
        LIMIT ? OFFSET ?`,
    )
    .bind(limit, offset)
    .all();

  return c.json({ logs: rs.results || [] });
});

export default app;
