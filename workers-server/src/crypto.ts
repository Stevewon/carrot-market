/**
 * Password hashing utilities (PBKDF2-SHA256, Web Crypto - runs on Workers).
 *
 * Format: `pbkdf2$<iterations>$<saltB64>$<hashB64>`
 * Everything we need for verification lives in the stored string itself, so
 * we can rotate iterations later without a migration.
 */

const ITERATIONS = 150_000;
const HASH_BITS = 256;
const SALT_BYTES = 16;

function bytesToB64(bytes: Uint8Array): string {
  // btoa wants a binary string
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function pbkdf2(
  password: string,
  salt: Uint8Array,
  iterations: number,
  bits: number,
): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    { name: 'PBKDF2' },
    false,
    ['deriveBits'],
  );
  const buf = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations, hash: 'SHA-256' },
    key,
    bits,
  );
  return new Uint8Array(buf);
}

/** Derive a storable password hash string from a plaintext password. */
export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(SALT_BYTES));
  const hash = await pbkdf2(password, salt, ITERATIONS, HASH_BITS);
  return `pbkdf2$${ITERATIONS}$${bytesToB64(salt)}$${bytesToB64(hash)}`;
}

/** Constant-time comparison of two Uint8Arrays. */
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/** Verify a plaintext password against a stored hash string. */
export async function verifyPassword(
  password: string,
  stored: string,
): Promise<boolean> {
  if (!stored) return false;
  const parts = stored.split('$');
  if (parts.length !== 4 || parts[0] !== 'pbkdf2') return false;
  const iterations = parseInt(parts[1], 10);
  if (!Number.isFinite(iterations) || iterations < 1000) return false;
  const salt = b64ToBytes(parts[2]);
  const expected = b64ToBytes(parts[3]);
  const actual = await pbkdf2(password, salt, iterations, expected.length * 8);
  return timingSafeEqual(actual, expected);
}

/**
 * Validate a Quantarium wallet address.
 * Format: "0x" + 40 hex chars (e.g. 0xE0c166B147a742E4FbCf5e5BCf73aCA631f14f0e)
 * — same as Ethereum / EVM addresses.
 */
export function isValidWallet(raw: string): boolean {
  const s = (raw || '').trim();
  return /^0x[a-fA-F0-9]{40}$/.test(s);
}

/**
 * Normalize a wallet address for storage + lookup.
 * - trim whitespace
 * - force "0x" prefix to lowercase
 * - KEEP the 40-char body as the user typed it (so the checksum capitalization
 *   is preserved on display). We match case-insensitively in SQL via
 *   `COLLATE NOCASE`, so this is safe.
 */
export function normalizeWallet(raw: string): string {
  const s = (raw || '').trim();
  if (s.length >= 2 && s.slice(0, 2).toLowerCase() === '0x') {
    return '0x' + s.slice(2);
  }
  return s;
}
