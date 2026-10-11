/**
 * 양자내성 송금 확인 — 퀀타리움 체인의 SPHINCS+ 서명 거래(type 0x7f)인지 RPC 로 확인한다.
 * scan.quantarium.io 는 이런 거래에 "Type 127 (SPHINCS+)" 와 SPHINCS+ 서명을 보여준다.
 * 일반 서명(ECDSA, type 0/2) 거래는 양자내성이 아니므로 받지 않는다.
 */

import type { Env } from '../types';

const DEFAULT_RPC = 'https://rpc.quantarium.io';
export const SPHINCS_TX_TYPE = '0x7f';

async function rpc<T>(url: string, method: string, params: unknown[]): Promise<T> {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  });
  if (!res.ok) throw new Error(`RPC ${method} HTTP ${res.status}`);
  const j = (await res.json()) as { result?: T; error?: { message: string } };
  if (j.error) throw new Error(`RPC ${method} error: ${j.error.message}`);
  return j.result as T;
}

export type QuantumCheck =
  | { ok: true }
  | { ok: false; code: 'bad_hash' | 'not_found' | 'not_quantum' | 'failed' | 'wrong_to' | 'short_value' | 'rpc'; message: string };

/** txHash 가 `to` 로 `minWei` 이상을 보낸, 성공한 SPHINCS+ 거래인지. */
export async function verifyQuantumTransfer(
  env: Env,
  txHash: string,
  to: string,
  minWei: bigint,
): Promise<QuantumCheck> {
  if (!/^0x[0-9a-fA-F]{64}$/.test(txHash)) {
    return { ok: false, code: 'bad_hash', message: '거래 해시 형식이 아니에요 (0x + 64자리)' };
  }
  const url = env.QTA_RPC_URL || DEFAULT_RPC;
  let tx: { type?: string; to?: string | null; value?: string; signature?: string } | null;
  let rc: { status?: string } | null;
  try {
    [tx, rc] = await Promise.all([
      rpc<typeof tx>(url, 'eth_getTransactionByHash', [txHash]),
      rpc<typeof rc>(url, 'eth_getTransactionReceipt', [txHash]),
    ]);
  } catch (e) {
    return { ok: false, code: 'rpc', message: `체인 조회 실패 — 잠시 후 다시 (${String((e as Error)?.message || e)})` };
  }
  if (!tx || !rc) return { ok: false, code: 'not_found', message: '체인에 아직 없는 거래예요 (블록 포함 후 다시)' };
  if ((tx.type || '').toLowerCase() !== SPHINCS_TX_TYPE || !tx.signature || tx.signature === '0x') {
    return {
      ok: false,
      code: 'not_quantum',
      message: `양자내성(SPHINCS+) 서명 거래가 아니에요 (type ${tx.type}). 양자내성 지갑에서 다시 보내 주세요`,
    };
  }
  if (rc.status !== '0x1') return { ok: false, code: 'failed', message: '실패한 거래예요' };
  if ((tx.to || '').toLowerCase() !== to.toLowerCase()) {
    return { ok: false, code: 'wrong_to', message: '받는 지갑 주소가 출금 신청 주소와 달라요' };
  }
  if (BigInt(tx.value || '0x0') < minWei) {
    return { ok: false, code: 'short_value', message: '보낸 수량이 출금 신청 수량보다 적어요' };
  }
  return { ok: true };
}
