/**
 * 2단계 휴대폰 인증 — Firebase 휴대폰 문자 인증 ID 토큰 검증.
 *
 * 앱이 Firebase Auth 로 문자 인증을 마치면 받은 ID 토큰을 서버로 보낸다.
 * 서버는 Google 공개키로 서명을 확인하고 phone_number 클레임을 꺼낸다.
 * 전화번호 평문은 저장하지 않고 해시만 쓴다.
 */

import type { Env } from './types';

const DEFAULT_PROJECT = 'eggplant-app-4cd70';
const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

interface Jwk { kid: string; n: string; e: string; kty: string; alg?: string }
let jwksCache: { keys: Jwk[]; until: number } | null = null;

async function getJwks(force = false): Promise<Jwk[]> {
  if (!force && jwksCache && jwksCache.until > Date.now()) return jwksCache.keys;
  const res = await fetch(JWKS_URL);
  if (!res.ok) throw new Error(`jwks ${res.status}`);
  const j = (await res.json()) as { keys: Jwk[] };
  const m = /max-age=(\d+)/.exec(res.headers.get('cache-control') || '');
  jwksCache = { keys: j.keys || [], until: Date.now() + Math.min(Number(m?.[1] || 3600), 21600) * 1000 };
  return jwksCache.keys;
}

function b64urlBytes(s: string): Uint8Array {
  const b = atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4));
  return Uint8Array.from(b, (ch) => ch.charCodeAt(0));
}

export type PhoneTokenResult =
  | { ok: true; phone: string; uid: string }
  | { ok: false; reason: string };

export async function verifyFirebasePhoneToken(env: Env, idToken: string): Promise<PhoneTokenResult> {
  const project = (env.FIREBASE_PROJECT_ID || DEFAULT_PROJECT).trim();
  const parts = String(idToken || '').split('.');
  if (parts.length !== 3) return { ok: false, reason: 'malformed' };
  let header: { alg?: string; kid?: string };
  let claims: Record<string, unknown>;
  try {
    header = JSON.parse(new TextDecoder().decode(b64urlBytes(parts[0])));
    claims = JSON.parse(new TextDecoder().decode(b64urlBytes(parts[1])));
  } catch {
    return { ok: false, reason: 'malformed' };
  }
  if (header.alg !== 'RS256' || !header.kid) return { ok: false, reason: 'bad_alg' };

  let jwk = (await getJwks()).find((k) => k.kid === header.kid);
  if (!jwk) jwk = (await getJwks(true)).find((k) => k.kid === header.kid);
  if (!jwk) return { ok: false, reason: 'unknown_kid' };
  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    b64urlBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!valid) return { ok: false, reason: 'bad_signature' };

  const now = Math.floor(Date.now() / 1000);
  if (claims.aud !== project) return { ok: false, reason: 'bad_aud' };
  if (claims.iss !== `https://securetoken.google.com/${project}`) return { ok: false, reason: 'bad_iss' };
  if (typeof claims.exp !== 'number' || claims.exp < now) return { ok: false, reason: 'expired' };
  if (typeof claims.iat !== 'number' || claims.iat > now + 300) return { ok: false, reason: 'bad_iat' };
  // 문자 인증 직후 받은 토큰만 (오래된 로그인 세션 토큰 재사용 차단).
  if (typeof claims.auth_time !== 'number' || claims.auth_time < now - 600) return { ok: false, reason: 'stale_auth' };
  const phone = typeof claims.phone_number === 'string' ? claims.phone_number : '';
  if (!/^\+\d{8,15}$/.test(phone)) return { ok: false, reason: 'no_phone' };
  const uid = typeof claims.sub === 'string' ? claims.sub : '';
  if (!uid) return { ok: false, reason: 'no_sub' };
  return { ok: true, phone, uid };
}
