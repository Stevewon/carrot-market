/**
 * 지갑 인증 — 본사가 5.xxxxxx 를 보내고, 회원이 1.xxxxxx 를 본사로 돌려보낸다 (migration 0029·0036).
 *
 * 1) createReceiveChallenge: 보낼 수량 5.000000~5.999999 와 돌려받을 수량 1.000000~1.999999 를
 *    임의로 정하고 송금 대기열(send_status='queued')에 넣는다.
 * 2) processReceiveSends: 본사 지갑(WALLET_VERIFY_ADDRESS)에서 5.xxxxxx 를 회원 지갑으로 보낸다
 *    (돌려보낼 때 쓸 수량 + 가스비). SPHINCS+ 서명이 무거워 한 번에 한 건씩 — 요청 직후와 1분 cron.
 * 3) confirmReceive: 회원 지갑 → 본사 지갑으로 1.xxxxxx 가 정확히 들어왔는지 블록 탐색기에서 찾는다.
 *
 * 보안: 본사가 보낸 수량은 scan 에 공개되므로 증명이 안 된다. 증명은 "그 지갑에서 나간 송금"뿐 —
 * 지갑 주인만 보낼 수 있다. 돌려받을 수량은 요청한 회원(기기)에게만 알려준다. 한 번 쓰면 끝.
 *
 * 송금 지갑 (큐알쳇 신규회원 자동 송금과 같은 방식):
 *   가지 서버 전용 송금 지갑. 비밀문구는 Workers 비밀값 HQ_WALLET_MNEMONIC 에만 있고(생성 즉시
 *   비밀값으로 들어가 사람·AI 누구도 보지 않음), 주소는 WALLET_VERIFY_ADDRESS.
 *   사장님은 이 주소로 QTA 를 입금만 한다. 잔액이 모자라면 송금이 대기로 남는다.
 */

import type { Env } from './types';
import { trl, type Lang } from './market';
import {
  deriveAccountFromMnemonic,
  fromHex,
  isValidMnemonic,
  signSphincsTx,
  toChecksumAddress,
  toHex,
} from './chain/qta-sphincs';
import { getNativeBalance, getNonce, sendRawTransaction, suggestFees, type EvmRpcConfig } from './chain/qta-evm';
import { keccak_256 } from '@noble/hashes/sha3.js';
import { listOutgoingTxs } from './walletProof';

const RECEIVE_TTL_HOURS = 2;           // 요청 후 돌려보내기까지 허용 시간
const MAX_CONFIRM_ATTEMPTS = 5;        // (예전 수량 입력 방식 — 남은 기회 표시용)
const SEND_UNITS_BASE = 5_000_000;     // 본사가 보내는 수량 5.xxxxxx
const RETURN_UNITS_BASE = 1_000_000;   // 회원이 돌려보내는 수량 1.xxxxxx
const MAX_SENDS_PER_DAY = 100;         // 본사 송금 전체 하루 상한 (5 QTA × 100)
const CHECK_COOLDOWN_SEC = 5;          // 블록 탐색기 조회 최소 간격
const MAX_SEND_ATTEMPTS = 3;           // 송금 실패 재시도
const SENDING_LEASE_MIN = 3;           // 'sending' 이 이보다 오래 멈춰 있으면 회수
const MAX_PER_USER_DAY = 3;            // 회원 1명당 하루 송금 요청 수
const MAX_PER_WALLET_DAY = 3;          // 지갑 1개당 하루 송금 요청 수
const MAX_PER_IP_DAY = 10;             // IP 1개당 하루 송금 요청 수
const DECIMALS = 6;
const WEI_PER_UNIT = 10n ** 12n;       // 0.000001 QTA (18 decimals)
const GAS_LIMIT = 100_000n;            // 거래소 자동반환과 같은 값
const DEFAULT_RPC = 'https://rpc.quantarium.io';
const DEFAULT_CHAIN_ID = 60000;

