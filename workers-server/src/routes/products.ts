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

  // Hide listings from anyone the current user has blocked. Done with a
  // NOT IN subquery instead of a join so the WHERE-clause stays simple.
  const user = c.get('user');
  if (user) {
    conditions.push(
      'seller_id NOT IN (SELECT blocked_id FROM user_blocks WHERE blocker_id = ?)'
    );
    params.push(user.id);
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  // Sort by the most recent of (bumped_at, created_at). Sellers who bump a
  // listing within the last 24h surface back to the top, exactly like 당근.
  const sql = `
    SELECT * FROM products ${where}
     ORDER BY COALESCE(bumped_at, created_at) DESC
     LIMIT ? OFFSET ?
  `;
  const rs = await c.env.DB
    .prepare(sql)
    .bind(...params, limit, offset)
    .all<ProductRow>();

  const rows = rs.results || [];
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
    .prepare(
      `SELECT * FROM products
        WHERE seller_id = ?
        ORDER BY COALESCE(bumped_at, created_at) DESC`,
    )
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

/**
 * PATCH /api/products/:id
 * Body (JSON, all fields optional):
 *   { title?, description?, price?, category?, youtube_url? }
 *
 * Only the owner can edit. Images / uploaded videos are kept (edit ≠ re-upload);
 * to change images the user can delete the product and upload again.
 * We DO allow changing the YouTube URL (or clearing it via empty string).
 */
app.patch('/:id', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');

  let body: Record<string, unknown> = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const row = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();
  if (!row) return c.json({ error: 'Not found' }, 404);
  if (row.seller_id !== user.id) return c.json({ error: 'Forbidden' }, 403);

  const updates: string[] = [];
  const params: (string | number)[] = [];

  if (typeof body.title === 'string') {
    const t = (body.title as string).trim();
    if (!t) return c.json({ error: '제목을 입력해주세요' }, 400);
    if (t.length > 80) return c.json({ error: '제목이 너무 길어요' }, 400);
    updates.push('title = ?');
    params.push(t);
  }
  if (typeof body.description === 'string') {
    const d = (body.description as string).trim();
    if (d.length < 10) return c.json({ error: '설명은 10자 이상 입력해주세요' }, 400);
    updates.push('description = ?');
    params.push(d);
  }
  if (body.price !== undefined) {
    const p = parseInt(String(body.price), 10);
    if (!Number.isFinite(p) || p < 0) {
      return c.json({ error: '가격이 올바르지 않아요' }, 400);
    }
    updates.push('price = ?');
    params.push(p);
  }
  if (typeof body.category === 'string' && (body.category as string).trim()) {
    updates.push('category = ?');
    params.push((body.category as string).trim());
  }
  if (typeof body.youtube_url === 'string') {
    const raw = (body.youtube_url as string).trim();
    if (raw === '') {
      // Clear video only if the current one is a YouTube URL; uploaded videos stay.
      if ((row.video_url || '').startsWith('http')) {
        updates.push('video_url = ?');
        params.push('');
      }
    } else {
      const normalized = normalizeYouTubeUrl(raw);
      if (!normalized) return c.json({ error: '유튜브 링크 형식이 올바르지 않아요' }, 400);
      updates.push('video_url = ?');
      params.push(normalized);
    }
  }

  if (updates.length === 0) {
    return c.json({ error: '수정할 내용이 없어요' }, 400);
  }

  updates.push("updated_at = datetime('now')");
  params.push(id);

  await c.env.DB
    .prepare(`UPDATE products SET ${updates.join(', ')} WHERE id = ?`)
    .bind(...params)
    .run();

  const updated = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();
  const product = await hydrate(c.env, updated, user.id);
  return c.json({ product });
});

/**
 * PUT /api/products/:id/status
 *
 * Seller updates listing status.
 * • status='sold' may carry a `buyer_id` — typically chosen from the chat
 *   partners that messaged about this product. Stored on the product so both
 *   sides can leave a review later.
 * • Switching back to 'sale' or 'reserved' clears any previous buyer_id.
 */
