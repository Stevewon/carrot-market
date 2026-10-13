import { Hono } from 'hono';
import type { Env, UserRow, UserPublic, Variables } from '../types';
import { authMiddleware } from '../jwt';
import { regionCenter, regionMarket, haversineKm, parseRegions, MAX_REGIONS, REGION_VERIFY_RADIUS_KM } from '../regions';
import { isAllowedMobile, normalizeMarket, tr, trl, reqLang, MARKET_CURRENCY, MONEY_PER_QTA, type Market, type Lang } from '../market';
import { buildAgoraToken, callIdentity, walletToAgoraUid } from '../utils/agoraToken';
import { challengeView, checkChallenge, consumeChallenge, createChallenge } from '../walletProof';
import { isValidWallet, normalizeWallet } from '../crypto';
import { encryptPhone, phoneHash, phoneVaultReady } from '../phoneVault';
import {
  grantVerifyBonus,
  settleReferrals,
  QTA_VERIFY_BONUS,
  MINING_REASONS,
  QTA_KRW_PER_QTA,
  QTA_LISTING_REWARD_PERCENT,
  QTA_LISTING_REWARD_MAX,
  QTA_LISTING_REWARD_DAILY_MAX,
} from '../qta';
import {
  confirmReceive,
  createReceiveChallenge,
  getReceiveChallenge,
  processReceiveSends,
  receiveView,
} from '../walletReceive';
import { verifyFirebasePhoneToken } from '../phoneVerify';
import { linkedQrchatUid } from '../qrchatBridge';
import { checkNickname } from '../prohibited';
import { NEGATIVE_CODES, PUBLIC_RATINGS_SQL, splitTags } from '../reviews';

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
    wallet_verified_at: u.wallet_verified_at ?? null,
    market: u.market ?? 'kr',
    regions: parseRegions(u.regions, u.region),
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
    market: u.market ?? 'kr',
    created_at: u.created_at,
    updated_at: u.updated_at,
  };
}