export interface ReceiveRow {
  id: string;
  user_id: string;
  wallet_address: string;
  amount_wei: string;
  amount_display: string;
  status: 'pending' | 'verified' | 'used';
  send_status: 'queued' | 'sending' | 'sent' | 'failed' | null;
  send_tx_hash: string | null;
  send_started_at: string | null;
  send_error: string | null;
  send_attempts: number;
  confirm_attempts: number;
  return_amount_wei: string | null;
  return_amount_display: string | null;
  tx_hash: string | null;
  last_checked_at: string | null;
  created_at: string;
  expires_at: string;
}

/** 5234567 → '5.234567' */
function unitsDisplay(units: number): string {
  return `${Math.floor(units / 1_000_000)}.${String(units % 1_000_000).padStart(DECIMALS, '0')}`;
}

function sqliteUtcMs(s: string): number {
  return Date.parse(s.replace(' ', 'T') + 'Z');
}

export function hqAddress(env: Env): string {
  return (env.WALLET_VERIFY_ADDRESS || '').trim().toLowerCase();
}

function hasLocalKey(env: Env): boolean {
  return !!(env.HQ_WALLET_MNEMONIC || '').trim() || !!(env.HQ_WALLET_SECRET_KEY || '').trim();
}


/** 클라이언트용 — 요청한 회원(기기)에게만 내려간다. 돌려보낼 수량은 본사 송금이 끝난 뒤에 알려준다. */
export function receiveView(row: ReceiveRow, env: Env) {
  const sent = row.send_status === 'sent';
  return {
    challenge_id: row.id,
    wallet_address: row.wallet_address,
    send_from: hqAddress(env),
    send_amount: sent ? row.amount_display : null,
    return_amount: sent ? row.return_amount_display : null,
    return_to: hqAddress(env),
    decimals: DECIMALS,
    send_status: row.send_status || 'queued',
    send_tx_hash: row.send_tx_hash,
    status: row.status,
    expires_at: row.expires_at,
    attempts_left: Math.max(0, MAX_CONFIRM_ATTEMPTS - (row.confirm_attempts || 0)),
  };
}

// ── 본사 지갑 서명키 ─────────────────────────────────────────────

interface Signer { address: string; publicKey: Uint8Array; secretKey: Uint8Array }
let cachedSigner: { key: string; signer: Signer } | null = null;

/**
 * HQ_WALLET_MNEMONIC(+HQ_WALLET_INDEX) 또는 HQ_WALLET_SECRET_KEY(SPHINCS+ 64바이트 hex).
 * 만든 주소가 WALLET_VERIFY_ADDRESS 와 다르면 보내지 않는다.
 */
export function hqSigner(env: Env): { ok: true; signer: Signer } | { ok: false; reason: string } {
  const expected = hqAddress(env);
  if (!expected) return { ok: false, reason: 'no_verify_address' };
  const mnemonic = (env.HQ_WALLET_MNEMONIC || '').trim();
  const skHex = (env.HQ_WALLET_SECRET_KEY || '').trim().replace(/^0x/, '');
  const index = Number(env.HQ_WALLET_INDEX || '0') || 0;
  const cacheKey = `${expected}|${index}|${mnemonic ? 'm' : ''}|${skHex.length}`;
  if (cachedSigner && cachedSigner.key === cacheKey) return { ok: true, signer: cachedSigner.signer };

  let signer: Signer;
  if (mnemonic) {
    if (!isValidMnemonic(mnemonic)) return { ok: false, reason: 'invalid_mnemonic' };
    const acc = deriveAccountFromMnemonic(mnemonic, index);
    signer = { address: acc.address, publicKey: acc.publicKey, secretKey: acc.secretKey };
  } else if (/^[0-9a-fA-F]{128}$/.test(skHex)) {
    // SLH-DSA-SHA2-128s: sk = SK.seed‖SK.prf‖PK.seed‖PK.root, pk = 뒤 32바이트.
    const secretKey = fromHex(skHex);
    const publicKey = secretKey.slice(32);
    const address = toChecksumAddress(toHex(keccak_256(publicKey).slice(-20)));
    signer = { address, publicKey, secretKey };
  } else {
    return { ok: false, reason: 'no_signing_key' };
  }
  if (signer.address.toLowerCase() !== expected) return { ok: false, reason: 'key_address_mismatch' };
  cachedSigner = { key: cacheKey, signer };
  return { ok: true, signer };
}