app.put('/:id/status', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');
  let body: { status?: string; buyer_id?: string | null } = {};
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

  // Validate buyer_id if provided (must be a real user, not the seller).
  let buyerId: string | null = null;
  if (body.status === 'sold' && body.buyer_id) {
    if (body.buyer_id === user.id) {
      return c.json({ error: '본인을 구매자로 지정할 수 없어요' }, 400);
    }
    const buyer = await c.env.DB
      .prepare('SELECT id FROM users WHERE id = ?')
      .bind(body.buyer_id)
      .first<{ id: string }>();
    if (!buyer) return c.json({ error: '구매자를 찾을 수 없어요' }, 400);
    buyerId = body.buyer_id;
  }

  if (body.status === 'sold') {
    await c.env.DB
      .prepare(
        "UPDATE products SET status = ?, buyer_id = ?, updated_at = datetime('now') WHERE id = ?"
      )
      .bind(body.status, buyerId, id)
      .run();
  } else {
    // sale / reserved → clear any stored buyer.
    await c.env.DB
      .prepare(
        "UPDATE products SET status = ?, buyer_id = NULL, updated_at = datetime('now') WHERE id = ?"
      )
      .bind(body.status, id)
      .run();
  }

  return c.json({ ok: true, status: body.status, buyer_id: buyerId });
});

// /api/products/:id/buyers 는 제거됨.
// 휘발성 채팅 정책상 서버에 chat_rooms 가 없으므로 "이 상품에 문의했던 사람" 같은
// 목록을 만들 수 없다. 대신 거래완료 시 판매자가 직접 구매자의 닉네임으로
// 검색해서 (GET /api/users/search) 선택한 buyer_id 를 PUT /:id/status 에 넣는다.

/**
 * POST /api/products/:id/review
 *
 * 거래후기. Either side (seller ↔ buyer) can leave one review per product.
 *   body: { rating: 'good' | 'soso' | 'bad', tags?: string[], comment?: string }
 *
 * Auto‑updates the reviewee's manner_score via DB trigger
 * (good +0.5°, soso 0°, bad -0.5°; stored *10).
 *
 * Constraints:
 *   • Product status must be 'sold'.
 *   • Reviewer must be the seller or the recorded buyer.
 *   • One review per (product, reviewer).
 */
