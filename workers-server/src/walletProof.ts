/**
 * 지갑 소유 증명 — 소액 송금 인증 (migration 0027).
 *
 * 1) createChallenge: 고유 소액(0.00000001~0.09999999 QTA, 소수 8자리)을 발급.
 * 2) 사용자가 그 지갑에서 정확히 그 금액을 송금. 받는 곳은 본인 지갑(자기송금)
 *    또는 WALLET_VERIFY_ADDRESS(설정된 경우).
 * 3) checkChallenge: Quantarium Blockscout 익스플로러에서 "그 지갑이 보낸"
 *    거래를 찾아 확인. from 이 그 지갑인 거래는 개인키 소유자만 만들 수 있다.
 * 4) consumeChallenge: 가입/비밀번호 재설정에서 1회 사용 처리.
 *
 * Quantarium 거래는 SPHINCS+ typed tx(0x7f) 라 원시 블록을 직접 파싱하지 않고,
 * 거래소(exchange/cron-worker/src/lib/qta-explorer.ts)와 같이 익스플로러가
 * 정규화한 JSON(hash/value/from/to/status/timestamp)을 읽는다.
 */

import type { Env } from './types';
import { trl, type Lang } from './market';

export type WalletProofPurpose = 'register' | 'reset' | 'verify';

const CHALLENGE_TTL_MIN = 30;        // 발급 후 송금까지 허용 시간
const VERIFIED_USE_WINDOW_MIN = 60;  // 확인 후 가입/재설정까지 허용 시간
const CHECK_COOLDOWN_SEC = 5;        // 익스플로러 조회 최소 간격 (챌린지당)
const DEFAULT_EXPLORER = 'https://scan.quantarium.io';
const WEI_PER_UNIT = 10n ** 10n;     // 0.00000001 QTA (18 decimals)

export interface WalletChallengeRow {
  id: string;
  wallet_address: string;
  purpose: WalletProofPurpose;
  device_uuid: string;
  amount_wei: string;
  amount_display: string;
  status: 'pending' | 'verified' | 'used';
  tx_hash: string | null;
  created_at: string;
  expires_at: string;
  verified_at: string | null;
  used_at: string | null;
  last_checked_at: string | null;
  direction?: 'from_user' | 'to_user';
}

/** 클라이언트에 보여줄 챌린지 정보. */
export function challengeView(row: WalletChallengeRow, env: Env) {
  const verifyAddr = (env.WALLET_VERIFY_ADDRESS || '').trim().toLowerCase();
  return {
    challenge_id: row.id,
    wallet_address: row.wallet_address,
    amount: row.amount_display,
    amount_wei: row.amount_wei,
    // 받는 주소: 본사 인증 지갑(WALLET_VERIFY_ADDRESS). 지갑 앱이 자기 자신에게
    // 송금을 막는 경우가 있어 본사 지갑으로 받는다. 미설정이면 자기송금으로 안내.
    send_to: verifyAddr || row.wallet_address,
    alt_send_to: null,
    status: row.status,
    expires_at: row.expires_at,
  };
}

/** SQLite 'YYYY-MM-DD HH:MM:SS' (UTC) → epoch ms. */
function sqliteUtcMs(s: string): number {
  return Date.parse(s.replace(' ', 'T') + 'Z');
}

/** 지갑 하나에 동시에 열려 있을 수 있는 pending 챌린지 수 (목적·기기 무관). */
const MAX_PENDING_PER_WALLET = 3;
/** IP 하나가 동시에 열어 둘 수 있는 pending 챌린지 수 — 대량 발급·익스플로러 증폭 차단. */
const MAX_PENDING_PER_IP = 10;

export type CreateResult =
  | { ok: true; row: WalletChallengeRow }
  | { ok: false; status: 429; error: string; code: string };

/**
 * 같은 지갑·목적·기기로 아직 유효한 pending 챌린지가 있으면 재사용,
 * 없으면 새로 만든다.
 *
 * 금액 가로채기 방어: 공격자가 체인에 올라온 남의 자기송금 금액과 같은 금액이
 * 나올 때까지 챌린지를 반복 발급해 그 거래로 인증받는 공격이 가능했다(후보 999개).
 *   - 금액 후보를 1천만 개로 늘리고 (0.00000001 단위),
 *   - 같은 지갑의 pending 챌린지끼리 금액이 겹치지 않게 하고,
 *   - 지갑·IP 당 동시 pending 수를 제한하고,
 *   - 챌린지를 만들기 "전에" 올라온 거래는 인정하지 않는다 (checkChallenge).
 */