/** PUT /api/users/me - update region / nickname */
app.put('/me', authMiddleware, async (c) => {
  const authUser = c.get('user');
  if (!authUser) return c.json({ error: 'Unauthorized' }, 401);

  let body: { region?: string; regions?: unknown; nickname?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);
  }

  const updates: string[] = [];
  const values: (string | null)[] = [];

  // 내 동네 목록(최대 10곳) + 지금 보는 동네(region).
  //   regions 를 보내면 목록을 통째로 바꾼다. region 만 보내면 목록에 없을 때 뒤에 붙인다.
  //   일본 회원은 일본 지역만, 한국 회원은 한국 지역만.
  if (body.region !== undefined || body.regions !== undefined) {
    const cur = await c.env.DB
      .prepare('SELECT market, region, regions FROM users WHERE id = ?')
      .bind(authUser.id)
      .first<{ market: string | null; region: string | null; regions: string | null }>();
    const market = cur?.market || 'kr';
    const badRegion = (r: string) => {
      const rm = regionMarket(r);
      return rm !== null && rm !== market;
    };

    let list = parseRegions(cur?.regions, cur?.region);
    if (body.regions !== undefined) {
      if (!Array.isArray(body.regions)) {
        return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);
      }
      list = [];
      for (const v of body.regions) {
        const r = String(v ?? '').trim();
        if (r && !list.includes(r)) list.push(r);
      }
    }
    let active = body.region !== undefined ? String(body.region ?? '').trim() : (cur?.region || '');
    if (active && !list.includes(active)) list.push(active);
    if (list.length > MAX_REGIONS) {
      return c.json({
        error: tr(c, `내 동네는 최대 ${MAX_REGIONS}곳까지 설정할 수 있어요`, `地域は最大${MAX_REGIONS}か所まで設定できます`, `You can set up to ${MAX_REGIONS} neighborhoods`),
        code: 'region_limit',
      }, 400);
    }
    if (list.some(badRegion)) {
      return c.json({ error: tr(c, '선택할 수 없는 지역이에요', '選択できない地域です', "This area can't be selected"), code: 'region_market' }, 400);
    }
    if (!active || !list.includes(active)) active = list[0] || '';
    if (!active) {
      return c.json({ error: tr(c, '동네를 한 곳 이상 남겨주세요', '地域を1か所以上設定してください', 'Please keep at least one neighborhood'), code: 'region_empty' }, 400);
    }
    updates.push('region = ?');
    values.push(active);
    updates.push('regions = ?');
    values.push(JSON.stringify(list));
  }

  if (body.nickname !== undefined) {
    const nick = body.nickname.trim();
    if (nick.length < 2 || nick.length > 12) {
      return c.json({ error: tr(c, '닉네임은 2~12자여야 해요', 'ニックネームは2〜12文字で入力してください', 'Nickname must be 2–12 characters') }, 400);
    }
    const nickPolicyErr = checkNickname(nick, reqLang(c));
    if (nickPolicyErr) return c.json({ error: nickPolicyErr, code: 'nickname_policy' }, 400);
    // Block nickname collisions (excluding ourselves).
    const collision = await c.env.DB
      .prepare('SELECT id FROM users WHERE nickname = ? COLLATE NOCASE AND id != ?')
      .bind(nick, authUser.id)
      .first<{ id: string }>();
    if (collision) {
      return c.json({ error: tr(c, '이미 사용 중인 닉네임이에요', 'このニックネームはすでに使われています', 'This nickname is already taken') }, 409);
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
 * lightweight aggregates: 공개 후기 수(best/good/soso — bad 는 비공개라 항상 0),
 * praise = 받은 매너 칭찬 [{code, count}] (많은 순).
 */
/**
 * GET /api/users/:id/call-info
 *
 * ★ v1.0.141 (2026-05-09): 통화용 peer 정보 자가 복구 엔드포인트.
 *
 * 통화 발생 시 수신자가 push 데이터로 받은 caller_wallet 이 누락되어
 * Agora 채널명 산정이 불가한 케이스 자가 복구용. user_id 만 알면
 * wallet_address + nickname 을 조회 가능.
 *
 * 정책:
 *   1) 인증된 사용자만 호출 가능 (authMiddleware)
 *   2) wallet_address 는 채널명 산정에만 쓰는 단순 페어 키이므로 노출 OK
 *      (Agora 토큰은 별도 인증으로 발급되므로 위·변조 실효성 0)
 *   3) 응답에 민감 정보(잔액/계좌/CI 등)는 절대 포함 안 함
 */
app.get('/:id/call-info', authMiddleware, async (c) => {
  const id = c.req.param('id');
  const u = await c.env.DB
    .prepare('SELECT id, nickname, wallet_address FROM users WHERE id = ?')
    .bind(id)
    .first<{ id: string; nickname: string; wallet_address: string | null }>();
  if (!u) return c.json({ error: 'Not found' }, 404);
  return c.json({
    id: u.id,
    nickname: u.nickname,
    // 통화 식별 키 (지갑 없으면 'u_<id>') — 필드명은 구버전 앱 호환용
    wallet_address: callIdentity(u.wallet_address, u.id),
  });
});

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

  // 후기 집계 — 당근처럼 'bad'(별로예요) 평가는 공개하지 않는다 (매너온도에만 반영).
  //   stats.total / good / soso / bad 는 구버전 앱이 읽는 키 — 공개 범위로 계산하고 bad 는 항상 0.
  const stats = await c.env.DB
    .prepare(
      `SELECT
         SUM(CASE WHEN rating IN ${PUBLIC_RATINGS_SQL} THEN 1 ELSE 0 END) AS total,
         SUM(CASE WHEN rating='best' THEN 1 ELSE 0 END) AS best,
         SUM(CASE WHEN rating='good' THEN 1 ELSE 0 END) AS good,
         SUM(CASE WHEN rating='soso' THEN 1 ELSE 0 END) AS soso,
         SUM(CASE WHEN rating IN ${PUBLIC_RATINGS_SQL} AND comment <> '' THEN 1 ELSE 0 END) AS with_comment
       FROM reviews WHERE reviewee_id = ?`
    )
    .bind(id)
    .first<{ total: number | null; best: number | null; good: number | null; soso: number | null; with_comment: number | null }>();

  // 받은 매너 칭찬 — 공개 후기의 항목 코드별 개수 (예전 자유 입력 태그는 문구 그대로 집계).
  // 비매너 코드는 공개 후기에 들어갈 수 없지만, 혹시 섞여 있어도 걸러낸다.
  const tagRows = await c.env.DB
    .prepare(
      `SELECT tags FROM reviews
        WHERE reviewee_id = ? AND rating IN ${PUBLIC_RATINGS_SQL} AND tags <> ''
        ORDER BY created_at DESC LIMIT 2000`
    )
    .bind(id)
    .all<{ tags: string }>();
  const praiseCounts = new Map<string, number>();
  for (const r of tagRows.results || []) {
    for (const t of splitTags(r.tags)) {
      if (NEGATIVE_CODES.has(t)) continue;
      praiseCounts.set(t, (praiseCounts.get(t) ?? 0) + 1);
    }
  }
  const praise = [...praiseCounts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([code, count]) => ({ code, count }));

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
      best: stats?.best ?? 0,
      good: stats?.good ?? 0,
      soso: stats?.soso ?? 0,
      bad: 0,
      with_comment: stats?.with_comment ?? 0,
      selling: sellingCount?.n ?? 0,
    },
    praise,
  });
});

/**
 * GET /api/users/:id/reviews
 *
 * Paginated list of reviews received by a user, newest first.
 *   ?limit=20&before=<iso>&with_comment=1
 *
 * • 'bad' 평가는 공개하지 않는다 (당근과 같음).
 * • with_comment=1 이면 후기 글이 있는 것만 ("받은 거래 후기" 목록).
 * • role: 후기를 쓴 사람이 그 거래에서 'buyer'(구매자) 였는지 'seller'(판매자) 였는지.
 */
