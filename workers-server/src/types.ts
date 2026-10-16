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
   * '1' 일 때만 /api/auth/sso/exchange 를 연다 (개발/테스트 전용).
   * QRChat external_token 서명 검증이 구현되기 전까지 운영에서는 비워둔다.
   * 검증 없이 열면 지갑주소만으로 남의 계정 토큰을 받을 수 있다.
   */
  ALLOW_UNVERIFIED_SSO?: string;

  /** '1' 일 때만 dummy 본인인증 provider 허용 (개발/테스트 전용). */
  ALLOW_DUMMY_VERIFY?: string;

  /**
   * 지갑 소유 증명(소액 송금)에 쓰는 Quantarium Blockscout 익스플로러.
   * 기본값 https://scan.quantarium.io
   */
  QTA_EXPLORER_URL?: string;

  /**
   * 소액 송금을 받을 회사 주소 (선택). 비워두면 본인 지갑으로 보내는
   * 자기송금만 인정한다 (회사가 사용자 돈을 받지 않음 — 가스비만 발생).
   */
  WALLET_VERIFY_ADDRESS?: string;

  /**
   * 1단계 지갑 인증 송금용 본사 지갑 서명키 (src/walletReceive.ts). 둘 중 하나.
   *   wrangler secret put HQ_WALLET_MNEMONIC     # 12단어 (+ HQ_WALLET_INDEX, 기본 0)
   *   wrangler secret put HQ_WALLET_SECRET_KEY   # SPHINCS+ 비밀키 64바이트 hex
   * 만든 주소가 WALLET_VERIFY_ADDRESS 와 다르면 보내지 않는다.
   */
  HQ_WALLET_MNEMONIC?: string;
  HQ_WALLET_INDEX?: string;
  HQ_WALLET_SECRET_KEY?: string;
  /** Quantarium RPC (기본 https://rpc.quantarium.io, chain 60000). */
  QTA_RPC_URL?: string;
  QTA_CHAIN_ID?: string;

  /** 2단계 휴대폰 인증 Firebase 프로젝트 (기본 eggplant-app-4cd70). */
  FIREBASE_PROJECT_ID?: string;
  /** 휴대폰 번호 암호화 키 (32바이트 base64, src/phoneVault.ts). 없으면 휴대폰 인증 불가. */
  PHONE_ENC_KEY?: string;

  /**
   * 큐알쳇 닉네임·비밀번호 확인 함수 (QRChat functions/eggplant_bridge.js).
   * 기본값 https://asia-northeast3-qrchat-b7a67.cloudfunctions.net/eggplantVerifyHttp
   */
  QRCHAT_BRIDGE_URL?: string;
  /**
   * 위 함수 호출 키 (QRChat Secret EGGPLANT_BRIDGE_KEY 와 같은 값, 32자 이상).
   *   wrangler secret put QRCHAT_BRIDGE_KEY
   * 비어 있으면 큐알쳇 로그인 연동은 꺼진다 (가지 계정 로그인만 동작).
   */
  QRCHAT_BRIDGE_KEY?: string;

  /**
   * Agora App ID (legacy, 큐알쳇과 공유). vars 로 주입.
   *   wrangler.toml [vars] AGORA_APP_ID = "..."
   * Eggplant 전용 신규 Project 도입 후 fallback 으로만 사용.
   */
  AGORA_APP_ID?: string;

  /**
   * Agora App Certificate (legacy, 큐알쳇용 HMAC-SHA256 서명 키).
   *   wrangler secret put AGORA_APP_CERTIFICATE
   * Eggplant 전용 신규 Project 도입 후 fallback 으로만 사용.
   */
  AGORA_APP_CERTIFICATE?: string;

  /**
   * Eggplant 전용 Agora App ID (큐알쳇과 완전 분리된 신규 Project).
   *   wrangler secret put AGORA_APP_ID_EGGPLANT
   * 큐알쳇 트래픽/장애와 100% 격리. 우선 사용, 없으면 AGORA_APP_ID 로 fallback.
   */
  AGORA_APP_ID_EGGPLANT?: string;

  /**
   * Eggplant 전용 Agora App Certificate (신규 Project Primary Certificate).
   *   wrangler secret put AGORA_APP_CERTIFICATE_EGGPLANT
   * 절대 클라이언트에 노출 X. 우선 사용, 없으면 AGORA_APP_CERTIFICATE 로 fallback.
   */
  AGORA_APP_CERTIFICATE_EGGPLANT?: string;

  /**
   * FCM (Firebase Cloud Messaging) — 3차 푸시.
   * 사장님 결정 (c): Firebase 프로젝트 신규 생성 후 키 등록 예정.
   *   wrangler secret put FCM_SERVICE_ACCOUNT_JSON  # 서비스 계정 JSON 전체
   *   wrangler secret put FCM_PROJECT_ID            # eggplant-app 등
   * 둘 다 미등록 시 placeholder 모드 — silent skip (앱 빌드/실행은 정상).
   */
  FCM_SERVICE_ACCOUNT_JSON?: string;
  FCM_PROJECT_ID?: string;

  /**
   * 어드민 보호용 공유 토큰. `Authorization: Admin <ADMIN_TOKEN>` 헤더로 전달.
   *   wrangler secret put ADMIN_TOKEN
   * 비어있으면 admin 라우트는 모두 401/403 (fail-closed).
   * jwt.ts 의 requireAdminToken 미들웨어에서 사용.
   */
  ADMIN_TOKEN?: string;
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
  /** 지갑 소유 증명 완료 시각 (migration 0027). 이전 가입자는 NULL. */
  wallet_verified_at?: string | null;
  /** 'kr' | 'jp' | 'ph' (migration 0033). 언어·화폐·지역 목록을 정한다. */
  market?: string;
  /** 내 동네 목록 JSON (최대 10곳, migration 0034). region 은 그중 지금 보는 동네. */
  regions?: string | null;
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
  /** 지갑 소유 증명(소액 송금) 완료 시각 — 출금 조건. migration 0027. */
  wallet_verified_at?: string | null;
  /** 'kr' | 'jp' | 'ph' */
  market?: string;
  /** 내 동네 목록 (본인 응답에만). */
  regions?: string[];
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
  /** 거래 희망 장소 (0038). */
  meet_place?: string | null;
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
  /** 구매자가 거래를 확인(QTA 결제 + 거래 보너스)한 시각. migration 0026. */
  buyer_confirmed_at: string | null;
  /** 상품 등록 채굴로 지금 지급돼 있는 QTA. migration 0031. */
  listing_reward?: number;
  /** 'kr'(원) | 'jp'(엔). 올린 사람의 시장. migration 0033. */
  market?: string;
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
  /** 거래 당사자(판매자·구매자)에게만 — 구매자 닉네임. */
  buyer_nickname?: string | null;
}

/**
 * Hono context variables (for authentication middleware)
 */
export type Variables = {
  user?: AuthPayload;
};
