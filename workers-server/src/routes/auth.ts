import { Hono } from 'hono';
import type { Env, UserRow, UserPublic, Variables } from '../types';
import { authMiddleware, signToken } from '../jwt';
import {
  hashPassword,
  verifyPassword,
  isValidWallet,
  normalizeWallet,
} from '../crypto';
import {
  grantSignupBonus,
  grantLoginDailyBonus,
  grantReferralBonus,
  clawbackReferralsOnDelete,
  QTA_LOGIN_DAILY_MAX,
  QTA_REFERRAL_BONUS,
} from '../qta';


const app = new Hono<{ Bindings: Env; Variables: Variables }>();

// ---------- Validation helpers ----------

const NICK_MIN = 2;
const NICK_MAX = 12;
const PW_MIN = 8;
const PW_MAX = 64;

function validatePassword(pw: unknown): string | null {
  if (typeof pw !== 'string') return '비밀번호를 입력해주세요';
  if (pw.length < PW_MIN) return `비밀번호는 ${PW_MIN}자 이상이어야 해요`;
  if (pw.length > PW_MAX) return `비밀번호는 ${PW_MAX}자 이하여야 해요`;
  return null;
}

function validateNickname(n: unknown): string | null {
  if (typeof n !== 'string') return '닉네임을 입력해주세요';
  const trimmed = n.trim();
  if (trimmed.length < NICK_MIN) return `닉네임은 ${NICK_MIN}자 이상이어야 해요`;
  if (trimmed.length > NICK_MAX) return `닉네임은 ${NICK_MAX}자 이하여야 해요`;
  return null;
}

/** Strip sensitive fields before returning to client. */
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
    verified_at: u.verified_at ?? null,
    bank_registered_at: u.bank_registered_at ?? null,
    created_at: u.created_at,
    updated_at: u.updated_at,
  };
}

