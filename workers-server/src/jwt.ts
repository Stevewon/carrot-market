import jwt from '@tsndr/cloudflare-worker-jwt';
import type { Context, MiddlewareHandler, Next } from 'hono';
import type { AuthPayload, Env, UserRow, Variables } from './types';

const JWT_EXPIRY_SECONDS = 60 * 60 * 24 * 90; // 90 days

export async function signToken(user: UserRow, secret: string): Promise<string> {
  const payload: AuthPayload = {
    id: user.id,
    nickname: user.nickname,
    device_uuid: user.device_uuid,
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

/** Required auth middleware. Rejects if no valid Bearer token. */
export const authMiddleware: MiddlewareHandler<{
  Bindings: Env;
  Variables: Variables;
}> = async (c, next) => {
  const header = c.req.header('authorization') || c.req.header('Authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return c.json({ error: 'Unauthorized' }, 401);

  const payload = await verifyToken(token, c.env.JWT_SECRET);
  if (!payload) return c.json({ error: 'Invalid token' }, 401);

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
    if (payload) c.set('user', payload);
  }
  await next();
};
