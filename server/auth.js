import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || 'eggplant-dev-secret';

export function signToken(user) {
  return jwt.sign(
    { id: user.id, nickname: user.nickname, device_uuid: user.device_uuid },
    JWT_SECRET,
    { expiresIn: '90d' }
  );
}

export function verifyToken(token) {
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch {
    return null;
  }
}

/** Express middleware requiring a valid JWT. */
export function authMiddleware(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Unauthorized' });

  const payload = verifyToken(token);
  if (!payload) return res.status(401).json({ error: 'Invalid token' });

  req.user = payload;
  next();
}

/** Optional auth - attaches req.user if valid, but does not reject. */
export function optionalAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (token) {
    const payload = verifyToken(token);
    if (payload) req.user = payload;
  }
  next();
}