export async function createChallenge(
  env: Env,
  walletLower: string,
  purpose: WalletProofPurpose,
  deviceUuid: string,
  clientIp = '',
  lang: Lang = 'ko',
): Promise<CreateResult> {
  const existing = await env.DB
    .prepare(
      `SELECT * FROM wallet_challenges
        WHERE wallet_address = ? AND purpose = ? AND device_uuid = ?
          AND direction = 'from_user' AND status = 'pending' AND expires_at > datetime('now')
        ORDER BY created_at DESC LIMIT 1`,
    )
    .bind(walletLower, purpose, deviceUuid)
    .first<WalletChallengeRow>();
  if (existing) return { ok: true, row: existing };

  // 오래된 행 정리 (만료 후 하루 지난 것) — 테이블이 무한히 커지지 않게.
  await env.DB
    .prepare(`DELETE FROM wallet_challenges WHERE expires_at < datetime('now', '-1 day')`)
    .run();

  const counts = await env.DB
    .prepare(
      `SELECT
         (SELECT COUNT(*) FROM wallet_challenges
           WHERE wallet_address = ? AND direction = 'from_user' AND status = 'pending' AND expires_at > datetime('now')) AS per_wallet,
         (SELECT COUNT(*) FROM wallet_challenges
           WHERE client_ip = ? AND ? != '' AND direction = 'from_user' AND status = 'pending' AND expires_at > datetime('now')) AS per_ip`,
    )
    .bind(walletLower, clientIp, clientIp)
    .first<{ per_wallet: number; per_ip: number }>();
  if ((counts?.per_wallet ?? 0) >= MAX_PENDING_PER_WALLET || (counts?.per_ip ?? 0) >= MAX_PENDING_PER_IP) {
    return {
      ok: false,
      status: 429,
      error: trl(lang, '진행 중인 지갑 인증이 너무 많아요. 30분 뒤에 다시 시도해주세요', '処理中のウォレット認証が多すぎます。30分後に再度お試しください'),
      code: 'too_many_challenges',
    };
  }

  // 1..9,999,999 × 0.00000001 QTA → 0.00000001 ~ 0.09999999 QTA.
  // 자기송금이라 돌아오지만 잔액이 금액+가스비 이상이어야 하므로 0.1 미만 유지.
  // 같은 지갑의 열린 챌린지와 금액이 겹치면 다시 뽑는다.
  let units = 0;
  for (let i = 0; i < 5; i++) {
    const buf = new Uint32Array(1);
    crypto.getRandomValues(buf);
    const candidate = (buf[0] % 9_999_999) + 1;
    const clash = await env.DB
      .prepare(
        `SELECT 1 FROM wallet_challenges
          WHERE wallet_address = ? AND amount_wei = ? AND status = 'pending' LIMIT 1`,
      )
      .bind(walletLower, (BigInt(candidate) * WEI_PER_UNIT).toString())
      .first();
    if (!clash) { units = candidate; break; }
  }
  if (!units) {
    return { ok: false, status: 429, error: trl(lang, '잠시 후 다시 시도해주세요', 'しばらくしてから再度お試しください'), code: 'amount_busy' };
  }
  const amountWei = (BigInt(units) * WEI_PER_UNIT).toString();
  const amountDisplay = `0.${String(units).padStart(8, '0')}`;

  const id = crypto.randomUUID();
  await env.DB
    .prepare(
      `INSERT INTO wallet_challenges
         (id, wallet_address, purpose, device_uuid, amount_wei, amount_display, expires_at, client_ip)
       VALUES (?, ?, ?, ?, ?, ?, datetime('now', ?), ?)`,
    )
    .bind(id, walletLower, purpose, deviceUuid, amountWei, amountDisplay, `+${CHALLENGE_TTL_MIN} minutes`, clientIp || null)
    .run();

  const row = await env.DB
    .prepare('SELECT * FROM wallet_challenges WHERE id = ?')
    .bind(id)
    .first<WalletChallengeRow>();
  return { ok: true, row: row! };
}

interface BsAddressRef { hash?: string | null }
interface BsTx {
  hash: string;
  value: string | null;
  from: BsAddressRef | null;
  to: BsAddressRef | null;
  status: string | null;
  result?: string | null;
  timestamp: string | null;
}
interface BsPage { items?: BsTx[]; next_page_params?: Record<string, unknown> | null }

