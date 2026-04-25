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
  created_at: string;
  updated_at: string;
}

export interface ProductRow {
  id: string;
  seller_id: string;
  title: string;
  description: string;
  price: number;
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
  is_liked: boolean;
}

/**
 * Hono context variables (for authentication middleware)
 */
export type Variables = {
  user?: AuthPayload;
};
