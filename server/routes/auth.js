import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import db from '../db.js';
import { signToken, authMiddleware } from '../auth.js';

const router = express.Router();

/**
 * Register an anonymous user.
 * Body: { nickname, device_uuid, region? }
 * - If device_uuid already exists, returns that user (re-login).
 */
router.post('/register', (req, res) => {
  const { nickname, device_uuid, region } = req.body || {};
  if (!nickname || typeof nickname !== 'string' || nickname.trim().length < 2) {
    return res.status(400).json({ error: '닉네임은 2자 이상이어야 해요' });
  }
  if (!device_uuid || typeof device_uuid !== 'string') {
    return res.status(400).json({ error: '기기 UUID가 필요해요' });
  }
  const cleanNick = nickname.trim().slice(0, 12);

  // Check if device already has an account - auto-login
  const existing = db.prepare('SELECT * FROM users WHERE device_uuid = ?').get(device_uuid);
  if (existing) {
    const token = signToken(existing);
    return res.json({ token, user: existing });
  }

  // New anonymous user
  const id = uuidv4();
  db.prepare(`
    INSERT INTO users (id, nickname, device_uuid, region)
    VALUES (?, ?, ?, ?)
  `).run(id, cleanNick, device_uuid, region || null);

  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
  const token = signToken(user);
  res.status(201).json({ token, user });
});

/**
 * Login with device UUID only.
 * Body: { device_uuid }
 */
router.post('/login', (req, res) => {
  const { device_uuid } = req.body || {};
  if (!device_uuid) return res.status(400).json({ error: '기기 UUID가 필요해요' });

  const user = db.prepare('SELECT * FROM users WHERE device_uuid = ?').get(device_uuid);
  if (!user) return res.status(404).json({ error: '가입되지 않은 기기예요' });

  const token = signToken(user);
  res.json({ token, user });
});

/** Get current user's profile. */
router.get('/me', authMiddleware, (req, res) => {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });
  res.json({ user });
});

export default router;
