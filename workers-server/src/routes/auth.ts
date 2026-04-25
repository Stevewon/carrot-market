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
  QTA_LOGIN_DAILY_MAX,
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
    created_at: u.created_at,
    updated_at: u.updated_at,
  };
}

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
  } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const { wallet_address, nickname, password, password_confirm, device_uuid, region } = body;

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

export default app;
