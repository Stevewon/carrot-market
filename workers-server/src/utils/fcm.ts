// ============================================================
// fcm.ts — Firebase Cloud Messaging HTTP v1 발송 유틸
// ============================================================
// 정책:
//   1) 사장님 결정 (c): Firebase 프로젝트 미생성 → placeholder 모드.
//      FCM_SERVICE_ACCOUNT_JSON / FCM_PROJECT_ID secret 미설정 시
//      silent skip (메시지 자체는 WebSocket 으로 정상 전달됨).
//
//   2) HTTP v1 API 사용 (legacy server key 는 2024-06 deprecate).
//      서비스 계정 JSON → JWT 서명 → access_token 발급 → FCM 호출.
//
//   3) 푸시 본문/이력은 D1 에 저장하지 않음 (0022 휘발성 정책).
//      access_token 도 5분 캐시만 (메모리 내), 디스크 저장 X.
//
//   4) 익명성 유지: 푸시 본문에 닉네임/메시지 본문 0자 포함.
//      "새 메시지 1개" 같은 generic 표시. tap → WebSocket 으로 본문 fetch.
// ============================================================

interface FcmServiceAccount {
  type: string;
  project_id: string;
  private_key_id: string;
  private_key: string;
  client_email: string;
  // ... 기타 필드는 사용하지 않음
}

// 메모리 캐시 (Workers 인스턴스 단위, 5분).
let _accessTokenCache: { token: string; expiresAt: number } | null = null;

/**
 * Service account JSON 으로 OAuth2 access_token 발급.
 * 5분 캐시. 만료 임박(60초 미만) 시 재발급.
 */
async function getAccessToken(serviceAccountJson: string): Promise<string | null> {
  const now = Math.floor(Date.now() / 1000);
  if (_accessTokenCache && _accessTokenCache.expiresAt - now > 60) {
    return _accessTokenCache.token;
  }

  let sa: FcmServiceAccount;
  try {
    sa = JSON.parse(serviceAccountJson) as FcmServiceAccount;
  } catch {
    console.warn('[fcm] FCM_SERVICE_ACCOUNT_JSON parse failed — push skipped');
    return null;
  }
  if (!sa.private_key || !sa.client_email) {
    console.warn('[fcm] service account missing private_key/client_email');
    return null;
  }

  // JWT 헤더/페이로드 빌드.
  const header = { alg: 'RS256', typ: 'JWT', kid: sa.private_key_id };
  const payload = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const enc = (obj: object) =>
    btoa(JSON.stringify(obj))
      .replace(/=/g, '')
      .replace(/\+/g, '-')
      .replace(/\//g, '_');
  const signingInput = `${enc(header)}.${enc(payload)}`;

  // RSA PKCS#8 키 import.
  const pemBody = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  let keyData: ArrayBuffer;
  try {
    const bin = atob(pemBody);
    const buf = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
    keyData = buf.buffer;
  } catch {
    console.warn('[fcm] private_key base64 decode failed');
    return null;
  }

  let cryptoKey: CryptoKey;
  try {
    cryptoKey = await crypto.subtle.importKey(
      'pkcs8',
      keyData,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign'],
    );
  } catch (e) {
    console.warn('[fcm] importKey failed:', e);
    return null;
  }

  const sigBuf = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );
  const sig = btoa(String.fromCharCode(...new Uint8Array(sigBuf)))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
  const jwt = `${signingInput}.${sig}`;

  // Token endpoint.
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    console.warn('[fcm] token endpoint failed:', res.status, await res.text());
    return null;
  }
  const data = (await res.json()) as { access_token?: string; expires_in?: number };
  if (!data.access_token) return null;

  _accessTokenCache = {
    token: data.access_token,
    expiresAt: now + (data.expires_in || 3600),
  };
  return data.access_token;
}

export interface FcmPushOptions {
  fcmToken: string;
  /** 알림 제목 (익명성: 닉네임/본문 노출 금지, generic 권장). */
  title: string;
  /** 알림 본문 (generic 권장. 예: "새 메시지가 도착했습니다"). */
  body: string;
  /** 앱 내 라우팅용 데이터 (e.g., room_id, type='message'|'call_invite'). */
  data?: Record<string, string>;
  /** 통화 invite 일 경우 high priority + CallKit 트리거. */
  isCall?: boolean;
}

/**
 * FCM 메시지 1건 발송.
 *
 * Firebase 키 미설정(placeholder 모드) → return false (silent).
 * 발송 성공 → return true.
 * 토큰 invalid (404 등) → 호출자가 fcm_token 컬럼 NULL 처리 권장.
 */
export async function sendFcm(
  env: { FCM_SERVICE_ACCOUNT_JSON?: string; FCM_PROJECT_ID?: string },
  opts: FcmPushOptions,
): Promise<boolean> {
  // Placeholder 모드: secret 미등록 → silent skip.
  if (!env.FCM_SERVICE_ACCOUNT_JSON || !env.FCM_PROJECT_ID) {
    return false;
  }
  if (!opts.fcmToken) return false;

  const token = await getAccessToken(env.FCM_SERVICE_ACCOUNT_JSON);
  if (!token) return false;

  // FCM HTTP v1 message format.
  const message: Record<string, unknown> = {
    token: opts.fcmToken,
    notification: { title: opts.title, body: opts.body },
    data: opts.data || {},
    android: {
      priority: opts.isCall ? 'HIGH' : 'NORMAL',
      notification: {
        channel_id: opts.isCall ? 'eggplant_calls' : 'eggplant_messages',
        // 통화는 ringing UI 가 떠야 하므로 high priority + sound default.
        ...(opts.isCall ? { sound: 'default', visibility: 'PUBLIC' } : {}),
      },
    },
  };

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${env.FCM_PROJECT_ID}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message }),
    },
  );

  if (res.ok) return true;
  const errText = await res.text();
  // 404 UNREGISTERED / 400 INVALID_ARGUMENT → 토큰 폐기 권장.
  if (res.status === 404 || errText.includes('UNREGISTERED')) {
    console.warn('[fcm] token unregistered, caller should clear column');
  } else {
    console.warn('[fcm] send failed:', res.status, errText);
  }
  return false;
}
