import { Hono } from 'hono';
import type { Env, ProductResponse, ProductRow, UserRow, Variables } from '../types';
import { authMiddleware, optionalAuth } from '../jwt';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

const MAX_IMAGES = 10;
const MAX_IMAGE_SIZE = 8 * 1024 * 1024; // 8 MB
const MAX_VIDEO_SIZE = 50 * 1024 * 1024; // 50 MB
const ALLOWED_VIDEO_EXT = /^(mp4|mov|m4v|webm)$/;

/** Normalize a user-provided YouTube URL into a plain https://youtu.be/<id> form (or youtube.com/watch?v=). */
function normalizeYouTubeUrl(raw: string): string | null {
  const url = raw.trim();
  if (!url) return null;
  // Accept youtube.com/watch?v=, youtu.be/, youtube.com/shorts/, youtube.com/embed/
  const patterns = [
    /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/shorts\/|youtube\.com\/embed\/)([A-Za-z0-9_-]{6,20})/,
  ];
  for (const re of patterns) {
    const m = url.match(re);
    if (m && m[1]) return `https://youtu.be/${m[1]}`;
  }
  return null;
}

/** Hydrate a product row with seller info + like status. */
async function hydrate(
  env: Env,
  row: ProductRow | null,
  currentUserId?: string
): Promise<ProductResponse | null> {
  if (!row) return null;

  const seller = await env.DB
    .prepare('SELECT nickname, manner_score FROM users WHERE id = ?')
    .bind(row.seller_id)
    .first<{ nickname: string; manner_score: number }>();

  let isLiked = false;
  if (currentUserId) {
    const like = await env.DB
      .prepare('SELECT 1 FROM product_likes WHERE user_id = ? AND product_id = ?')
      .bind(currentUserId, row.id)
      .first();
    isLiked = !!like;
  }

  return {
    ...row,
    images: row.images ? row.images.split(',').filter(Boolean) : [],
    video_url: row.video_url || '',
    seller_nickname: seller?.nickname || '익명가지',
    seller_manner_score: seller?.manner_score ?? 36,
    is_liked: isLiked,
  };
}

/** GET /api/products - list with filters */
app.get('/', optionalAuth, async (c) => {
  const category = c.req.query('category');
  const region = c.req.query('region');
  const search = c.req.query('search');
  const limit = Math.min(parseInt(c.req.query('limit') || '50', 10), 100);
  const offset = parseInt(c.req.query('offset') || '0', 10);

  const conditions: string[] = [];
  const params: (string | number)[] = [];

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
  const sql = `SELECT * FROM products ${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`;
  const rs = await c.env.DB
    .prepare(sql)
    .bind(...params, limit, offset)
    .all<ProductRow>();

  const rows = rs.results || [];
  const user = c.get('user');
  const products = await Promise.all(rows.map((r) => hydrate(c.env, r, user?.id)));
  return c.json({ products });
});

/** GET /api/products/my/likes */
app.get('/my/likes', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const rs = await c.env.DB
    .prepare(`
      SELECT p.* FROM products p
      JOIN product_likes l ON l.product_id = p.id
      WHERE l.user_id = ?
      ORDER BY l.created_at DESC
    `)
    .bind(user.id)
    .all<ProductRow>();

  const products = await Promise.all(
    (rs.results || []).map((r) => hydrate(c.env, r, user.id))
  );
  return c.json({ products });
});

/** GET /api/products/my/selling */
app.get('/my/selling', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const rs = await c.env.DB
    .prepare('SELECT * FROM products WHERE seller_id = ? ORDER BY created_at DESC')
    .bind(user.id)
    .all<ProductRow>();

  const products = await Promise.all(
    (rs.results || []).map((r) => hydrate(c.env, r, user.id))
  );
  return c.json({ products });
});

/** GET /api/products/:id - detail */
app.get('/:id', optionalAuth, async (c) => {
  const id = c.req.param('id');
  const row = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();

  if (!row) return c.json({ error: 'Not found' }, 404);

  const user = c.get('user');
  // Increment view_count for non-owners
  if (!user || user.id !== row.seller_id) {
    await c.env.DB
      .prepare('UPDATE products SET view_count = view_count + 1 WHERE id = ?')
      .bind(row.id)
      .run();
    row.view_count += 1;
  }

  const product = await hydrate(c.env, row, user?.id);
  return c.json({ product });
});

/**
 * POST /api/products - create
 * Accepts multipart/form-data with fields:
 *   title, description, price, category, region
 *   images (repeated; up to 5)
 */
