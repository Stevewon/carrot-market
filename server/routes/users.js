import express from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';

const router = express.Router();

/** Update my profile (region, nickname) */
router.put('/me', authMiddleware, (req, res) => {
  const { region, nickname } = req.body || {};
  const updates = [];
  const values = [];

  if (region !== undefined) {
    updates.push('region = ?');
    values.push(region);
  }
  if (nickname !== undefined && nickname.trim().length >= 2) {
    updates.push('nickname = ?');
    values.push(nickname.trim().slice(0, 12));
  }
  if (updates.length === 0) return res.json({ ok: true });

  updates.push("updated_at = datetime('now')");
  values.push(req.user.id);
  db.prepare(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`).run(...values);

  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  res.json({ user });
});

export default router;
