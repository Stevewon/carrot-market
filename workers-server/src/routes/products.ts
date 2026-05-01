import { Hono } from 'hono';
import type { Env, ProductResponse, ProductRow, UserRow, Variables } from '../types';
import { authMiddleware, optionalAuth } from '../jwt';
import {
  grantTradeBonus,
  payTrade,
  recordBrowseAndMaybeMine,
  grantListingMiningBonus,
  getBrowseMiningStatus,
  createEscrowIfEligible,
  ESCROW_MAX_AMOUNT_KRW,
} from '../qta';

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
    .prepare('SELECT nickname, manner_score, wallet_address FROM users WHERE id = ?')
    .bind(row.seller_id)
    .first<{ nickname: string; manner_score: number; wallet_address: string | null }>();

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
    // SSO 식별자 — Universal User ID. 클라이언트가 마스킹해서 표시.
    seller_wallet_address: seller?.wallet_address ?? null,
    is_liked: isLiked,
  };
}

/**
 * GET /api/products - list with filters
 *
 * 추가 필터:
 *   - range_km=2|4|6  → 인증된 사용자의 lat/lng 중심으로 Haversine 거리 필터.
 *                      미인증 사용자가 지정하면 무시된다 (사생활 보호: 서버는
 *                      클라이언트가 임의로 보낸 좌표를 신뢰하지 않는다).
 */
