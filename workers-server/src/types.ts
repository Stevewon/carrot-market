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
  iat?: number;
  exp?: number;
}

export interface UserRow {
  id: string;
  nickname: string;
  device_uuid: string;
  region: string | null;
  manner_score: number;
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
  created_at: string;
  updated_at: string;
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