// ================================================================
// SSO: 퀀타리움 지갑주소 = Universal User ID
//
// POST /api/auth/sso/exchange
// Body: {
//   wallet_address: '0x...',     // 필수
//   provider: 'qrchat',          // 'qrchat' / 'eggplant_self'
//   external_token?: '...',      // QRChat 발급 토큰 (선택)
//   nickname?: '...',            // 신규 가입 시 사용 (선택, 없으면 자동 생성)
//   device_uuid: '...'           // 필수
// }
//
// 동작:
//   1) wallet_address 로 가지 users 조회
//   2) 있으면 → token_version 그대로, device_uuid 만 갱신, 가지 JWT 발급
//   3) 없으면 → 신규 user 생성 (password_hash NULL = SSO-only 계정),
//      가입 보너스 +500 QTA 지급, 가지 JWT 발급
//   4) sso_links 에 (provider, user_id, wallet, device) 기록/갱신
//
// 보안:
//   - 현재는 external_token 의 형식만 점검(미래 QRChat 공개키 검증 자리 마련).
//     QRChat 측 SDK 가 공개되면 jwks 로 서명 검증 추가.
//   - SSO-only 계정은 password 로 직접 로그인 불가 (NULL hash → verifyPassword 실패).
// ================================================================
app.post('/sso/exchange', async (c) => {
  let body: {
    wallet_address?: string;
    provider?: string;
    external_token?: string;
    external_id?: string;
    nickname?: string;
    device_uuid?: string;
    region?: string;
  } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const { wallet_address, provider, external_token, external_id, device_uuid } =
    body;

  if (!wallet_address || !isValidWallet(wallet_address)) {
    return c.json(
      { error: '퀀타리움 지갑주소 형식을 확인해주세요 (0x + 40자리)' },
      400,
    );
  }
  if (!device_uuid || typeof device_uuid !== 'string' || device_uuid.length < 8) {
    return c.json({ error: '기기 정보가 올바르지 않아요' }, 400);
  }
  const prov = (provider ?? 'qrchat').trim().toLowerCase();
  if (!/^[a-z0-9_]{2,32}$/.test(prov)) {
    return c.json({ error: '잘못된 provider' }, 400);
  }

  // QRChat 토큰 검증 자리. 현재는 형식만 확인(64~2048 글자).
  // QRChat SDK 의 공개키/JWKS 가 확정되면 여기서 jwt.verify 추가.
  if (external_token != null) {
    if (typeof external_token !== 'string' ||
        external_token.length < 8 ||
        external_token.length > 4096) {
      return c.json({ error: '외부 토큰 형식이 올바르지 않아요' }, 400);
    }
  }

  const walletNorm = normalizeWallet(wallet_address);

  // 1) 기존 user 조회.
  let user = await c.env.DB
    .prepare('SELECT * FROM users WHERE wallet_address = ? COLLATE NOCASE')
    .bind(walletNorm)
    .first<UserRow>();

  let createdNew = false;
  let signupBonusGranted = false;

  if (!user) {
    // 2) 신규 가입 — SSO-only 계정 (password_hash = NULL).
    let nick = (body.nickname ?? '').trim();
    if (!nick) {
      // 닉네임 미지정 시 walletAddress 끝 6자리로 자동 생성.
      const tail = walletNorm.slice(-6).toLowerCase();
      nick = `사용자${tail}`;
    } else {
      const ne = validateNickname(nick);
      if (ne) return c.json({ error: ne }, 400);
    }
    // 닉네임 중복 시 뒤에 접미사 자동 추가 (최대 5회 시도).
    let finalNick = nick;
    for (let i = 0; i < 5; i++) {
      const taken = await c.env.DB
        .prepare('SELECT id FROM users WHERE nickname = ? COLLATE NOCASE')
        .bind(finalNick)
        .first<{ id: string }>();
      if (!taken) break;
      const tail = walletNorm.slice(-4 - i, -1).toLowerCase();
      finalNick = `${nick}_${tail}`;
    }

    const id = crypto.randomUUID();
    try {
      // device_uuid 가 다른 계정에 묶여 있으면 token_version 만 bump 해서 풀어준다.
      await c.env.DB
        .prepare(
          `UPDATE users
              SET device_uuid = 'released:' || id,
                  token_version = token_version + 1,
                  updated_at = datetime('now')
            WHERE device_uuid = ? AND id != ?`,
        )
        .bind(device_uuid, id)
        .run();
    } catch (e) {
      console.error('[auth/sso] device cleanup failed', e);
    }

    let insertedNew = false;
    try {
      await c.env.DB
        .prepare(
          `INSERT INTO users
             (id, nickname, device_uuid, wallet_address, password_hash, region, token_version)
           VALUES (?, ?, ?, ?, NULL, ?, 1)`,
        )
        .bind(id, finalNick, device_uuid, walletNorm, body.region ?? null)
        .run();
      insertedNew = true;
    } catch (e) {
      const msg = String((e as Error)?.message || e);
      console.error('[auth/sso] INSERT failed:', msg);
      if (/UNIQUE constraint failed: users\.wallet_address/i.test(msg)) {
        // race — 같은 지갑이 동시에 들어왔으면 다시 조회.
        const fetched = await c.env.DB
          .prepare('SELECT * FROM users WHERE wallet_address = ? COLLATE NOCASE')
          .bind(walletNorm)
          .first<UserRow>();
        if (!fetched) return c.json({ error: 'SSO 처리 중 오류' }, 500);
        user = fetched;
      } else {
        return c.json({ error: 'SSO 가입 중 오류가 발생했어요' }, 500);
      }
    }

    if (insertedNew) {
      // 가입 보너스 +500 QTA (멱등).
      try {
        await grantSignupBonus(c.env, id);
        signupBonusGranted = true;
      } catch (e) {
        console.error('[auth/sso] signup bonus failed', e);
      }
      const fetched = await c.env.DB
        .prepare('SELECT * FROM users WHERE id = ?')
        .bind(id)
        .first<UserRow>();
      if (!fetched) return c.json({ error: '사용자 생성 실패' }, 500);
      user = fetched;
      createdNew = true;
    }
  } else {
    // 3) 기존 user — device_uuid 갱신 (다른 기기에서 로그인하면 자연 교체).
    if (user.device_uuid !== device_uuid) {
      const existingId = user.id;
      try {
        // 다른 계정이 이 device_uuid 를 들고 있으면 풀어준다.
        await c.env.DB
          .prepare(
            `UPDATE users
                SET device_uuid = 'released:' || id,
                    token_version = token_version + 1,
                    updated_at = datetime('now')
              WHERE device_uuid = ? AND id != ?`,
          )
          .bind(device_uuid, existingId)
          .run();
        await c.env.DB
          .prepare(
            `UPDATE users
                SET device_uuid = ?,
                    token_version = token_version + 1,
                    updated_at = datetime('now')
              WHERE id = ?`,
          )
          .bind(device_uuid, existingId)
          .run();
        const fetched = await c.env.DB
          .prepare('SELECT * FROM users WHERE id = ?')
          .bind(existingId)
          .first<UserRow>();
        if (!fetched) return c.json({ error: 'SSO 갱신 실패' }, 500);
        user = fetched;
      } catch (e) {
        console.error('[auth/sso] device update failed', e);
      }
    }
  }

  // 여기까지 오면 user 는 반드시 채워져 있어야 한다 (모든 분기에서 보장).
  // TS narrowing 보강용 명시적 가드.
  if (!user) return c.json({ error: 'SSO 처리 실패' }, 500);
  const finalUser: UserRow = user;

  // 4) sso_links 기록/갱신 (멱등 upsert by provider+user).
  try {
    await c.env.DB
      .prepare(
        `INSERT INTO sso_links
           (id, user_id, provider, external_id, wallet_address, device_uuid, last_seen_at)
         VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
         ON CONFLICT(provider, user_id) DO UPDATE SET
           external_id    = COALESCE(excluded.external_id, sso_links.external_id),
           wallet_address = excluded.wallet_address,
           device_uuid    = excluded.device_uuid,
           last_seen_at   = datetime('now')`,
      )
      .bind(
        crypto.randomUUID(),
        finalUser.id,
        prov,
        external_id ?? null,
        walletNorm,
        device_uuid,
      )
      .run();
  } catch (e) {
    console.error('[auth/sso] sso_links upsert failed', e);
  }

  // 5) 일일 로그인 보너스 (가입 직후엔 패스, 기존 사용자만).
  let loginBonus: { credited: boolean; remaining: number } | null = null;
  if (!createdNew) {
    try {
      const r = await grantLoginDailyBonus(c.env, finalUser.id);
      loginBonus = { credited: r.credited, remaining: r.remaining };
    } catch (e) {
      console.error('[auth/sso] login bonus failed', e);
    }
  }

  const token = await signToken(finalUser, c.env.JWT_SECRET);
  return c.json({
    token,
    user: sanitize(finalUser),
    sso: {
      provider: prov,
      created_new: createdNew,
      signup_bonus_granted: signupBonusGranted,
    },
    login_bonus: loginBonus,
  });
});

