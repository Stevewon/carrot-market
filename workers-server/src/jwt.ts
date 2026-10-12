import jwt from '@tsndr/cloudflare-worker-jwt';
import type { Context, MiddlewareHandler, Next } from 'hono';
import type { AuthPayload, Env, UserRow, Variables } from './types';
import { tr } from './market';

const JWT_EXPIRY_SECONDS = 60 * 60 * 24 * 90; // 90 days

export async function signToken(user: UserRow, secret: string): Promise<string> {
  const payload: AuthPayload = {
    id: user.id,
    nickname: user.nickname,
    device_uuid: user.device_uuid,
    tv: user.token_version ?? 1,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + JWT_EXPIRY_SECONDS,
  };
  return jwt.sign(payload, secret);
}

export async function verifyToken(token: string, secret: string): Promise<AuthPayload | null> {
  try {
    const isValid = await jwt.verify(token, secret);
    if (!isValid) return null;
    const { payload } = jwt.decode(token);
    return payload as AuthPayload;
  } catch {
    return null;
  }
}

export type SessionFailure = 'not_found' | 'token_revoked' | 'device_mismatch' | 'banned';

/** 정지 여부 (migration 0026 user_bans — 행이 있으면 정지). */
export async function isUserBanned(db: D1Database, userId: string): Promise<boolean> {
  const row = await db
    .prepare('SELECT 1 AS b FROM user_bans WHERE user_id = ?')
    .bind(userId)
    .first<{ b: number }>();
  return !!row;
}

/**
 * JWT 서명 검증 이후의 DB 기준 세션 검사. REST 미들웨어와 WebSocket(ChatHub)
 * 접속이 같은 기준을 쓰도록 한 곳에 둔다.
 *   - `tv` (token_version) + `device_uuid` 가 users 행과 일치해야 함
 *     (비밀번호 재설정·로그아웃·다른 기기 로그인 시 기존 토큰 무효화)
 *   - 정지(user_bans)된 계정이면 거부
 * 통과하면 null, 아니면 실패 사유.
 */
export async function checkSession(
  db: D1Database,
  payload: Pick<AuthPayload, 'id' | 'device_uuid' | 'tv'>,
): Promise<SessionFailure | null> {
  const row = await db
    .prepare(
      `SELECT u.token_version, u.device_uuid,
              EXISTS (SELECT 1 FROM user_bans b WHERE b.user_id = u.id) AS banned
         FROM users u WHERE u.id = ?`,
    )
    .bind(payload.id)
    .first<{ token_version: number; device_uuid: string; banned: number }>();

  if (!row) return 'not_found';
  if ((row.token_version ?? 1) !== (payload.tv ?? 1)) return 'token_revoked';
  if (payload.device_uuid && row.device_uuid && payload.device_uuid !== row.device_uuid) {
    return 'device_mismatch';
  }
  if (row.banned) return 'banned';
  return null;
}

/**
 * Required auth middleware.
 *
 * Two layers of validation:
 *   1. JWT signature + expiry via verifyToken.
 *   2. checkSession: token_version / device_uuid / 정지 여부를 D1 과 대조.
 *      This means when a password is reset, or another device logs in with
 *      the same wallet, the previous device's token gets 401 on the very
 *      next request — "someone else logging in" no longer sticks.
 */
