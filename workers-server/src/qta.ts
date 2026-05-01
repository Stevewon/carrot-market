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
export const QTA_REFERRAL_BONUS = 200; // 친구 초대 1명당 추천인에게 지급 (무제한)

// ── 출금 정책 ──
export const QTA_WITHDRAWAL_MIN = 5000;   // 최소 신청액
export const QTA_WITHDRAWAL_UNIT = 5000;  // 5,000 단위만

// ── 채굴 정책 ──
export const QTA_MINING_LISTING_BONUS = 10;     // 상품 7일 유지 보너스
export const QTA_MINING_LISTING_DAYS = 7;        // 7일 이상 유지 시 지급
export const QTA_MINING_BROWSE_BONUS = 10;       // 둘러보기 일일 보너스
export const QTA_MINING_BROWSE_THRESHOLD = 10;   // 하루 10개 이상 봐야 지급

// ── 에스크로우 정책 ──
// 30,000원 미만 KRW 거래만 회사가 임시예치(에스크로우) 해줌.
// 그 이상은 당사자 직거래 — 회사 절대 미개입, 사고 시 자기책임.
// QTA 거래는 즉시 자동 송금, 에스크로우 없음.
export const ESCROW_MAX_AMOUNT_KRW = 30_000;

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
// 상품 거래 결제 (구매자 → 판매자, QTA 이체)
// ────────────────────────────────────────────────────────────────────────

export type PaymentResult =
  | { ok: true; charged: number; already_paid?: false }
  | { ok: true; charged: number; already_paid: true }
  | { ok: false; error: string; reason: 'insufficient' | 'invalid' | 'failed' };

/**
 * 상품 거래 결제. 판매자가 거래완료 토글하면 호출.
 *
 *   - amount=0 이면 결제 없음 (KRW 거래) → ok:true, charged:0
 *   - amount>0 이면 buyer 잔액에서 차감하고 seller 잔액에 가산 (1 batch)
 *   - 멱등 키 'trade_payment:<product_id>:debit' / ':credit' 가 둘 다
 *     UNIQUE 라 같은 상품에 두 번 결제되지 않는다.
 *   - buyer 잔액 부족 시 reason='insufficient' 로 실패.
 *
 * 호출 측 책임: status='sold' UPDATE 가 이미 끝난 다음에 호출하지 말고,
 * 결제가 성공한 다음 status 를 업데이트한다 (잔액 부족이면 거래 자체를 취소).
 */