/** 송금 기능이 켜져 있는지 (키·주소 설정 여부만, 서명은 안 함). */
export function receiveEnabled(env: Env): boolean {
  return !!hqAddress(env) && hasLocalKey(env);
}

// ── 1) 요청 ─────────────────────────────────────────────────────

/** verify = 로그인 회원의 지갑 등록 · reset = 비밀번호 재설정(계정 찾기) 때 가입 지갑 소유 확인. */
export type ReceivePurpose = 'verify' | 'reset';

export type CreateReceiveResult =
  | { ok: true; row: ReceiveRow }
  | { ok: false; status: 409 | 429 | 503; error: string; code: string };

export async function createReceiveChallenge(
  env: Env,
  userId: string,
  deviceUuid: string,
  walletLower: string,
  clientIp = '',
  lang: Lang = 'ko',
  purpose: ReceivePurpose = 'verify',
): Promise<CreateReceiveResult> {
  if (!receiveEnabled(env)) {
    return { ok: false, status: 503, error: trl(lang, '지갑 인증 송금을 준비 중이에요. 잠시 후 다시 시도해주세요', 'ウォレット認証の送金を準備中です。しばらくしてから再度お試しください', 'Wallet verification transfers are being prepared. Please try again in a moment'), code: 'sender_not_ready' };
  }
  if (walletLower === hqAddress(env)) {
    return { ok: false, status: 409, error: trl(lang, '이 주소는 등록할 수 없어요', 'このアドレスは登録できません', "This address can't be registered"), code: 'wallet_reserved' };
  }

  // 같은 회원·지갑·기기·용도로 아직 살아 있는 요청이 있으면 그대로 (다시 보내지 않음).
  const existing = await env.DB
    .prepare(
      `SELECT * FROM wallet_challenges
        WHERE direction = 'to_user' AND user_id = ? AND wallet_address = ?
          AND purpose = ? AND device_uuid = ?
          AND status = 'pending' AND send_status != 'failed'
          AND expires_at > datetime('now') AND confirm_attempts < ?
        ORDER BY created_at DESC LIMIT 1`,
    )
    .bind(userId, walletLower, purpose, deviceUuid, MAX_CONFIRM_ATTEMPTS)
    .first<ReceiveRow>();
  if (existing) return { ok: true, row: existing };

  const counts = await env.DB
    .prepare(
      `SELECT
         (SELECT COUNT(*) FROM wallet_challenges WHERE direction = 'to_user' AND user_id = ?
            AND created_at > datetime('now', '-1 day')) AS per_user,
         (SELECT COUNT(*) FROM wallet_challenges WHERE direction = 'to_user' AND wallet_address = ?
            AND created_at > datetime('now', '-1 day')) AS per_wallet,
         (SELECT COUNT(*) FROM wallet_challenges WHERE direction = 'to_user' AND client_ip = ? AND ? != ''
            AND created_at > datetime('now', '-1 day')) AS per_ip`,
    )
    .bind(userId, walletLower, clientIp, clientIp)
    .first<{ per_user: number; per_wallet: number; per_ip: number }>();
  const today = await env.DB
    .prepare(
      `SELECT COUNT(*) AS n FROM wallet_challenges WHERE direction = 'to_user'
          AND send_status IN ('queued', 'sending', 'sent') AND created_at > datetime('now', '-1 day')`,
    )
    .first<{ n: number }>();
  if ((today?.n ?? 0) >= MAX_SENDS_PER_DAY) {
    return {
      ok: false,
      status: 429,
      error: trl(lang, '오늘 지갑 인증 요청이 많아 잠시 멈췄어요. 내일 다시 시도해주세요', '本日のウォレット認証リクエストが多いため一時停止しています。明日再度お試しください', "There are too many wallet verification requests today, so we've paused them. Please try again tomorrow"),
      code: 'daily_cap',
    };
  }
  if ((counts?.per_user ?? 0) >= MAX_PER_USER_DAY
    || (counts?.per_wallet ?? 0) >= MAX_PER_WALLET_DAY
    || (counts?.per_ip ?? 0) >= MAX_PER_IP_DAY) {
    return {
      ok: false,
      status: 429,
      error: trl(lang, '오늘 지갑 인증 요청을 너무 많이 했어요. 내일 다시 시도해주세요', '本日のウォレット認証リクエストの上限に達しました。明日再度お試しください', "You've reached today's limit for wallet verification requests. Please try again tomorrow"),
      code: 'too_many_requests',
    };
  }

  // 보낼 수량 5.000000~5.999999, 돌려받을 수량 1.000000~1.999999 (단위 0.000001 QTA)
  const buf = new Uint32Array(2);
  crypto.getRandomValues(buf);
  const units = SEND_UNITS_BASE + (buf[0] % 1_000_000);
  const returnUnits = RETURN_UNITS_BASE + (buf[1] % 1_000_000);
  const amountWei = (BigInt(units) * WEI_PER_UNIT).toString();
  const amountDisplay = unitsDisplay(units);
  const returnWei = (BigInt(returnUnits) * WEI_PER_UNIT).toString();
  const returnDisplay = unitsDisplay(returnUnits);

  const id = crypto.randomUUID();
  await env.DB
    .prepare(
      `INSERT INTO wallet_challenges
         (id, wallet_address, purpose, device_uuid, amount_wei, amount_display, expires_at, client_ip,
          direction, user_id, send_status, return_amount_wei, return_amount_display)
       VALUES (?, ?, ?, ?, ?, ?, datetime('now', ?), ?, 'to_user', ?, 'queued', ?, ?)`,
    )
    .bind(id, walletLower, purpose, deviceUuid, amountWei, amountDisplay, `+${RECEIVE_TTL_HOURS} hours`, clientIp || null, userId,
      returnWei, returnDisplay)
    .run();
  const row = await env.DB.prepare('SELECT * FROM wallet_challenges WHERE id = ?').bind(id).first<ReceiveRow>();
  return { ok: true, row: row! };
}