/**
 * 그 지갑이 보낸(outgoing) 최근 거래 — 첫 페이지(최신 50건)만.
 * Quantarium 거래는 SPHINCS+ 서명(약 16KB)이 붙어 한 페이지가 ~870KB 라
 * 더 넘기지 않는다. 챌린지 유효시간(30분) 안의 송금은 첫 페이지에 있다.
 */
export async function listOutgoingTxs(env: Env, walletLower: string): Promise<BsTx[]> {
  const base = (env.QTA_EXPLORER_URL || DEFAULT_EXPLORER).replace(/\/+$/, '');
  const out: BsTx[] = [];
  let next: Record<string, unknown> | null = null;
  for (let page = 0; page < 1; page++) {
    const qs = new URLSearchParams({ filter: 'from' });
    if (next) for (const [k, v] of Object.entries(next)) qs.set(k, String(v));
    const res = await fetch(`${base}/api/v2/addresses/${walletLower}/transactions?${qs}`, {
      headers: { accept: 'application/json' },
    });
    if (res.status === 404) return out; // 거래가 한 번도 없는 주소
    if (!res.ok) throw new Error(`explorer ${res.status}`);
    const data = (await res.json()) as BsPage;
    out.push(...(data.items || []));
    next = data.next_page_params ?? null;
    if (!next) break;
  }
  return out;
}

export type CheckResult =
  | { ok: true; row: WalletChallengeRow }
  | { ok: false; status: 400 | 403 | 404 | 409 | 410 | 429 | 502; error: string; code: string };

/**
 * 익스플로러에서 송금을 찾아 챌린지를 verified 로 만든다.
 * 아직 안 보이면 code='not_found_yet' (클라이언트가 잠시 후 다시 시도).
 */
