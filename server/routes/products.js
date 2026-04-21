import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { v4 as uuidv4 } from 'uuid';
import { fileURLToPath } from 'url';

import db from '../db.js';
import { authMiddleware, optionalAuth } from '../auth.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const UPLOAD_DIR = path.join(__dirname, '..', 'uploads');
if (!fs.existsSync(UPLOAD_DIR)) fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const storage = multer.diskStorage({
  destination: UPLOAD_DIR,
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `${uuidv4()}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 8 * 1024 * 1024 }, // 8MB each
});

const router = express.Router();

/** Helper: serialize product row for API response */
function hydrate(row, currentUserId) {
  if (!row) return null;
  const seller = db.prepare('SELECT nickname, manner_score FROM users WHERE id = ?').get(row.seller_id);
  let isLiked = false;
  if (currentUserId) {
    const like = db.prepare('SELECT 1 FROM product_likes WHERE user_id = ? AND product_id = ?').get(currentUserId, row.id);
    isLiked = !!like;
  }
  return {
    ...row,
    images: row.images ? row.images.split(',').filter(Boolean) : [],
    seller_nickname: seller?.nickname || '익명가지',
    seller_manner_score: seller?.manner_score || 36,
    is_liked: isLiked,
  };
}

/** GET /api/products - list with filters */
router.get('/', optionalAuth, (req, res) => {
  const { category, region, search, limit = 50, offset = 0 } = req.query;
  const conditions = [];
  const params = [];

  if (category && category !== 'all') {
    conditions.push('category = ?');
    params.push(category);
  }
  if (region) {
    conditions.push('region = ?');
    params.push(region);
  }
  if (search) {
    conditions.push('(title LIKE ? OR description LIKE ?)');
    params.push(`%${search}%`, `%${search}%`);
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const rows = db.prepare(`
    SELECT * FROM products ${where}
    ORDER BY created_at DESC
    LIMIT ? OFFSET ?
  `).all(...params, Number(limit), Number(offset));

  const products = rows.map((r) => hydrate(r, req.user?.id));
  res.json({ products });
});

/** GET /api/products/my/likes */
router.get('/my/likes', authMiddleware, (req, res) => {
  const rows = db.prepare(`
    SELECT p.* FROM products p
    JOIN product_likes l ON l.product_id = p.id
    WHERE l.user_id = ?
    ORDER BY l.created_at DESC
  `).all(req.user.id);
  res.json({ products: rows.map((r) => hydrate(r, req.user.id)) });
});

/** GET /api/products/my/selling */
router.get('/my/selling', authMiddleware, (req, res) => {
  const rows = db.prepare(
    'SELECT * FROM products WHERE seller_id = ? ORDER BY created_at DESC'
  ).all(req.user.id);
  res.json({ products: rows.map((r) => hydrate(r, req.user.id)) });
});

/** GET /api/products/:id - detail */
router.get('/:id', optionalAuth, (req, res) => {
  const row = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'Not found' });

  // Increment view count (not from the owner)
  if (!req.user || req.user.id !== row.seller_id) {
    db.prepare('UPDATE products SET view_count = view_count + 1 WHERE id = ?').run(row.id);
    row.view_count += 1;
  }

  res.json({ product: hydrate(row, req.user?.id) });
});

/** POST /api/products - create */
router.post('/', authMiddleware, upload.array('images', 5), (req, res) => {
  const { title, description, price, category, region } = req.body || {};
  if (!title || !description || !category || !region) {
    return res.status(400).json({ error: '필수 정보가 부족해요' });
  }

  const id = uuidv4();
  const images = (req.files || []).map((f) => `/uploads/${f.filename}`).join(',');
  const priceInt = parseInt(price, 10) || 0;

  db.prepare(`
    INSERT INTO products (id, seller_id, title, description, price, category, region, images)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, req.user.id, title.trim(), description.trim(), priceInt, category, region, images);

  const row = db.prepare('SELECT * FROM products WHERE id = ?').get(id);
  res.status(201).json({ product: hydrate(row, req.user.id) });
});

/** POST /api/products/:id/like - toggle */
router.post('/:id/like', authMiddleware, (req, res) => {
  const productId = req.params.id;
  const existing = db.prepare(
    'SELECT id FROM product_likes WHERE user_id = ? AND product_id = ?'
  ).get(req.user.id, productId);

  if (existing) {
    db.prepare('DELETE FROM product_likes WHERE id = ?').run(existing.id);
    db.prepare('UPDATE products SET like_count = MAX(like_count - 1, 0) WHERE id = ?').run(productId);
    res.json({ liked: false });
  } else {
    db.prepare('INSERT INTO product_likes (user_id, product_id) VALUES (?, ?)').run(req.user.id, productId);
    db.prepare('UPDATE products SET like_count = like_count + 1 WHERE id = ?').run(productId);
    res.json({ liked: true });
  }
});

/** PUT /api/products/:id/status */
router.put('/:id/status', authMiddleware, (req, res) => {
  const { status } = req.body || {};
  if (!['sale', 'reserved', 'sold'].includes(status)) {
    return res.status(400).json({ error: '잘못된 상태' });
  }
  const row = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'Not found' });
  if (row.seller_id !== req.user.id) return res.status(403).json({ error: 'Forbidden' });

  db.prepare("UPDATE products SET status = ?, updated_at = datetime('now') WHERE id = ?")
    .run(status, req.params.id);
  res.json({ ok: true, status });
});

/** DELETE /api/products/:id */
router.delete('/:id', authMiddleware, (req, res) => {
  const row = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'Not found' });
  if (row.seller_id !== req.user.id) return res.status(403).json({ error: 'Forbidden' });

  db.prepare('DELETE FROM products WHERE id = ?').run(req.params.id);
  res.json({ ok: true });
});

export default router;