app.get('/', optionalAuth, async (c) => {
  const category = c.req.query('category');
  const region = c.req.query('region');
  const search = c.req.query('search');
  const rangeKmRaw = parseInt(c.req.query('range_km') || '0', 10);
  const rangeKm = [2, 4, 6, 10].includes(rangeKmRaw) ? rangeKmRaw : 0;
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

  // 인증·동네인증된 사용자만 거리 필터 사용. 우리는 본인 좌표를 DB 에서 직접 조회.
  const user = c.get('user');
  let myLat: number | null = null;
  let myLng: number | null = null;
  if (user && rangeKm > 0) {
    const me = await c.env.DB
      .prepare('SELECT lat, lng FROM users WHERE id = ?')
      .bind(user.id)
      .first<{ lat: number | null; lng: number | null }>();
    if (me?.lat != null && me?.lng != null) {
      myLat = me.lat;
      myLng = me.lng;
      // 위도 1° ≈ 111km, 경도 1° ≈ 111 * cos(lat) km. 거친 bbox prefilter 로 후보 축소.
      const dLat = rangeKm / 111;
      const dLng = rangeKm / (111 * Math.cos((myLat * Math.PI) / 180));
      conditions.push('lat IS NOT NULL AND lng IS NOT NULL');
      conditions.push('lat BETWEEN ? AND ?');
      params.push(myLat - dLat, myLat + dLat);
      conditions.push('lng BETWEEN ? AND ?');
      params.push(myLng - dLng, myLng + dLng);
    }
  }

  // Hide listings from anyone the current user has blocked. Done with a
  // NOT IN subquery instead of a join so the WHERE-clause stays simple.
  if (user) {
    conditions.push(
      'seller_id NOT IN (SELECT blocked_id FROM user_blocks WHERE blocker_id = ?)'
    );
    params.push(user.id);
    // Also hide individual products the user explicitly hid (당근 "이 게시물 가리기").
    conditions.push(
      'id NOT IN (SELECT product_id FROM hidden_products WHERE user_id = ?)'
    );
    params.push(user.id);
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  // 거리 필터가 켜져 있으면 후보를 더 많이 뽑은 뒤 정확히 거리 컷.
  const fetchLimit = rangeKm > 0 && myLat != null ? Math.min(limit * 4, 400) : limit;
  const sql = `
    SELECT * FROM products ${where}
     ORDER BY COALESCE(bumped_at, created_at) DESC
     LIMIT ? OFFSET ?
  `;
  const rs = await c.env.DB
    .prepare(sql)
    .bind(...params, fetchLimit, offset)
    .all<ProductRow>();

  let rows = rs.results || [];
  if (rangeKm > 0 && myLat != null && myLng != null) {
    const R = 6371;
    const toRad = (d: number) => (d * Math.PI) / 180;
    const myLatRad = toRad(myLat);
    rows = rows.filter((r) => {
      if (r.lat == null || r.lng == null) return false;
      const dLat = toRad(r.lat - myLat!);
      const dLng = toRad(r.lng - myLng!);
      const lat2 = toRad(r.lat);
      const h = Math.sin(dLat / 2) ** 2 +
                Math.sin(dLng / 2) ** 2 * Math.cos(myLatRad) * Math.cos(lat2);
      const dist = 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
      return dist <= rangeKm;
    }).slice(0, limit);
  }
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
  let mining: Awaited<ReturnType<typeof recordBrowseAndMaybeMine>> | null = null;
  if (!user || user.id !== row.seller_id) {
    await c.env.DB
      .prepare('UPDATE products SET view_count = view_count + 1 WHERE id = ?')
      .bind(row.id)
      .run();
    row.view_count += 1;

    // 둘러보기 채굴 카운트 (로그인 사용자, 자기 상품 아닐 때만).
    // best-effort — 실패해도 상세 조회는 정상 응답.
    if (user) {
      try {
        mining = await recordBrowseAndMaybeMine(c.env, user.id, row.id);
      } catch (e) {
        console.error('[mining] browse count failed', String((e as Error)?.message || e));
      }
    }

    // 7일 보유 채굴 — 상품이 sale 상태로 7일 이상 묵혔으면 자동 지급(상품당 1회).
    // 게으른 트리거: 상세 조회 시점에 lazily 검사. cron 불필요.
    if ((row.status ?? 'sale') === 'sale') {
      try {
        await grantListingMiningBonus(
          c.env,
          row.id,
          row.seller_id,
          row.created_at,
          row.status ?? 'sale',
        );
      } catch (e) {
        console.error('[mining] listing bonus failed', String((e as Error)?.message || e));
      }
    }
  }

  const product = await hydrate(c.env, row, user?.id);
  return c.json({ product, mining });
});

/**
 * GET /api/products/mining/browse — 오늘(KST) 둘러보기 채굴 현황.
 * my_tab 위젯에서 호출.
 *
 * 반환: { count, threshold, credited, ymd_kst }
 */
app.get('/mining/browse', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const status = await getBrowseMiningStatus(c.env, user.id);
  return c.json(status);
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
  let qtaPriceRaw = '0'; // 선택적 QTA 결제 금액 (정수)
  let videoUrl = ''; // final stored value — either https://youtu.be/<id> or /uploads/<key>.mp4
  const imageKeys: string[] = [];

  if (contentType.includes('multipart/form-data')) {
    const form = await c.req.formData();
    title = String(form.get('title') || '').trim();
    description = String(form.get('description') || '').trim();
    price = String(form.get('price') || '0');
    qtaPriceRaw = String(form.get('qta_price') || '0');
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
      qtaPriceRaw = String(body.qta_price ?? '0');
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
  const qtaPriceInt = Math.max(0, parseInt(qtaPriceRaw, 10) || 0);

  // 작성자의 동네 좌표를 그대로 복사 — 거리 필터에 사용.
  // 인증 안 된 사용자면 lat/lng 가 NULL 이라 거리 필터 결과에서 빠진다.
  const seller = await c.env.DB
    .prepare('SELECT lat, lng FROM users WHERE id = ?')
    .bind(user.id)
    .first<{ lat: number | null; lng: number | null }>();

  await c.env.DB
    .prepare(`
      INSERT INTO products (id, seller_id, title, description, price, qta_price, category, region, images, video_url, lat, lng)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `)
    .bind(
      id, user.id, title, description, priceInt, qtaPriceInt, category, region, images, videoUrl,
      seller?.lat ?? null, seller?.lng ?? null
    )
    .run();

  const row = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();

  const product = await hydrate(c.env, row, user.id);

  // ── 키워드 알림 fanout (당근식 "키워드 알림") ────────────────────────────
  // 본문/제목/카테고리에 등록 키워드가 포함된 사용자를 찾아 WS push.
  // 거리 기반 — 작성자(=상품 위치)에서 KEYWORD_ALERT_RADIUS_KM 이내의 사용자만.
  // 발송 이력은 절대 DB 에 남기지 않는다 (사생활 보호).
  c.executionCtx.waitUntil(
    fanoutKeywordAlerts(c.env, {
      product_id: id,
      seller_id: user.id,
      title,
      description,
      category,
      region,
      lat: seller?.lat ?? null,
      lng: seller?.lng ?? null,
      thumb: imageKeys[0]
        ? (c.env.PUBLIC_UPLOAD_URL
            ? `${c.env.PUBLIC_UPLOAD_URL.replace(/\/$/, '')}/${imageKeys[0]}`
            : `/uploads/${imageKeys[0]}`)
        : null,
    }).catch((e) => console.error('[alerts] fanout error', e))
  );

  return c.json({ product }, 201);
});

/** 새 상품 → 매칭 키워드 사용자 fanout. 거리 + 차단 + 본인제외 적용. */
async function fanoutKeywordAlerts(
  env: Env,
  p: {
    product_id: string;
    seller_id: string;
    title: string;
    description: string;
    category: string;
    region: string;
    lat: number | null;
    lng: number | null;
    thumb: string | null;
  }
) {
  const KEYWORD_ALERT_RADIUS_KM = 6;
  const haystack = `${p.title} ${p.description} ${p.category}`.toLowerCase();

  // 모든 키워드를 다 끌어오는 게 아니라 — 일단 짧은 LIKE 매치로 후보 user_id 만 추린다.
  // (D1 은 GROUP BY 효율이 그렇게 좋지 않으므로 keyword 기준으로 간단히 SCAN)
  const rs = await env.DB
    .prepare(
      `SELECT ka.user_id, ka.keyword, u.lat as u_lat, u.lng as u_lng
         FROM keyword_alerts ka
         JOIN users u ON u.id = ka.user_id
        WHERE ka.user_id != ?`
    )
    .bind(p.seller_id)
    .all<{ user_id: string; keyword: string; u_lat: number | null; u_lng: number | null }>();

  const matchedUsers = new Set<string>();
  for (const r of rs.results || []) {
    if (matchedUsers.has(r.user_id)) continue;
    const kw = (r.keyword || '').toLowerCase();
    if (!kw || !haystack.includes(kw)) continue;

    // 거리 필터 — 양쪽 다 좌표가 있을 때만.
    if (p.lat != null && p.lng != null && r.u_lat != null && r.u_lng != null) {
      const dist = haversine(p.lat, p.lng, r.u_lat, r.u_lng);
      if (dist > KEYWORD_ALERT_RADIUS_KM) continue;
    }
    matchedUsers.add(r.user_id);
  }

  if (matchedUsers.size === 0) return;

  // 차단/숨김 사용자는 알림에서 제외 (양방향).
  // - blocker가 seller 를 차단했어도 새 상품 자체가 GET 에서 안 보이게 되어 있으니
  //   알림도 같이 보내지 않는다.
  const userList = Array.from(matchedUsers);
  const placeholders = userList.map(() => '?').join(',');
  const blockedRs = await env.DB
    .prepare(
      `SELECT blocker_id FROM user_blocks
         WHERE blocked_id = ? AND blocker_id IN (${placeholders})`
    )
    .bind(p.seller_id, ...userList)
    .all<{ blocker_id: string }>();
  const blocked = new Set((blockedRs.results || []).map((r) => r.blocker_id));

  const finalUsers = userList.filter((u) => !blocked.has(u));
  if (finalUsers.length === 0) return;

  const payload = {
    type: 'keyword_alert',
    product_id: p.product_id,
    title: p.title,
    region: p.region,
    category: p.category,
    thumb: p.thumb,
    sent_at: new Date().toISOString(),
  };

  try {
    const id = env.CHAT_HUB.idFromName('global');
    const stub = env.CHAT_HUB.get(id);
    await stub.fetch('https://do/internal/fanout-users', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ user_ids: finalUsers, payload }),
    });
  } catch (e) {
    console.error('[alerts] fanout DO call failed', e);
  }
}