export async function checkChallenge(
  env: Env,
  challengeId: string,
  deviceUuid: string,
  lang: Lang = 'ko',
): Promise<CheckResult> {
  const row = await env.DB
    .prepare('SELECT * FROM wallet_challenges WHERE id = ?')
    .bind(challengeId)
    .first<WalletChallengeRow>();
  if (!row || row.direction === 'to_user') return { ok: false, status: 404, error: trl(lang, '인증 요청을 찾을 수 없어요', '認証リクエストが見つかりません'), code: 'not_found' };
  if (row.device_uuid !== deviceUuid) {
    return { ok: false, status: 403, error: trl(lang, '이 기기에서 만든 인증 요청이 아니에요', 'この端末で作成された認証リクエストではありません'), code: 'device_mismatch' };
  }
  if (row.status === 'verified') return { ok: true, row };
  if (row.status === 'used') {
    return { ok: false, status: 409, error: trl(lang, '이미 사용된 인증이에요. 처음부터 다시 진행해주세요', 'この認証はすでに使用されています。最初からやり直してください'), code: 'used' };
  }
  if (sqliteUtcMs(row.expires_at) < Date.now()) {
    return { ok: false, status: 410, error: trl(lang, '인증 시간이 지났어요. 새 금액을 받아 다시 진행해주세요', '認証の有効期限が切れました。新しい金額を受け取って再度お手続きください'), code: 'expired' };
  }
  if (row.last_checked_at && Date.now() - sqliteUtcMs(row.last_checked_at) < CHECK_COOLDOWN_SEC * 1000) {
    return { ok: false, status: 429, error: trl(lang, '잠시 후 다시 확인해주세요', 'しばらくしてから再度ご確認ください'), code: 'cooldown' };
  }
  await env.DB
    .prepare(`UPDATE wallet_challenges SET last_checked_at = datetime('now') WHERE id = ?`)
    .bind(row.id)
    .run();

  let txs: BsTx[];
  try {
    txs = await listOutgoingTxs(env, row.wallet_address);
  } catch (e) {
    console.error('[walletProof] explorer failed', String((e as Error)?.message || e));
    return { ok: false, status: 502, error: trl(lang, '블록 탐색기에 연결하지 못했어요. 잠시 후 다시 시도해주세요', 'ブロックエクスプローラーに接続できませんでした。しばらくしてから再度お試しください'), code: 'explorer_error' };
  }

  const verifyAddr = (env.WALLET_VERIFY_ADDRESS || '').trim().toLowerCase();

  // 챌린지를 만들기 "전에" 체인에 오른 거래는 인정하지 않는다 (시계 오차 5초만 허용).
  //   예전 60초 유예 때문에, 남의 자기송금을 보고 나서 같은 금액 챌린지를 뽑으면
  //   그 거래로 인증받을 수 있었다.
  const notBefore = sqliteUtcMs(row.created_at) - 5_000;
  const match = txs.find((t) => {
    const from = (t.from?.hash || '').toLowerCase();
    const to = (t.to?.hash || '').toLowerCase();
    // status 가 'ok' 인(성공·블록 포함) 거래만 인정. pending(null)·실패('error') 제외.
    const ok = t.status === 'ok';
    let value = '';
    try { value = BigInt(t.value || '0').toString(); } catch { value = ''; }
    const ts = t.timestamp ? Date.parse(t.timestamp) : NaN;
    return ok
      && from === row.wallet_address
      && (to === row.wallet_address || (!!verifyAddr && to === verifyAddr))
      && value === row.amount_wei
      && Number.isFinite(ts) && ts >= notBefore;
  });
  if (!match) {
    return {
      ok: false,
      status: 404,
      error: trl(lang, `아직 송금이 확인되지 않았어요. ${row.amount_display} QTA 를 보낸 뒤 블록에 담길 때까지 잠시 기다려주세요`, `まだ送金を確認できていません。${row.amount_display} QTA を送金後、ブロックに取り込まれるまでしばらくお待ちください`),
      code: 'not_found_yet',
    };
  }

  try {
    await env.DB
      .prepare(
        `UPDATE wallet_challenges
            SET status = 'verified', tx_hash = ?, verified_at = datetime('now')
          WHERE id = ? AND status = 'pending'`,
      )
      .bind(match.hash.toLowerCase(), row.id)
      .run();
  } catch (e) {
    if (/UNIQUE/i.test(String((e as Error)?.message || e))) {
      return { ok: false, status: 409, error: trl(lang, '이미 다른 인증에 쓰인 거래예요. 새 금액으로 다시 송금해주세요', 'この取引はすでに別の認証に使用されています。新しい金額で再度送金してください'), code: 'tx_reused' };
    }
    throw e;
  }

  const updated = await env.DB
    .prepare('SELECT * FROM wallet_challenges WHERE id = ?')
    .bind(row.id)
    .first<WalletChallengeRow>();
  if (!updated || updated.status === 'pending') {
    return { ok: false, status: 409, error: trl(lang, '인증 상태가 바뀌었어요. 다시 시도해주세요', '認証の状態が変更されました。再度お試しください'), code: 'conflict' };
  }
  return { ok: true, row: updated };
}

/**
 * verified 챌린지를 1회 사용 처리. 지갑·목적·기기가 모두 맞고, 확인 후
 * VERIFIED_USE_WINDOW_MIN 이내여야 한다. 원자적 UPDATE 라 같은 챌린지로
 * 두 번 가입/재설정할 수 없다.
 */
// 소유 증명 = 그 지갑에서 나간 송금. from_user(회원이 본사로 송금)와 to_user(본사가 보낸 뒤
// 회원이 1.xxxxxx 를 돌려보냄 — tx_hash 가 그 거래) 모두 그 거래가 있어야 verified 가 된다.
export async function consumeChallenge(
  env: Env,
  challengeId: string,
  walletLower: string,
  purpose: WalletProofPurpose,
  deviceUuid: string,
): Promise<boolean> {
  const res = await env.DB
    .prepare(
      `UPDATE wallet_challenges
          SET status = 'used', used_at = datetime('now')
        WHERE id = ? AND wallet_address = ? AND purpose = ? AND device_uuid = ?
          AND status = 'verified' AND tx_hash IS NOT NULL
          AND verified_at >= datetime('now', ?)`,
    )
    .bind(challengeId, walletLower, purpose, deviceUuid, `-${VERIFIED_USE_WINDOW_MIN} minutes`)
    .run();
  return (res.meta?.changes ?? 0) === 1;
}

/** 가입 INSERT 가 실패했을 때 챌린지를 다시 쓸 수 있게 되돌린다. */
export async function releaseChallenge(env: Env, challengeId: string): Promise<void> {
  await env.DB
    .prepare(`UPDATE wallet_challenges SET status = 'verified', used_at = NULL WHERE id = ? AND status = 'used'`)
    .bind(challengeId)
    .run();
}
