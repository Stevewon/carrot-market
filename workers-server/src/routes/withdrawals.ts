/**
 * QTA 출금 신청 라우트.
 *
 *   GET  /api/withdrawals                 — 내 신청 내역 (최근 50건)
 *   POST /api/withdrawals                 — 새 출금 신청  body:{ amount }
 *   GET  /api/withdrawals/policy          — 정책(min, unit) 노출 (UI 용)
 *
 *   (운영자 전용 — 향후 admin 미들웨어 추가 시 활성)
 *   POST /api/withdrawals/:id/reject      — 거부 + 자동 환불  body:{ reason }
 *   POST /api/withdrawals/:id/process     — 송금 처리 시작
 *   POST /api/withdrawals/:id/complete    — 송금 완료  body:{ tx_hash }
 */

import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { authMiddleware, adminMiddleware } from '../jwt';
import {
  QTA_WITHDRAWAL_MIN,
  QTA_WITHDRAWAL_UNIT,
  requestWithdrawal,
  refundWithdrawal,
  processWithdrawal,
  completeWithdrawal,
  type WithdrawalRow,
} from '../qta';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

/** 정책 정보 — 인증 없어도 노출 가능. */
app.get('/policy', (c) => {
  return c.json({
    min: QTA_WITHDRAWAL_MIN,
    unit: QTA_WITHDRAWAL_UNIT,
    note:
      `최소 ${QTA_WITHDRAWAL_MIN.toLocaleString('ko-KR')} QTA 부터 ` +
      `${QTA_WITHDRAWAL_UNIT.toLocaleString('ko-KR')} QTA 단위로만 신청할 수 있어요`,
  });
});

app.use('*', authMiddleware);

/** 내 출금 신청 내역. */
app.get('/', async (c) => {
  const me = c.get('user')!;
  const rs = await c.env.DB
    .prepare(
      `SELECT id, user_id, wallet_address, amount, status,
              requested_at, processed_at, tx_hash, reject_reason
         FROM qta_withdrawals
        WHERE user_id = ?
        ORDER BY requested_at DESC
        LIMIT 50`,
    )
    .bind(me.id)
    .all<WithdrawalRow>();
  return c.json({
    withdrawals: rs.results || [],
    policy: { min: QTA_WITHDRAWAL_MIN, unit: QTA_WITHDRAWAL_UNIT },
  });
});

/** 출금 신청. */
app.post('/', async (c) => {
  const me = c.get('user')!;
  let body: { amount?: number | string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: '잘못된 요청' }, 400);
  }

  const raw = body.amount;
  const amount =
    typeof raw === 'number' ? raw : typeof raw === 'string' ? parseInt(raw, 10) : NaN;
  if (!Number.isFinite(amount)) {
    return c.json({ error: '출금 금액을 입력해주세요' }, 400);
  }

  const result = await requestWithdrawal(c.env, me.id, amount);
  if (!result.ok) {
    return c.json({ error: result.error }, (result.status as 400 | 404 | 409 | 500) || 400);
  }

  // 출금 후 잔액도 같이 응답해서 UI 가 즉시 반영하기 쉽게.
  const u = await c.env.DB
    .prepare('SELECT qta_balance FROM users WHERE id = ?')
    .bind(me.id)
    .first<{ qta_balance: number }>();

  return c.json(
    {
      withdrawal: result.withdrawal,
      qta_balance: u?.qta_balance ?? 0,
    },
    201,
  );
});

// ────────────────────────────────────────────────────────────────────
// 운영자 전용 (현재는 자기 신청만 거부 가능 = 사용자 취소 용도).
// 추후 admin 미들웨어 적용해 운영자만 호출하도록 강화 예정.
// ────────────────────────────────────────────────────────────────────

/**
 * 신청 취소(=거부 + 환불). 사용자 본인이 아직 'requested' 상태인 자기 신청을 취소할 때.
 * 'processing' 이상은 취소 불가 — 운영자에게 문의 필요.
 */