// ================================================================
// POST /api/auth/register
// Body: { wallet_address, nickname, password, password_confirm, device_uuid, region? }
// ================================================================
app.post('/register', async (c) => {
  let body: {
    wallet_address?: string;
    nickname?: string;
    password?: string;
    password_confirm?: string;
    device_uuid?: string;
    region?: string;
    referrer_nickname?: string; // 친구 초대 — 추천인 닉네임 (선택)
  } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const { wallet_address, nickname, password, password_confirm, device_uuid, region, referrer_nickname } = body;

  // --- Validate ---
  if (!wallet_address || !isValidWallet(wallet_address)) {
    return c.json({ error: '퀀타리움 지갑주소 형식을 확인해주세요 (0x + 40자리)' }, 400);
  }
  const nickErr = validateNickname(nickname);
  if (nickErr) return c.json({ error: nickErr }, 400);

  const pwErr = validatePassword(password);
  if (pwErr) return c.json({ error: pwErr }, 400);
  if (password !== password_confirm) {
    return c.json({ error: '비밀번호가 일치하지 않아요' }, 400);
  }

  if (!device_uuid || typeof device_uuid !== 'string' || device_uuid.length < 8) {
    return c.json({ error: '기기 정보가 올바르지 않아요' }, 400);
  }

  const walletNorm = normalizeWallet(wallet_address);
  const cleanNick = nickname!.trim();

  // --- Duplicate checks ---
  const walletTaken = await c.env.DB
    .prepare('SELECT id FROM users WHERE wallet_address = ? COLLATE NOCASE')
    .bind(walletNorm)
    .first<{ id: string }>();
  if (walletTaken) {
    return c.json({ error: '이미 가입된 지갑주소예요' }, 409);
  }

  const nickTaken = await c.env.DB
    .prepare('SELECT id FROM users WHERE nickname = ? COLLATE NOCASE')
    .bind(cleanNick)
    .first<{ id: string }>();
  if (nickTaken) {
    return c.json({ error: '이미 사용 중인 닉네임이에요' }, 409);
  }

  // --- Create ---
  const hash = await hashPassword(password!);
  const id = crypto.randomUUID();

  // Safety net: if migration 0005 hasn't been applied yet and this device_uuid
  // was previously bound to some other wallet, free it up by nulling the old
  // binding and bumping that user's token_version so their session dies on the
  // next request. (Post-0005 this is a no-op because the column isn't UNIQUE.)
  try {
    await c.env.DB
      .prepare(`
        UPDATE users
           SET device_uuid = 'released:' || id,
               token_version = token_version + 1,
               updated_at = datetime('now')
         WHERE device_uuid = ? AND id != ?
      `)
      .bind(device_uuid, id)
      .run();
  } catch (e) {
    // Ignore — this is best-effort cleanup.
    console.error('[auth/register] device_uuid cleanup:', e);
  }

  try {
    await c.env.DB
      .prepare(`
        INSERT INTO users
          (id, nickname, device_uuid, wallet_address, password_hash, region, token_version)
        VALUES (?, ?, ?, ?, ?, ?, 1)
      `)
      .bind(id, cleanNick, device_uuid, walletNorm, hash, region || null)
      .run();
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    console.error('[auth/register] INSERT failed:', msg);
    // Surface the common schema-level failures with friendly Korean messages.
    if (/UNIQUE constraint failed: users\.wallet_address/i.test(msg)) {
      return c.json({ error: '이미 가입된 지갑주소예요' }, 409);
    }
    if (/UNIQUE constraint failed: users\.nickname/i.test(msg)) {
      return c.json({ error: '이미 사용 중인 닉네임이에요' }, 409);
    }
    if (/UNIQUE constraint failed: users\.device_uuid/i.test(msg)) {
      return c.json(
        { error: '이 기기에 다른 계정이 남아있어요. 앱을 재설치하거나 관리자에게 문의해주세요.' },
        409,
      );
    }
    return c.json({ error: '가입 중 오류가 발생했어요' }, 500);
  }

  // ── 가입 보너스 +500 QTA (멱등) ──────────────────────────────
  // INSERT 직후 grantSignupBonus 가 ledger 1행 + qta_balance + 500 처리.
  try {
    await grantSignupBonus(c.env, id);
  } catch (e) {
    console.error('[auth/register] signup bonus failed', e);
    // 보너스 실패해도 가입 자체는 성공으로 본다 (사용자 입장에서 재시도 어려움).
  }

  // ── 친구 초대 보너스 (추천인에게 +200 QTA, 무제한, best-effort) ──
  let referralResult: { credited: boolean; inviter_nickname?: string; reason?: string } | null = null;
  if (referrer_nickname && typeof referrer_nickname === 'string' && referrer_nickname.trim()) {
    const refTrim = referrer_nickname.trim();
    if (refTrim.toLowerCase() === cleanNick.toLowerCase()) {
      referralResult = { credited: false, reason: 'self_referral' };
    } else {
      try {
        const inviter = await c.env.DB
          .prepare('SELECT id, nickname FROM users WHERE nickname = ? COLLATE NOCASE')
          .bind(refTrim)
          .first<{ id: string; nickname: string }>();
        if (!inviter) {
          referralResult = { credited: false, reason: 'inviter_not_found' };
        } else {
          const r = await grantReferralBonus(c.env, inviter.id, id);
          referralResult = { credited: r.credited, inviter_nickname: inviter.nickname, reason: r.reason };
        }
      } catch (e) {
        console.error('[auth/register] referral grant failed', e);
        referralResult = { credited: false, reason: 'error' };
      }
    }
  }

  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(id)
    .first<UserRow>();
  if (!user) return c.json({ error: '사용자 생성 실패' }, 500);

  const token = await signToken(user, c.env.JWT_SECRET);
  return c.json({
    token,
    user: sanitize(user),
    qta_bonus: { reason: 'signup', amount: 500 },
    referral: referralResult
      ? {
          credited: referralResult.credited,
          inviter_nickname: referralResult.inviter_nickname ?? null,
          inviter_bonus: referralResult.credited ? QTA_REFERRAL_BONUS : 0,
          reason: referralResult.reason ?? null,
        }
      : null,
  }, 201);
});

