import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { normalizeMarket, type Market } from '../market';
import { loadSettings } from '../cointrip';

/**
 * GET /c/:code — 코인트립 친구 연합 초대 링크의 웹 페이지 (친구 연합 → "연합 초대 링크 보내기").
 *  - 앱이 있으면 "가지 앱에서 연합 들어가기" → eggplant://app/cointrip/union?code=<코드> (코드가 채워진다).
 *  - 아직 가입 전이면 → eggplant://app/register?ref=<연합장 닉네임> (연합장이 친구 초대 보너스도 받는다).
 *  - 앱이 없으면 eggplant.life 에서 받기.
 *  연합 이름 · 연합장 닉네임 · 인원 말고는 내보내지 않는다.
 */
const app = new Hono<{ Bindings: Env; Variables: Variables }>();

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]!);

const TEXT: Record<Market, {
  title: (u: string) => string; by: (n: string) => string; members: (n: number, max: number) => string; desc: string;
  code: string; join: string; register: string; get: string; full: string; gone: string; lang: string;
}> = {
  kr: {
    title: (u) => `'${u}' 연합에 초대됐어요`, by: (n) => `연합장 ${n}`, members: (n, m) => `연합원 ${n}/${m}명`,
    desc: '코인트립에서 연합원 누가 코인을 주워도 함께 나눠 받아요',
    code: '초대 코드', join: '가지 앱에서 연합 들어가기', register: '아직 가입 전이면 — 가입하기', get: '가지 앱 받기',
    full: '연합 인원이 다 찼어요', gone: '없는 연합 초대 링크예요', lang: 'ko',
  },
  jp: {
    title: (u) => `「${u}」連合に招待されました`, by: (n) => `連合長 ${n}`, members: (n, m) => `メンバー ${n}/${m}人`,
    desc: 'コイントリップで連合の誰がコインを拾っても一緒に分け合えます',
    code: '招待コード', join: 'アプリで連合に参加', register: 'まだ登録していない方 — 会員登録', get: 'アプリをダウンロード',
    full: '連合の人数がいっぱいです', gone: 'この連合招待リンクは無効です', lang: 'ja',
  },
  ph: {
    title: (u) => `You're invited to the '${u}' union`, by: (n) => `Leader ${n}`, members: (n, m) => `Members ${n}/${m}`,
    desc: 'In CoinTrip, whenever anyone in the union picks up a coin, everyone shares it',
    code: 'Invite code', join: 'Join the union in Eggplant', register: 'Not signed up yet? Sign up', get: 'Get the Eggplant app',
    full: 'This union is full', gone: 'This union invite link is invalid', lang: 'en',
  },
};

app.get('/:code', async (c) => {
  const code = c.req.param('code').toUpperCase();
  const row = await c.env.DB
    .prepare(
      `SELECT u.name, u.code, o.nickname AS owner, o.market,
              (SELECT COUNT(*) FROM ct_union_members m WHERE m.union_id = u.id) AS n
         FROM ct_unions u LEFT JOIN users o ON o.id = u.owner_id
        WHERE u.code = ?`,
    )
    .bind(code)
    .first<{ name: string; code: string; owner: string | null; market: string | null; n: number }>();
  const s = await loadSettings(c.env);

  const market: Market = normalizeMarket(row?.market) ?? 'kr';
  const t = TEXT[market];
  const title = row ? t.title(row.name) : t.gone;
  const full = !!row && row.n >= s.unionMax;
  const joinLink = `eggplant://app/cointrip/union?code=${encodeURIComponent(row?.code ?? '')}`;
  const regLink = `eggplant://app/register?ref=${encodeURIComponent(row?.owner ?? '')}`;
  const getUrl = 'https://eggplant.life/#download';

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
  .sub{margin:4px 0 0;color:#6B5B7B;font-size:14px;line-height:1.5}
  .code{margin-top:18px;background:#F3E8FF;border-radius:12px;padding:12px 14px}
  .code small{display:block;color:#6B5B7B;font-size:12px}
  .code b{display:block;font-size:24px;letter-spacing:3px}
  .warn{margin-top:14px;color:#DC2626;font-weight:800}
  .btn{display:block;text-align:center;text-decoration:none;font-weight:800;border-radius:12px;padding:14px;margin-top:12px}
  .primary{background:#7C3AED;color:#fff}
  .ghost{background:#fff;color:#7C3AED;border:1.5px solid #7C3AED}
</style>
</head>
<body>
<div class="wrap">
  <div class="card">
    <div class="ph">🪙</div>
    <h1>${esc(title)}</h1>
    ${row ? `<p class="sub">${esc(row.owner ? t.by(row.owner) + ' · ' : '')}${esc(t.members(row.n, s.unionMax))}</p>
    <p class="sub">${esc(t.desc)}</p>
    <div class="code"><small>${esc(t.code)}</small><b>${esc(row.code)}</b></div>
    ${full ? `<p class="warn">${esc(t.full)}</p>` : ''}` : ''}
  </div>
  ${row && !full ? `<a class="btn primary" href="${esc(joinLink)}">${esc(t.join)}</a>` : ''}
  ${row && !full && row.owner ? `<a class="btn ghost" href="${esc(regLink)}">${esc(t.register)}</a>` : ''}
  <a class="btn ghost" href="${esc(getUrl)}">${esc(t.get)}</a>
</div>
</body>
</html>`;
  return c.html(html, row ? 200 : 404, { 'Cache-Control': 'public, max-age=60' });
});

export default app;
