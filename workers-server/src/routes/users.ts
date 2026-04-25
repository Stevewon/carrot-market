import { Hono } from 'hono';
import type { Env, UserRow, UserPublic, Variables } from '../types';
import { authMiddleware } from '../jwt';
import { regionCenter, haversineKm, REGION_VERIFY_RADIUS_KM } from '../regions';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

function sanitize(u: UserRow): UserPublic {
  return {
    id: u.id,
    nickname: u.nickname,
    device_uuid: u.device_uuid,
    wallet_address: u.wallet_address,
    region: u.region,
    region_verified_at: u.region_verified_at,
    manner_score: u.manner_score,
    qta_balance: u.qta_balance ?? 0,
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

/**
 * POST /api/users/me/region/verify
 *
 * 동네 인증 (당근식). 클라이언트가 GPS 좌표를 보내면 현재 region 의 중심점에서
 * REGION_VERIFY_RADIUS_KM(=4km) 안에 있는지만 검증한다.
 *
 * 사생활 보호:
 *   - 정확한 GPS 는 검증 직후 폐기. DB 에는 region 중심 좌표만 저장.
 *   - 같은 동네 모든 사용자는 같은 점을 갖는다 → 다른 사용자에게 노출되지 않는다.
 *   - 응답으로도 본인의 region/verified_at 만 돌려준다.
 *
 * Body: { lat: number, lng: number, region?: string }
 *   region 이 들어오면 그 region 으로 동시에 변경하면서 인증한다.
 *   region 이 없으면 현재 저장된 user.region 을 사용한다.
 */
app.post('/me/region/verify', authMiddleware, async (c) => {
  const me = c.get('user')!;
  let body: { lat?: number; lng?: number; region?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const lat = Number(body.lat);
  const lng = Number(body.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)
      || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return c.json({ error: 'GPS 좌표가 유효하지 않아요' }, 400);
  }

  // 현재 또는 새 region 결정.
  let region = (body.region || '').trim();
  if (!region) {
    const cur = await c.env.DB
      .prepare('SELECT region FROM users WHERE id = ?')
      .bind(me.id)
      .first<{ region: string | null }>();
    region = cur?.region || '';
  }
  if (!region) {
    return c.json({ error: '먼저 동네를 선택해주세요' }, 400);
  }

  const center = regionCenter(region);
  if (!center) {
    return c.json({ error: '지원하지 않는 지역이에요' }, 400);
  }

  const dist = haversineKm({ lat, lng }, center);
  if (dist > REGION_VERIFY_RADIUS_KM) {
    return c.json({
      error: '내 동네에서 너무 멀어요',
      distance_km: Math.round(dist * 10) / 10,
      radius_km: REGION_VERIFY_RADIUS_KM,
    }, 403);
  }

  // 검증 통과 — 정확한 좌표는 버리고 region 중심점만 저장.
  const nowIso = new Date().toISOString();
  await c.env.DB
    .prepare(
      `UPDATE users
         SET region = ?, lat = ?, lng = ?,
             region_verified_at = ?, updated_at = datetime('now')
       WHERE id = ?`
    )
    .bind(region, center.lat, center.lng, nowIso, me.id)
    .run();

  return c.json({
    ok: true,
    region,
    region_verified_at: nowIso,
    distance_km: Math.round(dist * 10) / 10,
  });
});

/**
 * GET /api/users/me/qta/ledger?limit=30
 *
 * 본인 QTA 잔액 + 최근 변동 내역. 본인 외에는 절대 조회 불가.
 * 응답: { balance, items: [{amount, reason, created_at, meta}] }
 */
app.get('/me/qta/ledger', authMiddleware, async (c) => {
  const me = c.get('user')!;
  const limit = Math.min(100, parseInt(c.req.query('limit') || '30', 10) || 30);

  const userRow = await c.env.DB
    .prepare('SELECT qta_balance FROM users WHERE id = ?')
    .bind(me.id)
    .first<{ qta_balance: number }>();

  const rs = await c.env.DB
    .prepare(
      `SELECT amount, reason, meta, created_at
         FROM qta_ledger
        WHERE user_id = ?
        ORDER BY created_at DESC
        LIMIT ?`,
    )
    .bind(me.id, limit)
    .all<{
      amount: number;
      reason: string;
      meta: string | null;
      created_at: string;
    }>();

  return c.json({
    balance: userRow?.qta_balance ?? 0,
    items: (rs.results || []).map((r) => ({
      amount: r.amount,
      reason: r.reason,
      meta: r.meta ? safeJson(r.meta) : null,
      created_at: r.created_at,
    })),
  });
});

function safeJson(s: string): unknown {
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}

/**
 * GET /api/users/search?nickname=xxx
 *
 * 닉네임 부분 일치(대소문자 무시) 검색. 거래완료 시 판매자가 구매자를 직접
 * 닉네임으로 찾기 위해 사용된다 (휘발성 채팅이라 chat_rooms 로 구매자 후보를
 * 뽑을 수 없음). 자기 자신은 결과에서 제외하고, 최대 20명만 반환한다.
 *
 * 응답에는 wallet_address / device_uuid 같은 식별자는 절대 포함되지 않는다.
 */
app.get('/search', authMiddleware, async (c) => {
  const me = c.get('user')!;
  const q = (c.req.query('nickname') || '').trim();
  if (q.length < 1) {
    return c.json({ users: [] });
  }
  const like = `%${q.replace(/[%_]/g, '\\$&')}%`;
  const { results } = await c.env.DB
    .prepare(
      `SELECT id, nickname, manner_score, region
         FROM users
        WHERE nickname LIKE ? ESCAPE '\\' COLLATE NOCASE
          AND id != ?
        ORDER BY
          CASE WHEN nickname = ? COLLATE NOCASE THEN 0 ELSE 1 END,
          length(nickname) ASC
        LIMIT 20`
    )
    .bind(like, me.id, q)
    .all<{ id: string; nickname: string; manner_score: number; region: string | null }>();
  return c.json({ users: results || [] });
});

export default app;