// ================================================================
// POST /api/auth/login
// Body: { nickname, password, device_uuid }
//
// Nickname is the display name AND the login ID (unique, COLLATE NOCASE).
// Wallet address is only used for signup and for recovery (finding
// nickname / resetting password).
//
// On success:
//  - If the new device_uuid differs from the one on file, we *replace* it
//    and bump token_version. This invalidates the previous device's JWT.
// ================================================================
app.post('/login', async (c) => {
  let body: { nickname?: string; password?: string; device_uuid?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const { nickname, password, device_uuid } = body;
  if (!nickname || typeof nickname !== 'string' || !nickname.trim()) {
    return c.json({ error: '닉네임을 입력해주세요' }, 400);
  }
  if (!password || typeof password !== 'string') {
    return c.json({ error: '비밀번호를 입력해주세요' }, 400);
  }
  if (!device_uuid || typeof device_uuid !== 'string' || device_uuid.length < 8) {
    return c.json({ error: '기기 정보가 올바르지 않아요' }, 400);
  }

  const nickTrim = nickname.trim();
  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE nickname = ? COLLATE NOCASE')
    .bind(nickTrim)
    .first<UserRow>();

  // Intentionally same error for "not found" vs "wrong password" to avoid
  // leaking which nicknames are registered.
  const ok = user && user.password_hash
    ? await verifyPassword(password, user.password_hash)
    : false;
  if (!user || !ok) {
    return c.json({ error: '닉네임 또는 비밀번호가 올바르지 않아요' }, 401);
  }

  // If logging in from a new device, kick the old device out.
  let tokenVersion = user.token_version ?? 1;
  if (user.device_uuid !== device_uuid) {
    tokenVersion += 1;
    await c.env.DB
      .prepare("UPDATE users SET device_uuid = ?, token_version = ?, updated_at = datetime('now') WHERE id = ?")
      .bind(device_uuid, tokenVersion, user.id)
      .run();
    user.device_uuid = device_uuid;
    user.token_version = tokenVersion;
  }

  // ── 일일 로그인 보너스 +10 QTA (하루 3회) ─────────────────────
  let qtaBonus: { credited: boolean; count: number; remaining: number; amount: number } | null = null;
  try {
    const r = await grantLoginDailyBonus(c.env, user.id);
    qtaBonus = { ...r, amount: r.credited ? 10 : 0 };
    if (r.credited) {
      // 응답 sanitize 가 정확한 잔액을 반영하도록 row 다시 읽기.
      const fresh = await c.env.DB
        .prepare('SELECT qta_balance FROM users WHERE id = ?')
        .bind(user.id)
        .first<{ qta_balance: number }>();
      if (fresh) user.qta_balance = fresh.qta_balance;
    }
  } catch (e) {
    console.error('[auth/login] login bonus failed', e);
  }

  const token = await signToken(user, c.env.JWT_SECRET);
  return c.json({
    token,
    user: sanitize(user),
    qta_bonus: qtaBonus
      ? {
          reason: 'login_daily',
          credited: qtaBonus.credited,
          amount: qtaBonus.amount,
          today_count: qtaBonus.count,
          today_max: QTA_LOGIN_DAILY_MAX,
          remaining: qtaBonus.remaining,
        }
      : null,
  });
});

// ================================================================
// POST /api/auth/recover/nickname
// Body: { wallet_address }
// Returns: { nickname }  (safe: nickname is public info)
// ================================================================
app.post('/recover/nickname', async (c) => {
  let body: { wallet_address?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }
  if (!body.wallet_address || !isValidWallet(body.wallet_address)) {
    return c.json({ error: '지갑주소 형식을 확인해주세요 (0x + 40자리)' }, 400);
  }

  const walletNorm = normalizeWallet(body.wallet_address);
  const row = await c.env.DB
    .prepare('SELECT nickname FROM users WHERE wallet_address = ? COLLATE NOCASE')
    .bind(walletNorm)
    .first<{ nickname: string }>();

  if (!row) return c.json({ error: '가입되지 않은 지갑주소예요' }, 404);
  return c.json({ nickname: row.nickname });
});

// ================================================================
// POST /api/auth/reset-password
// Body: { wallet_address, new_password, new_password_confirm, device_uuid }
//
// Password reset via wallet ownership (the wallet IS the credential).
// Bumps token_version so any still-active sessions are invalidated.
// Returns a fresh token for the caller's device.
// ================================================================
app.post('/reset-password', async (c) => {
  let body: {
    wallet_address?: string;
    new_password?: string;
    new_password_confirm?: string;
    device_uuid?: string;
  } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const { wallet_address, new_password, new_password_confirm, device_uuid } = body;
  if (!wallet_address || !isValidWallet(wallet_address)) {
    return c.json({ error: '지갑주소 형식을 확인해주세요 (0x + 40자리)' }, 400);
  }
  const pwErr = validatePassword(new_password);
  if (pwErr) return c.json({ error: pwErr }, 400);
  if (new_password !== new_password_confirm) {
    return c.json({ error: '비밀번호가 일치하지 않아요' }, 400);
  }
  if (!device_uuid || typeof device_uuid !== 'string' || device_uuid.length < 8) {
    return c.json({ error: '기기 정보가 올바르지 않아요' }, 400);
  }

  const walletNorm = normalizeWallet(wallet_address);
  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE wallet_address = ? COLLATE NOCASE')
    .bind(walletNorm)
    .first<UserRow>();
  if (!user) return c.json({ error: '가입되지 않은 지갑주소예요' }, 404);

  const hash = await hashPassword(new_password!);
  const newVersion = (user.token_version ?? 1) + 1;

  await c.env.DB
    .prepare(`
      UPDATE users
      SET password_hash = ?, token_version = ?, device_uuid = ?, updated_at = datetime('now')
      WHERE id = ?
    `)
    .bind(hash, newVersion, device_uuid, user.id)
    .run();

  user.password_hash = hash;
  user.token_version = newVersion;
  user.device_uuid = device_uuid;

  const token = await signToken(user, c.env.JWT_SECRET);
  return c.json({ token, user: sanitize(user) });
});

// ================================================================
// POST /api/auth/logout
// Bumps token_version so the current token (and any other active ones)
// are invalidated immediately.
// ================================================================
app.post('/logout', authMiddleware, async (c) => {
  const authUser = c.get('user')!;
  await c.env.DB
    .prepare("UPDATE users SET token_version = token_version + 1, updated_at = datetime('now') WHERE id = ?")
    .bind(authUser.id)
    .run();
  return c.json({ ok: true });
});

// ================================================================
// GET /api/auth/me
// ================================================================
app.get('/me', authMiddleware, async (c) => {
  const authUser = c.get('user')!;
  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(authUser.id)
    .first<UserRow>();
  if (!user) return c.json({ error: 'User not found' }, 404);
  return c.json({ user: sanitize(user) });
});

// ================================================================
// GET /api/auth/check-nickname?nickname=...
// 추천인 닉네임 입력 시 존재 여부 확인 (회원가입 전 사용)
// ================================================================
app.get('/check-nickname', async (c) => {
  const nick = (c.req.query('nickname') || '').trim();
  if (!nick) return c.json({ exists: false });
  const row = await c.env.DB
    .prepare('SELECT nickname FROM users WHERE nickname = ? COLLATE NOCASE')
    .bind(nick)
    .first<{ nickname: string }>();
  return c.json({ exists: !!row, nickname: row?.nickname ?? null });
});

// ================================================================
// DELETE /api/auth/me
// 본인 계정 탈퇴 — "한 번 사라진 건 영구 보관 X"
// Body: { password } (재인증)
//
// 처리 흐름:
//   1) 비밀번호 재확인 (실수 방지)
//   2) 친구 초대 보너스 즉시 회수 (clawbackReferralsOnDelete)
//      - 탈퇴자가 inviter 였으면 탈퇴자 본인에게서 -200 each (어차피 행 삭제되지만 ledger 일관성)
//      - 탈퇴자가 referee 였으면 추천인에게서 -200 회수
//   3) users 행 DELETE → ON DELETE CASCADE 로
//      qta_ledger / qta_daily_login / referrals / hidden_products /
//      keyword_alerts / user_blocks(따로 정리) 등이 자동 정리됨
//   4) 탈퇴자 데이터는 서버에 흔적 없음 (개인정보·잔여 QTA 모두 사라짐)
// ================================================================
app.delete('/me', authMiddleware, async (c) => {
  const authUser = c.get('user')!;
  let body: { password?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    // 비밀번호 없이도 시도 가능하지만 권장 X — 기본 차단.
    return c.json({ error: '비밀번호를 입력해주세요' }, 400);
  }

  const { password } = body;
  if (!password || typeof password !== 'string') {
    return c.json({ error: '비밀번호를 입력해주세요' }, 400);
  }

  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(authUser.id)
    .first<UserRow>();
  if (!user) return c.json({ error: '계정을 찾을 수 없어요' }, 404);

  const ok = user.password_hash
    ? await verifyPassword(password, user.password_hash)
    : false;
  if (!ok) {
    return c.json({ error: '비밀번호가 올바르지 않아요' }, 401);
  }

  // 1) referral 보너스 즉시 회수
  let clawback = { inviter_clawbacks: 0, referee_clawbacks: 0 };
  try {
    clawback = await clawbackReferralsOnDelete(c.env, user.id);
  } catch (e) {
    console.error('[auth/delete] clawback failed', e);
  }

  // 2) 사용자 컨텐츠 best-effort 정리 (CASCADE 가 없는 테이블 대비)
  //    - products 의 lat/lng 는 무관하지만 본인 게시물은 즉시 삭제
  //    - user_blocks (양방향) 정리
  try {
    await c.env.DB.batch([
      c.env.DB.prepare('DELETE FROM products WHERE seller_id = ?').bind(user.id),
      c.env.DB.prepare('DELETE FROM user_blocks WHERE blocker_id = ? OR blocked_id = ?')
        .bind(user.id, user.id),
    ]);
  } catch (e) {
    console.error('[auth/delete] cleanup non-cascade tables failed', e);
  }

  // 3) users 행 DELETE → ON DELETE CASCADE 가 ledger 등을 즉시 청소
  try {
    await c.env.DB.prepare('DELETE FROM users WHERE id = ?').bind(user.id).run();
  } catch (e) {
    console.error('[auth/delete] DELETE users failed', e);
    return c.json({ error: '탈퇴 처리 중 오류가 발생했어요' }, 500);
  }

  return c.json({
    ok: true,
    message: '계정이 영구 삭제되었어요. 모든 흔적이 즉시 사라졌습니다.',
    referral_clawback: clawback,
  });
});

export default app;
