import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { normalizeMarket, type Market } from '../market';

/**
 * GET /i/:nickname — 친구 초대 링크의 웹 페이지 (내 정보 → 친구 초대 → "초대 링크 보내기").
 *  - 가지 앱 받기 → 가입할 때 추천인 칸에 초대한 사람 닉네임 (복사 버튼).
 *  - 앱이 이미 있으면 "가지 앱에서 가입하기" → eggplant://app/register?ref=<닉네임> (추천인 칸이 채워진다).
 *  닉네임 말고는 아무것도 내보내지 않는다 (익명 마켓).
 */
const app = new Hono<{ Bindings: Env; Variables: Variables }>();

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]!);

const TEXT: Record<Market, {
  title: (n: string) => string; desc: string; ref: string; copy: string; copied: string;
  get: string; open: string; steps: string[]; gone: string; lang: string;
}> = {
  kr: {
    title: (n) => `${n} 님이 가지에 초대했어요`, desc: '익명으로 안전하게 사고파는 중고 마켓',
    ref: '추천인', copy: '복사', copied: '복사했어요', get: '가지 앱 받기', open: '앱이 있으면 — 가지 앱에서 가입하기',
    steps: ['가지 앱을 받아 설치해요', '회원가입 마지막 칸 "추천인"에 위 닉네임을 넣어요', '가입하면 초대한 친구가 +200 QTA를 받아요'],
    gone: '없는 초대 링크예요', lang: 'ko',
  },
  jp: {
    title: (n) => `${n}さんがナスに招待しました`, desc: '匿名で安心して売り買いできるフリマ',
    ref: '紹介者', copy: 'コピー', copied: 'コピーしました', get: 'アプリをダウンロード', open: 'アプリがある方 — アプリで登録',
    steps: ['ナスアプリをインストール', '会員登録の最後の「紹介者」に上のニックネームを入力', '登録すると招待した友だちに +200 QTA'],
    gone: 'この招待リンクは無効です', lang: 'ja',
  },
  ph: {
    title: (n) => `${n} invited you to Eggplant`, desc: 'Buy and sell anonymously and safely',
    ref: 'Referrer', copy: 'Copy', copied: 'Copied', get: 'Get the Eggplant app', open: 'Have the app? Sign up in Eggplant',
    steps: ['Install the Eggplant app', 'Enter the nickname above in the last "Referrer" field when signing up', 'Your friend gets +200 QTA when you join'],
    gone: 'This invite link is invalid', lang: 'en',
  },
};

app.get('/:nick', async (c) => {
  const nick = c.req.param('nick');
  const row = await c.env.DB
    .prepare('SELECT nickname, market FROM users WHERE nickname = ?')
    .bind(nick)
    .first<{ nickname: string; market: string | null }>();

  const market: Market = normalizeMarket(row?.market) ?? 'kr';
  const t = TEXT[market];
  const deepLink = `eggplant://app/register?ref=${encodeURIComponent(row?.nickname ?? '')}`;
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
  .card{background:#fff;border-radius:16px;padding:28px 16px;text-align:center;box-shadow:0 2px 12px rgba(80,20,120,.08)}
  .ph{font-size:64px}
  h1{font-size:20px;margin:10px 0 6px;word-break:break-all}
  .sub{margin:0;color:#6B5B7B;font-size:14px}
  .ref{display:flex;align-items:center;gap:8px;margin-top:18px;background:#F3E8FF;border-radius:12px;padding:12px 14px;text-align:left}
  .ref small{display:block;color:#6B5B7B;font-size:12px}
  .ref b{display:block;font-size:18px;word-break:break-all}
  .ref button{margin-left:auto;flex:none;border:0;border-radius:10px;background:#7C3AED;color:#fff;font-weight:800;padding:10px 14px;font-size:14px}
  ol{text-align:left;margin:16px 0 0;padding-left:22px;color:#3B2A4F;font-size:14px;line-height:1.7}
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
    ${row ? `<p class="sub">${esc(t.desc)}</p>
    <div class="ref"><div><small>${esc(t.ref)}</small><b id="nick">${esc(row.nickname)}</b></div><button type="button" id="cp">${esc(t.copy)}</button></div>
    <ol>${t.steps.map((s) => `<li>${esc(s)}</li>`).join('')}</ol>` : ''}
  </div>
  <a class="btn primary" href="${esc(getUrl)}">${esc(t.get)}</a>
  ${row ? `<a class="btn ghost" href="${esc(deepLink)}">${esc(t.open)}</a>` : ''}
</div>
${row ? `<script>
document.getElementById('cp').addEventListener('click', function () {
  var b = this, n = document.getElementById('nick').textContent;
  var done = function () { b.textContent = ${JSON.stringify(t.copied)}; };
  if (navigator.clipboard) navigator.clipboard.writeText(n).then(done, done); else done();
});
</script>` : ''}
</body>
</html>`;
  return c.html(html, row ? 200 : 404, { 'Cache-Control': 'public, max-age=300' });
});

export default app;