app.post('/:id/cancel', async (c) => {
  const me = c.get('user')!;
  const wid = c.req.param('id');

  const w = await c.env.DB
    .prepare('SELECT user_id, status FROM qta_withdrawals WHERE id = ?')
    .bind(wid)
    .first<{ user_id: string; status: string }>();
  if (!w) return c.json({ error: '신청을 찾을 수 없어요' }, 404);
  if (w.user_id !== me.id) return c.json({ error: '권한이 없어요' }, 403);
  if (w.status !== 'requested') {
    return c.json(
      { error: `이미 처리되고 있어 취소할 수 없어요 (${w.status})` },
      409,
    );
  }

  const r = await refundWithdrawal(c.env, wid, '사용자 취소');
  if (!r.ok) return c.json({ error: r.error || '취소 실패' }, 500);

  const u = await c.env.DB
    .prepare('SELECT qta_balance FROM users WHERE id = ?')
    .bind(me.id)
    .first<{ qta_balance: number }>();

  return c.json({ ok: true, qta_balance: u?.qta_balance ?? 0 });
});

// ────────────────────────────────────────────────────────────────────
// 운영자 전용 (ADMIN_USER_IDS 에 있는 user_id 만 통과).
//
// 워크플로:
//   requested → (admin GET /admin/pending 으로 확인)
//             → POST /admin/:id/process       (외부 송금 시작 표시)
//             → POST /admin/:id/complete       (tx_hash 기록 + 종료)
//   또는
//   requested → POST /admin/:id/reject?reason  (거부 + 환불)
// ────────────────────────────────────────────────────────────────────

/**
 * GET /api/withdrawals/admin/pending
 *
 * 처리 대기(requested) + 진행중(processing) 신청 목록. 운영자 콘솔 진입 화면용.
 */
app.get('/admin/pending', adminMiddleware, async (c) => {
  const rows = await c.env.DB
    .prepare(
      `SELECT w.id, w.user_id, w.wallet_address, w.amount, w.status,
              w.requested_at, w.processed_at, w.tx_hash, w.reject_reason,
              u.nickname AS user_nickname
         FROM qta_withdrawals w
    LEFT JOIN users u ON u.id = w.user_id
        WHERE w.status IN ('requested', 'processing')
     ORDER BY w.requested_at ASC
        LIMIT 200`,
    )
    .all<WithdrawalRow & { user_nickname: string | null }>();
  return c.json({ rows: rows.results || [] });
});

/**
 * POST /api/withdrawals/admin/:id/reject
 *   body: { reason?: string }
 *
 * 신청을 거부하고 잔액을 즉시 환불. 'requested' 상태에서만 호출 가능.
 */
app.post('/admin/:id/reject', adminMiddleware, async (c) => {
  const wid = c.req.param('id');
  let reason = '운영자 거부';
  try {
    const body = await c.req.json<{ reason?: string }>();
    if (body?.reason && typeof body.reason === 'string' && body.reason.trim()) {
      reason = body.reason.trim().slice(0, 200);
    }
  } catch {
    /* body 없을 수 있음 — 기본 사유 사용 */
  }

  const w = await c.env.DB
    .prepare('SELECT status FROM qta_withdrawals WHERE id = ?')
    .bind(wid)
    .first<{ status: string }>();
  if (!w) return c.json({ error: 'not found' }, 404);
  if (w.status !== 'requested') {
    return c.json(
      { error: `거부할 수 없는 상태에요 (${w.status})` },
      409,
    );
  }

  const r = await refundWithdrawal(c.env, wid, reason);
  if (!r.ok) return c.json({ error: r.error || 'reject failed' }, 500);
  return c.json({ ok: true });
});

/**
 * POST /api/withdrawals/admin/:id/process
 *
 * 외부 송금을 시작했다는 의미. requested → processing 상태 전환.
 * 잔액에는 영향 없음 (이미 신청 시점에 차감됨).
 */
app.post('/admin/:id/process', adminMiddleware, async (c) => {
  const wid = c.req.param('id');
  const r = await processWithdrawal(c.env, wid);
  if (!r.ok) return c.json({ error: r.error || 'process failed' }, 400);
  return c.json({ ok: true });
});

/**
 * POST /api/withdrawals/admin/:id/complete
 *   body: { tx_hash: string }
 *
 * 송금이 완료됐음을 기록. requested|processing → completed.
 */
app.post('/admin/:id/complete', adminMiddleware, async (c) => {
  const wid = c.req.param('id');
  let txHash = '';
  try {
    const body = await c.req.json<{ tx_hash?: string }>();
    txHash = String(body?.tx_hash || '').trim();
  } catch {
    return c.json({ error: 'body 가 비어 있어요' }, 400);
  }
  if (!txHash) return c.json({ error: 'tx_hash 필수' }, 400);

  const r = await completeWithdrawal(c.env, wid, txHash);
  if (!r.ok) return c.json({ error: r.error || 'complete failed' }, 400);
  return c.json({ ok: true });
});

export default app;