export async function getReceiveChallenge(
  env: Env,
  userId: string,
  id: string,
  purpose: ReceivePurpose = 'verify',
): Promise<ReceiveRow | null> {
  return env.DB
    .prepare(`SELECT * FROM wallet_challenges WHERE id = ? AND user_id = ? AND direction = 'to_user' AND purpose = ?`)
    .bind(id, userId, purpose)
    .first<ReceiveRow>();
}

// ── 2) 본사 지갑 송금 ────────────────────────────────────────────

async function rpc<T>(url: string, method: string, params: unknown[]): Promise<T> {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  });
  if (!res.ok) throw new Error(`RPC ${method} HTTP ${res.status}`);
  const j = (await res.json()) as { result?: T; error?: { message: string } };
  if (j.error) throw new Error(`RPC ${method} error: ${j.error.message}`);
  return j.result as T;
}

export interface SendTickResult { picked: number; id?: string; tx_hash?: string; reason?: string }

/**
 * 대기열에서 한 건을 골라 본사 지갑에서 보낸다. 동시에 두 건이 서명·전송되지 않도록
 * 'sending' 중인 행이 있으면 아무것도 하지 않는다 (nonce 충돌 방지).
 */
export async function processReceiveSends(env: Env): Promise<SendTickResult> {
  if (!receiveEnabled(env)) return { picked: 0, reason: 'sender_not_ready' };
  const cfg: EvmRpcConfig = {
    rpcUrl: env.QTA_RPC_URL || DEFAULT_RPC,
    chainId: Number(env.QTA_CHAIN_ID || DEFAULT_CHAIN_ID) || DEFAULT_CHAIN_ID,
  };

  // 오래 멈춘 'sending' 회수: 거래가 체인에 있으면 sent, 없으면 다시 대기열로.
  const stuck = await env.DB
    .prepare(
      `SELECT * FROM wallet_challenges
        WHERE direction = 'to_user' AND send_status = 'sending'
          AND send_started_at < datetime('now', ?)`,
    )
    .bind(`-${SENDING_LEASE_MIN} minutes`)
    .all<ReceiveRow>();
  for (const s of stuck.results || []) {
    let onChain = false;
    if (s.send_tx_hash) {
      try { onChain = !!(await rpc<unknown>(cfg.rpcUrl, 'eth_getTransactionByHash', [s.send_tx_hash])); } catch { /* 다음 tick */ continue; }
    }
    const attempts = (s.send_attempts || 0) + (onChain ? 0 : 1);
    const next = onChain ? 'sent' : attempts >= MAX_SEND_ATTEMPTS ? 'failed' : 'queued';
    await env.DB
      .prepare(
        `UPDATE wallet_challenges SET send_status = ?, send_attempts = ?,
                send_tx_hash = CASE WHEN ? = 'sent' THEN send_tx_hash ELSE NULL END
          WHERE id = ? AND send_status = 'sending'`,
      )
      .bind(next, attempts, next, s.id)
      .run();
  }

  // 한 건 점유 — 다른 'sending' 이 없을 때만.
  const pick = await env.DB
    .prepare(
      `UPDATE wallet_challenges
          SET send_status = 'sending', send_started_at = datetime('now')
        WHERE id = (
                SELECT id FROM wallet_challenges
                 WHERE direction = 'to_user' AND send_status = 'queued' AND status = 'pending'
                   AND expires_at > datetime('now')
                 ORDER BY created_at ASC LIMIT 1)
          AND send_status = 'queued'
          AND NOT EXISTS (SELECT 1 FROM wallet_challenges WHERE direction = 'to_user' AND send_status = 'sending')
        RETURNING *`,
    )
    .first<ReceiveRow>();
  if (!pick) return { picked: 0 };

  const fail = async (reason: string, terminal: boolean) => {
    const attempts = (pick.send_attempts || 0) + 1;
    const next = terminal || attempts >= MAX_SEND_ATTEMPTS ? 'failed' : 'queued';
    await env.DB
      .prepare(
        `UPDATE wallet_challenges SET send_status = ?, send_attempts = ?, send_error = ?, send_tx_hash = NULL
          WHERE id = ? AND send_status = 'sending'`,
      )
      .bind(next, attempts, reason.slice(0, 300), pick.id)
      .run();
    console.error('[wallet-receive] send failed', pick.id, reason);
    return { picked: 1, id: pick.id, reason };
  };

  const s = hqSigner(env);
  if (!s.ok) return fail(s.reason, true);
  const signer = s.signer;
  const value = BigInt(pick.amount_wei);

  try {
    const [nonce, fees, balance] = await Promise.all([
      getNonce(cfg, signer.address),
      suggestFees(cfg),
      getNativeBalance(cfg, signer.address),
    ]);
    if (balance < value + GAS_LIMIT * fees.maxFeePerGas) {
      return fail(`hq_wallet_insufficient: have ${balance} need ${value + GAS_LIMIT * fees.maxFeePerGas}`, false);
    }
    const { rawTx, txHash } = signSphincsTx(
      {
        chainId: cfg.chainId,
        nonce,
        maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
        maxFeePerGas: fees.maxFeePerGas,
        gasLimit: GAS_LIMIT,
        to: toChecksumAddress(pick.wallet_address),
        value,
        data: '0x',
      },
      signer.publicKey,
      signer.secretKey,
    );
    // 전송 전에 해시를 남겨 둔다 — 전송 직후 죽어도 회수 단계에서 체인 확인 가능.
    await env.DB
      .prepare(`UPDATE wallet_challenges SET send_tx_hash = ? WHERE id = ? AND send_status = 'sending'`)
      .bind(txHash, pick.id)
      .run();
    let finalHash = txHash;
    try {
      finalHash = await sendRawTransaction(cfg, rawTx);
    } catch (e) {
      const msg = String((e as Error)?.message || e);
      if (!/already known/i.test(msg)) throw e;
    }
    await env.DB
      .prepare(
        `UPDATE wallet_challenges SET send_status = 'sent', send_tx_hash = ?, send_error = NULL
          WHERE id = ? AND send_status = 'sending'`,
      )
      .bind(finalHash, pick.id)
      .run();
    console.log(`[wallet-receive] sent ${pick.amount_display} QTA → ${pick.wallet_address} tx=${finalHash}`);
    return { picked: 1, id: pick.id, tx_hash: finalHash };
  } catch (e) {
    return fail('send_failed: ' + String((e as Error)?.message || e), false);
  }
}

