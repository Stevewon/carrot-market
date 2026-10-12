import { Hono } from 'hono';
import type { Env, ProductResponse, ProductRow, UserRow, Variables } from '../types';
import { authMiddleware, optionalAuth } from '../jwt';
import { sendFcm } from '../utils/fcm';
import {
  grantTradeBonus,
  payTrade,
  recordBrowseAndMaybeMine,
  grantListingMiningBonus,
  getBrowseMiningStatus,
  createEscrowIfEligible,
  ESCROW_MAX_AMOUNT_KRW,
  grantListingReward,
  adjustListingRewardOnPrice,
  deleteProductWithClawback,
} from '../qta';
import { checkProductText, checkReviewText, recordContentFlags } from '../prohibited';
import {
  allowedTags,
  COMMENT_MAX,
  LEGACY_RATINGS,
  MANNER_DELTA,
  MANNER_MAX,
  MANNER_MIN,
  MAX_TAGS,
  NEW_RATINGS,
  type ReviewerRole,
  type ReviewRating,
} from '../reviews';
import { marketLang, normalizeMarket, reqLang, requestMarket, tr, trl, type Lang, type Market } from '../market';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();
/** 본인인증(Lv1) 여부 — QTA 결제 거래·QTA 가격 설정의 조건. */async function isVerified(env: Env, userId: string): Promise<boolean> {  const r = await env.DB    .prepare('SELECT verification_level FROM users WHERE id = ?')    .bind(userId)    .first<{ verification_level: number | null }>();  return (r?.verification_level ?? 0) >= 1;}

const MAX_IMAGES = 10;
const MAX_IMAGE_SIZE = 8 * 1024 * 1024; // 8 MB
const MAX_VIDEO_SIZE = 50 * 1024 * 1024; // 50 MB
const ALLOWED_VIDEO_EXT = /^(mp4|mov|m4v|webm)$/;

/** 멀티파트 업로드 파일의 최소 인터페이스 (Workers / undici / DOM 통용). */
interface UploadedFile {
  size: number;
  name: string;
  type: string;
  arrayBuffer(): Promise<ArrayBuffer>;
}

/**
 * `FormData.get/getAll` 의 반환값 (`string | File | null`) 중에서
 * 파일 객체만 안전하게 골라내는 type guard.
 *
 * Cloudflare Workers 빌드에서는 globalThis.File 타입 추론이 약해서
 * `instanceof File` 분기가 TS2358 / TS2339 를 유발한다.
 * 따라서 duck-typing(필요 멤버 보유 여부)으로 분기한다.
 */