export const authMiddleware: MiddlewareHandler<{
  Bindings: Env;
  Variables: Variables;
}> = async (c, next) => {
  const header = c.req.header('authorization') || c.req.header('Authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return c.json({ error: 'Unauthorized' }, 401);

  const payload = await verifyToken(token, c.env.JWT_SECRET);
  if (!payload) return c.json({ error: 'Invalid token' }, 401);

  const failure = await checkSession(c.env.DB, payload);
  switch (failure) {
    case 'not_found':
      return c.json({ error: 'Account not found' }, 401);
    case 'token_revoked':
      return c.json({ error: 'Session expired', code: 'token_revoked' }, 401);
    case 'device_mismatch':
      return c.json({ error: 'Session moved to another device', code: 'device_mismatch' }, 401);
    case 'banned':
      return c.json({ error: tr(c, '이용이 정지된 계정이에요. 고객센터로 문의해주세요', 'このアカウントは利用停止中です。お問い合わせ窓口までご連絡ください', 'This account has been suspended. Please contact customer support'), code: 'banned' }, 403);
  }

  c.set('user', payload);
  await next();
};

/** Optional auth - attaches user if token is valid, otherwise continues anonymously. */
export const optionalAuth: MiddlewareHandler<{
  Bindings: Env;
  Variables: Variables;
}> = async (c, next) => {
  const header = c.req.header('authorization') || c.req.header('Authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (token) {
    const payload = await verifyToken(token, c.env.JWT_SECRET);
    // Same DB-backed check as authMiddleware, but silently ignore on failure.
    if (payload && (await checkSession(c.env.DB, payload)) === null) {
      c.set('user', payload);
    }
  }
  await next();
};

/**
 * 운영자 전용 미들웨어. authMiddleware 다음에 체이닝해서 사용.
 *
 *   app.use('/admin/*', authMiddleware, adminMiddleware)
 *
 * 검증 방식:
 *   - `c.get('user')` 의 id 가 환경변수 `ADMIN_USER_IDS` (쉼표 구분) 안에 있으면 통과.
 *   - ADMIN_USER_IDS 가 비어 있거나 등록되지 않은 user_id 면 403.
 *   - 평문 패스워드/토큰을 추가로 받지 않는다 — 운영자도 보통 사용자 계정으로
 *     로그인한 다음 동일 JWT 로 admin 라우트를 호출한다.
 */
export const adminMiddleware: MiddlewareHandler<{
  Bindings: Env;
  Variables: Variables;
}> = async (c, next) => {
  const user = c.get('user');
  if (!user) return c.json({ error: 'Unauthorized' }, 401);

  const raw = (c.env.ADMIN_USER_IDS || '').trim();
  if (!raw) {
    // fail-closed: 운영자 명단이 설정 안 됐으면 누구도 admin 아님.
    return c.json({ error: 'admin not configured' }, 403);
  }
  const allow = new Set(
    raw.split(',').map((s) => s.trim()).filter(Boolean),
  );
  if (!allow.has(user.id)) {
    return c.json({ error: 'Forbidden (admin only)' }, 403);
  }
  await next();
};

/**
 * 별도 어드민 토큰 미들웨어 (웹 어드민 admin.eggplant.life 전용).
 *
 * 사용자 JWT 와 완전 분리:
 *   - 헤더: `Authorization: Admin <ADMIN_TOKEN>`
 *   - Workers Secrets 의 ADMIN_TOKEN 과 정확히 일치해야 통과
 *   - 미설정 시 503 (fail-closed)
 *
 * 등록:
 *   wrangler secret put ADMIN_TOKEN
 *   # → 32자 이상 hex/base64 랜덤 문자열 권장
 *
 * 보안 권고:
 *   - PC 전용 (모바일 차단은 클라이언트 가드)
 *   - HTTPS 필수 (Workers 는 기본)
 *   - 토큰 노출 시 즉시 secret 교체
 */
export const requireAdminToken: MiddlewareHandler<{
  Bindings: Env;
  Variables: Variables;
}> = async (c, next) => {
  const expected = (c.env.ADMIN_TOKEN || '').trim();
  if (!expected) {
    // fail-closed: 토큰 미설정 시 어드민 비활성
    return c.json({ error: 'admin disabled' }, 503);
  }

  const header = c.req.header('authorization') || c.req.header('Authorization') || '';
  const token = header.startsWith('Admin ') ? header.slice(6).trim() : '';
  if (!token) {
    return c.json({ error: 'admin token required' }, 401);
  }

  // timing-safe compare (charCode XOR) — 단순 === 비교는 timing attack 가능성
  if (token.length !== expected.length) {
    return c.json({ error: 'invalid admin token' }, 401);
  }
  let diff = 0;
  for (let i = 0; i < token.length; i++) {
    diff |= token.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  if (diff !== 0) {
    return c.json({ error: 'invalid admin token' }, 401);
  }

  await next();
};
