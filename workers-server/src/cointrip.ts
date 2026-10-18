/**
 * 코인트립 공용 — 설정값, 수량(micro) 변환, 거리 계산, 탈퇴 정리.
 * 라우트: routes/cointrip.ts (회원) · routes/cointripAdmin.ts (어드민).
 */
import type { Env } from './types';

export const MICRO = 1_000_000;

export interface CtSettings {
  enabled: boolean;
  testerIds: string[];
  pickRadiusM: number;
  preciseRadiusM: number;
  finderMultiplier: number;
  unionMax: number;
}

export const SETTING_KEYS = [
  'enabled',
  'tester_ids',
  'pick_radius_m',
  'precise_radius_m',
  'finder_multiplier',
  'union_max',
] as const;

function num(v: string | undefined, def: number, min: number, max: number): number {
  const n = Number(v);
  if (!Number.isFinite(n)) return def;
  return Math.min(max, Math.max(min, n));
}

export async function loadSettings(env: Env): Promise<CtSettings> {
  const rs = await env.DB.prepare('SELECT key, value FROM ct_settings').all<{ key: string; value: string }>();
  const m: Record<string, string> = {};
  for (const r of rs.results || []) m[r.key] = r.value;
  return {
    enabled: m.enabled === '1',
    testerIds: (m.tester_ids || '').split(',').map((s) => s.trim()).filter(Boolean),
    pickRadiusM: num(m.pick_radius_m, 30, 5, 500),
    preciseRadiusM: num(m.precise_radius_m, 300, 30, 5000),
    finderMultiplier: num(m.finder_multiplier, 2, 1, 100),
    unionMax: Math.round(num(m.union_max, 50, 2, 500)),
  };
}

/** 이 회원에게 코인트립이 열려 있나 (전체 공개 또는 테스터). */
export function openFor(s: CtSettings, userId: string): boolean {
  return s.enabled || s.testerIds.includes(userId);
}

/** '1.5' → 1500000. 소수점 6자리까지. 잘못된 값은 null. */
export function toMicro(v: unknown): number | null {
  const s = String(v ?? '').trim();
  if (!/^\d{1,12}(\.\d{1,6})?$/.test(s)) return null;
  const [i, f = ''] = s.split('.');
  return Number(i) * MICRO + Number((f + '000000').slice(0, 6));
}

/** 1500000 → '1.5'. */
export function fromMicro(n: number): string {
  const neg = n < 0;
  const a = Math.abs(Math.trunc(n));
  const i = Math.floor(a / MICRO);
  const f = String(a % MICRO).padStart(6, '0').replace(/0+$/, '');
  return `${neg ? '-' : ''}${i}${f ? '.' + f : ''}`;
}

/** 두 점 사이 거리 (m). */
export function distanceM(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6_371_000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** 일반 코인 받을 기존 지갑 주소 (0x + 40자리). */
export function isEvmAddress(v: string): boolean {
  return /^0x[0-9a-fA-F]{40}$/.test(v);
}

/** 솔라나 지갑 주소 (base58, 32~44자). */
export function isSolanaAddress(v: string): boolean {
  return /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(v);
}

/**
 * 코인 체인 (어드민이 고른다). 체인이 정하는 받는 주소:
 *   quantarium → 퀀타리움 월렛 · evm → 기존 0x 지갑 주소 · solana → 솔라나 지갑 주소
 */
export const NETWORKS = [
  { name: 'Quantarium', key: 'quantarium', kind: 'quantarium' },
  { name: 'Ethereum', key: 'evm', kind: 'general' },
  { name: 'BNB Smart Chain', key: 'evm', kind: 'general' },
  { name: 'Polygon', key: 'evm', kind: 'general' },
  { name: 'Solana', key: 'solana', kind: 'general' },
] as const;

export type WalletKey = 'quantarium' | 'evm' | 'solana';

export function walletKeyOf(coin: { wallet_kind: string; network?: string | null }): WalletKey {
  if (coin.wallet_kind === 'quantarium') return 'quantarium';
  return coin.network === 'Solana' ? 'solana' : 'evm';
}

/** SQL 안에서 같은 판정 (ct_coins 별칭 k). */
export const WALLET_KEY_SQL =
  "(CASE WHEN k.wallet_kind = 'quantarium' THEN 'quantarium' WHEN k.network = 'Solana' THEN 'solana' ELSE 'evm' END)";

/** 받는 주소가 담긴 users 컬럼. */
export function walletColumn(key: WalletKey): 'wallet_address' | 'ext_wallet_address' | 'sol_wallet_address' {
  return key === 'quantarium' ? 'wallet_address' : key === 'solana' ? 'sol_wallet_address' : 'ext_wallet_address';
}

/**
 * 연합 나눔 — 주운 사람은 multiplier 몫, 나머지는 1 몫씩. 나눠 떨어지지 않는 자투리는 주운 사람에게.
 * 반환: [userId, micro][] (주운 사람이 첫 번째).
 */
export function splitShares(total: number, finderId: string, others: string[], multiplier: number): [string, number][] {
  const w = multiplier + others.length;
  const each = Math.floor(total / w);
  const out: [string, number][] = others.map((id) => [id, each]);
  const finder = total - each * others.length;
  return [[finderId, finder], ...out.filter(([, n]) => n > 0)];
}

/** 탈퇴 — 연합에서 빠지고(방장이면 넘김) 잔액·내역을 지운다. 출금 대기 중이면 탈퇴 자체를 막는다. */
export async function cointripOnUserDelete(env: Env, userId: string): Promise<void> {
  const owned = await env.DB.prepare('SELECT id FROM ct_unions WHERE owner_id = ?').bind(userId).all<{ id: string }>();
  for (const u of owned.results || []) {
    const next = await env.DB
      .prepare('SELECT user_id FROM ct_union_members WHERE union_id = ? AND user_id != ? ORDER BY joined_at LIMIT 1')
      .bind(u.id, userId)
      .first<{ user_id: string }>();
    if (next) {
      await env.DB.prepare('UPDATE ct_unions SET owner_id = ? WHERE id = ?').bind(next.user_id, u.id).run();
    } else {
      await env.DB.prepare('DELETE FROM ct_unions WHERE id = ?').bind(u.id).run();
    }
  }
  await env.DB.batch([
    env.DB.prepare('DELETE FROM ct_union_members WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM ct_balances WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM ct_ledger WHERE user_id = ?').bind(userId),
  ]);
}