function isUploadedFile(v: unknown): v is UploadedFile {
  if (v == null || typeof v !== 'object') return false;
  const o = v as Record<string, unknown>;
  return (
    typeof o.size === 'number' &&
    typeof o.name === 'string' &&
    typeof o.type === 'string' &&
    typeof o.arrayBuffer === 'function'
  );
}

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

  // 거래 당사자에게만 구매자 닉네임 (판매자가 구매자에게 후기를 보낼 때 이름 표시용).
  let buyerNickname: string | null | undefined;
  if (row.buyer_id && currentUserId && (currentUserId === row.seller_id || currentUserId === row.buyer_id)) {
    const b = await env.DB
      .prepare('SELECT nickname FROM users WHERE id = ?')
      .bind(row.buyer_id)
      .first<{ nickname: string }>();
    buyerNickname = b?.nickname ?? null;
  }

  return {
    ...(buyerNickname !== undefined ? { buyer_nickname: buyerNickname } : {}),
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

  // 같은 시장(한국/일본) 상품만. 로그인 회원은 가입 때 정해진 시장, 아니면 요청 언어.
  const viewer = c.get('user');
  let market: Market = requestMarket(c);
  if (viewer) {
    const m = await c.env.DB
      .prepare('SELECT market FROM users WHERE id = ?')
      .bind(viewer.id)
      .first<{ market: string | null }>();
    market = normalizeMarket(m?.market) ?? market;
  }
  conditions.push('market = ?');
  params.push(market);

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

/**
 * GET /api/products/my/purchases — 구매 내역 (판매자가 나를 구매자로 지정한 거래완료 상품).
 * 각 상품에 my_review_rating (내가 보낸 후기 평가, 없으면 null) 을 붙인다.
 */
app.get('/my/purchases', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const rs = await c.env.DB
    .prepare(
      `SELECT p.*, r.rating AS my_review_rating
         FROM products p
         LEFT JOIN reviews r ON r.product_id = p.id AND r.reviewer_id = ?
        WHERE p.buyer_id = ? AND p.status = 'sold'
        ORDER BY p.updated_at DESC
        LIMIT 200`,
    )
    .bind(user.id, user.id)
    .all<ProductRow & { my_review_rating: string | null }>();

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
  // ?peek=1 — 화면 보조 조회(채팅방 상품 배너의 거래 후기 버튼 등). 조회수·둘러보기 채굴 없이 읽기만.
  const peek = c.req.query('peek') === '1';
  // Increment view_count for non-owners
  let mining: Awaited<ReturnType<typeof recordBrowseAndMaybeMine>> | null = null;
  if (!peek && (!user || user.id !== row.seller_id)) {
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

    // 거래 금지 품목 · 금지어 · 외부 연락처 — 이미지/영상 업로드 전에 거절 (R2 고아 파일 방지)
    const early = checkProductText({ title, description, category });
    if (early.action === 'block') {
      c.executionCtx.waitUntil(recordContentFlags(c.env.DB, { userId: user.id, targetType: 'product', targetId: null, result: early }));
      return c.json({ error: tr(c, early.message ?? '', early.messageJa ?? early.message ?? '', early.messageEn ?? early.message ?? ''), code: 'prohibited', category: early.blocked ? tr(c, early.blocked.label, early.blocked.labelJa, early.blocked.labelEn) : undefined }, 400);
    }

    // Collect all "images" files (multer array-style).
    // Cloudflare Workers 환경에선 globalThis.File 의 타입 추론이 약해서
    // instanceof 대신 duck-typing(arrayBuffer 메서드 보유 여부)으로 분기.
    // FormDataEntryValue 가 string | File 인데 type guard narrowing 이
    // 안정적으로 안 먹어서 명시 캐스트.
    const files: UploadedFile[] = (form.getAll('images') as unknown[]).filter(
      isUploadedFile,
    );
    if (files.length > MAX_IMAGES) {
      return c.json({ error: tr(c, `이미지는 최대 ${MAX_IMAGES}장까지에요`, `画像は最大${MAX_IMAGES}枚までです`, `You can add up to ${MAX_IMAGES} photos`) }, 400);
    }
    for (const f of files) {
      if (f.size > MAX_IMAGE_SIZE) {
        return c.json({ error: tr(c, `파일 크기는 8MB 이하여야 해요`, `ファイルサイズは8MB以下にしてください`, 'Files must be 8MB or smaller') }, 400);
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
        return c.json({ error: tr(c, '유튜브 링크 형식이 올바르지 않아요', 'YouTubeリンクの形式が正しくありません', `That YouTube link doesn't look right`) }, 400);
      }
      videoUrl = normalized;
    }

    // Optional uploaded video file (only if no YouTube link)
    if (!videoUrl) {
      const raw = form.get('video');
      const vFile = isUploadedFile(raw) ? raw : null;
      if (vFile && vFile.size > 0) {
        if (vFile.size > MAX_VIDEO_SIZE) {
          return c.json({ error: tr(c, '영상 크기는 50MB 이하여야 해요', '動画のサイズは50MB以下にしてください', 'Videos must be 50MB or smaller') }, 400);
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
          return c.json({ error: tr(c, '유튜브 링크 형식이 올바르지 않아요', 'YouTubeリンクの形式が正しくありません', `That YouTube link doesn't look right`) }, 400);
        }
        videoUrl = normalized;
      }
    } catch {
      return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);
    }
  }

  if (!title || !description || !category || !region) {
    return c.json({ error: tr(c, '필수 정보가 부족해요', '必須項目が入力されていません', 'Some required info is missing') }, 400);
  }

  // 거래 금지 품목 · 금지어 · 외부 연락처 (서버가 최종 판단). REVIEW 는 등록 후 검토 큐 적재.
  const moderation = checkProductText({ title, description, category });
  if (moderation.action === 'block') {
    c.executionCtx.waitUntil(recordContentFlags(c.env.DB, { userId: user.id, targetType: 'product', targetId: null, result: moderation }));
    return c.json({ error: tr(c, moderation.message ?? '', moderation.messageJa ?? moderation.message ?? '', moderation.messageEn ?? moderation.message ?? ''), code: 'prohibited', category: moderation.blocked ? tr(c, moderation.blocked.label, moderation.blocked.labelJa, moderation.blocked.labelEn) : undefined }, 400);
  }

  const id = crypto.randomUUID();
  const images = imageKeys.join(',');
  const priceInt = parseInt(price, 10) || 0;
  const qtaPriceInt = Math.max(0, parseInt(qtaPriceRaw, 10) || 0);
  // QTA 가격 상품은 본인인증한 판매자만 — 인증 없이는 거래완료를 할 수 없어 팔 수 없는 상품이 된다.
  if (qtaPriceInt > 0 && !(await isVerified(c.env, user.id))) {
    return c.json({ error: tr(c, 'QTA 가격은 본인 인증 후에 설정할 수 있어요', 'QTA価格は本人確認後に設定できます', 'You can set a QTA price after verifying your identity') }, 403);
  }

  // ── 핵심 INSERT 블록을 try/catch 로 감싸 사장님께 정확한 한국어 에러 노출 ──
  // 마이그레이션 누락(qta_price/video_url/lat/lng 컬럼 없음)이나 D1 일시 장애를
  // 그냥 "Internal Server Error" 로 떨어뜨리지 않고, 어떤 단계에서 깨졌는지를
  // 응답 본문에 명시한다. 운영 디버깅 + 사용자 안내 메시지 두 마리 토끼.
  let row: ProductRow | null = null;
  let sellerLat: number | null = null;
  let sellerLng: number | null = null;
  let sellerMarket: Market = 'kr';

  try {
    // 작성자의 동네 좌표를 그대로 복사 — 거리 필터에 사용.
    // 인증 안 된 사용자면 lat/lng 가 NULL 이라 거리 필터 결과에서 빠진다.
    // users.lat/lng 컬럼이 없으면 0012 마이그레이션 미적용. 이때는 좌표 없이 진행.
    try {
      const seller = await c.env.DB
        .prepare('SELECT lat, lng, market FROM users WHERE id = ?')
        .bind(user.id)
        .first<{ lat: number | null; lng: number | null; market: string | null }>();
      sellerLat = seller?.lat ?? null;
      sellerLng = seller?.lng ?? null;
      sellerMarket = normalizeMarket(seller?.market) ?? 'kr';
    } catch (e) {
      // users.lat/lng 미존재 → 좌표 없이 진행 (거리 필터에서만 빠짐)
      console.error('[products.create] users.lat/lng 조회 실패 (무시):', e);
    }

    await c.env.DB
      .prepare(`
        INSERT INTO products (id, seller_id, title, description, price, qta_price, category, region, images, video_url, lat, lng, market)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `)
      .bind(
        id, user.id, title, description, priceInt, qtaPriceInt, category, region, images, videoUrl,
        sellerLat, sellerLng, sellerMarket
      )
      .run();

    row = await c.env.DB
      .prepare('SELECT * FROM products WHERE id = ?')
      .bind(id)
      .first<ProductRow>();
  } catch (e) {
    // 마이그레이션 누락이 가장 흔한 원인. 정확한 원본 메시지를 응답에 포함.
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[products.create] INSERT 실패:', msg);
    return c.json({
      error: tr(c, '상품 저장 중 서버 오류가 발생했어요. 잠시 후 다시 시도해주세요.', '商品の保存中にサーバーエラーが発生しました。しばらくしてから再度お試しください。', 'A server error occurred while saving your item. Please try again in a moment.'),
      detail: msg, // 운영 진단용 — 클라이언트는 표시만 안 하면 됨
    }, 500);
  }

  if (!row) {
    return c.json({ error: tr(c, '상품 저장 직후 조회 실패 — 잠시 후 다시 시도해주세요.', '商品を保存しましたが、読み込みに失敗しました。しばらくしてから再度お試しください。', `Your item was saved but couldn't be loaded. Please try again in a moment.`) }, 500);
  }

  // 상품 등록 채굴 — 가격의 10% 를 QTA 로 (1 QTA = 10원, 건당·하루 상한).
  let listingReward = 0;
  try {
    listingReward = await grantListingReward(c.env, user.id, { id, title, price: priceInt, market: sellerMarket });
    if (listingReward > 0) row = { ...row, listing_reward: listingReward };
  } catch (e) {
    console.error('[products.create] listing reward failed', e);
  }

  const product = await hydrate(c.env, row, user.id);

  if (moderation.action === 'review') {
    c.executionCtx.waitUntil(recordContentFlags(c.env.DB, { userId: user.id, targetType: 'product', targetId: id, result: moderation }));
  }

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
      lat: sellerLat,
      lng: sellerLng,
      thumb: imageKeys[0]
        ? (c.env.PUBLIC_UPLOAD_URL
            ? `${c.env.PUBLIC_UPLOAD_URL.replace(/\/$/, '')}/${imageKeys[0]}`
            : `/uploads/${imageKeys[0]}`)
        : null,
    }).catch((e) => console.error('[alerts] fanout error', e))
  );

  return c.json({ product, listing_reward: listingReward }, 201);
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
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);
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
    if (!t) return c.json({ error: tr(c, '제목을 입력해주세요', '商品名を入力してください', 'Please enter a title') }, 400);
    if (t.length > 80) return c.json({ error: tr(c, '제목이 너무 길어요', '商品名が長すぎます', 'The title is too long') }, 400);
    updates.push('title = ?');
    params.push(t);
  }
  if (typeof body.description === 'string') {
    const d = (body.description as string).trim();
    if (d.length < 10) return c.json({ error: tr(c, '설명은 10자 이상 입력해주세요', '商品説明は10文字以上で入力してください', 'Please write a description of at least 10 characters') }, 400);
    updates.push('description = ?');
    params.push(d);
  }
  if (body.price !== undefined) {
    const p = parseInt(String(body.price), 10);
    if (!Number.isFinite(p) || p < 0) {
      return c.json({ error: tr(c, '가격이 올바르지 않아요', '価格が正しくありません', 'Invalid price') }, 400);
    }
    updates.push('price = ?');
    params.push(p);
  }
  if (body.qta_price !== undefined) {
    const q = parseInt(String(body.qta_price), 10);
    if (!Number.isFinite(q) || q < 0) {
      return c.json({ error: tr(c, 'QTA 가격이 올바르지 않아요', 'QTA価格が正しくありません', 'Invalid QTA price') }, 400);
    }
    // 거래완료 후에는 결제가 끝났으므로 변경 금지.
    if (row.status === 'sold') {
      return c.json({ error: tr(c, '거래완료된 상품은 가격 변경 불가', '取引完了した商品は価格を変更できません', `You can't change the price of a sold item`) }, 400);
    }
    if (q > 0 && !(await isVerified(c.env, user.id))) {
      return c.json({ error: tr(c, 'QTA 가격은 본인 인증 후에 설정할 수 있어요', 'QTA価格は本人確認後に設定できます', 'You can set a QTA price after verifying your identity') }, 403);
    }
    updates.push('qta_price = ?');
    params.push(q);
  }
  if (typeof body.category === 'string' && (body.category as string).trim()) {
    updates.push('category = ?');
    params.push((body.category as string).trim());
  }
  if (typeof body.region === 'string' && (body.region as string).trim()) {
    const newRegion = (body.region as string).trim();
    updates.push('region = ?');
    params.push(newRegion);
    // region 변경 시 작성자의 현재 lat/lng 도 같이 갱신 (거리 필터 일관성).
    // users.lat/lng 컬럼이 없는 환경(0012 마이그레이션 미적용)에서는 좌표 없이 진행.
    try {
      const seller = await c.env.DB
        .prepare('SELECT lat, lng FROM users WHERE id = ?')
        .bind(user.id)
        .first<{ lat: number | null; lng: number | null }>();
      updates.push('lat = ?');
      params.push((seller?.lat ?? null) as unknown as number);
      updates.push('lng = ?');
      params.push((seller?.lng ?? null) as unknown as number);
    } catch (e) {
      console.error('[products.patch] users.lat/lng 조회 실패 (무시):', e);
    }
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
      if (!normalized) return c.json({ error: tr(c, '유튜브 링크 형식이 올바르지 않아요', 'YouTubeリンクの形式が正しくありません', `That YouTube link doesn't look right`) }, 400);
      updates.push('video_url = ?');
      params.push(normalized);
    }
  }

  if (updates.length === 0) {
    return c.json({ error: tr(c, '수정할 내용이 없어요', '変更する内容がありません', 'Nothing to update') }, 400);
  }

  // 거래 금지 품목 · 금지어 · 외부 연락처 — 수정 후 최종 상태(바뀐 필드 + 기존 값)로 검사.
  const nextTitle = typeof body.title === 'string' ? (body.title as string).trim() : row.title;
  const nextDesc = typeof body.description === 'string' ? (body.description as string).trim() : row.description;
  const nextCategory = typeof body.category === 'string' && (body.category as string).trim()
    ? (body.category as string).trim()
    : row.category;
  const textChanged = typeof body.title === 'string' || typeof body.description === 'string' || nextCategory !== row.category;
  if (textChanged) {
    const moderation = checkProductText({ title: nextTitle, description: nextDesc, category: nextCategory });
    if (moderation.action === 'block') {
      c.executionCtx.waitUntil(recordContentFlags(c.env.DB, { userId: user.id, targetType: 'product', targetId: id, result: moderation }));
      return c.json({ error: tr(c, moderation.message ?? '', moderation.messageJa ?? moderation.message ?? '', moderation.messageEn ?? moderation.message ?? ''), code: 'prohibited', category: moderation.blocked ? tr(c, moderation.blocked.label, moderation.blocked.labelJa, moderation.blocked.labelEn) : undefined }, 400);
    }
    if (moderation.action === 'review') {
      c.executionCtx.waitUntil(recordContentFlags(c.env.DB, { userId: user.id, targetType: 'product', targetId: id, result: moderation }));
    }
  }

  updates.push("updated_at = datetime('now')");
  params.push(id);

  await c.env.DB
    .prepare(`UPDATE products SET ${updates.join(', ')} WHERE id = ?`)
    .bind(...params)
    .run();

  // 가격을 내렸으면 등록 채굴 보상 차액 회수 (올려도 더 주지는 않음).
  let rewardClawback = 0;
  if (body.price !== undefined) {
    try {
      rewardClawback = await adjustListingRewardOnPrice(c.env, user.id, {
        id,
        title: nextTitle,
        price: parseInt(String(body.price), 10),
        listing_reward: row.listing_reward ?? 0,
        market: normalizeMarket(row.market) ?? 'kr',
      });
    } catch (e) {
      console.error('[products.patch] listing reward adjust failed', e);
    }
  }

  const updated = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();
  const product = await hydrate(c.env, updated, user.id);
  return c.json({ product, listing_reward_clawback: rewardClawback });
});