app.post('/:id/review', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');

  let body: { rating?: string; tags?: string[]; comment?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }
  if (!['good', 'soso', 'bad'].includes(body.rating || '')) {
    return c.json({ error: '평가를 선택해주세요' }, 400);
  }

  const product = await c.env.DB
    .prepare('SELECT seller_id, buyer_id, status FROM products WHERE id = ?')
    .bind(id)
    .first<{ seller_id: string; buyer_id: string | null; status: string }>();
  if (!product) return c.json({ error: 'Not found' }, 404);
  if (product.status !== 'sold') {
    return c.json({ error: '거래완료 후에 후기를 남길 수 있어요' }, 400);
  }
  if (!product.buyer_id) {
    return c.json({ error: '구매자가 지정되지 않았어요' }, 400);
  }

  // Determine reviewee.
  let revieweeId: string | null = null;
  if (user.id === product.seller_id) revieweeId = product.buyer_id;
  else if (user.id === product.buyer_id) revieweeId = product.seller_id;
  if (!revieweeId) {
    return c.json({ error: '거래 당사자만 후기를 남길 수 있어요' }, 403);
  }

  // Duplicate check — UNIQUE(product_id, reviewer_id) is the source of truth,
  // but we want a friendly Korean error rather than a 500 from the DB.
  const dup = await c.env.DB
    .prepare('SELECT 1 FROM reviews WHERE product_id = ? AND reviewer_id = ?')
    .bind(id, user.id)
    .first();
  if (dup) return c.json({ error: '이미 후기를 남기셨어요' }, 409);

  const tags = Array.isArray(body.tags)
    ? body.tags.map((t) => String(t).trim()).filter(Boolean).slice(0, 8).join(',')
    : '';
  const comment = (body.comment || '').toString().trim().slice(0, 300);

  const reviewId = crypto.randomUUID();
  await c.env.DB
    .prepare(
      `INSERT INTO reviews (id, product_id, reviewer_id, reviewee_id, rating, tags, comment)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    )
    .bind(reviewId, id, user.id, revieweeId, body.rating, tags, comment)
    .run();

  // Trigger has already adjusted manner_score; fetch the new value to return.
  const updated = await c.env.DB
    .prepare('SELECT manner_score FROM users WHERE id = ?')
    .bind(revieweeId)
    .first<{ manner_score: number }>();

  return c.json({
    ok: true,
    review_id: reviewId,
    reviewee_id: revieweeId,
    new_manner_score: updated?.manner_score ?? 365,
  });
});

/**
 * GET /api/products/:id/review/me
 *
 * Returns the current user's review on this product (if any). Used by the
 * client to know whether to show the "후기 남기기" CTA or "후기 보기".
 */
app.get('/:id/review/me', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');
  const review = await c.env.DB
    .prepare(
      'SELECT id, rating, tags, comment, created_at FROM reviews WHERE product_id = ? AND reviewer_id = ?'
    )
    .bind(id, user.id)
    .first();
  return c.json({ review: review || null });
});

/**
 * POST /api/products/:id/bump
 * 끌어올리기 — re-promote my listing to the top of the feed.
 *   - Owner-only.
 *   - Cooldown: 24h between bumps. Returns the next-allowed time on 429.
 *   - Only "sale" listings can be bumped (sold/reserved doesn't make sense).
 */
app.post('/:id/bump', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');

  const row = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();
  if (!row) return c.json({ error: 'Not found' }, 404);
  if (row.seller_id !== user.id) return c.json({ error: 'Forbidden' }, 403);
  if (row.status !== 'sale') {
    return c.json({ error: '판매중인 상품만 끌어올릴 수 있어요' }, 400);
  }

  // 24h cooldown — we read bumped_at via a typed cast since ProductRow
  // doesn't (yet) include the new column in some envs.
  const bumpedAt = (row as ProductRow & { bumped_at?: string | null }).bumped_at || null;
  if (bumpedAt) {
    const last = Date.parse(bumpedAt);
    if (Number.isFinite(last)) {
      const COOLDOWN_MS = 24 * 60 * 60 * 1000;
      const elapsed = Date.now() - last;
      if (elapsed < COOLDOWN_MS) {
        const remainingSec = Math.ceil((COOLDOWN_MS - elapsed) / 1000);
        const hours = Math.floor(remainingSec / 3600);
        const mins = Math.ceil((remainingSec % 3600) / 60);
        const wait = hours > 0 ? `${hours}시간 ${mins}분` : `${mins}분`;
        return c.json(
          {
            error: `${wait} 후에 다시 끌어올릴 수 있어요`,
            next_allowed_at: new Date(last + COOLDOWN_MS).toISOString(),
            remaining_seconds: remainingSec,
          },
          429,
        );
      }
    }
  }

  const now = new Date().toISOString();
  await c.env.DB
    .prepare("UPDATE products SET bumped_at = ?, updated_at = datetime('now') WHERE id = ?")
    .bind(now, id)
    .run();

  const updated = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();
  const product = await hydrate(c.env, updated, user.id);
  return c.json({ product, bumped_at: now });
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

  // Delete uploaded video from R2 (only for non-YouTube videos — YouTube URLs
  // start with http, uploaded files live under /uploads/<key>.<ext>).
  // Without this the R2 bucket accumulates orphaned video blobs whenever a
  // seller deletes a listing that had a self-hosted clip.
  const video = row.video_url || '';
  if (video && video.startsWith('/uploads/')) {
    const vkey = video.replace(/^\/uploads\//, '');
    if (vkey) {
      try { await c.env.UPLOADS.delete(vkey); } catch {}
    }
  }

  await c.env.DB
    .prepare('DELETE FROM products WHERE id = ?')
    .bind(id)
    .run();

  return c.json({ ok: true });
});

export default app;