function haversine(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.sin(dLng / 2) ** 2 * Math.cos(toRad(lat1)) * Math.cos(toRad(lat2));
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

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
  if (body.qta_price !== undefined) {
    const q = parseInt(String(body.qta_price), 10);
    if (!Number.isFinite(q) || q < 0) {
      return c.json({ error: 'QTA 가격이 올바르지 않아요' }, 400);
    }
    // 거래완료 후에는 결제가 끝났으므로 변경 금지.
    if (row.status === 'sold') {
      return c.json({ error: '거래완료된 상품은 가격 변경 불가' }, 400);
    }
    updates.push('qta_price = ?');
    params.push(q);
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

  // ── QTA 결제 (qta_price > 0 인 상품 한정) ─────────────────────────
  // 거래완료(sold) + 구매자 지정 시점에 buyer→seller 로 자동 이체.
  // 결제 실패 (잔액부족 등) 면 status 변경 자체를 거부 → 거래 미완료.
  let qtaPayment:
    | { ok: true; charged: number; already_paid?: boolean }
    | null = null;
  if (body.status === 'sold' && buyerId && (row.qta_price ?? 0) > 0) {
    const pay = await payTrade(
      c.env,
      id,
      user.id,
      buyerId,
      row.qta_price,
    );
    if (!pay.ok) {
      const code = pay.reason === 'insufficient' ? 402 : 400;
      return c.json({ error: pay.error, reason: pay.reason }, code);
    }
    qtaPayment = pay;
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

  // ── 거래완료 보너스 (양쪽 +10 QTA, 멱등) ────────────────────────
  // sold + buyer_id 가 모두 있을 때만. idem_key='trade:<pid>:seller|buyer' 가
  // UNIQUE 라 다시 sale → sold 토글되어도 한 번만 지급된다.
  let qtaBonus: { seller_credited: boolean; buyer_credited: boolean; amount: number } | null = null;
  if (body.status === 'sold' && buyerId) {
    try {
      const r = await grantTradeBonus(c.env, id, user.id, buyerId);
      qtaBonus = { ...r, amount: 10 };
    } catch (e) {
      console.error('[products/status] trade bonus failed', e);
    }
  }

  return c.json({
    ok: true,
    status: body.status,
    buyer_id: buyerId,
    qta_bonus: qtaBonus,
    qta_payment: qtaPayment,
  });
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
 * Auto‑updates the reviewee's manner_score in the same batch as the review
 * INSERT (good +0.5°, soso 0°, bad -0.5°; stored *10, clamped 0..990).
 *
 * NOTE: 원래는 DB 트리거(trg_reviews_update_manner)로 처리했지만 D1 의
 *       `migrations apply` 단계에서 트리거 본문 안의 세미콜론 split 이슈로
 *       인해 (`incomplete input: SQLITE_ERROR [code: 7500]`) 트리거를 못
 *       만들었다. 따라서 application-level 에서 batch 두 statement 로 처리.
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

  // good = +5 (+0.5°), bad = -5 (-0.5°), soso = 0. *10 스케일이라 정수.
  const delta = body.rating === 'good' ? 5 : body.rating === 'bad' ? -5 : 0;

  // INSERT review + UPDATE manner_score 를 한 batch 로 묶어 atomic 보장.
  // MIN/MAX 로 0..990 범위 클램프 (당근식 매너온도 0.0° ~ 99.0°).
  await c.env.DB.batch([
    c.env.DB
      .prepare(
        `INSERT INTO reviews (id, product_id, reviewer_id, reviewee_id, rating, tags, comment)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(reviewId, id, user.id, revieweeId, body.rating, tags, comment),
    c.env.DB
      .prepare(
        `UPDATE users
            SET manner_score = MIN(990, MAX(0, manner_score + ?)),
                updated_at   = datetime('now')
          WHERE id = ?`,
      )
      .bind(delta, revieweeId),
  ]);

  // 업데이트된 manner_score 를 응답에 포함 (클라이언트가 즉시 표시할 수 있도록).
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

/**
 * POST /api/products/:id/escrow
 *
 * 30,000원 미만 KRW 거래에 대한 에스크로(임시예치) 생성.
 *  - 호출자: 구매자 (buyer). 본인인증 Lv1 필수.
 *  - 같은 product+buyer 로 이미 pending 인 게 있으면 그 메모/금액 그대로 반환 (멱등).
 *  - 30,000원 이상은 거부 → 클라이언트가 직거래로 안내.
 *
 * Body: (없음 — product.price 를 그대로 사용)
 * 응답: { ok, escrow_id, deposit_memo, amount_krw, bank_info }
 */
app.post('/:id/escrow', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');

  // 본인인증(Lv1) 필수
  const meRow = await c.env.DB
    .prepare('SELECT verification_level FROM users WHERE id = ?')
    .bind(user.id)
    .first<{ verification_level: number }>();
  if (!meRow || (meRow.verification_level ?? 0) < 1) {
    return c.json({ error: '본인인증(Lv1) 후 거래할 수 있어요', need_verify: 1 }, 403);
  }

  const row = await c.env.DB
    .prepare('SELECT id, seller_id, price, status FROM products WHERE id = ?')
    .bind(id)
    .first<{ id: string; seller_id: string; price: number; status: string }>();
  if (!row) return c.json({ error: '상품을 찾을 수 없어요' }, 404);
  if (row.seller_id === user.id) {
    return c.json({ error: '본인 상품에는 에스크로를 만들 수 없어요' }, 400);
  }
  if (row.status === 'sold') {
    return c.json({ error: '이미 거래 완료된 상품이에요' }, 400);
  }
  if (row.price >= ESCROW_MAX_AMOUNT_KRW) {
    return c.json(
      {
        error: '30,000원 이상은 당사자 직거래에요',
        reason: 'over_limit',
        threshold: ESCROW_MAX_AMOUNT_KRW,
      },
      400,
    );
  }

  const result = await createEscrowIfEligible(
    c.env,
    row.id,
    user.id,
    row.seller_id,
    row.price,
  );
  if (!result.ok) {
    const code = result.reason === 'over_limit' ? 400 : 500;
    return c.json({ error: result.error, reason: result.reason }, code);
  }

  // 회사 임시 예치 계좌 정보 — 환경변수에서 읽음 (운영 시 secret 으로 관리)
  const bankInfo = {
    bank_name: (c.env as { ESCROW_BANK_NAME?: string }).ESCROW_BANK_NAME || '국민은행',
    account_number:
      (c.env as { ESCROW_ACCOUNT_NUMBER?: string }).ESCROW_ACCOUNT_NUMBER ||
      '000-0000-0000-00',
    account_holder:
      (c.env as { ESCROW_ACCOUNT_HOLDER?: string }).ESCROW_ACCOUNT_HOLDER ||
      '(주)가지마켓',
  };

  return c.json({
    ok: true,
    escrow_id: result.escrow_id,
    deposit_memo: result.deposit_memo,
    amount_krw: result.amount_krw,
    already_exists: result.already_exists ?? false,
    bank_info: bankInfo,
  });
});

/**
 * GET /api/products/:id/escrow
 *
 * 해당 상품에 대해 본인이 만든 에스크로 상태 조회.
 *  - 본인이 buyer 또는 seller 인 경우만 조회 가능.
 */
app.get('/:id/escrow', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');

  const tx = await c.env.DB
    .prepare(
      `SELECT id, product_id, buyer_id, seller_id, amount_krw, status,
              deposit_memo, admin_note, created_at, updated_at
         FROM escrow_transactions
        WHERE product_id = ?
          AND (buyer_id = ? OR seller_id = ?)
        ORDER BY created_at DESC
        LIMIT 1`,
    )
    .bind(id, user.id, user.id)
    .first<{
      id: string;
      product_id: string;
      buyer_id: string;
      seller_id: string;
      amount_krw: number;
      status: string;
      deposit_memo: string;
      admin_note: string | null;
      created_at: string;
      updated_at: string;
    }>();

  if (!tx) return c.json({ escrow: null });

  return c.json({
    escrow: {
      id: tx.id,
      product_id: tx.product_id,
      amount_krw: tx.amount_krw,
      status: tx.status,
      deposit_memo: tx.deposit_memo,
      role: tx.buyer_id === user.id ? 'buyer' : 'seller',
      created_at: tx.created_at,
      updated_at: tx.updated_at,
    },
  });
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
