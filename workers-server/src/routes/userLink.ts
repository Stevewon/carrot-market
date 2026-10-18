import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { normalizeMarket, type Market } from '../market';

/**
 * GET /u/:id — 내 QR · "QR 링크 복사" 로 보낸 링크의 웹 페이지.
 *  - 카톡·문자에서 눌리는 https 링크 (예전 eggplant://<id>/<닉네임> 은 눌리지도 않고 앱이 열지도 못했다).
 *  - "가지 앱에서 익명 채팅하기" → eggplant://app/u/<id> (앱이 그 회원과 채팅방을 연다).
 *  - 앱이 없으면 eggplant.life 에서 받기.
 *  닉네임 말고는 아무것도 내보내지 않는다 (익명 마켓).
 */
const app = new Hono<{ Bindings: Env; Variables: Variables }>();

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]!);

const TEXT: Record<Market, { title: (n: string) => string; desc: string; open: string; get: string; gone: string; lang: string }> = {
  kr: { title: (n) => `${n} 님과 익명 채팅`, desc: '대화는 저장되지 않아요', open: '가지 앱에서 채팅하기', get: '가지 앱 받기', gone: '없는 회원이에요', lang: 'ko' },
  jp: { title: (n) => `${n}さんと匿名チャット`, desc: '会話は保存されません', open: 'ナスアプリでチャット', get: 'アプリをダウンロード', gone: 'この会員は存在しません', lang: 'ja' },
  ph: { title: (n) => `Anonymous chat with ${n}`, desc: 'Chats are never stored', open: 'Chat in Eggplant', get: 'Get the Eggplant app', gone: 'This member no longer exists', lang: 'en' },
};

app.get('/:id', async (c) => {
  const id = c.req.param('id');
  const row = await c.env.DB
    .prepare('SELECT id, nickname, market FROM users WHERE id = ?')
    .bind(id)
    .first<{ id: string; nickname: string; market: string | null }>();

  const market: Market = normalizeMarket(row?.market) ?? 'kr';
  const t = TEXT[market];
  const deepLink = `eggplant://app/u/${encodeURIComponent(id)}?n=${encodeURIComponent(row?.nickname ?? '')}`;
  const getUrl = 'https://eggplant.life/#download';
  const title = row ? t.title(row.nickname) : t.gone;

  const html = `<!doctype html>
<html lang="${t.lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} · 가지</title>
<meta property="og:type" content="website">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(row ? t.desc : '')}">
<meta name="robots" content="noindex">
<style>
  body{margin:0;font-family:-apple-system,system-ui,'Noto Sans KR','Noto Sans JP',sans-serif;background:#FAF5FF;color:#1F1235}
  .wrap{max-width:480px;margin:0 auto;padding:16px}
  .card{background:#fff;border-radius:16px;padding:32px 16px;text-align:center;box-shadow:0 2px 12px rgba(80,20,120,.08)}
  .ph{font-size:72px}
  h1{font-size:20px;margin:12px 0 6px;word-break:break-all}
  p{margin:0;color:#6B5B7B;font-size:14px}
  .btn{display:block;text-align:center;text-decoration:none;font-weight:800;border-radius:12px;padding:14px;margin-top:12px}
  .primary{background:#7C3AED;color:#fff}
  .ghost{background:#fff;color:#7C3AED;border:1.5px solid #7C3AED}
</style>
</head>
<body>
<div class="wrap">
  <div class="card">
    <div class="ph">🍆</div>
    <h1>${esc(title)}</h1>
    ${row ? `<p>🔐 ${esc(t.desc)}</p>` : ''}
  </div>
  ${row ? `<a class="btn primary" href="${esc(deepLink)}">${esc(t.open)}</a>` : ''}
  <a class="btn ghost" href="${esc(getUrl)}">${esc(t.get)}</a>
</div>
</body>
</html>`;
  return c.html(html, row ? 200 : 404, { 'Cache-Control': 'public, max-age=300' });
});

export default app;
