/**
 * 알림함 — 서버가 보내는 푸시(가격 내림·거래 확인·후기)를 같이 적어 둔다.
 * 푸시를 놓치거나 지워도 앱의 알림함에서 다시 볼 수 있게. 30일 지나면 cron 이 지운다.
 */
import type { Env } from '../types';

export interface InboxItem {
  userId: string;
  type: string;
  title: string;
  body?: string;
  productId?: string | null;
  targetUserId?: string | null;
  thumb?: string | null;
}

export async function addNotifications(env: Env, items: InboxItem[]): Promise<void> {
  if (!items.length) return;
  const stmt = env.DB.prepare(
    `INSERT INTO notifications (id, user_id, type, title, body, product_id, target_user_id, thumb)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  );
  // D1 batch 는 한 번에 너무 많으면 느려진다 → 100개씩.
  for (let i = 0; i < items.length; i += 100) {
    await env.DB.batch(
      items.slice(i, i + 100).map((n) =>
        stmt.bind(
          crypto.randomUUID(),
          n.userId,
          n.type,
          n.title.slice(0, 120),
          (n.body ?? '').slice(0, 300),
          n.productId ?? null,
          n.targetUserId ?? null,
          n.thumb ?? null,
        ),
      ),
    );
  }
}

/** 30일 지난 알림과 30일 지난 검색어 집계를 지운다. */
export async function purgeOldInbox(env: Env): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM notifications WHERE created_at < datetime('now', '-30 days')"),
    env.DB.prepare("DELETE FROM search_terms WHERE day < date('now', '-30 days')"),
  ]);
}