// ── 3) 수량 입력 확인 ────────────────────────────────────────────

/** '0.234567', '.234567', '234567', '0.234567 QTA' → '234567'. 형식이 다르면 null. */
export function normalizeAmountInput(input: string): string | null {
  const s = String(input || '').replace(/qta/gi, '').replace(/\s+/g, '');
  let m = /^0?\.(\d{1,6})$/.exec(s);
  if (m) return m[1].padEnd(DECIMALS, '0');
  m = /^(\d{6})$/.exec(s);
  if (m) return m[1];
  return null;
}

export type ConfirmResult =
  | { ok: true; row: ReceiveRow }
  | { ok: false; status: 400 | 404 | 409 | 410 | 429 | 502; error: string; code: string; attempts_left?: number };

/**
 * 회원 지갑 → 본사 지갑으로 돌려보낸 1.xxxxxx 를 블록 탐색기에서 찾는다.
 * [_input] 은 예전 앱(받은 수량 입력)과 호환하려고 받기만 하고 쓰지 않는다.
 */
export async function confirmReceive(
  env: Env,
  userId: string,
  id: string,
  _input: string,
  lang: Lang = 'ko',
  purpose: ReceivePurpose = 'verify',
): Promise<ConfirmResult> {
  const row = await getReceiveChallenge(env, userId, id, purpose);
  if (!row) return { ok: false, status: 404, error: trl(lang, '인증 요청을 찾을 수 없어요', '認証リクエストが見つかりません', "We couldn't find this verification request"), code: 'not_found' };
  if (row.status !== 'pending') {
    return { ok: false, status: 409, error: trl(lang, '이미 끝난 인증이에요. 처음부터 다시 진행해주세요', 'この認証はすでに終了しています。最初からやり直してください', 'This verification has already ended. Please start over'), code: 'used' };
  }
  if (sqliteUtcMs(row.expires_at) < Date.now() || !row.return_amount_wei) {
    return { ok: false, status: 410, error: trl(lang, '인증 시간이 지났어요. 다시 요청해주세요', '認証の有効期限が切れました。再度リクエストしてください', 'Verification has expired. Please request again'), code: 'expired' };
  }
  if (row.send_status !== 'sent') {
    return {
      ok: false,
      status: 409,
      error: row.send_status === 'failed'
        ? trl(lang, '본사 지갑 송금에 실패했어요. 다시 요청해주세요', '運営ウォレットからの送金に失敗しました。再度リクエストしてください', 'The transfer from the Eggplant wallet failed. Please request again')
        : trl(lang, '아직 본사 지갑에서 보내는 중이에요. 잠시 후 다시 확인해주세요', '運営ウォレットから送金中です。しばらくしてから再度ご確認ください', 'The Eggplant wallet is still sending. Please check again in a moment'),
      code: row.send_status === 'failed' ? 'send_failed' : 'not_sent_yet',
    };
  }
  if (row.last_checked_at && Date.now() - sqliteUtcMs(row.last_checked_at) < CHECK_COOLDOWN_SEC * 1000) {
    return { ok: false, status: 429, error: trl(lang, '잠시 후 다시 확인해주세요', 'しばらくしてから再度ご確認ください', 'Please check again in a moment'), code: 'cooldown' };
  }
  await env.DB.prepare(`UPDATE wallet_challenges SET last_checked_at = datetime('now') WHERE id = ?`).bind(row.id).run();

  let txs: Awaited<ReturnType<typeof listOutgoingTxs>>;
  try {
    txs = await listOutgoingTxs(env, row.wallet_address);
  } catch (e) {
    console.error('[wallet-receive] explorer failed', String((e as Error)?.message || e));
    return { ok: false, status: 502, error: trl(lang, '블록 탐색기에 연결하지 못했어요. 잠시 후 다시 시도해주세요', 'ブロックエクスプローラーに接続できませんでした。しばらくしてから再度お試しください', "We couldn't connect to the block explorer. Please try again in a moment"), code: 'explorer_error' };
  }
  const hq = hqAddress(env);
  // 요청 "전에" 체인에 오른 거래는 인정하지 않는다 (시계 오차 5초).
  const notBefore = sqliteUtcMs(row.created_at) - 5_000;
  const match = txs.find((t) => {
    let value = '';
    try { value = BigInt(t.value || '0').toString(); } catch { value = ''; }
    const ts = t.timestamp ? Date.parse(t.timestamp) : NaN;
    return t.status === 'ok'
      && (t.from?.hash || '').toLowerCase() === row.wallet_address
      && (t.to?.hash || '').toLowerCase() === hq
      && value === row.return_amount_wei
      && Number.isFinite(ts) && ts >= notBefore;
  });
  if (!match) {
    return {
      ok: false,
      status: 404,
      error: trl(
        lang,
        `아직 돌려보낸 송금이 확인되지 않았어요. 내 지갑에서 ${row.return_amount_display} QTA 를 가지 본사 지갑(${hq})으로 보낸 뒤, 블록에 담길 때까지 잠시 기다려주세요`,
        `まだ返送を確認できていません。ご自身のウォレットから ${row.return_amount_display} QTA を Eggplant 本社ウォレット(${hq})へ送金し、ブロックに取り込まれるまでしばらくお待ちください`,
        `We haven't found your return transfer yet. Send ${row.return_amount_display} QTA from your wallet to the Eggplant HQ wallet (${hq}), then wait a moment until it's included in a block`,
      ),
      code: 'not_found_yet',
    };
  }
  // reset 은 'verified' 로 두고, 비밀번호 재설정(consumeChallenge)이 'used' 로 바꾼다.
  let done: ReceiveRow | null;
  try {
    done = await env.DB
      .prepare(
        purpose === 'reset'
          ? `UPDATE wallet_challenges SET status = 'verified', tx_hash = ?, verified_at = datetime('now')
              WHERE id = ? AND status = 'pending' RETURNING *`
          : `UPDATE wallet_challenges SET status = 'used', tx_hash = ?, verified_at = datetime('now'), used_at = datetime('now')
              WHERE id = ? AND status = 'pending' RETURNING *`,
      )
      .bind(match.hash.toLowerCase(), row.id)
      .first<ReceiveRow>();
  } catch (e) {
    if (/UNIQUE/i.test(String((e as Error)?.message || e))) {
      return { ok: false, status: 409, error: trl(lang, '이미 다른 인증에 쓰인 거래예요. 다시 요청해서 새 수량으로 보내주세요', 'この取引はすでに別の認証に使用されています。再度リクエストして新しい数量で送金してください', 'This transaction was already used for another verification. Please request again and send the new amount'), code: 'tx_reused' };
    }
    throw e;
  }
  if (!done) return { ok: false, status: 409, error: trl(lang, '이미 끝난 인증이에요', 'この認証はすでに終了しています', 'This verification has already ended'), code: 'used' };
  return { ok: true, row: done };
}
