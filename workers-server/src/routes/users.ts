import { Hono } from 'hono';
import type { Env, UserRow, UserPublic, Variables } from '../types';
import { authMiddleware } from '../jwt';
import { regionCenter, haversineKm, REGION_VERIFY_RADIUS_KM } from '../regions';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

/**
 * 본인 응답용 (모든 필드 포함).
 * verified_at / bank_registered_at 같은 민감 시각도 포함되지만
 * 라우트 호출자에서 본인 인증 후에만 호출되므로 OK.
 */
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
    verification_level: u.verification_level ?? 0,
    verified_at: u.verified_at,
    bank_registered_at: u.bank_registered_at,
    created_at: u.created_at,
    updated_at: u.updated_at,
  };
}

/**
 * 타인 프로필 응답용 (민감 정보 제거).
 * 잔액·계좌 등록일·CI 해시 등은 절대 노출하지 않음.
 * verification_level 자체는 신뢰 표시용으로 노출 (배지 표시).
 */
function sanitizePublic(u: UserRow): UserPublic {
  return {
    id: u.id,
    nickname: u.nickname,
    device_uuid: '',
    wallet_address: null,
    region: u.region,
    region_verified_at: u.region_verified_at,
    manner_score: u.manner_score,
    qta_balance: 0,
    verification_level: u.verification_level ?? 0,
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
      'SELECT id, nickname, region, manner_score, verification_level, created_at FROM users WHERE id = ?'
    )
    .bind(id)
    .first<{
      id: string;
      nickname: string;
      region: string | null;
      manner_score: number;
      verification_level: number;
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
 * POST /api/users/me/verify/identity
 *
 * 본인인증 (Lv1). PASS / SMS / KISA provider 분기 구조.
 *
 * Body: {
 *   provider: 'pass' | 'sms' | 'kisa' | 'dummy',
 *   ci_token: string,            // 인증 사업자가 발급한 CI (Connecting Information)
 *   nonce?: string,              // (옵션) PASS/KISA 트랜잭션 nonce — replay 방지
 *   tx_id?: string,              // (옵션) 사업자 트랜잭션 ID — 감사용
 *   phone_hash?: string,         // (옵션) 클라이언트가 미리 SHA-256 해시한 전화번호. 평문 절대 금지
 * }
 *
 * 정책:
 *   - 휴대폰 번호 평문은 절대 받지 않고 저장 X. 해시만 옵션으로 받음.
 *   - CI 의 SHA-256 해시만 저장 → 같은 사람의 중복 가입 차단용
 *   - 같은 CI 가 다른 계정에 이미 등록되어 있으면 409
 *   - provider='dummy' 는 개발/테스트 모드에서만 허용 (env.ALLOW_DUMMY_VERIFY === '1')
 */
app.post('/me/verify/identity', authMiddleware, async (c) => {
  const me = c.get('user')!;

  let body: {
    provider?: string;
    ci_token?: string;
    nonce?: string;
    tx_id?: string;
    phone_hash?: string;
  } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const provider = (body.provider || 'dummy').trim().toLowerCase();
  const ci = (body.ci_token || '').trim();
  const nonce = (body.nonce || '').trim();
  const txId = (body.tx_id || '').trim();
  const phoneHash = (body.phone_hash || '').trim();

  if (!ci || ci.length < 8) {
    return c.json({ error: '인증 토큰이 유효하지 않아요' }, 400);
  }

  // ── provider 별 검증 ─────────────────────────────────────────────
  // 실제 SDK 연동 시 각 case 안에서 해당 provider 의 verify API 를 호출.
  // 현재는 인터페이스만 분리해 두고, dummy 외 케이스는 토큰 형식만 검사.
  switch (provider) {
    case 'pass': {
      // PASS (이통3사 본인확인) 토큰. 보통 base64-url 형식, 100+ chars.
      if (ci.length < 32) {
        return c.json({ error: 'PASS 인증 토큰 형식이 잘못됐어요' }, 400);
      }
      if (!nonce) {
        return c.json({ error: 'PASS 인증 nonce 가 필요해요' }, 400);
      }
      // TODO: PASS 사업자 서버에 (ci_token, nonce, tx_id) 검증 요청
      break;
    }
    case 'sms': {
      // SMS 인증 — CI 가 없는 경우가 많아 ci_token 자리에 phone+otp 해시가 들어옴.
      // 폰 번호 자체는 절대 받지 않음.
      if (!phoneHash || phoneHash.length !== 64) {
        return c.json({ error: 'SMS 인증은 phone_hash(SHA-256) 가 필요해요' }, 400);
      }
      break;
    }
    case 'kisa': {
      // KISA 본인확인 (NICE/KCB 등). PASS 와 비슷하게 nonce 필수.
      if (!nonce) {
        return c.json({ error: 'KISA 인증 nonce 가 필요해요' }, 400);
      }
      break;
    }
    case 'dummy': {
      // 개발/시연 모드. 운영 배포에서는 ALLOW_DUMMY_VERIFY=0 으로 차단해야 함.
      const allow = (c.env as { ALLOW_DUMMY_VERIFY?: string }).ALLOW_DUMMY_VERIFY;
      if (allow !== '1') {
        return c.json({ error: '운영 환경에서는 dummy provider 가 허용되지 않아요' }, 403);
      }
      break;
    }
    default:
      return c.json({ error: '지원하지 않는 인증 사업자에요' }, 400);
  }

  // SHA-256(ci) — 식별자 해시
  const ciHash = await sha256Hex(`${provider}:${ci}`);

  // 같은 사람이 다른 계정에 이미 등록되어 있는지 확인
  const dup = await c.env.DB
    .prepare(
      'SELECT id FROM users WHERE verified_ci_hash = ? AND id != ?',
    )
    .bind(ciHash, me.id)
    .first<{ id: string }>();
  if (dup) {
    return c.json({ error: '이미 다른 계정에 등록된 본인인증이에요' }, 409);
  }

  const nowIso = new Date().toISOString();
  await c.env.DB
    .prepare(
      `UPDATE users
         SET verification_level = MAX(verification_level, 1),
             verified_ci_hash = ?,
             verified_at = ?,
             updated_at = datetime('now')
       WHERE id = ?`,
    )
    .bind(ciHash, nowIso, me.id)
    .run();

  // 감사 로그 — provider/tx_id 기록 (CI 평문/해시는 별도 컬럼에만)
  try {
    await c.env.DB
      .prepare(
        `INSERT INTO verification_audit
           (id, user_id, provider, tx_id, phone_hash, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        crypto.randomUUID(),
        me.id,
        provider,
        txId || null,
        phoneHash || null,
        nowIso,
      )
      .run();
  } catch (e) {
    // verification_audit 테이블이 아직 없을 수 있음 — 무시
    console.log('[verify] audit log skipped:', e);
  }

  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(me.id)
    .first<UserRow>();
  if (!user) return c.json({ error: 'User not found' }, 404);

  return c.json({ ok: true, user: sanitize(user), provider });
});

/**
 * POST /api/users/me/verify/bank
 *
 * 계좌 등록 (Lv2). 본인인증(Lv1) 선행 필수.
 * 계좌번호는 절대 평문 저장하지 않고, SHA-256(bank_code + account_number) 해시만 저장.
 *
 * Body: { bank_code: string, account_number: string }
 */
app.post('/me/verify/bank', authMiddleware, async (c) => {
  const me = c.get('user')!;

  // 본인인증 선행 체크
  const cur = await c.env.DB
    .prepare('SELECT verification_level FROM users WHERE id = ?')
    .bind(me.id)
    .first<{ verification_level: number }>();
  if (!cur || (cur.verification_level ?? 0) < 1) {
    return c.json({ error: '먼저 본인인증을 완료해주세요' }, 403);
  }

  let body: { bank_code?: string; account_number?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const bankCode = (body.bank_code || '').trim();
  const acctNum = (body.account_number || '').trim().replace(/[-\s]/g, '');
  if (!bankCode || !acctNum || acctNum.length < 6) {
    return c.json({ error: '은행 정보가 유효하지 않아요' }, 400);
  }

  const bankHash = await sha256Hex(`${bankCode}:${acctNum}`);

  const nowIso = new Date().toISOString();
  await c.env.DB
    .prepare(
      `UPDATE users
         SET verification_level = 2,
             bank_account_hash = ?,
             bank_registered_at = ?,
             updated_at = datetime('now')
       WHERE id = ?`,
    )
    .bind(bankHash, nowIso, me.id)
    .run();

  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(me.id)
    .first<UserRow>();
  if (!user) return c.json({ error: 'User not found' }, 404);

  return c.json({ ok: true, user: sanitize(user) });
});

/** SHA-256 hex helper using Web Crypto API. */
async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const buf = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

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

// ── 닉네임 검색 rate-limit (in-memory, isolate-scoped) ──────────────────
// 같은 isolate(보통 같은 colo) 내에서 IP+user_id 별 분당 호출수를 셈.
// 분산 환경에서 perfect 하지는 않지만, scrape/봇 트래픽이 한 colo 에 몰리는
// 패턴 (대부분 단일 IP + 단일 데이터센터 지역) 에 효과적이다.
//   • 한도: 분당 30회
//   • key: `${ip}:${user_id}` — 같은 IP 라도 여러 계정으로 우회하면 각각 카운팅
const SEARCH_RATE_LIMIT = 30;
const SEARCH_RATE_WINDOW_MS = 60_000;
type RateBucket = { count: number; resetAt: number };
const _searchRateMap = new Map<string, RateBucket>();

function _checkSearchRateLimit(key: string): { ok: true } | { ok: false; retryAfterSec: number } {
  const now = Date.now();
  const b = _searchRateMap.get(key);
  if (!b || b.resetAt <= now) {
    _searchRateMap.set(key, { count: 1, resetAt: now + SEARCH_RATE_WINDOW_MS });
    return { ok: true };
  }
  if (b.count >= SEARCH_RATE_LIMIT) {
    return { ok: false, retryAfterSec: Math.max(1, Math.ceil((b.resetAt - now) / 1000)) };
  }
  b.count += 1;
  return { ok: true };
}

// 메모리 누수 방지 — 최대 10K 엔트리 유지, 그 이상이면 만료된 항목 청소.
function _pruneSearchRateMap() {
  if (_searchRateMap.size < 10_000) return;
  const now = Date.now();
  for (const [k, v] of _searchRateMap) {
    if (v.resetAt <= now) _searchRateMap.delete(k);
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
 *
 * Rate-limit: IP+user_id 별 분당 30회. 초과 시 429 + Retry-After 헤더.
 */
app.get('/search', authMiddleware, async (c) => {
  const me = c.get('user')!;
  // CF-Connecting-IP 우선 (Cloudflare 표준), 없으면 X-Forwarded-For 첫 토큰.
  const ip =
    c.req.header('cf-connecting-ip') ||
    (c.req.header('x-forwarded-for') || '').split(',')[0].trim() ||
    'unknown';
  _pruneSearchRateMap();
  const rl = _checkSearchRateLimit(`${ip}:${me.id}`);
  if (!rl.ok) {
    c.header('Retry-After', String(rl.retryAfterSec));
    return c.json(
      { error: '요청이 너무 많아요. 잠시 후 다시 시도해주세요', retry_after: rl.retryAfterSec },
      429,
    );
  }

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
