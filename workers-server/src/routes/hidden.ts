/**
 * 게시물 숨김 (당근식 "이 게시물 가리기").
 *
 * 사용자가 보고 싶지 않은 게시물을 숨김 처리하면 피드/검색 결과에서 사라진다.
 * 본인만 알 수 있고, 게시물 작성자는 알 수 없다.
 *
 * 엔드포인트:
 *   POST   /api/hidden/:productId   - 숨기기
 *   DELETE /api/hidden/:productId   - 숨김 해제
 *   GET    /api/hidden              - 내가 숨긴 목록 (최대 100개)
 *
 * 피드 필터(products GET) 측에서 LEFT JOIN 으로 숨김 항목을 제외한다.
 */

import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { authMiddleware } from '../jwt';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use('*', authMiddleware);

/** POST /api/hidden/:productId */
app.post('/:productId', async (c) => {
  const me = c.get('user')!;
  const productId = c.req.param('productId');

  // 존재하는 게시물인지만 가볍게 체크 (없어도 무시).
  const exists = await c.env.DB
    .prepare('SELECT 1 FROM products WHERE id = ?')
    .bind(productId)
    .first();
  if (!exists) {
    return c.json({ error: '존재하지 않는 게시물이에요' }, 404);
  }

  await c.env.DB
    .prepare(
      `INSERT OR IGNORE INTO hidden_products (user_id, product_id)
         VALUES (?, ?)`
    )
    .bind(me.id, productId)
    .run();
  return c.json({ ok: true });
});

/** DELETE /api/hidden/:productId */
app.delete('/:productId', async (c) => {
  const me = c.get('user')!;
  const productId = c.req.param('productId');
  await c.env.DB
    .prepare('DELETE FROM hidden_products WHERE user_id = ? AND product_id = ?')
    .bind(me.id, productId)
    .run();
  return c.json({ ok: true });
});

/** GET /api/hidden — 내가 숨긴 게시물 ID 목록. (간단히 ID만 반환) */
app.get('/', async (c) => {
  const me = c.get('user')!;
  const rs = await c.env.DB
    .prepare(
      `SELECT product_id FROM hidden_products
         WHERE user_id = ? ORDER BY created_at DESC LIMIT 100`
    )
    .bind(me.id)
    .all<{ product_id: string }>();
  return c.json({
    hidden: (rs.results || []).map((r) => r.product_id),
  });
});

export default app;
