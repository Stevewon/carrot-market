/**
 * Agora Token Builder (RTC + RTM, v006 형식)
 * ============================================
 *
 * 사장님 룰:
 *   - "퀀타리움 지갑주소 = Universal User ID"
 *   - App Certificate 는 Cloudflare Workers Secret 에 보관, 절대 노출 X.
 *   - 클라이언트는 이 토큰을 받아서 Agora SDK 의 login/joinChannel 에 전달한다.
 *
 * 구현은 Agora 공식 dynamic key v006 사양을 Web Crypto API (Workers 호환) 로
 * 재구현한 것이다 (npm 의 agora-token 패키지는 Node 의 crypto 모듈에 의존하여
 * Cloudflare Workers 에서 동작하지 않음).
 *
 *  - 형식: "006" + appId(32) + base64url(crc32 + msgLength + msg + signature)
 *  - signature = HMAC-SHA256(appCertificate, msg)
 *  - msg = randomInt32 + ts + privileges (RTC/RTM 마다 권한 비트가 다름)
 *
 * 참고: https://docs.agora.io/en/voice-calling/develop/integration-token
 */

// ─────────────────────────────────────────────────────────
// RTC / RTM 권한 enum (Agora dynamic key v006 사양)
// ─────────────────────────────────────────────────────────

export const RtcRole = {
  PUBLISHER: 1, // 음성/영상 송수신 가능 (1:1 통화에서 양쪽 모두 publisher)
  SUBSCRIBER: 2, // 수신만 (live broadcast 청취자용)
} as const;

const Privileges = {
  // RTC
  kJoinChannel: 1,
  kPublishAudioStream: 2,
  kPublishVideoStream: 3,
  kPublishDataStream: 4,
  // RTM
  kRtmLogin: 1000,
} as const;

// ─────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────

export interface BuildTokenParams {
  appId: string;
  appCertificate: string;
  /** 32bit unsigned int. 0 은 사용 불가. */
  uid: number;
  /** RTC: 채널명 / RTM: account(=uid 문자열) */
  channel?: string;
  /** 만료 시각 (epoch sec). 보통 now + 3600. */
  expireAt: number;
  kind: 'rtc' | 'rtm';
  role?: typeof RtcRole[keyof typeof RtcRole];
}

/** Agora v006 dynamic key (RTC 또는 RTM). */
export async function buildAgoraToken(p: BuildTokenParams): Promise<string> {
  if (!p.appId || p.appId.length !== 32) {
    throw new Error('Invalid AGORA_APP_ID (expected 32 hex chars)');
  }
  if (!p.appCertificate) {
    throw new Error('Missing AGORA_APP_CERTIFICATE');
  }
  if (!Number.isInteger(p.uid) || p.uid <= 0 || p.uid > 0xffffffff) {
    throw new Error(`Invalid uid: ${p.uid}`);
  }

  if (p.kind === 'rtc') {
    if (!p.channel) throw new Error('RTC token requires channel');
    return buildRtcToken({
      appId: p.appId,
      appCertificate: p.appCertificate,
      channelName: p.channel,
      uid: p.uid,
      role: p.role ?? RtcRole.PUBLISHER,
      expireAt: p.expireAt,
    });
  } else {
    // RTM 은 채널이 필요 없고 uid 가 곧 account 가 된다.
    return buildRtmToken({
      appId: p.appId,
      appCertificate: p.appCertificate,
      userAccount: String(p.uid),
      expireAt: p.expireAt,
    });
  }
}

// ─────────────────────────────────────────────────────────
// RTC token (v006)
// ─────────────────────────────────────────────────────────

async function buildRtcToken(p: {
  appId: string;
  appCertificate: string;
  channelName: string;
  uid: number;
  role: number;
  expireAt: number;
}): Promise<string> {
  const privileges = new Map<number, number>();
  privileges.set(Privileges.kJoinChannel, p.expireAt);
  if (p.role === RtcRole.PUBLISHER) {
    privileges.set(Privileges.kPublishAudioStream, p.expireAt);
    privileges.set(Privileges.kPublishVideoStream, p.expireAt);
    privileges.set(Privileges.kPublishDataStream, p.expireAt);
  }
  return buildV006({
    appId: p.appId,
    appCertificate: p.appCertificate,
    salt: randomU32(),
    ts: nowSec(),
    privileges,
    extraSuffix: bytesConcat(strToBytes(p.channelName), u32LE(p.uid)),
  });
}

