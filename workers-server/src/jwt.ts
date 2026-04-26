import jwt from '@tsndr/cloudflare-worker-jwt';
import type { Context, MiddlewareHandler, Next } from 'hono';
import type { AuthPayload, Env, UserRow, Variables } from './types';

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

/**
 * Required auth middleware.
 *
 * Two layers of validation:
 *   1. JWT signature + expiry via verifyToken.
 *   2. `tv` (token_version) + `device_uuid` must match the row in D1.
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

  // Re-validate against DB.
  const row = await c.env.DB
    .prepare('SELECT token_version, device_uuid FROM users WHERE id = ?')
    .bind(payload.id)
    .first<{ token_version: number; device_uuid: string }>();

  if (!row) return c.json({ error: 'Account not found' }, 401);

  const currentTv = row.token_version ?? 1;
  const tokenTv = payload.tv ?? 1;
  if (currentTv !== tokenTv) {
    return c.json({ error: 'Session expired', code: 'token_revoked' }, 401);
  }
  if (payload.device_uuid && row.device_uuid && payload.device_uuid !== row.device_uuid) {
    return c.json({ error: 'Session moved to another device', code: 'device_mismatch' }, 401);
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
    if (payload) {
      // Same DB-backed check as authMiddleware, but silently ignore on failure.
      const row = await c.env.DB
        .prepare('SELECT token_version, device_uuid FROM users WHERE id = ?')
        .bind(payload.id)
        .first<{ token_version: number; device_uuid: string }>();
      if (row && (row.token_version ?? 1) === (payload.tv ?? 1) &&
          (!payload.device_uuid || row.device_uuid === payload.device_uuid)) {
        c.set('user', payload);
      }
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
