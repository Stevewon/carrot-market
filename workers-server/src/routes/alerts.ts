/**
 * 키워드 알림 (당근식 "키워드 알림").
 *
 * 사용자가 미리 등록해 둔 키워드와 새 상품이 매칭되면
 * WebSocket(type:'keyword_alert') 푸시가 가고, 클라이언트는 NotificationService 로
 * 로컬 알림을 띄운다. 알림 발송 이력은 DB 에 남기지 않는다 (사생활 보호).
 *
 * 엔드포인트:
 *   GET    /api/alerts/keywords           - 내 키워드 목록
 *   POST   /api/alerts/keywords           - 키워드 추가 (max 5)
 *   DELETE /api/alerts/keywords/:id       - 키워드 삭제
 *
 * 매칭은 product.title + description + category 의 lower-case 에서 LIKE '%keyword%'.
 * 거리 필터는 서버 fanout 시점에 적용한다 (사용자 lat/lng 와 product lat/lng 의
 * Haversine 거리 ≤ KEYWORD_ALERT_RADIUS_KM).
 */

import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { authMiddleware } from '../jwt';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use('*', authMiddleware);

const MAX_KEYWORDS_PER_USER = 5;
const MIN_KEYWORD_LEN = 2;
const MAX_KEYWORD_LEN = 30;

/** 정규화 — 양옆 공백 제거 + lower-case. 한글은 lower-case 영향 없음. */
function normalizeKeyword(raw: string): string {
  return raw.trim().toLowerCase();
}

interface KeywordRow {
  id: string;
  keyword: string;
  created_at: string;
}

/**
 * GET /api/alerts/keywords
 * 응답: { keywords: [{id, keyword, created_at}], max: 5 }
 */
app.get('/keywords', async (c) => {
  const me = c.get('user')!;
  const rs = await c.env.DB
    .prepare(
      'SELECT id, keyword, created_at FROM keyword_alerts WHERE user_id = ? ORDER BY created_at DESC'
    )
    .bind(me.id)
    .all<KeywordRow>();
  return c.json({
    keywords: rs.results || [],
    max: MAX_KEYWORDS_PER_USER,
  });
});

/**
 * POST /api/alerts/keywords
 * Body: { keyword: string }
 */
app.post('/keywords', async (c) => {
  const me = c.get('user')!;
  let body: { keyword?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const kw = normalizeKeyword(body.keyword || '');
  if (kw.length < MIN_KEYWORD_LEN) {
    return c.json({ error: `키워드는 ${MIN_KEYWORD_LEN}자 이상이어야 해요` }, 400);
  }
  if (kw.length > MAX_KEYWORD_LEN) {
    return c.json({ error: `키워드는 ${MAX_KEYWORD_LEN}자 이하로 입력해주세요` }, 400);
  }

  // 개수 체크.
  const cnt = await c.env.DB
    .prepare('SELECT COUNT(*) as n FROM keyword_alerts WHERE user_id = ?')
    .bind(me.id)
    .first<{ n: number }>();
  if ((cnt?.n ?? 0) >= MAX_KEYWORDS_PER_USER) {
    return c.json({ error: `키워드는 최대 ${MAX_KEYWORDS_PER_USER}개까지 등록할 수 있어요` }, 400);
  }

  const id = crypto.randomUUID();
  try {
    await c.env.DB
      .prepare('INSERT INTO keyword_alerts (id, user_id, keyword) VALUES (?, ?, ?)')
      .bind(id, me.id, kw)
      .run();
  } catch (e: any) {
    if (String(e?.message || '').includes('UNIQUE')) {
      return c.json({ error: '이미 등록된 키워드예요' }, 409);
    }
    throw e;
  }

  const row = await c.env.DB
    .prepare('SELECT id, keyword, created_at FROM keyword_alerts WHERE id = ?')
    .bind(id)
    .first<KeywordRow>();
  return c.json({ keyword: row }, 201);
});

/**
 * DELETE /api/alerts/keywords/:id
 */
app.delete('/keywords/:id', async (c) => {
  const me = c.get('user')!;
  const id = c.req.param('id');
  await c.env.DB
    .prepare('DELETE FROM keyword_alerts WHERE id = ? AND user_id = ?')
    .bind(id, me.id)
    .run();
  return c.json({ ok: true });
});

export default app;
