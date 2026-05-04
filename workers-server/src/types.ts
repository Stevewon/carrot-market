/**
 * Cloudflare bindings + app context types
 */
export interface Env {
  DB: D1Database;
  UPLOADS: R2Bucket;
  CHAT_HUB: DurableObjectNamespace;
  JWT_SECRET: string;
  ENVIRONMENT: string;
  PUBLIC_UPLOAD_URL: string;
  /**
   * 쉼표로 구분된 운영자 user_id 목록.
   *   wrangler secret put ADMIN_USER_IDS  # → "uuid1,uuid2"
   * 비어 있으면 admin 라우트는 모두 403. (보안 fail-closed)
   *
   * Legacy: 기존 사용자 JWT + 화이트리스트 방식 (앱 내 어드민 화면용).
   * 웹 어드민은 Firebase(qrchat-b7a67) 위에서 별도 구축.
   */
  ADMIN_USER_IDS?: string;

  /**
   * Agora App ID (큐알쳇과 공유). vars 로 주입.
   *   wrangler.toml [vars] AGORA_APP_ID = "..."
   * 클라이언트에서도 같은 값을 --dart-define 으로 주입받는다.
   */
  AGORA_APP_ID?: string;

  /**
   * Agora App Certificate (HMAC-SHA256 서명 키). 절대 클라이언트에 노출 X.
   *   wrangler secret put AGORA_APP_CERTIFICATE
   * 사장님이 Firebase Secret Manager 에서 직접 조회 후 등록.
   * 비어있으면 토큰 발급 라우트는 503 반환 (fail-closed).
   */
  AGORA_APP_CERTIFICATE?: string;

  /**
   * FCM (Firebase Cloud Messaging) — 3차 푸시.
   * 사장님 결정 (c): Firebase 프로젝트 신규 생성 후 키 등록 예정.
   *   wrangler secret put FCM_SERVICE_ACCOUNT_JSON  # 서비스 계정 JSON 전체
   *   wrangler secret put FCM_PROJECT_ID            # eggplant-app 등
   * 둘 다 미등록 시 placeholder 모드 — silent skip (앱 빌드/실행은 정상).
   */
  FCM_SERVICE_ACCOUNT_JSON?: string;
  FCM_PROJECT_ID?: string;
}

export interface AuthPayload {
  id: string;
  nickname: string;
  device_uuid: string;
  /**
   * Bumped when the user changes password or logs in on a new device.
   * If `token_version` in a JWT doesn't match the user row, the token is
   * rejected — this is how we kick out a previously-logged-in device.
   */
  tv: number;
  iat?: number;
  exp?: number;
}

export interface UserRow {
  id: string;
  nickname: string;
  device_uuid: string;
  wallet_address: string | null;
  password_hash: string | null;
  password_salt: string | null; // legacy / unused (we store salt inside password_hash now)
  token_version: number;
  region: string | null;
  /** region 중심 좌표 (동네 인증 통과 시 채워짐). */
  lat: number | null;
  lng: number | null;
  region_verified_at: string | null;
  manner_score: number;
  /** QTA 토큰 잔액. 본인에게만 노출. */
  qta_balance: number;
  /**
   * 인증 단계 (migration 0019).
   *   0 = 미인증 (가입 직후, 둘러보기·채팅·통화·상품등록만 가능)
   *   1 = 본인인증 완료 (KRW/QTA 결제 가능)
   *   2 = 계좌 등록 완료 (QTA 출금 가능)
   * 채팅·통화는 단계와 무관하게 항상 익명.
   */
  verification_level: number;
  /** SHA-256(CI). 휴대폰 번호 자체는 절대 저장 X. */
  verified_ci_hash: string | null;
  verified_at: string | null;
  /** SHA-256(bank_code + account_number). 계좌번호 자체는 저장 X. */
  bank_account_hash: string | null;
  bank_registered_at: string | null;
  created_at: string;
  updated_at: string;
}

/** Shape returned to the client (never expose password_hash). */
export interface UserPublic {
  id: string;
  nickname: string;
  device_uuid: string;
  wallet_address: string | null;
  region: string | null;
  region_verified_at: string | null;
  manner_score: number;
  /** QTA 잔액 — 본인 응답에만 포함. 타인 프로필에는 ::sanitize 가 빼고 보낸다. */
  qta_balance: number;
  /** 인증 단계 (0/1/2). 본인 응답·타인 프로필 모두 노출 (신뢰 표시). */
  verification_level: number;
  /** 본인 응답에만 포함. 타인 프로필에는 sanitize 가 뺀다. */
  verified_at?: string | null;
  /** 본인 응답에만 포함. */
  bank_registered_at?: string | null;
  created_at: string;
  updated_at: string;
}

export interface ProductRow {
  id: string;
  seller_id: string;
  title: string;
  description: string;
  price: number;
  /**
   * QTA 거래 가격 (정수). 0 = KRW 거래(기본). 양수면 거래 완료 시 자동으로
   * buyer→seller 잔액 이체. migration 0017 에서 추가됨.
   */
  qta_price: number;
  category: string;
  region: string;
  images: string; // comma-separated
  video_url: string | null; // YouTube URL OR /uploads/<key>.mp4 path
  status: 'sale' | 'reserved' | 'sold';
  view_count: number;
  like_count: number;
  chat_count: number;
  /** Last time the seller pressed "끌어올리기" (24h cooldown). NULL if never. */
  bumped_at: string | null;
  /** Set when the seller marks the listing as 'sold' and picks a buyer. */
  buyer_id: string | null;
  /** 작성자의 region 중심 좌표(인증 시점에 복사). 거리 필터에 사용. */
  lat: number | null;
  lng: number | null;
  created_at: string;
  updated_at: string;
}

export interface ReviewRow {
  id: string;
  product_id: string;
  reviewer_id: string;
  reviewee_id: string;
  rating: 'good' | 'soso' | 'bad';
  tags: string; // CSV
  comment: string;
  created_at: string;
}

/**
 * Hydrated product shape returned to clients
 */
export interface ProductResponse extends Omit<ProductRow, 'images'> {
  images: string[];
  video_url: string;
  seller_nickname: string;
  seller_manner_score: number;
  /** SSO Universal User ID — 클라이언트가 마스킹해서 표시. */
  seller_wallet_address: string | null;
  is_liked: boolean;
}

/**
 * Hono context variables (for authentication middleware)
 */
export type Variables = {
  user?: AuthPayload;
};