export async function payTrade(
  env: Env,
  product_id: string,
  seller_id: string,
  buyer_id: string,
  amount: number,
): Promise<PaymentResult> {
  if (!amount || amount <= 0) {
    return { ok: true, charged: 0 };
  }
  if (!Number.isFinite(amount) || !Number.isInteger(amount)) {
    return { ok: false, error: '잘못된 결제 금액', reason: 'invalid' };
  }
  if (seller_id === buyer_id) {
    return { ok: false, error: '본인에게 결제할 수 없어요', reason: 'invalid' };
  }

  // 1) 멱등 — 이미 결제됐는지 ledger 의 buyer 차감 행으로 확인.
  const existed = await env.DB
    .prepare('SELECT 1 FROM qta_ledger WHERE idem_key = ? LIMIT 1')
    .bind(`trade_payment:${product_id}:debit`)
    .first<{ '1': number }>();
  if (existed) {
    return { ok: true, charged: amount, already_paid: true };
  }

  // 2) 잔액 확인 (커밋 전 사전 체크 — 동시성 보호는 batch UPDATE 의 WHERE 로).
  const buyerRow = await env.DB
    .prepare('SELECT qta_balance FROM users WHERE id = ?')
    .bind(buyer_id)
    .first<{ qta_balance: number }>();
  if (!buyerRow) {
    return { ok: false, error: '구매자 정보를 찾을 수 없어요', reason: 'invalid' };
  }
  if ((buyerRow.qta_balance ?? 0) < amount) {
    return {
      ok: false,
      error: `구매자의 QTA 잔액이 부족해요 (${buyerRow.qta_balance} < ${amount})`,
      reason: 'insufficient',
    };
  }

  // 3) ledger 2행 + 양쪽 잔액 UPDATE 를 한 batch 로.
  //    buyer UPDATE WHERE qta_balance >= amount 로 race 조건 차단.
  const debitId = crypto.randomUUID();
  const creditId = crypto.randomUUID();
  const meta = JSON.stringify({ product_id });

  try {
    const out = await env.DB.batch([
      env.DB
        .prepare(
          `INSERT INTO qta_ledger (id, user_id, amount, reason, idem_key, meta)
             VALUES (?, ?, ?, 'trade_payment_out', ?, ?)`,
        )
        .bind(debitId, buyer_id, -amount, `trade_payment:${product_id}:debit`, meta),
      env.DB
        .prepare(
          `UPDATE users
              SET qta_balance = qta_balance - ?, updated_at = datetime('now')
            WHERE id = ? AND qta_balance >= ?`,
        )
        .bind(amount, buyer_id, amount),
      env.DB
        .prepare(
          `INSERT INTO qta_ledger (id, user_id, amount, reason, idem_key, meta)
             VALUES (?, ?, ?, 'trade_payment_in', ?, ?)`,
        )
        .bind(creditId, seller_id, amount, `trade_payment:${product_id}:credit`, meta),
      env.DB
        .prepare(
          `UPDATE users
              SET qta_balance = qta_balance + ?, updated_at = datetime('now')
            WHERE id = ?`,
        )
        .bind(amount, seller_id),
    ]);

    // batch 안의 buyer UPDATE 가 0행이면 race 로 잔액 부족이 된 것.
    // D1 batch 결과는 각 statement 의 meta.changes 를 가지고 있음.
    const buyerUpdate = out[1];
    const changes = (buyerUpdate?.meta as { changes?: number } | undefined)?.changes ?? 1;
    if (changes === 0) {
      // 보정 — 가능한 한 ledger 정리. (실패해도 일관성을 깨지는 않음:
      // INSERT 가 batch 안이라 같이 롤백됐을 가능성이 큼.)
      return {
        ok: false,
        error: '결제 처리 중 잔액이 부족해졌어요. 잠시 후 다시 시도해주세요',
        reason: 'insufficient',
      };
    }
    return { ok: true, charged: amount };
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    if (/UNIQUE/i.test(msg)) {
      // race: 다른 호출이 먼저 결제 완료. → 멱등 처리.
      return { ok: true, charged: amount, already_paid: true };
    }
    console.error('[qta] payTrade failed', { product_id, msg });
    return { ok: false, error: '결제 실패 (서버 오류)', reason: 'failed' };
  }
}

// ────────────────────────────────────────────────────────────────────────
// 친구 초대 (referral) — 1명당 +200, 무제한
// ────────────────────────────────────────────────────────────────────────

/**
 * 신규 가입자(referee) 가 추천인 닉네임을 입력했을 때 호출.
 *  - inviter 와 referee 가 같으면 무시 (자기 자신 추천 방지)
 *  - referee_id UNIQUE → 동일 신규가 두 번 트리거되지 않도록 referrals 테이블이 보장
 *  - ledger.idem_key = 'referral:<referee_id>' 로 한번 더 방어
 *
 * 호출은 회원가입 트랜잭션 직후에 best-effort 로 실행. 실패해도 가입은 성공시킴.
 */