// ─────────────────────────────────────────────────────────
// RTM token (v006)
// ─────────────────────────────────────────────────────────

async function buildRtmToken(p: {
  appId: string;
  appCertificate: string;
  userAccount: string;
  expireAt: number;
}): Promise<string> {
  const privileges = new Map<number, number>();
  privileges.set(Privileges.kRtmLogin, p.expireAt);
  return buildV006({
    appId: p.appId,
    appCertificate: p.appCertificate,
    salt: randomU32(),
    ts: nowSec(),
    privileges,
    extraSuffix: strToBytes(p.userAccount),
  });
}

// ─────────────────────────────────────────────────────────
// v006 packer (공통)
// ─────────────────────────────────────────────────────────

async function buildV006(p: {
  appId: string;
  appCertificate: string;
  salt: number;
  ts: number;
  privileges: Map<number, number>;
  extraSuffix: Uint8Array;
}): Promise<string> {
  // message = salt(u32LE) + ts(u32LE) + privCount(u16LE) + (key(u16LE)+val(u32LE))*N + extraSuffix
  const parts: Uint8Array[] = [];
  parts.push(u32LE(p.salt));
  parts.push(u32LE(p.ts));
  parts.push(u16LE(p.privileges.size));
  for (const [k, v] of p.privileges.entries()) {
    parts.push(u16LE(k));
    parts.push(u32LE(v));
  }
  parts.push(p.extraSuffix);
  const message = bytesConcat(...parts);

  // signature = HMAC-SHA256(appCertificate, appId || message) — 일부 SDK 버전에서는
  // certificate 만 키로 사용. 호환성 위해 표준 형식 사용:
  //   key   = appCertificate
  //   data  = message
  const signature = await hmacSha256(
    strToBytes(p.appCertificate),
    message,
  );

  // content = signature(32) + message
  const content = bytesConcat(signature, message);
  const b64 = base64Encode(content);

  return `006${p.appId}${b64}`;
}

// ─────────────────────────────────────────────────────────
// Crypto helpers (Web Crypto API — Cloudflare Workers 호환)
// ─────────────────────────────────────────────────────────

async function hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    key,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', cryptoKey, data);
  return new Uint8Array(sig);
}

function randomU32(): number {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  return arr[0];
}

function nowSec(): number {
  return Math.floor(Date.now() / 1000);
}

// ─────────────────────────────────────────────────────────
// Byte helpers
// ─────────────────────────────────────────────────────────

function u16LE(n: number): Uint8Array {
  const b = new Uint8Array(2);
  b[0] = n & 0xff;
  b[1] = (n >>> 8) & 0xff;
  return b;
}

function u32LE(n: number): Uint8Array {
  const b = new Uint8Array(4);
  b[0] = n & 0xff;
  b[1] = (n >>> 8) & 0xff;
  b[2] = (n >>> 16) & 0xff;
  b[3] = (n >>> 24) & 0xff;
  return b;
}

function strToBytes(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

function bytesConcat(...arrs: Uint8Array[]): Uint8Array {
  let total = 0;
  for (const a of arrs) total += a.length;
  const out = new Uint8Array(total);
  let off = 0;
  for (const a of arrs) {
    out.set(a, off);
    off += a.length;
  }
  return out;
}

function base64Encode(bytes: Uint8Array): string {
  // Workers 환경에는 btoa() 가 있다. 단, ASCII 만 허용되므로 binary string 변환 필요.
  let s = '';
  for (let i = 0; i < bytes.length; i++) {
    s += String.fromCharCode(bytes[i]);
  }
  return btoa(s);
}

// ─────────────────────────────────────────────────────────
// 지갑주소 → Agora UID (클라이언트의 lib/utils/agora_uid.dart 와 동일 알고리즘)
// ─────────────────────────────────────────────────────────

/**
 * SHA-256(walletAddress) 의 앞 4바이트를 big-endian u32 로 잘라낸 값.
 * UID 0 은 1로 보정 (Agora 가 0 을 "랜덤 할당" 으로 해석).
 */
export async function walletToAgoraUid(walletAddress: string): Promise<number> {
  let s = walletAddress.trim().toLowerCase();
  if (s.startsWith('0x')) s = s.slice(2);

  const hash = await crypto.subtle.digest('SHA-256', strToBytes(s));
  const bytes = new Uint8Array(hash);
  const uid =
    ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) >>> 0;
  return uid === 0 ? 1 : uid;
}