/**
 * PUT /api/products/:id/status
 *
 * Seller updates listing status.
 * • status='sold' may carry a `buyer_id` — typically chosen from the chat
 *   partners that messaged about this product. Stored on the product so both
 *   sides can leave a review later.
 * • Switching back to 'sale' or 'reserved' clears any previous buyer_id.
 * • 판매자는 구매자를 "지정"만 한다. QTA 결제와 거래 보너스는 구매자가
 *   POST /:id/confirm-purchase 로 직접 확인했을 때만 실행된다.
 *   (예전에는 여기서 바로 payTrade 를 호출해서, 판매자가 아무 사용자나
 *    구매자로 지정하면 그 사람의 QTA 가 빠져나갔다.)
 * • 구매자가 확인한 거래(buyer_confirmed_at)는 상태를 더 이상 바꿀 수 없다.
 */
app.put('/:id/status', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');
  let body: { status?: string; buyer_id?: string | null } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);
  }
  if (!['sale', 'reserved', 'sold'].includes(body.status || '')) {
    return c.json({ error: tr(c, '잘못된 상태', '不正なステータスです', 'Invalid status') }, 400);
  }

  const row = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();

  if (!row) return c.json({ error: 'Not found' }, 404);
  if (row.seller_id !== user.id) return c.json({ error: 'Forbidden' }, 403);
  if (row.buyer_confirmed_at) {
    return c.json({ error: tr(c, '구매자가 거래를 확인한 상품은 상태를 바꿀 수 없어요', '購入者が取引を確認した商品はステータスを変更できません', `You can't change the status after the buyer has confirmed the deal`) }, 409);
  }

  // Validate buyer_id if provided (must be a real user, not the seller).
  let buyerId: string | null = null;
  if (body.status === 'sold' && body.buyer_id) {
    if (body.buyer_id === user.id) {
      return c.json({ error: tr(c, '본인을 구매자로 지정할 수 없어요', 'ご自身を購入者に指定することはできません', `You can't set yourself as the buyer`) }, 400);
    }
    // QTA 결제 거래만 본인인증(Lv1) 판매자로 제한 — 돈(QTA)이 오가는 거래.
    // 원화 거래는 인증 없이 거래완료·후기 가능 (거래 보너스는 양쪽 인증 시에만 지급).
    if ((row.qta_price ?? 0) > 0) {
      const seller = await c.env.DB
        .prepare('SELECT verification_level FROM users WHERE id = ?')
        .bind(user.id)
        .first<{ verification_level: number | null }>();
      if ((seller?.verification_level ?? 0) < 1) {
        return c.json({ error: tr(c, 'QTA 결제 거래는 본인 인증 후에 완료할 수 있어요', 'QTA決済の取引は本人確認後に完了できます', 'You can complete QTA deals after verifying your identity') }, 403);
      }
    }
    const buyer = await c.env.DB
      .prepare('SELECT id FROM users WHERE id = ?')
      .bind(body.buyer_id)
      .first<{ id: string }>();
    if (!buyer) return c.json({ error: tr(c, '구매자를 찾을 수 없어요', '購入者が見つかりません', 'Buyer not found') }, 400);
    // QTA 결제 거래는 구매자도 본인인증이 있어야 확인(결제)할 수 있다. 미인증 구매자를
    // 지정하면 구매자가 영영 확인할 수 없는 거래가 되므로 여기서 미리 막는다.
    if ((row.qta_price ?? 0) > 0 && !(await isVerified(c.env, body.buyer_id))) {
      return c.json(
        { error: tr(c, '구매자가 본인 인증을 해야 QTA 결제 거래를 완료할 수 있어요', 'QTA決済の取引を完了するには、購入者の本人確認が必要です', 'The buyer needs to verify their identity to complete a QTA deal'), code: 'buyer_not_verified' },
        403,
      );
    }
    buyerId = body.buyer_id;
  }

  // buyer_confirmed_at IS NULL 조건 — 위 체크와 이 UPDATE 사이에 구매자가
  // 확인한 경우까지 막는다.
  const res = await c.env.DB
    .prepare(
      `UPDATE products SET status = ?, buyer_id = ?, updated_at = datetime('now')
        WHERE id = ? AND buyer_confirmed_at IS NULL`,
    )
    .bind(body.status, body.status === 'sold' ? buyerId : null, id)
    .run();
  if ((res.meta?.changes ?? 0) !== 1) {
    return c.json({ error: tr(c, '구매자가 거래를 확인한 상품은 상태를 바꿀 수 없어요', '購入者が取引を確認した商品はステータスを変更できません', `You can't change the status after the buyer has confirmed the deal`) }, 409);
  }

  // 구매자에게 "거래 확인 요청" 푸시 — 안 보내면 구매자가 상품 상세에 직접
  // 들어가기 전까지 요청을 알 수 없다. 탭하면 상품 상세(거래 확인 카드)로 이동.
  if (body.status === 'sold' && buyerId) {
    // 거래 후기 요청도 같은 알림에 담는다 (당근: "거래 후기를 남겨주세요"). 받는 사람의 시장 언어로.
    const buyerToken = await c.env.DB
      .prepare('SELECT fcm_token, market FROM users WHERE id = ?')
      .bind(buyerId)
      .first<{ fcm_token: string | null; market: string | null }>();
    if (buyerToken?.fcm_token) {
      const pl: Lang = marketLang(normalizeMarket(buyerToken.market));
      c.executionCtx.waitUntil(
        sendFcm(c.env, {
          fcmToken: buyerToken.fcm_token,
          title: trl(pl, '거래 확인 요청', '取引確認のお願い', 'Please confirm your deal'),
          body: trl(pl, '판매자가 거래완료로 표시했어요. 거래를 확인하고 거래 후기를 남겨주세요', '出品者が取引完了にしました。取引を確認して、評価をお願いします', 'The seller marked the deal as complete. Please confirm it and leave a review'),
          data: { type: 'purchase_confirm', product_id: id },
        }).catch((e) => console.error('[products/status] buyer push failed', e)),
      );
    }
  }

  return c.json({
    ok: true,
    status: body.status,
    buyer_id: buyerId,
    // 결제/보너스는 구매자 확인 후. 구버전 앱 호환을 위해 키는 유지.
    qta_bonus: null,
    qta_payment: null,
    awaiting_buyer_confirmation: body.status === 'sold' && !!buyerId,
  });
});