export async function grantReferralBonus(
  env: Env,
  inviter_id: string,
  referee_id: string,
): Promise<{ credited: boolean; reason?: string }> {
  if (!inviter_id || !referee_id) {
    return { credited: false, reason: 'missing_id' };
  }
  if (inviter_id === referee_id) {
    return { credited: false, reason: 'self_referral' };
  }

  const refId = crypto.randomUUID();
  const ledgerId = crypto.randomUUID();
  const idem = `referral:${referee_id}`;

  try {
    await env.DB.batch([
      // referrals 행 — referee_id UNIQUE 라 중복 시 실패 → 전체 롤백
      env.DB
        .prepare(
          `INSERT INTO referrals (id, inviter_id, referee_id, status, bonus_ledger_id)
             VALUES (?, ?, ?, 'granted', ?)`,
        )
        .bind(refId, inviter_id, referee_id, ledgerId),
      env.DB
        .prepare(
          `INSERT INTO qta_ledger (id, user_id, amount, reason, idem_key, meta)
             VALUES (?, ?, ?, 'referral_inviter', ?, ?)`,
        )
        .bind(
          ledgerId,
          inviter_id,
          QTA_REFERRAL_BONUS,
          idem,
          JSON.stringify({ referee_id }),
        ),
      env.DB
        .prepare(
          `UPDATE users SET qta_balance = qta_balance + ?, updated_at = datetime('now')
             WHERE id = ?`,
        )
        .bind(QTA_REFERRAL_BONUS, inviter_id),
    ]);
    return { credited: true };
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    if (/UNIQUE/i.test(msg)) {
      // 이미 처리됨 (referee_id 또는 idem_key 충돌)
      return { credited: false, reason: 'already_processed' };
    }
    console.error('[qta] referral bonus failed', msg);
    return { credited: false, reason: 'error' };
  }
}

/**
 * 탈퇴 시 referral 보너스 즉시 회수 (clawback).
 *
 * 회수 대상:
 *   1) 탈퇴자가 추천인(inviter)이었던 referrals → -200 each
 *   2) 탈퇴자가 referee 였던 referrals      → 추천인에게서 -200
 *
 * 각 회수는 ledger 1행 + qta_balance -= 200 으로 즉시 반영.
 * 멱등키: 'referral_clawback:<referrals.id>'
 *
 * 주의: users 행을 DELETE 하기 _직전_ 에 호출해야 함. (CASCADE 발동 전)
 */