app.post('/', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const contentType = c.req.header('content-type') || '';

  let title = '', description = '', price = '0', category = '', region = '';
  let videoUrl = ''; // final stored value — either https://youtu.be/<id> or /uploads/<key>.mp4
  const imageKeys: string[] = [];

  if (contentType.includes('multipart/form-data')) {
    const form = await c.req.formData();
    title = String(form.get('title') || '').trim();
    description = String(form.get('description') || '').trim();
    price = String(form.get('price') || '0');
    category = String(form.get('category') || '').trim();
    region = String(form.get('region') || '').trim();

    // Collect all "images" files (multer array-style)
    const files = form.getAll('images').filter((v): v is File => v instanceof File);
    if (files.length > MAX_IMAGES) {
      return c.json({ error: `이미지는 최대 ${MAX_IMAGES}장까지에요` }, 400);
    }
    for (const f of files) {
      if (f.size > MAX_IMAGE_SIZE) {
        return c.json({ error: `파일 크기는 8MB 이하여야 해요` }, 400);
      }
      const ext = f.name.split('.').pop()?.toLowerCase() || 'jpg';
      const safeExt = /^(jpg|jpeg|png|gif|webp)$/.test(ext) ? ext : 'jpg';
      const key = `${crypto.randomUUID()}.${safeExt}`;
      const body = await f.arrayBuffer();
      await c.env.UPLOADS.put(key, body, {
        httpMetadata: { contentType: f.type || `image/${safeExt}` },
      });
      imageKeys.push(`/uploads/${key}`);
    }

    // Optional YouTube link (priority if both are present)
    const ytRaw = String(form.get('youtube_url') || '').trim();
    if (ytRaw) {
      const normalized = normalizeYouTubeUrl(ytRaw);
      if (!normalized) {
        return c.json({ error: '유튜브 링크 형식이 올바르지 않아요' }, 400);
      }
      videoUrl = normalized;
    }

    // Optional uploaded video file (only if no YouTube link)
    if (!videoUrl) {
      const vFile = form.get('video');
      if (vFile instanceof File && vFile.size > 0) {
        if (vFile.size > MAX_VIDEO_SIZE) {
          return c.json({ error: '영상 크기는 50MB 이하여야 해요' }, 400);
        }
        const ext = vFile.name.split('.').pop()?.toLowerCase() || 'mp4';
        const safeExt = ALLOWED_VIDEO_EXT.test(ext) ? ext : 'mp4';
        const key = `${crypto.randomUUID()}.${safeExt}`;
        const body = await vFile.arrayBuffer();
        await c.env.UPLOADS.put(key, body, {
          httpMetadata: { contentType: vFile.type || `video/${safeExt}` },
        });
        videoUrl = `/uploads/${key}`;
      }
    }
  } else {
    // JSON fallback (no images/video file, but YouTube URL can be passed)
    try {
      const body = (await c.req.json()) as Record<string, string | number>;
      title = String(body.title || '').trim();
      description = String(body.description || '').trim();
      price = String(body.price ?? '0');
      category = String(body.category || '').trim();
      region = String(body.region || '').trim();
      const ytRaw = String(body.youtube_url || '').trim();
      if (ytRaw) {
        const normalized = normalizeYouTubeUrl(ytRaw);
        if (!normalized) {
          return c.json({ error: '유튜브 링크 형식이 올바르지 않아요' }, 400);
        }
        videoUrl = normalized;
      }
    } catch {
      return c.json({ error: '잘못된 요청' }, 400);
    }
  }

  if (!title || !description || !category || !region) {
    return c.json({ error: '필수 정보가 부족해요' }, 400);
  }

  const id = crypto.randomUUID();
  const images = imageKeys.join(',');
  const priceInt = parseInt(price, 10) || 0;

  await c.env.DB
    .prepare(`
      INSERT INTO products (id, seller_id, title, description, price, category, region, images, video_url)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `)
    .bind(id, user.id, title, description, priceInt, category, region, images, videoUrl)
    .run();

  const row = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();

  const product = await hydrate(c.env, row, user.id);
  return c.json({ product }, 201);
});

/** POST /api/products/:id/like - toggle */
app.post('/:id/like', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const productId = c.req.param('id');

  const existing = await c.env.DB
    .prepare('SELECT id FROM product_likes WHERE user_id = ? AND product_id = ?')
    .bind(user.id, productId)
    .first<{ id: number }>();

  if (existing) {
    await c.env.DB
      .prepare('DELETE FROM product_likes WHERE id = ?')
      .bind(existing.id)
      .run();
    await c.env.DB
      .prepare('UPDATE products SET like_count = MAX(like_count - 1, 0) WHERE id = ?')
      .bind(productId)
      .run();
    return c.json({ liked: false });
  }

  await c.env.DB
    .prepare('INSERT INTO product_likes (user_id, product_id) VALUES (?, ?)')
    .bind(user.id, productId)
    .run();
  await c.env.DB
    .prepare('UPDATE products SET like_count = like_count + 1 WHERE id = ?')
    .bind(productId)
    .run();
  return c.json({ liked: true });
});

/** PUT /api/products/:id/status */
app.put('/:id/status', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');
  let body: { status?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }
  if (!['sale', 'reserved', 'sold'].includes(body.status || '')) {
    return c.json({ error: '잘못된 상태' }, 400);
  }

  const row = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();

  if (!row) return c.json({ error: 'Not found' }, 404);
  if (row.seller_id !== user.id) return c.json({ error: 'Forbidden' }, 403);

  await c.env.DB
    .prepare("UPDATE products SET status = ?, updated_at = datetime('now') WHERE id = ?")
    .bind(body.status, id)
    .run();

  return c.json({ ok: true, status: body.status });
});

/** DELETE /api/products/:id */
app.delete('/:id', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');

  const row = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();

  if (!row) return c.json({ error: 'Not found' }, 404);
  if (row.seller_id !== user.id) return c.json({ error: 'Forbidden' }, 403);

  // Delete associated R2 images (best-effort)
  const imageKeys = (row.images || '').split(',').filter(Boolean);
  for (const path of imageKeys) {
    const key = path.replace(/^\/uploads\//, '');
    if (key) {
      try { await c.env.UPLOADS.delete(key); } catch {}
    }
  }

  await c.env.DB
    .prepare('DELETE FROM products WHERE id = ?')
    .bind(id)
    .run();

  return c.json({ ok: true });
});

export default app;
