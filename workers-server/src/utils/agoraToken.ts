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
  // ★ v1.0.153 root-cause fix:
  //   Agora 공식 v006 RTC 토큰의 content 레이아웃은
  //     signature(32) + crc_channel(4 LE) + crc_uid(4 LE) + msg_len(2 LE) + message
  //   기존 코드는 CRC32 + msg_len 을 누락하고 signature + message 만 base64 인코딩 →
  //   Agora 서버가 토큰 파싱 실패 → ConnectionChangedReasonType.connectionChangedInvalidToken
  //   거부. v1.0.151 진단 토스트로 양쪽 모두 발생한 증상의 진짜 root cause.
  return buildV006Rtc({
    appId: p.appId,
    appCertificate: p.appCertificate,
    channelName: p.channelName,
    uidStr: String(p.uid),
    salt: randomU32(),
    ts: nowSec(),
    privileges,
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
  // RTM 토큰은 channelName 자리에 빈 문자열, uid 자리에 userAccount 사용.
  // (Agora 공식 RtmTokenBuilder 도 RtcTokenBuilder 와 같은 v006 packer 를 공유함)
  return buildV006Rtc({
    appId: p.appId,
    appCertificate: p.appCertificate,
    channelName: '',
    uidStr: p.userAccount,
    salt: randomU32(),
    ts: nowSec(),
    privileges,
  });
}

// ─────────────────────────────────────────────────────────
// v006 RTC/RTM packer (Agora 공식 알고리즘)
// ─────────────────────────────────────────────────────────
// 정확한 byte layout (Agora 공식 SDK Python/Node/Go 동일):
//
// [message] (HMAC-SHA256 서명 대상)
//   salt(u32LE 4B) + ts(u32LE 4B) + privCount(u16LE 2B)
//   + (privKey(u16LE 2B) + privVal(u32LE 4B)) * N
//   + channelName_utf8_bytes
//   + uidStr_utf8_bytes
//
// [content] (base64 인코딩 대상)
//   signature(32B) + crc_channel(u32LE 4B) + crc_uid(u32LE 4B)
//   + msgLen(u16LE 2B) + message
//
// [최종 토큰 문자열]
//   "006" + appId(32 hex chars) + base64(content)

async function buildV006Rtc(p: {
  appId: string;
  appCertificate: string;
  channelName: string;
  uidStr: string;
  salt: number;
  ts: number;
  privileges: Map<number, number>;
}): Promise<string> {
  const channelBytes = strToBytes(p.channelName);
  const uidBytes = strToBytes(p.uidStr);

  // 1) message = salt + ts + privCount + (key+val)*N + channelName + uidStr
  const msgParts: Uint8Array[] = [];
  msgParts.push(u32LE(p.salt));
  msgParts.push(u32LE(p.ts));
  msgParts.push(u16LE(p.privileges.size));
  for (const [k, v] of p.privileges.entries()) {
    msgParts.push(u16LE(k));
    msgParts.push(u32LE(v));
  }
  msgParts.push(channelBytes);
  msgParts.push(uidBytes);
  const message = bytesConcat(...msgParts);

  // 2) signature = HMAC-SHA256(appCertificate_bytes, message)
  const signature = await hmacSha256(strToBytes(p.appCertificate), message);

  // 3) CRC32 of channelName & uidStr (Agora 공식 사양)
  const crcChannel = crc32(channelBytes);
  const crcUid = crc32(uidBytes);

  // 4) content = signature(32) + crc_channel(4 LE) + crc_uid(4 LE) + msgLen(2 LE) + message
  const content = bytesConcat(
    signature,
    u32LE(crcChannel),
    u32LE(crcUid),
    u16LE(message.length),
    message,
  );
  const b64 = base64Encode(content);

  // 5) 최종 = "006" + appId + base64(content)
  return `006${p.appId}${b64}`;
}

// ─────────────────────────────────────────────────────────
// CRC32 (IEEE 802.3 polynomial 0xEDB88320, Agora 공식 SDK 와 동일)
// ─────────────────────────────────────────────────────────
// Agora Python SDK / Node SDK 모두 zlib.crc32 사용 → 결과값을 unsigned 32-bit
// little-endian 으로 직렬화. 우리는 zlib 의존 없이 Workers 에서 동작하도록
// table 기반 계산 + (>>> 0) 로 unsigned 보장.

let _crc32Table: Uint32Array | null = null;

function getCrc32Table(): Uint32Array {
  if (_crc32Table) return _crc32Table;
  const table = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    }
    table[i] = c >>> 0;
  }
  _crc32Table = table;
  return table;
}

function crc32(bytes: Uint8Array): number {
  const table = getCrc32Table();
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) {
    crc = (table[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8)) >>> 0;
  }
  return (crc ^ 0xffffffff) >>> 0;
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