/**
 * POST /api/products/:id/confirm-purchase
 *
 * 판매자가 거래완료로 지정한 구매자 본인이 거래를 확인한다.
 *   1) buyer_confirmed_at 을 먼저 원자적으로 기록 (이후 판매자는 상태/구매자 변경 불가)
 *   2) qta_price > 0 이면 buyer → seller QTA 결제. 실패하면 1) 을 되돌린다.
 *   3) 거래완료 보너스 (양쪽 +10, 멱등)
 */
app.post('/:id/confirm-purchase', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');

  const row = await c.env.DB
    .prepare('SELECT * FROM products WHERE id = ?')
    .bind(id)
    .first<ProductRow>();
  if (!row) return c.json({ error: 'Not found' }, 404);
  if (row.status !== 'sold' || row.buyer_id !== user.id) {
    return c.json({ error: tr(c, '이 상품의 구매자로 지정되지 않았어요', 'この商品の購入者に指定されていません', `You're not set as the buyer of this item`) }, 403);
  }
  if (row.buyer_confirmed_at) {
    return c.json({ ok: true, already_confirmed: true, qta_payment: null, qta_bonus: null });
  }
  // QTA 결제 거래는 구매자도 본인인증(Lv1) 필수. 가입 보너스를 받은 다계정이
  // 가짜 거래로 한 판매자 계정에 QTA 를 몰아주는 경로를 막는다 (1인 1계정 = CI 중복 차단).
  const levels = await c.env.DB
    .prepare(
      `SELECT (SELECT verification_level FROM users WHERE id = ?) AS buyer_lv,
              (SELECT verification_level FROM users WHERE id = ?) AS seller_lv`,
    )
    .bind(user.id, row.seller_id)
    .first<{ buyer_lv: number | null; seller_lv: number | null }>();
  const bothVerified = (levels?.buyer_lv ?? 0) >= 1 && (levels?.seller_lv ?? 0) >= 1;
  if ((row.qta_price ?? 0) > 0 && (levels?.buyer_lv ?? 0) < 1) {
    return c.json({ error: tr(c, '거래 확인에는 본인 인증이 필요해요', '取引の確認には本人確認が必要です', 'Identity verification is required to confirm a deal'), code: 'verification_required' }, 403);
  }

  // 구매자가 화면에서 본 QTA 가격 (앱이 보냄). 다르면 판매자가 그사이 가격을 바꾼 것 →
  // 구매자가 보지 못한 가격이 청구되지 않도록 거부. (구버전 앱은 안 보냄 → 검사 생략)
  let expectedQta: number | null = null;
  try {
    const b = (await c.req.json().catch(() => ({}))) as { expected_qta_price?: number };
    if (typeof b.expected_qta_price === 'number') expectedQta = b.expected_qta_price;
  } catch { /* body 없음 */ }
  if (expectedQta !== null && expectedQta !== (row.qta_price ?? 0)) {
    return c.json({ error: tr(c, '판매자가 가격을 바꿨어요. 상품을 다시 확인해주세요', '出品者が価格を変更しました。商品をもう一度ご確認ください', 'The seller changed the price. Please check the item again'), code: 'price_changed' }, 409);
  }

  const lock = await c.env.DB
    .prepare(
      `UPDATE products SET buyer_confirmed_at = datetime('now'), updated_at = datetime('now')
        WHERE id = ? AND status = 'sold' AND buyer_id = ? AND buyer_confirmed_at IS NULL
          AND qta_price = ?`,
    )
    .bind(id, user.id, row.qta_price ?? 0)
    .run();
  if ((lock.meta?.changes ?? 0) !== 1) {
    // 동시에 판매자가 상태·가격을 바꿨거나, 다른 요청이 먼저 확인함.
    return c.json({ error: tr(c, '거래 상태가 바뀌었어요. 다시 확인해주세요', '取引のステータスが変わりました。もう一度ご確認ください', 'The deal status has changed. Please check again') }, 409);
  }
  const unlock = () =>
    c.env.DB
      .prepare('UPDATE products SET buyer_confirmed_at = NULL WHERE id = ? AND buyer_id = ?')
      .bind(id, user.id)
      .run();

  let qtaPayment: { ok: true; charged: number; already_paid?: boolean } | null = null;
  if ((row.qta_price ?? 0) > 0) {
    // 결제 중 예외(D1 일시 오류 등)가 나도 확인 표시를 되돌린다 — 안 그러면
    // "확인됨·미결제" 로 굳어 다시 확인도, 판매자 변경도 못 하게 된다.
    let pay: Awaited<ReturnType<typeof payTrade>>;
    try {
      pay = await payTrade(c.env, id, row.seller_id, user.id, row.qta_price, reqLang(c));
    } catch (e) {
      console.error('[products/confirm-purchase] payTrade threw', e);
      await unlock().catch(() => {});
      return c.json({ error: tr(c, '결제 처리 중 문제가 생겼어요. 잠시 후 다시 시도해주세요', '決済処理中に問題が発生しました。しばらくしてから再度お試しください', 'Something went wrong with the payment. Please try again in a moment') }, 500);
    }
    if (!pay.ok) {
      await unlock();
      const code = pay.reason === 'insufficient' ? 402 : 400;
      return c.json({ error: pay.error, reason: pay.reason }, code);
    }
    qtaPayment = pay;
  }

  // 거래 보너스(+10 씩)는 양쪽 모두 본인인증한 경우에만 — 인증 없는 다계정끼리
  // 가짜 원화 거래로 보너스를 무한히 만드는 것을 막는다.
  let qtaBonus: { seller_credited: boolean; buyer_credited: boolean; amount: number } | null = null;
  if (bothVerified) {
    try {
      const r = await grantTradeBonus(c.env, id, row.seller_id, user.id);
      qtaBonus = { ...r, amount: 10 };
    } catch (e) {
      console.error('[products/confirm-purchase] trade bonus failed', e);
    }
  }

  return c.json({ ok: true, qta_payment: qtaPayment, qta_bonus: qtaBonus });
});

