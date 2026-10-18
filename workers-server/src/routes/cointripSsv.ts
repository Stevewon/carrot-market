/**
 * AdMob 보상형 광고 서버 확인 (SSV) 콜백 — GET /api/cointrip-ssv?...&signature=...&key_id=...
 *
 * 블랙코인 꽝에서 광고를 끝까지 보면 구글이 이 주소를 부른다. 서명이 맞으면 그 꽝(custom_data)을
 * "광고 봄"으로 정리한다. AdMob 콘솔의 보상형 광고 단위 → "서버 측 확인" 에 이 주소를 넣고,
 * 어드민 코인트립 설정의 광고 확인 방식을 ssv 로 바꾸면 앱이 보내는 신호 대신 이것만 인정한다.
 * 로그인 없이 구글이 부르므로 authMiddleware 를 거치지 않는다.
 */
import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { markAdWatched } from './cointrip';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

const KEYS_URL = 'https://www.gstatic.com/admob/reward/verifier-keys.json';

function b64ToBytes(s: string): Uint8Array {
  const b = atob(s.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(s.length / 4) * 4, '='));
  return Uint8Array.from(b, (ch) => ch.charCodeAt(0));
}

/** DER ECDSA 서명 → WebCrypto 가 받는 r||s (각 32바이트). */
function derToRaw(der: Uint8Array): Uint8Array {
  let i = 2;
  if (der[1] & 0x80) i += der[1] & 0x7f;
  const read = () => {
    if (der[i] !== 0x02) throw new Error('bad der');
    const len = der[i + 1];
    let v = der.slice(i + 2, i + 2 + len);
    i += 2 + len;
    while (v.length > 32 && v[0] === 0) v = v.slice(1);
    const out = new Uint8Array(32);
    out.set(v, 32 - v.length);
    return out;
  };
  const r = read();
  const s = read();
  const raw = new Uint8Array(64);
  raw.set(r, 0);
  raw.set(s, 32);
  return raw;
}

async function verify(query: string, keyId: string, signature: string): Promise<boolean> {
  const res = await fetch(KEYS_URL, { cf: { cacheTtl: 3600, cacheEverything: true } } as RequestInit);
  if (!res.ok) return false;
  const j = (await res.json()) as { keys?: { keyId: number | string; base64: string }[] };
  const k = (j.keys || []).find((x) => String(x.keyId) === keyId);
  if (!k) return false;
  const key = await crypto.subtle.importKey('spki', b64ToBytes(k.base64), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
  return crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    derToRaw(b64ToBytes(signature)),
    new TextEncoder().encode(query),
  );
}

app.get('/', async (c) => {
  const url = new URL(c.req.url);
  const raw = url.search.slice(1);
  const at = raw.indexOf('&signature=');
  const signature = url.searchParams.get('signature') || '';
  const keyId = url.searchParams.get('key_id') || '';
  // 구글이 처음 주소를 등록할 때 서명 없이 한 번 부른다 → 200.
  if (at < 0 || !signature) return c.text('ok');
  let ok = false;
  try {
    ok = await verify(raw.slice(0, at), keyId, signature);
  } catch (e) {
    console.error('[ssv] verify failed', e);
  }
  if (!ok) return c.text('bad signature', 400);
  const penaltyId = url.searchParams.get('custom_data') || '';
  const userId = url.searchParams.get('user_id') || '';
  if (penaltyId && userId) await markAdWatched(c.env, userId, penaltyId);
  return c.text('ok');
});

export default app;
