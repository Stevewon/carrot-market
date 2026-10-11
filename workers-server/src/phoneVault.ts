/**
 * 휴대폰 번호 암호화 보관 (불법 사용자 추적 전용).
 *
 *   wrangler secret put PHONE_ENC_KEY   # 32바이트 base64 (openssl rand -base64 32)
 *
 * - 저장: AES-256-GCM, 'v1:' + base64(iv 12바이트 || 암호문+태그)
 * - 중복 확인용 해시: HMAC-SHA256(키에서 파생). 번호 공간이 작아 그냥 SHA-256 이면
 *   DB 만 유출돼도 몇 분이면 번호를 되돌릴 수 있다. 키 없이는 못 되돌린다.
 * - 키가 없으면 휴대폰 인증 자체를 막는다 (평문 저장·추적 불가 상태로 진행하지 않음).
 * - 키를 바꾸면 기존 암호문/해시를 읽을 수 없으니 절대 교체·분실하지 말 것.
 */
import type { Env } from './types';

/** 한국 휴대폰 번호 (+82 10/11/16~19) 만. */
export function isKoreanMobile(e164: string): boolean {
  return /^\+821[016789]\d{7,8}$/.test(e164);
}

function b64(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function unb64(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

let cached: { raw: string; aes: CryptoKey; hmac: CryptoKey } | null = null;

async function keys(env: Env): Promise<{ aes: CryptoKey; hmac: CryptoKey } | null> {
  const raw = (env.PHONE_ENC_KEY || '').trim();
  if (!raw) return null;
  if (cached?.raw === raw) return cached;
  const master = unb64(raw);
  if (master.length !== 32) throw new Error('PHONE_ENC_KEY must be 32 bytes (base64)');
  const base = await crypto.subtle.importKey('raw', master, 'HKDF', false, ['deriveKey']);
  const derive = (info: string, alg: Parameters<typeof crypto.subtle.deriveKey>[2], usages: string[]) =>
    crypto.subtle.deriveKey(
      { name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info: new TextEncoder().encode(info) },
      base,
      alg,
      false,
      usages,
    );
  const aes = await derive('eggplant-phone-enc-v1', { name: 'AES-GCM', length: 256 }, ['encrypt', 'decrypt']);
  const hmac = await derive('eggplant-phone-hash-v1', { name: 'HMAC', hash: 'SHA-256', length: 256 }, ['sign']);
  cached = { raw, aes, hmac };
  return cached;
}

export async function phoneVaultReady(env: Env): Promise<boolean> {
  try {
    return (await keys(env)) !== null;
  } catch (e) {
    console.error('[phoneVault] bad key', e);
    return false;
  }
}

export async function phoneHash(env: Env, e164: string): Promise<string> {
  const k = await keys(env);
  if (!k) throw new Error('PHONE_ENC_KEY missing');
  const sig = await crypto.subtle.sign('HMAC', k.hmac, new TextEncoder().encode(`phone:${e164}`));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function encryptPhone(env: Env, e164: string): Promise<string> {
  const k = await keys(env);
  if (!k) throw new Error('PHONE_ENC_KEY missing');
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, k.aes, new TextEncoder().encode(e164)));
  const out = new Uint8Array(iv.length + ct.length);
  out.set(iv);
  out.set(ct, iv.length);
  return `v1:${b64(out)}`;
}

export async function decryptPhone(env: Env, enc: string): Promise<string> {
  const k = await keys(env);
  if (!k) throw new Error('PHONE_ENC_KEY missing');
  if (!enc.startsWith('v1:')) throw new Error('unknown phone_enc version');
  const buf = unb64(enc.slice(3));
  const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: buf.slice(0, 12) }, k.aes, buf.slice(12));
  return new TextDecoder().decode(pt);
}
