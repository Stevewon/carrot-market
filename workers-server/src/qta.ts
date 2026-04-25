/**
 * QTA 토큰 경제 공용 로직.
 *
 * 모든 입출금은 ledger 1행 + users.qta_balance UPDATE 를 한 batch 로 수행한다.
 * idem_key UNIQUE 제약으로 중복 적립 자동 차단.
 *
 * 반환값: { credited: boolean, reason?: string }
 *   credited=false 인 경우는 멱등 충돌(이미 지급됨) 또는 카운터 초과.
 */

import type { Env } from './types';

export const QTA_SIGNUP_BONUS = 500;
export const QTA_LOGIN_BONUS = 10;
export const QTA_LOGIN_DAILY_MAX = 3;
export const QTA_TRADE_BONUS = 10;

// ── 출금 정책 ──
export const QTA_WITHDRAWAL_MIN = 5000;   // 최소 신청액
export const QTA_WITHDRAWAL_UNIT = 5000;  // 5,000 단위만

/** 'YYYY-MM-DD' (UTC). */
function ymdUtc(d = new Date()): string {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/**
 * 단일 ledger 행 + 잔액 갱신 (멱등).
 * idem_key 가 이미 존재하면 INSERT 가 실패하고 false 반환.
 */
async function creditOnce(
  env: Env,
  user_id: string,
  amount: number,
  reason: string,
  idem_key: string,
  meta?: Record<string, unknown>,
): Promise<boolean> {
  const id = crypto.randomUUID();
  const metaStr = meta ? JSON.stringify(meta) : null;

  try {
    // batch 로 atomically 처리. INSERT 가 UNIQUE 충돌이면 batch 전체 실패하므로 잔액도 안 변함.
    await env.DB.batch([
      env.DB
        .prepare(
          `INSERT INTO qta_ledger (id, user_id, amount, reason, idem_key, meta)
             VALUES (?, ?, ?, ?, ?, ?)`,
        )
        .bind(id, user_id, amount, reason, idem_key, metaStr),
      env.DB
        .prepare(
          `UPDATE users SET qta_balance = qta_balance + ?, updated_at = datetime('now')
             WHERE id = ?`,
        )
        .bind(amount, user_id),
    ]);
    return true;
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    if (/UNIQUE/i.test(msg)) {
      // 이미 지급됨 — 정상.
      return false;
    }
    console.error('[qta] credit failed', { reason, idem_key, msg });
    throw e;
  }
}

/** 회원가입 보너스 (1회, 멱등). */
export async function grantSignupBonus(env: Env, user_id: string): Promise<boolean> {
  return creditOnce(
    env,
    user_id,
    QTA_SIGNUP_BONUS,
    'signup',
    `signup:${user_id}`,
    { bonus: QTA_SIGNUP_BONUS },
  );
}

/**
 * 로그인 일일 보너스. 하루 최대 QTA_LOGIN_DAILY_MAX 번까지 지급.
 * - qta_daily_login(user_id, ymd) 카운터를 1 증가시키고 그 결과 카운트가 N 이면
 *   idem_key='login_daily:<user_id>:<ymd>:<N>' 로 ledger 에 1회 적립.
 * - 동시 요청이 와도 INSERT OR REPLACE + COUNT update 후 idem_key 가 자연 중복 방지.
 *
 * 반환:
 *   { credited: true, count: N }   ← 이번 호출에서 N 번째 보너스 지급됨
 *   { credited: false, count: N }  ← 이미 한도 도달했거나 멱등 충돌
 */
export async function grantLoginDailyBonus(
  env: Env,
  user_id: string,
): Promise<{ credited: boolean; count: number; remaining: number }> {
  const ymd = ymdUtc();

  // 1) 현재 카운트 조회 (없으면 0).
  const cur = await env.DB
    .prepare('SELECT count FROM qta_daily_login WHERE user_id = ? AND ymd = ?')
    .bind(user_id, ymd)
    .first<{ count: number }>();
  const currentCount = cur?.count ?? 0;

  if (currentCount >= QTA_LOGIN_DAILY_MAX) {
    return { credited: false, count: currentCount, remaining: 0 };
  }

  const nextCount = currentCount + 1;

  // 2) 카운터 upsert + ledger insert 를 batch 로.
  //    ledger 가 idem 충돌 나면 batch 가 통째로 실패해 카운터도 그대로 둠.
  const idem = `login_daily:${user_id}:${ymd}:${nextCount}`;
  const ledgerId = crypto.randomUUID();

  try {
    await env.DB.batch([
      env.DB
        .prepare(
          `INSERT INTO qta_daily_login (user_id, ymd, count, updated_at)
             VALUES (?, ?, ?, datetime('now'))
             ON CONFLICT(user_id, ymd)
             DO UPDATE SET count = excluded.count, updated_at = datetime('now')`,
        )
        .bind(user_id, ymd, nextCount),
      env.DB
        .prepare(
          `INSERT INTO qta_ledger (id, user_id, amount, reason, idem_key, meta)
             VALUES (?, ?, ?, 'login_daily', ?, ?)`,
        )
        .bind(
          ledgerId,
          user_id,
          QTA_LOGIN_BONUS,
          idem,
          JSON.stringify({ ymd, n: nextCount }),
        ),
      env.DB
        .prepare(
          `UPDATE users SET qta_balance = qta_balance + ?, updated_at = datetime('now')
             WHERE id = ?`,
        )
        .bind(QTA_LOGIN_BONUS, user_id),
    ]);
    return {
      credited: true,
      count: nextCount,
      remaining: QTA_LOGIN_DAILY_MAX - nextCount,
    };
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    if (/UNIQUE/i.test(msg)) {
      // 동시 호출 등으로 이미 같은 (user, ymd, n) 이 들어감 — 무시.
      return {
        credited: false,
        count: currentCount,
        remaining: QTA_LOGIN_DAILY_MAX - currentCount,
      };
    }
    console.error('[qta] login bonus failed', msg);
    throw e;
  }
}

/**
 * 거래완료 보너스 — 판매자·구매자 각각 +10 QTA (멱등).
 * 같은 product_id 로 두 번 호출되어도 중복 지급되지 않는다.
 */
export async function grantTradeBonus(
  env: Env,
  product_id: string,
  seller_id: string,
  buyer_id: string,
): Promise<{ seller_credited: boolean; buyer_credited: boolean }> {
  const sellerOk = await creditOnce(
    env,
    seller_id,
    QTA_TRADE_BONUS,
    'trade_seller',
    `trade:${product_id}:seller`,
    { product_id, role: 'seller' },
  );
  const buyerOk = await creditOnce(
    env,
    buyer_id,
    QTA_TRADE_BONUS,
    'trade_buyer',
    `trade:${product_id}:buyer`,
    { product_id, role: 'buyer' },
  );
  return { seller_credited: sellerOk, buyer_credited: buyerOk };
}

// ────────────────────────────────────────────────────────────────────────
// 출금 신청 / 환불
// ────────────────────────────────────────────────────────────────────────

export interface WithdrawalRow {
  id: string;
  user_id: string;
  wallet_address: string;
  amount: number;
  status: 'requested' | 'processing' | 'completed' | 'rejected';
  requested_at: string;
  processed_at: string | null;
  tx_hash: string | null;
  reject_reason: string | null;
  ledger_id: string;
  refund_ledger_id: string | null;
}

/**
 * 출금 신청을 생성한다 (잔액 차감 + 신청행 생성을 atomic batch).
 *
 * 검증:
 *   - amount >= QTA_WITHDRAWAL_MIN
 *   - amount % QTA_WITHDRAWAL_UNIT === 0
 *   - 사용자에 wallet_address 가 등록되어 있어야 함
 *   - 잔액 >= amount
 *   - 진행 중(requested/processing) 출금이 없어야 함
 *
 * 반환:
 *   { ok: true, withdrawal }  성공
 *   { ok: false, error }       사용자에게 보여줄 에러 메시지
 */
export async function requestWithdrawal(
  env: Env,
  user_id: string,
  amount: number,
): Promise<{ ok: true; withdrawal: WithdrawalRow } | { ok: false; error: string; status?: number }> {
  if (!Number.isInteger(amount) || amount <= 0) {
    return { ok: false, error: '출금 금액이 올바르지 않아요', status: 400 };
  }
  if (amount < QTA_WITHDRAWAL_MIN) {
    return {
      ok: false,
      error: `최소 출금 금액은 ${QTA_WITHDRAWAL_MIN.toLocaleString('ko-KR')} QTA 예요`,
      status: 400,
    };
  }
  if (amount % QTA_WITHDRAWAL_UNIT !== 0) {
    return {
      ok: false,
      error: `${QTA_WITHDRAWAL_UNIT.toLocaleString('ko-KR')} QTA 단위로만 신청할 수 있어요`,
      status: 400,
    };
  }

  // 사용자 잔액·지갑 조회.
  const u = await env.DB
    .prepare('SELECT wallet_address, qta_balance FROM users WHERE id = ?')
    .bind(user_id)
    .first<{ wallet_address: string | null; qta_balance: number }>();
  if (!u) return { ok: false, error: '사용자를 찾을 수 없어요', status: 404 };
  if (!u.wallet_address) {
    return { ok: false, error: '지갑 주소가 등록되지 않았어요', status: 400 };
  }
  if ((u.qta_balance ?? 0) < amount) {
    return { ok: false, error: 'QTA 잔액이 부족해요', status: 400 };
  }

  // 진행중 신청 존재 여부.
  const pending = await env.DB
    .prepare(
      `SELECT id FROM qta_withdrawals
         WHERE user_id = ? AND status IN ('requested','processing')
         LIMIT 1`,
    )
    .bind(user_id)
    .first<{ id: string }>();
  if (pending) {
    return {
      ok: false,
      error: '진행 중인 출금 신청이 이미 있어요. 처리된 후 다시 신청해주세요.',
      status: 409,
    };
  }

  const wid = crypto.randomUUID();
  const ledgerId = crypto.randomUUID();
  const idem = `withdrawal:${wid}`;

  // batch: ledger -N + users.qta_balance -= N + qta_withdrawals INSERT
  // 동시 신청 시 부분 UNIQUE 인덱스가 두 번째 INSERT 를 막아 batch 전체 롤백.
  try {
    await env.DB.batch([
      env.DB
        .prepare(
          `INSERT INTO qta_ledger (id, user_id, amount, reason, idem_key, meta)
             VALUES (?, ?, ?, 'withdrawal', ?, ?)`,
        )
        .bind(
          ledgerId,
          user_id,
          -amount,
          idem,
          JSON.stringify({ withdrawal_id: wid, wallet: u.wallet_address }),
        ),
      env.DB
        .prepare(
          `UPDATE users SET qta_balance = qta_balance - ?, updated_at = datetime('now')
             WHERE id = ? AND qta_balance >= ?`,
        )
        .bind(amount, user_id, amount),
      env.DB
        .prepare(
          `INSERT INTO qta_withdrawals
             (id, user_id, wallet_address, amount, status, ledger_id)
             VALUES (?, ?, ?, ?, 'requested', ?)`,
        )
        .bind(wid, user_id, u.wallet_address, amount, ledgerId),
    ]);
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    if (/UNIQUE.*one_pending_per_user/i.test(msg)) {
      return {
        ok: false,
        error: '진행 중인 출금 신청이 이미 있어요',
        status: 409,
      };
    }
    console.error('[qta] withdrawal request failed', msg);
    return { ok: false, error: '출금 신청 처리 중 오류가 발생했어요', status: 500 };
  }

  // 잔액이 race condition 으로 음수 되었으면 롤백 (가드).
  const after = await env.DB
    .prepare('SELECT qta_balance FROM users WHERE id = ?')
    .bind(user_id)
    .first<{ qta_balance: number }>();
  if (!after || after.qta_balance < 0) {
    // 비정상 — 환불.
    await refundWithdrawal(env, wid, '잔액 검증 실패').catch(() => {});
    return { ok: false, error: 'QTA 잔액이 부족해요', status: 400 };
  }

  const row = await env.DB
    .prepare('SELECT * FROM qta_withdrawals WHERE id = ?')
    .bind(wid)
    .first<WithdrawalRow>();
  return { ok: true, withdrawal: row! };
}

/**
 * 출금 신청을 거부 처리하고 자동 환불 (운영자 또는 시스템 호출).
 * - 'requested' / 'processing' 상태에서만 가능.
 * - ledger 에 reason='withdrawal_refund' 로 +amount 환불 + qta_balance 복구.
 */
export async function refundWithdrawal(
  env: Env,
  withdrawal_id: string,
  reason: string,
): Promise<{ ok: boolean; error?: string }> {
  const w = await env.DB
    .prepare('SELECT * FROM qta_withdrawals WHERE id = ?')
    .bind(withdrawal_id)
    .first<WithdrawalRow>();
  if (!w) return { ok: false, error: 'not found' };
  if (w.status !== 'requested' && w.status !== 'processing') {
    return { ok: false, error: `이미 처리된 신청이에요 (${w.status})` };
  }

  const refundLedgerId = crypto.randomUUID();
  const idem = `withdrawal_refund:${withdrawal_id}`;

  try {
    await env.DB.batch([
      env.DB
        .prepare(
          `INSERT INTO qta_ledger (id, user_id, amount, reason, idem_key, meta)
             VALUES (?, ?, ?, 'withdrawal_refund', ?, ?)`,
        )
        .bind(
          refundLedgerId,
          w.user_id,
          w.amount,
          idem,
          JSON.stringify({ withdrawal_id, refund_reason: reason }),
        ),
      env.DB
        .prepare(
          `UPDATE users SET qta_balance = qta_balance + ?, updated_at = datetime('now')
             WHERE id = ?`,
        )
        .bind(w.amount, w.user_id),
      env.DB
        .prepare(
          `UPDATE qta_withdrawals
             SET status = 'rejected',
                 processed_at = datetime('now'),
                 reject_reason = ?,
                 refund_ledger_id = ?
             WHERE id = ?`,
        )
        .bind(reason, refundLedgerId, withdrawal_id),
    ]);
    return { ok: true };
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    if (/UNIQUE/i.test(msg)) {
      // 이미 환불됨 — 정상.
      return { ok: true };
    }
    console.error('[qta] refund failed', msg);
    return { ok: false, error: msg };
  }
}

