#!/usr/bin/env node
/**
 * 어드민 비밀번호 해시 생성기 (PBKDF2-SHA256, 100k iterations)
 *
 * 사용법:
 *   node workers-server/scripts/hash.mjs "비밀번호"
 *
 * 출력 형식 (workers-server/src/crypto.ts 와 동일):
 *   pbkdf2$100000$<saltB64>$<hashB64>
 *
 * 위 출력 문자열을 D1 콘솔에서 admins.password_hash 컬럼에 INSERT.
 */

import { webcrypto } from 'node:crypto';

const ITERATIONS = 100_000;
const HASH_BITS = 256;
const SALT_BYTES = 16;

function bytesToB64(bytes) {
  return Buffer.from(bytes).toString('base64');
}

async function pbkdf2(password, salt, iterations, bits) {
  const key = await webcrypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    { name: 'PBKDF2' },
    false,
    ['deriveBits'],
  );
  const buf = await webcrypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations, hash: 'SHA-256' },
    key,
    bits,
  );
  return new Uint8Array(buf);
}

async function main() {
  const pw = process.argv[2];
  if (!pw) {
    console.error('Usage: node hash.mjs "<password>"');
    process.exit(1);
  }
  if (pw.length < 8 || pw.length > 64) {
    console.error('Password must be 8-64 characters');
    process.exit(1);
  }
  const salt = webcrypto.getRandomValues(new Uint8Array(SALT_BYTES));
  const hash = await pbkdf2(pw, salt, ITERATIONS, HASH_BITS);
  const stored = `pbkdf2$${ITERATIONS}$${bytesToB64(salt)}$${bytesToB64(hash)}`;
  console.log(stored);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