// /api/products/:id/buyers 는 제거됨.
// 휘발성 채팅 정책상 서버에 chat_rooms 가 없으므로 "이 상품에 문의했던 사람" 같은
// 목록을 만들 수 없다. 대신 거래완료 시 판매자가 직접 구매자의 닉네임으로
// 검색해서 (GET /api/users/search) 선택한 buyer_id 를 PUT /:id/status 에 넣는다.

/**
 * POST /api/products/:id/review
 *
 * 거래 후기 (당근식). 판매자 ↔ 구매자 서로 한 번씩, 상품당 1개.
 *   body (새 앱, v=2):
 *     { v: 2, rating: 'best'|'good'|'bad', tags: string[], comment?: string }
 *     • tags: 역할·평가별 허용 코드 (src/reviews.ts allowedTags), 최소 1개.
 *   body (구버전 앱): { rating: 'good'|'soso'|'bad', tags: [], comment }
 *     • 구버전 앱은 항목을 보내지 않으므로 항목 없이 받는다 (자유 입력 태그는 더 이상 저장 안 함).
 *
 * 매너온도는 같은 batch 안에서 갱신 (MANNER_DELTA: best +0.5° / good +0.2° / soso 0 / bad −0.5°,
 * ×10 정수, 0..990 클램프).
 *
 * NOTE: 원래는 DB 트리거(trg_reviews_update_manner)로 처리했지만 D1 의
 *       `migrations apply` 단계에서 트리거 본문 안의 세미콜론 split 이슈로
 *       인해 (`incomplete input: SQLITE_ERROR [code: 7500]`) 트리거를 못
 *       만들었다. 따라서 application-level 에서 batch 두 statement 로 처리.
 *
 * Constraints:
 *   • Product status must be 'sold' with a buyer.
 *   • Reviewer must be the seller or the recorded buyer (본인 평가 불가).
 *   • One review per (product, reviewer).
 *   • 탈퇴한 상대에게는 후기를 남길 수 없다 (410).
 */