app.get('/:id/reviews', async (c) => {
  const id = c.req.param('id');
  const limit = Math.min(parseInt(c.req.query('limit') || '20', 10) || 20, 50);
  const before = c.req.query('before');
  const withComment = c.req.query('with_comment') === '1';

  const where = [`r.reviewee_id = ?`, `r.rating IN ${PUBLIC_RATINGS_SQL}`];
  const params: (string | number)[] = [id];
  if (withComment) where.push(`r.comment <> ''`);
  if (before) {
    where.push('r.created_at < ?');
    params.push(before);
  }
  params.push(limit);

  const { results } = await c.env.DB
    .prepare(
      `SELECT r.id, r.rating, r.tags, r.comment, r.created_at,
              r.reviewer_id, COALESCE(ru.nickname, '') AS reviewer_nickname,
              p.id AS product_id, p.title AS product_title,
              CASE WHEN r.reviewer_id = p.seller_id THEN 'seller' ELSE 'buyer' END AS role
         FROM reviews r
         LEFT JOIN users ru ON ru.id = r.reviewer_id
         JOIN products p  ON p.id  = r.product_id
        WHERE ${where.join(' AND ')}
        ORDER BY r.created_at DESC LIMIT ?`,
    )
    .bind(...params)
    .all<{ tags: string }>();
  // 공개 목록에는 비매너 코드를 절대 내보내지 않는다.
  const reviews = (results || []).map((r) => ({
    ...r,
    tags: splitTags(r.tags).filter((t) => !NEGATIVE_CODES.has(t)).join(','),
  }));
  return c.json({ reviews });
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
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);
  }

  const lat = Number(body.lat);
  const lng = Number(body.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)
      || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return c.json({ error: tr(c, 'GPS 좌표가 유효하지 않아요', '位置情報（GPS）が正しくありません', 'Invalid GPS location') }, 400);
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
    return c.json({ error: tr(c, '먼저 동네를 선택해주세요', '先に地域を選択してください', 'Please choose your neighborhood first') }, 400);
  }

  const center = regionCenter(region);
  if (!center) {
    return c.json({ error: tr(c, '지원하지 않는 지역이에요', '対応していない地域です', "This area isn't supported") }, 400);
  }
  {
    const mine = await c.env.DB
      .prepare('SELECT market FROM users WHERE id = ?')
      .bind(me.id)
      .first<{ market: string | null }>();
    if (regionMarket(region) !== (mine?.market || 'kr')) {
      return c.json({ error: tr(c, '선택할 수 없는 지역이에요', '選択できない地域です', "This area can't be selected"), code: 'region_market' }, 400);
    }
  }

  const dist = haversineKm({ lat, lng }, center);
  if (dist > REGION_VERIFY_RADIUS_KM) {
    return c.json({
      error: tr(c, '내 동네에서 너무 멀어요', '設定した地域から離れすぎています', "You're too far from your neighborhood"),
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
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);
  }

  const provider = (body.provider || 'dummy').trim().toLowerCase();
  const ci = (body.ci_token || '').trim();
  const nonce = (body.nonce || '').trim();
  const txId = (body.tx_id || '').trim();
  const phoneHash = (body.phone_hash || '').trim();

  if (!ci || ci.length < 8) {
    return c.json({ error: tr(c, '인증 토큰이 유효하지 않아요', '認証トークンが無効です', 'Invalid verification token') }, 400);
  }

  // ── provider 별 검증 ─────────────────────────────────────────────
  // pass / sms / kisa 는 사업자 서버 검증(SDK 연동)이 아직 없다. 예전에는
  // 토큰 "형식" 만 보고 Lv1 을 부여해서 아무 문자열로 인증이 통과됐다.
  // 사업자 검증이 붙기 전까지는 거부한다. 연동 시 각 case 에서 verify API 를
  // 호출하고 성공했을 때만 break 하도록 바꾼다.
  switch (provider) {
    case 'pass':
    case 'sms':
    case 'kisa': {
      // TODO(pass-sdk): 사업자 서버에 (ci_token, nonce, tx_id) 검증 요청 후 통과 시 break.
      return c.json(
        { error: tr(c, '본인인증 서비스를 준비 중이에요. 잠시 후 다시 시도해주세요', '本人確認サービスを準備中です。しばらくしてから再度お試しください', "Identity verification isn't available yet. Please try again in a moment"), code: 'provider_not_ready' },
        503,
      );
    }
    case 'dummy': {
      // 개발/시연 모드. 운영 배포에서는 ALLOW_DUMMY_VERIFY 를 비워 차단.
      if (c.env.ALLOW_DUMMY_VERIFY !== '1') {
        return c.json({ error: tr(c, '운영 환경에서는 dummy provider 가 허용되지 않아요', '本番環境では dummy provider は使用できません', "The dummy provider isn't allowed in production") }, 403);
      }
      break;
    }
    default:
      return c.json({ error: tr(c, '지원하지 않는 인증 사업자에요', '対応していない認証事業者です', 'Unsupported verification provider') }, 400);
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
    return c.json({ error: tr(c, '이미 다른 계정에 등록된 본인인증이에요', 'この本人確認はすでに別のアカウントで登録されています', 'This identity is already verified on another account') }, 409);
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

  const verifyBonus = await maybeGrantVerifyBonus(c.env, me.id);
  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(me.id)
    .first<UserRow>();
  if (!user) return c.json({ error: 'User not found' }, 404);

  return c.json({ ok: true, user: sanitize(user), provider, verify_bonus: verifyBonus });
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
    return c.json({ error: tr(c, '먼저 본인인증을 완료해주세요', '先に本人確認を完了してください', 'Please complete identity verification first') }, 403);
  }

  let body: { bank_code?: string; account_number?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);
  }

  const bankCode = (body.bank_code || '').trim();
  const acctNum = (body.account_number || '').trim().replace(/[-\s]/g, '');
  if (!bankCode || !acctNum || acctNum.length < 6) {
    return c.json({ error: tr(c, '은행 정보가 유효하지 않아요', '銀行情報が正しくありません', 'Invalid bank information') }, 400);
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

/**
 * 로그인한 회원의 지갑 소유 증명 (출금 조건) — src/walletProof.ts 의 purpose='verify'.
 *
 * POST /api/users/me/wallet-proof                → 본인 지갑으로 챌린지 발급
 * POST /api/users/me/wallet-proof/:id/check      → 송금 확인되면 wallet_verified_at 기록
 *
 * 가입 때 지갑 인증을 거친 회원은 이미 wallet_verified_at 이 있다. 이전 가입자·
 * 큐알쳇 로그인으로 만든 계정이 출금 전에 한 번 거친다.
 */
app.post('/me/wallet-proof', authMiddleware, async (c) => {
  const me = c.get('user')!;
  let body: { wallet_address?: string } = {};
  try { body = await c.req.json(); } catch { /* 본문 없음 = 등록된 지갑으로 */ }
  const u = await c.env.DB
    .prepare('SELECT wallet_address, wallet_verified_at FROM users WHERE id = ?')
    .bind(me.id)
    .first<{ wallet_address: string | null; wallet_verified_at: string | null }>();
  if (!u) return c.json({ error: 'User not found' }, 404);
  if (u.wallet_address && u.wallet_verified_at) {
    return c.json({ error: tr(c, '이미 지갑 인증을 마쳤어요', 'ウォレット認証はすでに完了しています', 'Your wallet is already verified'), code: 'already_verified' }, 409);
  }
  // 지갑 없이 가입한 회원은 여기서 지갑을 등록한다 (인증이 끝나야 저장됨).
  // 인증 전 지갑(예전 가입자)도 주소를 바꿔 입력할 수 있다.
  const input = (body.wallet_address || '').trim();
  if (input && !isValidWallet(input)) {
    return c.json({ error: tr(c, '퀀타리움 지갑주소 형식을 확인해주세요 (0x + 40자리)', 'Quantariumウォレットアドレスの形式をご確認ください（0x + 40桁）', 'Please check your Quantarium wallet address (0x + 40 characters)') }, 400);
  }
  const target = (input ? normalizeWallet(input) : u.wallet_address || '').toLowerCase();
  if (!target) return c.json({ error: tr(c, '지갑주소를 입력해주세요', 'ウォレットアドレスを入力してください', 'Please enter your wallet address'), code: 'wallet_required' }, 400);
  const holder = await c.env.DB
    .prepare('SELECT id FROM users WHERE wallet_address = ? COLLATE NOCASE AND id != ?')
    .bind(target, me.id)
    .first<{ id: string }>();
  if (holder) {
    return c.json(
      {
        error: tr(c, '이미 다른 가지 계정에 등록된 지갑이에요. 본인 지갑이라면 '
          + "'계정 찾기 → 비밀번호 재설정' 에서 지갑 인증으로 그 계정을 되찾을 수 있어요", 'このウォレットはすでに別のEggplantアカウントに登録されています。ご自身のウォレットであれば、「アカウントを探す → パスワード再設定」からウォレット認証でそのアカウントを取り戻せます', "This wallet is already registered to another Eggplant account. If it's your wallet, you can recover that account with wallet verification under 'Find account → Reset password'"),
        code: 'wallet_taken',
      },
      409,
    );
  }
  const created = await createChallenge(
    c.env, target, 'verify', me.device_uuid, c.req.header('cf-connecting-ip') || '', reqLang(c),
  );
  if (!created.ok) return c.json({ error: created.error, code: created.code }, created.status);
  const row = created.row;
  return c.json(challengeView(row, c.env));
});

app.post('/me/wallet-proof/:id/check', authMiddleware, async (c) => {
  const me = c.get('user')!;
  const id = c.req.param('id');
  const r = await checkChallenge(c.env, id, me.device_uuid, reqLang(c));
  if (!r.ok) return c.json({ verified: false, error: r.error, code: r.code }, r.status);

  const consumed = await consumeChallenge(c.env, id, r.row.wallet_address, 'verify', me.device_uuid);
  if (!consumed) return c.json({ verified: false, error: tr(c, '인증이 만료됐어요. 다시 진행해주세요', '認証の有効期限が切れました。もう一度お試しください', 'Verification expired. Please try again'), code: 'expired' }, 410);
  // 인증된 지갑을 이 계정에 저장 (지갑 없던 회원은 여기서 처음 등록).
  // 이미 인증된 지갑이 있으면 바꾸지 않는다.
  try {
    const res = await c.env.DB
      .prepare(
        `UPDATE users SET wallet_address = ?, wallet_verified_at = datetime('now'), updated_at = datetime('now')
          WHERE id = ? AND (wallet_verified_at IS NULL OR wallet_address IS NULL)`,
      )
      .bind(r.row.wallet_address, me.id)
      .run();
    if ((res.meta?.changes ?? 0) !== 1) {
      return c.json({ verified: false, error: tr(c, '이미 지갑 인증을 마쳤어요', 'ウォレット認証はすでに完了しています', 'Your wallet is already verified'), code: 'already_verified' }, 409);
    }
  } catch (e) {
    if (/UNIQUE/i.test(String((e as Error)?.message || e))) {
      return c.json({ verified: false, error: tr(c, '이미 다른 가지 계정에 등록된 지갑이에요', 'このウォレットはすでに別のEggplantアカウントに登録されています', 'This wallet is already registered to another Eggplant account'), code: 'wallet_taken' }, 409);
    }
    throw e;
  }

  // 1·2단계를 다 마쳤으면 인증 보너스 (+1,000 QTA, 사람 단위 1회).
  const verifyBonus = await maybeGrantVerifyBonus(c.env, me.id);
  const user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(me.id).first<UserRow>();
  return c.json({ verified: true, user: user ? sanitize(user) : null, signup_bonus: 0, verify_bonus: verifyBonus });
});

/**
 * 1·2단계(지갑 + 휴대폰) 인증을 모두 마쳤으면 +1,000 QTA. 지급한 금액(없으면 0)을 돌려준다.
 * 사람 단위 1회 — 지갑·전화번호·큐알쳇 계정 중 하나라도 받은 적 있으면 지급 안 함.
 */
async function maybeGrantVerifyBonus(env: Env, userId: string): Promise<number> {
  try {
    const u = await env.DB
      .prepare('SELECT wallet_address, wallet_verified_at, verified_at, verified_ci_hash FROM users WHERE id = ?')
      .bind(userId)
      .first<{
        wallet_address: string | null;
        wallet_verified_at: string | null;
        verified_at: string | null;
        verified_ci_hash: string | null;
      }>();
    if (!u || !u.wallet_address || !u.wallet_verified_at || !u.verified_at || !u.verified_ci_hash) return 0;
    const keys = [`wallet:${u.wallet_address.toLowerCase()}`, `phone:${u.verified_ci_hash}`];
    const q = await linkedQrchatUid(env, userId);
    if (q) keys.push(`qrchat:${q}`);
    const granted = await grantVerifyBonus(env, userId, keys);
    // 3단계를 마쳤으니 미뤄 둔 친구 초대 보상도 정산 (실패해도 인증 보너스는 그대로).
    await settleReferrals(env, userId).catch((e) => console.error('[referral] settle failed', e));
    return granted ? QTA_VERIFY_BONUS : 0;
  } catch (e) {
    console.error('[verify-bonus] failed', e);
    return 0;
  }
}

/** 지갑 등록 전 공통 확인 — 이미 인증했는지, 남이 쓰는 지갑인지. 통과하면 소문자 주소. */
async function walletTargetFor(
  env: Env,
  userId: string,
  input: string,
  lang: Lang = 'ko',
): Promise<{ ok: true; wallet: string } | { ok: false; status: 400 | 404 | 409; error: string; code?: string }> {
  const u = await env.DB
    .prepare('SELECT wallet_address, wallet_verified_at FROM users WHERE id = ?')
    .bind(userId)
    .first<{ wallet_address: string | null; wallet_verified_at: string | null }>();
  if (!u) return { ok: false, status: 404, error: 'User not found' };
  if (u.wallet_address && u.wallet_verified_at) {
    return { ok: false, status: 409, error: trl(lang, '이미 지갑 인증을 마쳤어요', 'ウォレット認証はすでに完了しています', 'Your wallet is already verified'), code: 'already_verified' };
  }
  const raw = (input || '').trim();
  if (raw && !isValidWallet(raw)) {
    return { ok: false, status: 400, error: trl(lang, '퀀타리움 지갑주소 형식을 확인해주세요 (0x + 40자리)', 'Quantariumウォレットアドレスの形式をご確認ください（0x + 40桁）', 'Please check your Quantarium wallet address (0x + 40 characters)'), code: 'bad_wallet' };
  }
  const target = (raw ? normalizeWallet(raw) : u.wallet_address || '').toLowerCase();
  if (!target) return { ok: false, status: 400, error: trl(lang, '지갑주소를 입력해주세요', 'ウォレットアドレスを入力してください', 'Please enter your wallet address'), code: 'wallet_required' };
  const holder = await env.DB
    .prepare('SELECT id FROM users WHERE wallet_address = ? COLLATE NOCASE AND id != ?')
    .bind(target, userId)
    .first<{ id: string }>();
  if (holder) {
    return {
      ok: false,
      status: 409,
      error: trl(lang, '이미 다른 가지 계정에 등록된 지갑이에요. 본인 지갑이라면 '
        + "'계정 찾기 → 비밀번호 재설정' 에서 지갑 인증으로 그 계정을 되찾을 수 있어요", 'このウォレットはすでに別のEggplantアカウントに登録されています。ご自身のウォレットであれば、「アカウントを探す → パスワード再設定」からウォレット認証でそのアカウントを取り戻せます', "This wallet is already registered to another Eggplant account. If it's your wallet, you can recover that account with wallet verification under 'Find account → Reset password'"),
      code: 'wallet_taken',
    };
  }
  return { ok: true, wallet: target };
}

/**
 * 1단계 지갑 인증 — 본사 지갑이 소수점 6자리 임의 수량을 보내고, 회원이 받은 수량을 입력.
 *
 * POST /api/users/me/wallet-receive              body:{ wallet_address } → 송금 요청 (금액은 안 알려줌)
 * GET  /api/users/me/wallet-receive/:id          → 송금 상태 (queued/sending/sent/failed)
 * POST /api/users/me/wallet-receive/:id/confirm  body:{ amount } → 맞으면 지갑 등록
 */
app.post('/me/wallet-receive', authMiddleware, async (c) => {
  const me = c.get('user')!;
  let body: { wallet_address?: string } = {};
  try { body = await c.req.json(); } catch { /* 본문 없음 = 등록된 지갑으로 */ }
  const t = await walletTargetFor(c.env, me.id, body.wallet_address || '', reqLang(c));
  if (!t.ok) return c.json({ error: t.error, code: t.code }, t.status);
  const r = await createReceiveChallenge(
    c.env, me.id, me.device_uuid, t.wallet, c.req.header('cf-connecting-ip') || '', reqLang(c),
  );
  if (!r.ok) return c.json({ error: r.error, code: r.code }, r.status);
  // 바로 보내기 시작 (서명에 수 초) — 실패하면 1분 cron 이 다시 시도.
  if (r.row.send_status === 'queued') {
    c.executionCtx.waitUntil(processReceiveSends(c.env).catch((e) => console.error('[wallet-receive] tick', e)));
  }
  return c.json(receiveView(r.row, c.env));
});

app.get('/me/wallet-receive/:id', authMiddleware, async (c) => {
  const me = c.get('user')!;
  const row = await getReceiveChallenge(c.env, me.id, c.req.param('id'));
  if (!row) return c.json({ error: tr(c, '인증 요청을 찾을 수 없어요', '認証リクエストが見つかりません', 'Verification request not found'), code: 'not_found' }, 404);
  return c.json(receiveView(row, c.env));
});

app.post('/me/wallet-receive/:id/confirm', authMiddleware, async (c) => {
  const me = c.get('user')!;
  let body: { amount?: string | number } = {};
  try { body = await c.req.json(); } catch { /* 아래에서 형식 오류 */ }
  const r = await confirmReceive(c.env, me.id, c.req.param('id'), String(body.amount ?? ''), reqLang(c));
  if (!r.ok) {
    return c.json({ verified: false, error: r.error, code: r.code, attempts_left: r.attempts_left }, r.status);
  }
  try {
    const res = await c.env.DB
      .prepare(
        `UPDATE users SET wallet_address = ?, wallet_verified_at = datetime('now'), updated_at = datetime('now')
          WHERE id = ? AND (wallet_verified_at IS NULL OR wallet_address IS NULL)`,
      )
      .bind(r.row.wallet_address, me.id)
      .run();
    if ((res.meta?.changes ?? 0) !== 1) {
      return c.json({ verified: false, error: tr(c, '이미 지갑 인증을 마쳤어요', 'ウォレット認証はすでに完了しています', 'Your wallet is already verified'), code: 'already_verified' }, 409);
    }
  } catch (e) {
    if (/UNIQUE/i.test(String((e as Error)?.message || e))) {
      return c.json({ verified: false, error: tr(c, '이미 다른 가지 계정에 등록된 지갑이에요', 'このウォレットはすでに別のEggplantアカウントに登録されています', 'This wallet is already registered to another Eggplant account'), code: 'wallet_taken' }, 409);
    }
    throw e;
  }
  const verifyBonus = await maybeGrantVerifyBonus(c.env, me.id);
  const user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(me.id).first<UserRow>();
  return c.json({ verified: true, user: user ? sanitize(user) : null, verify_bonus: verifyBonus });
});

/**
 * 2단계 휴대폰 인증 — 앱이 Firebase 문자 인증 후 받은 ID 토큰을 보낸다.
 * 1단계(지갑 인증)를 먼저 마쳐야 한다. 끝나면 +1,000 QTA.
 *
 * POST /api/users/me/verify/phone  body:{ id_token }
 */
app.post('/me/verify/phone', authMiddleware, async (c) => {
  const me = c.get('user')!;
  let body: { id_token?: string } = {};
  try { body = await c.req.json(); } catch { /* 아래에서 오류 */ }
  const cur = await c.env.DB
    .prepare('SELECT wallet_address, wallet_verified_at, verified_at FROM users WHERE id = ?')
    .bind(me.id)
    .first<{ wallet_address: string | null; wallet_verified_at: string | null; verified_at: string | null }>();
  if (!cur) return c.json({ error: 'User not found' }, 404);
  if (!cur.wallet_address || !cur.wallet_verified_at) {
    return c.json({ error: tr(c, '1단계 지갑 인증을 먼저 마쳐주세요', '先にステップ1のウォレット認証を完了してください', 'Please complete step 1 wallet verification first'), code: 'wallet_first' }, 403);
  }
  if (cur.verified_at) return c.json({ error: tr(c, '이미 휴대폰 인증을 마쳤어요', '電話番号認証はすでに完了しています', 'Your phone number is already verified'), code: 'already_verified' }, 409);
  // 번호를 암호화해 보관할 키가 없으면 인증하지 않는다 (평문 저장·추적 불가 상태로 진행 X).
  if (!(await phoneVaultReady(c.env))) {
    return c.json({ error: tr(c, '휴대폰 인증을 잠시 쓸 수 없어요. 잠시 후 다시 시도해주세요', '電話番号認証は現在ご利用いただけません。しばらくしてから再度お試しください', 'Phone verification is unavailable right now. Please try again in a moment'), code: 'verify_unavailable' }, 503);
  }

  let v;
  try {
    v = await verifyFirebasePhoneToken(c.env, body.id_token || '');
  } catch (e) {
    console.error('[verify/phone] token check failed', e);
    return c.json({ error: tr(c, '인증 서버에 연결하지 못했어요. 잠시 후 다시 시도해주세요', '認証サーバーに接続できませんでした。しばらくしてから再度お試しください', "Couldn't connect to the verification server. Please try again in a moment"), code: 'verify_unavailable' }, 502);
  }
  if (!v.ok) {
    return c.json({ error: tr(c, '휴대폰 인증이 확인되지 않았어요. 다시 시도해주세요', '電話番号認証を確認できませんでした。もう一度お試しください', "Phone verification couldn't be confirmed. Please try again"), code: 'invalid_token', reason: v.reason }, 400);
  }

  if (!isAllowedMobile(v.phone)) {
    return c.json({
      error: tr(c, '한국(010)·일본(070/080/090)·필리핀(09) 휴대폰 번호로만 인증할 수 있어요', '日本(070/080/090)・韓国(010)・フィリピン(09)の携帯電話番号のみ認証できます', 'Only Philippine (09), Korean (010) or Japanese (070/080/090) mobile numbers can be verified'),
      code: 'mobile_only',
    }, 400);
  }

  // 같은 번호로 두 계정 인증 불가 (1인 1계정). 해시는 키가 있어야 만들 수 있는 HMAC.
  // 번호 자체는 암호문으로 phone_vault 에만 — 불법 사용자 추적 때 super_admin 만 복호화.
  const ciHash = await phoneHash(c.env, v.phone);
  const phoneEnc = await encryptPhone(c.env, v.phone);
  const dup = await c.env.DB
    .prepare('SELECT id FROM users WHERE verified_ci_hash = ? AND id != ?')
    .bind(ciHash, me.id)
    .first<{ id: string }>();
  if (dup) return c.json({ error: tr(c, '이 번호는 이미 다른 가지 계정에서 인증했어요', 'この電話番号はすでに別のEggplantアカウントで認証されています', 'This number is already verified on another Eggplant account'), code: 'phone_taken' }, 409);

  const nowIso = new Date().toISOString();
  try {
    await c.env.DB.batch([
      c.env.DB
        .prepare(
          `UPDATE users
              SET verification_level = MAX(verification_level, 1),
                  verified_ci_hash = ?, verified_at = ?, updated_at = datetime('now')
            WHERE id = ? AND verified_at IS NULL`,
        )
        .bind(ciHash, nowIso, me.id),
      c.env.DB
        .prepare(
          `INSERT INTO phone_vault (user_id, phone_enc, phone_hash) VALUES (?, ?, ?)
             ON CONFLICT(user_id) DO UPDATE SET phone_enc = excluded.phone_enc,
               phone_hash = excluded.phone_hash, created_at = datetime('now')`,
        )
        .bind(me.id, phoneEnc, ciHash),
    ]);
  } catch (e) {
    if (/UNIQUE/i.test(String((e as Error)?.message || e))) {
      return c.json({ error: tr(c, '이 번호는 이미 다른 가지 계정에서 인증했어요', 'この電話番号はすでに別のEggplantアカウントで認証されています', 'This number is already verified on another Eggplant account'), code: 'phone_taken' }, 409);
    }
    throw e;
  }
  try {
    await c.env.DB
      .prepare(
        `INSERT INTO verification_audit (id, user_id, provider, tx_id, phone_hash, created_at)
         VALUES (?, ?, 'firebase_phone', ?, ?, ?)`,
      )
      .bind(crypto.randomUUID(), me.id, v.uid, ciHash, nowIso)
      .run();
  } catch (e) {
    console.log('[verify/phone] audit log skipped:', e);
  }

  const verifyBonus = await maybeGrantVerifyBonus(c.env, me.id);
  const user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(me.id).first<UserRow>();
  return c.json({ ok: true, user: user ? sanitize(user) : null, verify_bonus: verifyBonus });
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

/**
 * GET /api/users/me/qta/mining?limit=100
 *
 * 채굴 내역 (상품 등록 채굴 · 가격 인하/삭제 회수 · 7일 보유 · 둘러보기).
 * 응답: { total, listing_total, rule: {...}, items: [{amount, reason, meta, created_at}] }
 */
app.get('/me/qta/mining', authMiddleware, async (c) => {
  const me = c.get('user')!;
  const limit = Math.min(200, parseInt(c.req.query('limit') || '100', 10) || 100);
  const marks = MINING_REASONS.map(() => '?').join(',');
  const mrow = await c.env.DB.prepare('SELECT market FROM users WHERE id = ?').bind(me.id).first<{ market: string | null }>();
  const mk: Market = normalizeMarket(mrow?.market) ?? 'kr';

  const sums = await c.env.DB
    .prepare(
      `SELECT COALESCE(SUM(amount), 0) AS total,
              COALESCE(SUM(CASE WHEN reason LIKE 'listing_reward%' THEN amount ELSE 0 END), 0) AS listing_total
         FROM qta_ledger WHERE user_id = ? AND reason IN (${marks})`,
    )
    .bind(me.id, ...MINING_REASONS)
    .first<{ total: number; listing_total: number }>();

  const rs = await c.env.DB
    .prepare(
      `SELECT amount, reason, meta, created_at FROM qta_ledger
        WHERE user_id = ? AND reason IN (${marks})
        ORDER BY created_at DESC LIMIT ?`,
    )
    .bind(me.id, ...MINING_REASONS, limit)
    .all<{ amount: number; reason: string; meta: string | null; created_at: string }>();

  return c.json({
    total: sums?.total ?? 0,
    listing_total: sums?.listing_total ?? 0,
    rule: {
      currency: MARKET_CURRENCY[mk],
      money_per_qta: MONEY_PER_QTA[mk],
      krw_per_qta: QTA_KRW_PER_QTA,
      percent: QTA_LISTING_REWARD_PERCENT,
      max_per_listing: QTA_LISTING_REWARD_MAX,
      max_per_day: QTA_LISTING_REWARD_DAILY_MAX,
    },
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
      { error: tr(c, '요청이 너무 많아요. 잠시 후 다시 시도해주세요', 'リクエストが多すぎます。しばらくしてから再度お試しください', 'Too many requests. Please try again in a moment'), retry_after: rl.retryAfterSec },
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

/**
 * GET /api/users/agora/token?kind=rtm|rtc&uid=<int>&channel=<string>
 *
 * Agora 토큰 발급 (HMAC-SHA256 서명, App Certificate 사용).
 *
 * 정책:
 *   1) 인증된 사용자만 발급 가능 (authMiddleware).
 *   2) uid 파라미터는 무시하고, 서버에서 wallet_address 로부터 결정론적
 *      재계산. 클라이언트가 다른 사람 UID 를 위장 발급하는 것을 차단.
 *   3) 채널명에 'eggplant_' prefix 강제. 큐알쳇 트래픽과 섞이지 않도록.
 *   4) AGORA_APP_CERTIFICATE 가 미설정이면 503 (fail-closed).
 *   5) 만료 시각: now + 3600s (1시간). 클라이언트가 만료 5분 전 자동 갱신.
 *
 * 응답: { token, uid, expire_at, channel? }
 */
app.get('/agora/token', authMiddleware, async (c) => {
  const me = c.get('user')!;
  const env = c.env;

  // Eggplant 전용 Project(c60b4a7f...) 우선, 미설정 시 legacy(큐알쳇 공유) 로 fallback.
  // 큐알쳇 트래픽/장애와 100% 격리 보장.
  const agoraAppId = env.AGORA_APP_ID_EGGPLANT || env.AGORA_APP_ID;
  const agoraAppCert = env.AGORA_APP_CERTIFICATE_EGGPLANT || env.AGORA_APP_CERTIFICATE;

  if (!agoraAppId || !agoraAppCert) {
    return c.json(
      { error: 'Agora not configured', code: 'agora_unconfigured' },
      503,
    );
  }

  const kindRaw = (c.req.query('kind') || 'rtm').toLowerCase();
  if (kindRaw !== 'rtm' && kindRaw !== 'rtc') {
    return c.json({ error: 'kind must be rtm or rtc' }, 400);
  }
  const kind = kindRaw as 'rtm' | 'rtc';

  const channel = (c.req.query('channel') || '').trim();
  if (kind === 'rtc') {
    if (!channel) {
      return c.json({ error: 'channel is required for rtc' }, 400);
    }
    // 큐알쳇 트래픽 분리: Eggplant 클라이언트는 반드시 'eggplant_' prefix 만 사용.
    if (!channel.startsWith('eggplant_')) {
      return c.json(
        { error: 'channel must start with eggplant_', code: 'bad_channel' },
        400,
      );
    }
    if (channel.length > 64) {
      return c.json({ error: 'channel too long' }, 400);
    }
  }

  // 서버에서 직접 wallet_address 조회 → UID 재계산 (위장 차단)
  const row = await env.DB
    .prepare('SELECT wallet_address FROM users WHERE id = ?')
    .bind(me.id)
    .first<{ wallet_address: string | null }>();
  if (!row) return c.json({ error: 'User not found' }, 404);

  // 지갑 없는 회원은 'u_<id>' 로 (chat-hub 의 채널 계산과 같은 규칙)
  const uid = await walletToAgoraUid(callIdentity(row.wallet_address, me.id));

  // 통화 채널은 'eggplant_call_<lo>_<hi>' (양쪽 지갑의 Agora UID 오름차순).
  // 요청자 UID 가 채널의 두 참여자 중 하나일 때만 토큰을 준다. 이게 없으면
  // 공개된 지갑주소로 남의 채널명을 계산해 통화에 끼어들 수 있었다.
  if (kind === 'rtc') {
    const m = /^eggplant_call_(\d{1,10})_(\d{1,10})$/.exec(channel);
    if (!m || (Number(m[1]) !== uid && Number(m[2]) !== uid)) {
      return c.json(
        { error: 'not a participant of this channel', code: 'bad_channel' },
        403,
      );
    }
  }

  const expireAt = Math.floor(Date.now() / 1000) + 3600;

  // 캐시 컬럼 갱신 (best-effort, 실패해도 토큰 발급은 진행)
  try {
    await env.DB
      .prepare('UPDATE users SET agora_uid = ? WHERE id = ? AND (agora_uid IS NULL OR agora_uid != ?)')
      .bind(uid, me.id, uid)
      .run();
  } catch (e) {
    // agora_uid 컬럼이 없는 환경(미마이그레이션) 무시
    console.log('[agora] uid cache update skipped:', e);
  }

  let token: string;
  try {
    token = await buildAgoraToken({
      appId: agoraAppId,
      appCertificate: agoraAppCert,
      uid,
      channel: kind === 'rtc' ? channel : undefined,
      expireAt,
      kind,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.log('[agora] token build error:', msg);
    return c.json({ error: 'token build failed' }, 500);
  }

  return c.json({
    token,
    uid,
    expire_at: expireAt,
    channel: kind === 'rtc' ? channel : null,
    kind,
    // 클라이언트가 서버 발급 AppID 와 동일한 값으로 join 하도록 명시 반환.
    // (AGORA_APP_ID_EGGPLANT 우선, 없으면 legacy AGORA_APP_ID.)
    // 클라/서버 AppID 불일치로 인한 invalidToken 을 원천 차단.
    app_id: agoraAppId,
  });
});

/**
 * POST /api/users/me/push-token  (3차 푸시 — placeholder 모드)
 *
 * Body: { fcm_token: string, platform?: 'android'|'ios' }
 *
 * 정책:
 *  - FCM 토큰만 저장. 푸시 본문/이력은 D1 에 절대 저장 X (0022 휘발성).
 *  - 토큰은 OS 가 발급한 디바이스 식별자라 Google 계정과 무관 (익명성 유지).
 *  - placeholder 모드: Firebase 프로젝트 미생성 상태에서도 라우트는 정상 동작.
 *    클라이언트는 토큰 발급 실패 시 빈 문자열을 보내며, 서버는 NULL 로 갱신.
 *  - iOS APNs 는 코드베이스에 빌드 자체가 없어 별도 처리 X (Android only).
 */
app.post('/me/push-token', authMiddleware, async (c) => {
  const me = c.get('user');
  if (!me) return c.json({ error: 'unauthorized' }, 401);

  let body: { fcm_token?: string; platform?: string };
  try {
    body = (await c.req.json()) as typeof body;
  } catch {
    return c.json({ error: 'invalid_body' }, 400);
  }
  const env = c.env as Env;

  // 빈 문자열 / null → 토큰 폐기 (logout / 푸시 거부 시).
  const raw = (body.fcm_token ?? '').trim();
  const token = raw.length === 0 ? null : raw;

  // 길이 제한 (FCM 토큰은 보통 ~163자, 최대 ~250자).
  if (token && token.length > 512) {
    return c.json({ error: 'token_too_long' }, 400);
  }

  const now = new Date().toISOString();
  try {
    await env.DB.prepare(
      'UPDATE users SET fcm_token = ?, push_updated_at = ?, updated_at = ? WHERE id = ?',
    )
      .bind(token, token ? now : null, now, me.id)
      .run();
  } catch (e) {
    // 0024 마이그레이션 미적용 환경 → silent skip.
    console.log('[push-token] update skipped:', e);
    return c.json({ ok: true, applied: false });
  }
  return c.json({ ok: true, applied: true });
});

export default app;
