/**
 * Agora Token Builder (RTC + RTM, v007 공식 패키지)
 * ============================================
 *
 * v1.0.154 (2026-05-11): 공식 agora-token 패키지 도입.
 *   - 자체 v006 구현(buildV006Rtc) 폐기.
 *   - Mark Orcena (Agora.io) 권고 — github.com/AgoraIO/Tools 공식 알고리즘 사용.
 *   - v006 → v007 토큰 업그레이드 (Agora Console 이 발급하는 형식과 동일).
 *   - Cloudflare Workers nodejs_compat flag 활성화 상태에서 작동.
 *
 * 사장님 룰:
 *   - "퀀타리움 지갑주소 = Universal User ID"
 *   - App Certificate 는 Cloudflare Workers Secret 에 보관, 절대 노출 X.
 *   - 클라이언트는 이 토큰을 받아서 Agora SDK 의 login/joinChannel 에 전달한다.
 *
 *  - 형식: "007" + base64(zlib.deflate(signature + appId + issueTs + expire + salt + services))
 *  - signature = HMAC-SHA256(appCertificate, signing_info)
 *  - 공식 npm 패키지 'agora-token' v2.0.5 사용.
 *
 * 참고: https://github.com/AgoraIO/Tools/tree/master/DynamicKey/AgoraDynamicKey/nodejs
 */

// @ts-ignore — agora-token 패키지에 types 매핑은 있지만 namespace 형태라 TS strict 에서 경고 가능
import { RtcTokenBuilder, RtmTokenBuilder, RtcRole as PkgRtcRole } from 'agora-token';

// ─────────────────────────────────────────────────────────
// RTC 권한 enum (Public API 호환을 위해 유지)
// ─────────────────────────────────────────────────────────

export const RtcRole = {
  PUBLISHER: 1, // 음성/영상 송수신 가능 (1:1 통화에서 양쪽 모두 publisher)
  SUBSCRIBER: 2, // 수신만 (live broadcast 청취자용)
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

/**
 * Agora 공식 v007 dynamic key (RTC 또는 RTM).
 *
 * 공식 패키지 'agora-token' v2.0.5 의 RtcTokenBuilder / RtmTokenBuilder 사용.
 * 토큰 prefix 는 "007" (Agora Console Temp Token 과 동일 형식).
 */
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

  // 공식 패키지 API 는 "남은 시간(seconds)" 을 받는다 — epoch 절대시각 X.
  // expireAt(epoch sec) → tokenExpire(remaining sec) 로 변환.
  const nowSec = Math.floor(Date.now() / 1000);
  const remainingSec = Math.max(60, p.expireAt - nowSec); // 최소 60초 보장

  if (p.kind === 'rtc') {
    if (!p.channel) throw new Error('RTC token requires channel');
    const role = p.role ?? RtcRole.PUBLISHER;
    // RtcTokenBuilder.buildTokenWithUid(appId, appCert, channelName, uid,
    //   role, tokenExpire, privilegeExpire)
    //   - tokenExpire: 토큰 만료 (재인증 시점)
    //   - privilegeExpire: 권한 만료 (보통 tokenExpire 와 동일)
    const token: string = RtcTokenBuilder.buildTokenWithUid(
      p.appId,
      p.appCertificate,
      p.channel,
      p.uid,
      role,
      remainingSec,
      remainingSec,
    );
    return token;
  } else {
    // RTM 은 채널이 필요 없고 uid 가 곧 account 가 된다.
    // RtmTokenBuilder.buildToken(appId, appCert, userId, expire)
    const token: string = RtmTokenBuilder.buildToken(
      p.appId,
      p.appCertificate,
      String(p.uid),
      remainingSec,
    );
    return token;
  }
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

  const enc = new TextEncoder();
  const hash = await crypto.subtle.digest('SHA-256', enc.encode(s));
  const bytes = new Uint8Array(hash);
  const uid =
    ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) >>> 0;
  return uid === 0 ? 1 : uid;
}