app.post('/:id/review', authMiddleware, async (c) => {
  const user = c.get('user')!;
  const id = c.req.param('id');
  const lang = reqLang(c);

  let body: { v?: number; rating?: string; tags?: unknown; comment?: unknown } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです', 'Invalid request') }, 400);
  }
  const rating = String(body.rating || '') as ReviewRating;
  const rawTags = Array.isArray(body.tags) ? body.tags.map((t) => String(t).trim()).filter(Boolean) : [];
  // 새 앱은 v=2 를 보낸다. 'best' 나 항목 코드를 보내는 요청도 새 규칙으로 검사.
  const strict = Number(body.v) >= 2 || rating === 'best' || rawTags.length > 0;
  if (!(strict ? NEW_RATINGS : LEGACY_RATINGS).includes(rating)) {
    return c.json({ error: tr(c, '평가를 선택해주세요', '評価を選択してください', 'Please choose a rating'), code: 'invalid_rating' }, 400);
  }

  const product = await c.env.DB
    .prepare('SELECT seller_id, buyer_id, status, price FROM products WHERE id = ?')
    .bind(id)
    .first<{ seller_id: string; buyer_id: string | null; status: string; price: number }>();
  if (!product) return c.json({ error: 'Not found' }, 404);
  if (product.status !== 'sold') {
    return c.json({ error: tr(c, '거래완료 후에 후기를 남길 수 있어요', '評価は取引完了後に投稿できます', 'You can leave a review after the deal is complete') }, 400);
  }
  if (!product.buyer_id) {
    return c.json({ error: tr(c, '구매자가 지정되지 않았어요', '購入者が指定されていません', 'No buyer has been set') }, 400);
  }

  // Determine reviewee + my role.
  let revieweeId: string | null = null;
  let role: ReviewerRole | null = null;
  if (user.id === product.seller_id) {
    revieweeId = product.buyer_id;
    role = 'seller';
  } else if (user.id === product.buyer_id) {
    revieweeId = product.seller_id;
    role = 'buyer';
  }
  if (!revieweeId || !role) {
    return c.json({ error: tr(c, '거래 당사자만 후기를 남길 수 있어요', '評価は取引の当事者のみ投稿できます', 'Only the people in the deal can leave a review') }, 403);
  }
  if (revieweeId === user.id) {
    return c.json({ error: tr(c, '나에게는 후기를 남길 수 없어요', 'ご自身を評価することはできません', `You can't review yourself`) }, 400);
  }

  // 항목 검사 — 역할·평가에 맞는 코드만, 최소 1개.
  let tags: string[] = [];
  if (strict) {
    const allowed = allowedTags(role, rating, { free: (product.price ?? 0) === 0 });
    tags = [...new Set(rawTags)];
    if (tags.length === 0) {
      return c.json({ error: tr(c, '매너 항목을 하나 이상 선택해주세요', '項目を1つ以上選択してください', 'Please select at least one item'), code: 'tags_required' }, 400);
    }
    if (tags.length > MAX_TAGS || tags.some((t) => !allowed.includes(t))) {
      return c.json({ error: tr(c, '선택할 수 없는 항목이 있어요', '選択できない項目が含まれています', `Some selected items aren't allowed`), code: 'invalid_tag' }, 400);
    }
  }

  const comment = (typeof body.comment === 'string' ? body.comment : '').trim();
  if ([...comment].length > COMMENT_MAX) {
    return c.json({ error: tr(c, `후기는 ${COMMENT_MAX}자까지 쓸 수 있어요`, `コメントは${COMMENT_MAX}文字以内で入力してください`, `Reviews can be up to ${COMMENT_MAX} characters`), code: 'comment_too_long' }, 400);
  }
  const commentErr = checkReviewText(comment, lang);
  if (commentErr) return c.json({ error: commentErr, code: 'prohibited' }, 400);

  const reviewee = await c.env.DB
    .prepare('SELECT id, fcm_token, market FROM users WHERE id = ?')
    .bind(revieweeId)
    .first<{ id: string; fcm_token: string | null; market: string | null }>();
  if (!reviewee) {
    return c.json({ error: tr(c, '탈퇴한 사용자에게는 후기를 남길 수 없어요', '退会したユーザーは評価できません', `You can't review a user who has left`), code: 'reviewee_gone' }, 410);
  }

  // Duplicate check — UNIQUE(product_id, reviewer_id) is the source of truth,
  // but we want a friendly error rather than a 500 from the DB.
  const dup = await c.env.DB
    .prepare('SELECT 1 FROM reviews WHERE product_id = ? AND reviewer_id = ?')
    .bind(id, user.id)
    .first();
  if (dup) return c.json({ error: tr(c, '이미 후기를 남기셨어요', 'すでに評価を投稿済みです', `You've already left a review`), code: 'duplicate' }, 409);

  const reviewId = crypto.randomUUID();
  const delta = MANNER_DELTA[rating];

  // INSERT review + UPDATE manner_score 를 한 batch 로 묶어 atomic 보장.
  // 예전 가입 회원은 manner_score 가 36(×1 스케일, users 기본값)일 수 있어 365(36.5°)로 맞춘 뒤 더한다
  // (앱도 100 미만이면 ×10 으로 해석 — 안 맞추면 36+5=41 → 41.0° 로 튀었다).
  // 동시 요청이 dup 체크를 함께 통과해도 UNIQUE 위반으로 batch 전체가 롤백된다.
  try {
    await c.env.DB.batch([
      c.env.DB
        .prepare(
          `INSERT INTO reviews (id, product_id, reviewer_id, reviewee_id, rating, tags, comment)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
        )
        .bind(reviewId, id, user.id, revieweeId, rating, tags.join(','), comment),
      c.env.DB
        .prepare(
          `UPDATE users
              SET manner_score = MIN(${MANNER_MAX}, MAX(${MANNER_MIN}, (CASE WHEN manner_score < 100 THEN manner_score * 10 + 5 ELSE manner_score END) + ?)),
                  updated_at   = datetime('now')
            WHERE id = ?`,
        )
        .bind(delta, revieweeId),
    ]);
  } catch (e) {
    if (/UNIQUE/i.test(String(e))) {
      return c.json({ error: tr(c, '이미 후기를 남기셨어요', 'すでに評価を投稿済みです', `You've already left a review`), code: 'duplicate' }, 409);
    }
    throw e;
  }

  // 업데이트된 manner_score 를 응답에 포함 (클라이언트가 즉시 표시할 수 있도록).
  const updated = await c.env.DB
    .prepare('SELECT manner_score FROM users WHERE id = ?')
    .bind(revieweeId)
    .first<{ manner_score: number }>();

  // 받은 사람에게 알림 — "OO님이 거래 후기를 보냈어요". 'bad' 는 공개되지 않는 평가라 알리지 않는다.
  // 받은 사람이 아직 후기를 안 썼으면 상품 상세(후기 보내기 버튼)로, 썼으면 내 프로필(받은 후기)로.
  // 받은 사람이 나를 차단했으면 보내지 않는다.
  if (rating !== 'bad' && reviewee.fcm_token) {
    c.executionCtx.waitUntil(
      (async () => {
        const [me, blocked, theirs] = await Promise.all([
          c.env.DB.prepare('SELECT nickname FROM users WHERE id = ?').bind(user.id).first<{ nickname: string }>(),
          c.env.DB.prepare('SELECT 1 FROM user_blocks WHERE blocker_id = ? AND blocked_id = ?').bind(revieweeId, user.id).first(),
          c.env.DB.prepare('SELECT 1 FROM reviews WHERE product_id = ? AND reviewer_id = ?').bind(id, revieweeId).first(),
        ]);
        if (blocked) return;
        const pl: Lang = marketLang(normalizeMarket(reviewee.market));
        const nick = me?.nickname || trl(pl, '거래 상대', '取引相手', 'Your trade partner');
        await sendFcm(c.env, {
          fcmToken: reviewee.fcm_token!,
          title: trl(pl, `${nick}님이 거래 후기를 보냈어요`, `${nick}さんから取引の評価が届きました`, `${nick} sent you a review`),
          body: theirs
            ? trl(pl, '내 프로필에서 받은 후기를 확인해보세요', 'プロフィールで受け取った評価を確認しましょう', 'Check the review on your profile')
            : trl(pl, '나도 거래 후기를 남겨주세요', 'あなたも取引の評価をしましょう', 'Leave a review for them too'),
          data: theirs
            ? { type: 'review_received', user_id: revieweeId! }
            : { type: 'review_request', product_id: id },
        });
      })().catch((e) => console.error('[products/review] push failed', e)),
    );
  }

  return c.json({
    ok: true,
    review_id: reviewId,
    reviewee_id: revieweeId,
    role,
    rating,
    manner_delta: delta,
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
    return c.json({ error: tr(c, '판매중인 상품만 끌어올릴 수 있어요', '上位表示できるのは販売中の商品のみです', 'Only items on sale can be bumped') }, 400);
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
        const waitJa = hours > 0 ? `${hours}時間${mins}分` : `${mins}分`;
        const waitEn = hours > 0 ? `${hours}h ${mins}m` : `${mins}m`;
        return c.json(
          {
            error: tr(c, `${wait} 후에 다시 끌어올릴 수 있어요`, `${waitJa}後に再度上位表示できます`, `You can bump again in ${waitEn}`),
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
    return c.json({ error: tr(c, '본인인증(Lv1) 후 거래할 수 있어요', '本人確認（Lv1）後に取引できます', 'You can trade after identity verification (Lv1)'), need_verify: 1 }, 403);
  }

  const row = await c.env.DB
    .prepare('SELECT id, seller_id, price, status, market FROM products WHERE id = ?')
    .bind(id)
    .first<{ id: string; seller_id: string; price: number; status: string; market: string | null }>();
  if (!row) return c.json({ error: tr(c, '상품을 찾을 수 없어요', '商品が見つかりません', 'Item not found') }, 404);
  // 안전거래는 한국 계좌 입금 방식이라 한국 상품만.
  if ((row.market || 'kr') !== 'kr') {
    return c.json({ error: tr(c, '이 상품은 안전거래를 쓸 수 없어요', 'この商品は安全取引をご利用いただけません', `Safe payment isn't available for this item`), reason: 'market' }, 400);
  }
  if (row.seller_id === user.id) {
    return c.json({ error: tr(c, '본인 상품에는 에스크로를 만들 수 없어요', 'ご自身の商品には安全取引を利用できません', `You can't use safe payment on your own item`) }, 400);
  }
  if (row.status === 'sold') {
    return c.json({ error: tr(c, '이미 거래 완료된 상품이에요', 'すでに取引完了した商品です', 'This item has already been sold') }, 400);
  }
  if (row.price >= ESCROW_MAX_AMOUNT_KRW) {
    return c.json(
      {
        error: tr(c, '30,000원 이상은 당사자 직거래에요', 'この金額の商品は安全取引の対象外です。当事者間で直接お取引ください', `Safe payment isn't available for items at this price. Please trade directly with the other person`),
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
    reqLang(c),
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

  // 삭제와 등록 채굴 보상 회수를 한 batch 로.
  const rewardClawback = await deleteProductWithClawback(c.env, user.id, row);

  return c.json({ ok: true, listing_reward_clawback: rewardClawback });
});

export default app;