export async function clawbackReferralsOnDelete(
  env: Env,
  user_id: string,
): Promise<{ inviter_clawbacks: number; referee_clawbacks: number }> {
  // 1) 탈퇴자가 inviter 였던 케이스 — 탈퇴자 자신에게서 회수
  //    (탈퇴자 행이 곧 사라지므로 자기 잔액 차감 → 어차피 의미 없지만, ledger 일관성을 위해 기록)
  //    실제로는 status='granted' 인 행만 대상.
  const asInviter = await env.DB
    .prepare(
      `SELECT id, referee_id FROM referrals
         WHERE inviter_id = ? AND status = 'granted'`,
    )
    .bind(user_id)
    .all<{ id: string; referee_id: string }>();

  // 2) 탈퇴자가 referee 였던 케이스 — 추천인에게서 회수
  const asReferee = await env.DB
    .prepare(
      `SELECT id, inviter_id FROM referrals
         WHERE referee_id = ? AND status = 'granted'`,
    )
    .bind(user_id)
    .all<{ id: string; inviter_id: string }>();

  const stmts: D1PreparedStatement[] = [];

  // ── inviter clawback: 탈퇴자 본인에게서 -200 each ──
  for (const row of asInviter.results || []) {
    const lid = crypto.randomUUID();
    stmts.push(
      env.DB
        .prepare(
          `INSERT INTO qta_ledger (id, user_id, amount, reason, idem_key, meta)
             VALUES (?, ?, ?, 'referral_clawback', ?, ?)`,
        )
        .bind(
          lid,
          user_id,
          -QTA_REFERRAL_BONUS,
          `referral_clawback:${row.id}`,
          JSON.stringify({ ref_id: row.id, role: 'inviter_self_delete' }),
        ),
      env.DB
        .prepare(
          `UPDATE users SET qta_balance = qta_balance - ?, updated_at = datetime('now')
             WHERE id = ?`,
        )
        .bind(QTA_REFERRAL_BONUS, user_id),
      env.DB
        .prepare(
          `UPDATE referrals
             SET status = 'clawed_back', clawback_ledger_id = ?, updated_at = datetime('now')
             WHERE id = ? AND status = 'granted'`,
        )
        .bind(lid, row.id),
    );
  }

  // ── referee clawback: 추천인에게서 -200 회수 ──
  for (const row of asReferee.results || []) {
    const lid = crypto.randomUUID();
    stmts.push(
      env.DB
        .prepare(
          `INSERT INTO qta_ledger (id, user_id, amount, reason, idem_key, meta)
             VALUES (?, ?, ?, 'referral_clawback', ?, ?)`,
        )
        .bind(
          lid,
          row.inviter_id,
          -QTA_REFERRAL_BONUS,
          `referral_clawback:${row.id}`,
          JSON.stringify({ ref_id: row.id, role: 'referee_deleted' }),
        ),
      env.DB
        .prepare(
          `UPDATE users SET qta_balance = qta_balance - ?, updated_at = datetime('now')
             WHERE id = ?`,
        )
        .bind(QTA_REFERRAL_BONUS, row.inviter_id),
      env.DB
        .prepare(
          `UPDATE referrals
             SET status = 'clawed_back', clawback_ledger_id = ?, updated_at = datetime('now')
             WHERE id = ? AND status = 'granted'`,
        )
        .bind(lid, row.id),
    );
  }

  if (stmts.length > 0) {
    try {
      await env.DB.batch(stmts);
    } catch (e) {
      // best-effort. 일부 idem 충돌 시에도 다음 단계(account delete)는 진행.
      console.error('[qta] referral clawback failed', String((e as Error)?.message || e));
    }
  }

  return {
    inviter_clawbacks: asInviter.results?.length ?? 0,
    referee_clawbacks: asReferee.results?.length ?? 0,
  };
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

/**
 * 출금 신청을 'processing' 상태로 전환. 운영자가 외부 송금을 시작할 때 호출.
 *
 *   requested → processing
 *
 * 잔액에는 영향 없음 (이미 requestWithdrawal 에서 차감됨).
 */
export async function processWithdrawal(
  env: Env,
  withdrawal_id: string,
): Promise<{ ok: boolean; error?: string }> {
  const w = await env.DB
    .prepare('SELECT id, status FROM qta_withdrawals WHERE id = ?')
    .bind(withdrawal_id)
    .first<{ id: string; status: string }>();
  if (!w) return { ok: false, error: 'not found' };
  if (w.status !== 'requested') {
    return { ok: false, error: `이미 처리되고 있거나 종료됐어요 (${w.status})` };
  }
  await env.DB
    .prepare(
      `UPDATE qta_withdrawals
          SET status = 'processing', processed_at = datetime('now')
        WHERE id = ?`,
    )
    .bind(withdrawal_id)
    .run();
  return { ok: true };
}

/**
 * 출금 완료 처리. 운영자가 외부 송금을 마치고 tx_hash 를 기록할 때 호출.
 *
 *   requested | processing → completed
 *
 * tx_hash 는 외부 체인의 트랜잭션 해시(또는 내부 송금 영수증). UNIQUE 제약은
 * 없으므로 운영자가 실수로 두 신청에 같은 tx_hash 를 쓸 수도 있다 — UI 측에서
 * 중복 검증 권장.
 */
export async function completeWithdrawal(
  env: Env,
  withdrawal_id: string,
  tx_hash: string,
): Promise<{ ok: boolean; error?: string }> {
  if (!tx_hash || !tx_hash.trim()) {
    return { ok: false, error: 'tx_hash 가 비어 있어요' };
  }
  const w = await env.DB
    .prepare('SELECT id, status FROM qta_withdrawals WHERE id = ?')
    .bind(withdrawal_id)
    .first<{ id: string; status: string }>();
  if (!w) return { ok: false, error: 'not found' };
  if (w.status !== 'requested' && w.status !== 'processing') {
    return { ok: false, error: `완료할 수 없는 상태에요 (${w.status})` };
  }
  await env.DB
    .prepare(
      `UPDATE qta_withdrawals
          SET status = 'completed',
              processed_at = COALESCE(processed_at, datetime('now')),
              tx_hash = ?
        WHERE id = ?`,
    )
    .bind(tx_hash.trim(), withdrawal_id)
    .run();
  return { ok: true };
}

