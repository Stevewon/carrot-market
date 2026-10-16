import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { normalizeMarket, type Market } from '../market';

/**
 * GET /p/:id — 공유한 상품 링크의 웹 미리보기.
 *  - 카톡·라인 등에서 사진·제목·가격이 보이도록 Open Graph 태그.
 *  - "가지 앱에서 보기" → eggplant://app/product/<id> (앱이 그 상품을 연다).
 *  - 앱이 없으면 eggplant.life 에서 받기.
 *  판매자 정보·설명 전문은 내보내지 않는다 (익명 마켓).
 */
const app = new Hono<{ Bindings: Env; Variables: Variables }>();

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]!);

const TEXT: Record<Market, { open: string; get: string; gone: string; free: string; lang: string }> = {
  kr: { open: '가지 앱에서 보기', get: '가지 앱 받기', gone: '없어진 상품이에요', free: '나눔', lang: 'ko' },
  jp: { open: 'ナスアプリで見る', get: 'アプリをダウンロード', gone: 'この商品は削除されました', free: '無料', lang: 'ja' },
  ph: { open: 'Open in Eggplant', get: 'Get the Eggplant app', gone: 'This item is no longer available', free: 'Free', lang: 'en' },
};

function priceLabel(price: number, market: Market, free: string): string {
  if (price <= 0) return free;
  const n = price.toLocaleString('en-US');
  return market === 'jp' ? `¥${n}` : market === 'ph' ? `₱${n}` : `${n}원`;
}

app.get('/:id', async (c) => {
  const id = c.req.param('id');
  const row = await c.env.DB
    .prepare('SELECT id, title, description, price, images, market, status FROM products WHERE id = ?')
    .bind(id)
    .first<{ id: string; title: string; description: string | null; price: number; images: string | null; market: string | null; status: string }>();

  const market: Market = normalizeMarket(row?.market) ?? 'kr';
  const t = TEXT[market];
  const origin = new URL(c.req.url).origin;
  const deepLink = `eggplant://app/product/${encodeURIComponent(id)}`;
  const getUrl = 'https://eggplant.life/#download';

  const title = row ? row.title : t.gone;
  const price = row ? priceLabel(row.price, market, t.free) : '';
  const firstImg = row?.images?.split(',').filter(Boolean)[0];
  const img = firstImg ? (firstImg.startsWith('http') ? firstImg : `${origin}${firstImg.startsWith('/') ? '' : '/'}${firstImg}`) : '';
  const desc = (row?.description || '').replace(/\s+/g, ' ').slice(0, 120);

  const html = `<!doctype html>
<html lang="${t.lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} · 가지</title>
<meta property="og:type" content="product">
<meta property="og:title" content="${esc(price ? `${title} · ${price}` : title)}">
<meta property="og:description" content="${esc(desc)}">
${img ? `<meta property="og:image" content="${esc(img)}">` : ''}
<meta name="robots" content="noindex">
<style>
  body{margin:0;font-family:-apple-system,system-ui,'Noto Sans KR','Noto Sans JP',sans-serif;background:#FAF5FF;color:#1F1235}
  .wrap{max-width:480px;margin:0 auto;padding:16px}
  .card{background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(80,20,120,.08)}
  .img{width:100%;aspect-ratio:1;object-fit:cover;background:#F3E8FF;display:block}
  .ph{width:100%;aspect-ratio:1;display:flex;align-items:center;justify-content:center;font-size:72px;background:#F3E8FF}
  .body{padding:16px}
  h1{font-size:20px;margin:0 0 6px}
  .price{font-size:18px;font-weight:800}
  .sold{display:inline-block;margin-left:6px;font-size:12px;color:#fff;background:#6B7280;border-radius:6px;padding:2px 6px;vertical-align:middle}
  .btn{display:block;text-align:center;text-decoration:none;font-weight:800;border-radius:12px;padding:14px;margin-top:12px}
  .primary{background:#7C3AED;color:#fff}
  .ghost{background:#fff;color:#7C3AED;border:1.5px solid #7C3AED}
</style>
</head>
<body>
<div class="wrap">
  <div class="card">
    ${img ? `<img class="img" src="${esc(img)}" alt="">` : '<div class="ph">🍆</div>'}
    <div class="body">
      <h1>${esc(title)}</h1>
      ${price ? `<div class="price">${esc(price)}${row?.status === 'sold' ? '<span class="sold">SOLD</span>' : ''}</div>` : ''}
    </div>
  </div>
  ${row ? `<a class="btn primary" href="${esc(deepLink)}">${esc(t.open)}</a>` : ''}
  <a class="btn ghost" href="${esc(getUrl)}">${esc(t.get)}</a>
</div>
</body>
</html>`;
  return c.html(html, row ? 200 : 404, { 'Cache-Control': 'public, max-age=300' });
});

export default app;
