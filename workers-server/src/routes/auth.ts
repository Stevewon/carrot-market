import { Hono } from 'hono';
import type { Env, UserRow, UserPublic, Variables } from '../types';
import { authMiddleware, signToken } from '../jwt';
import {
  hashPassword,
  verifyPassword,
  isValidWallet,
  normalizeWallet,
} from '../crypto';

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
    manner_score: u.manner_score,
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

  await c.env.DB
    .prepare(`
      INSERT INTO users
        (id, nickname, device_uuid, wallet_address, password_hash, region, token_version)
      VALUES (?, ?, ?, ?, ?, ?, 1)
    `)
    .bind(id, cleanNick, device_uuid, walletNorm, hash, region || null)
    .run();

  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(id)
    .first<UserRow>();
  if (!user) return c.json({ error: '사용자 생성 실패' }, 500);

  const token = await signToken(user, c.env.JWT_SECRET);
  return c.json({ token, user: sanitize(user) }, 201);
});

// ================================================================
// POST /api/auth/login
// Body: { wallet_address, password, device_uuid }
//
// On success:
//  - If the new device_uuid differs from the one on file, we *replace* it
//    and bump token_version. This invalidates the previous device's JWT.
// ================================================================
app.post('/login', async (c) => {
  let body: { wallet_address?: string; password?: string; device_uuid?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const { wallet_address, password, device_uuid } = body;
  if (!wallet_address || !isValidWallet(wallet_address)) {
    return c.json({ error: '지갑주소 형식을 확인해주세요 (0x + 40자리)' }, 400);
  }
  if (!password || typeof password !== 'string') {
    return c.json({ error: '비밀번호를 입력해주세요' }, 400);
  }
  if (!device_uuid || typeof device_uuid !== 'string' || device_uuid.length < 8) {
    return c.json({ error: '기기 정보가 올바르지 않아요' }, 400);
  }

  const walletNorm = normalizeWallet(wallet_address);
  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE wallet_address = ? COLLATE NOCASE')
    .bind(walletNorm)
    .first<UserRow>();

  // Intentionally same error for "not found" vs "wrong password" to avoid
  // leaking which wallets are registered.
  const ok = user && user.password_hash
    ? await verifyPassword(password, user.password_hash)
    : false;
  if (!user || !ok) {
    return c.json({ error: '지갑주소 또는 비밀번호가 올바르지 않아요' }, 401);
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

  const token = await signToken(user, c.env.JWT_SECRET);
  return c.json({ token, user: sanitize(user) });
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
