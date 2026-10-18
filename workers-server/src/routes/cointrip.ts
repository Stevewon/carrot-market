/**
 * 코인트립 (지도 코인 찾기) — 회원용.
 *
 *   GET    /api/cointrip/status           - 열려 있나, 설정값, 내 지갑 등록 여부, 첫 안내 확인 여부, 연합
 *   POST   /api/cointrip/ack              - 빨간 글씨 책임 공지 "확인했습니다" 기록 { context }
 *   PUT    /api/cointrip/ext-wallet       - 일반 코인 받을 기존 지갑 주소 { address, ack: true }
 *   DELETE /api/cointrip/ext-wallet       - 지우기
 *   PUT    /api/cointrip/sol-wallet       - 솔라나 코인 받을 지갑 주소 { address, ack: true }
 *   DELETE /api/cointrip/sol-wallet       - 지우기
 *   GET    /api/cointrip/drops?lat&lng&radius_m - 내 주변 코인 (받을 지갑이 있는 코인만)
 *   POST   /api/cointrip/drops/:id/pick   - 줍기 { lat, lng, accuracy, mocked }
 *   GET    /api/cointrip/wallet           - 코인별 잔액 + 출금 신청
 *   GET    /api/cointrip/ledger           - 내역
 *   POST   /api/cointrip/withdrawals      - 출금 신청 { coin_id, amount, ack: true }
 *   GET    /api/cointrip/union            - 내 연합
 *   POST   /api/cointrip/union            - 만들기 { name }
 *   POST   /api/cointrip/union/join       - 들어가기 { code }
 *   POST   /api/cointrip/union/leave      - 나가기
 *   POST   /api/cointrip/union/kick       - 내보내기 (방장) { user_id }
 *
 * 받을 지갑은 코인의 체인이 정한다: Quantarium → users.wallet_address,
 *   Ethereum·BNB·Polygon → users.ext_wallet_address (0x), Solana → users.sol_wallet_address.
 * 그 지갑이 없는 회원에게는 그 코인을 아예 보내지 않는다 (사장님 결정).
 */
import { Hono } from 'hono';
import type { Context } from 'hono';
import type { Env, Variables } from '../types';
import { authMiddleware } from '../jwt';
import { tr, trl, marketLang } from '../market';
import { addNotifications } from '../utils/inbox';
import { deductCointripDud } from '../qta';
import {
  distanceM,
  fromMicro,
  isEvmAddress,
  isSolanaAddress,
  walletColumn,
  walletKeyOf,
  WALLET_KEY_SQL,
  type WalletKey,
  loadSettings,
  openFor,
  splitShares,
  toMicro,
  type CtSettings,
} from '../cointrip';

type C = Context<{ Bindings: Env; Variables: Variables }>;

const app = new Hono<{ Bindings: Env; Variables: Variables }>();
app.use('*', authMiddleware);

interface Me {
  id: string;
  nickname: string;
  market: string | null;
  wallet_address: string | null;
  ext_wallet_address: string | null;
  sol_wallet_address: string | null;
  verified_at: string | null;
  verified_ci_hash: string | null;
}

async function loadMe(c: C): Promise<Me> {
  const u = await c.env.DB
    .prepare(
      `SELECT id, nickname, market, wallet_address, ext_wallet_address, sol_wallet_address, verified_at, verified_ci_hash
         FROM users WHERE id = ?`,
    )
    .bind(c.get('user')!.id)
    .first<Me>();
  return u!;
}

/** 이 회원이 받을 수 있는 지갑 종류. */
type Wallets = Pick<Me, 'wallet_address' | 'ext_wallet_address' | 'sol_wallet_address'>;

/** 이 회원이 받을 수 있는 주소 종류 (quantarium · evm · solana). */
function walletKinds(u: Wallets): WalletKey[] {
  const k: WalletKey[] = [];
  if (u.wallet_address) k.push('quantarium');
  if (u.ext_wallet_address) k.push('evm');
  if (u.sol_wallet_address) k.push('solana');
  return k;
}

function phoneVerified(u: Pick<Me, 'verified_at' | 'verified_ci_hash'>): boolean {
  return !!(u.verified_at && u.verified_ci_hash);
}

function addressFor(u: Wallets, key: WalletKey): string | null {
  return u[walletColumn(key)];
}

async function body(c: C): Promise<Record<string, unknown>> {
  try {
    return (await c.req.json()) as Record<string, unknown>;
  } catch {
    return {};
  }
}

async function guard(c: C): Promise<{ s: CtSettings; me: Me } | Response> {
  const s = await loadSettings(c.env);
  const me = await loadMe(c);
  if (!me) return c.json({ error: 'not found' }, 404);
  if (!openFor(s, me.id)) {
    return c.json({ error: tr(c, '코인트립은 아직 준비 중이에요', 'コイントリップは準備中です', 'CoinTrip is coming soon'), code: 'closed' }, 403);
  }
  return { s, me };
}

async function logAck(env: Env, userId: string, context: string, detail: string | null): Promise<void> {
  await env.DB
    .prepare('INSERT INTO wallet_notice_acks (user_id, context, detail) VALUES (?, ?, ?)')
    .bind(userId, context, detail)
    .run();
}

async function unionOf(env: Env, userId: string) {
  const u = await env.DB
    .prepare(
      `SELECT un.id, un.name, un.code, un.owner_id
         FROM ct_union_members m JOIN ct_unions un ON un.id = m.union_id
        WHERE m.user_id = ?`,
    )
    .bind(userId)
    .first<{ id: string; name: string; code: string; owner_id: string }>();
  if (!u) return null;
  const rs = await env.DB
    .prepare(
      `SELECT m.user_id, u.nickname, m.joined_at
         FROM ct_union_members m LEFT JOIN users u ON u.id = m.user_id
        WHERE m.union_id = ? ORDER BY m.joined_at`,
    )
    .bind(u.id)
    .all<{ user_id: string; nickname: string | null; joined_at: string }>();
  return {
    id: u.id,
    name: u.name,
    code: u.code,
    owner_id: u.owner_id,
    members: (rs.results || []).map((m) => ({ user_id: m.user_id, nickname: m.nickname ?? '', joined_at: m.joined_at })),
  };
}

// ── 상태 ──────────────────────────────────────────────────────────────
app.get('/status', async (c) => {
  const s = await loadSettings(c.env);
  const me = await loadMe(c);
  const open = openFor(s, me.id);
  if (!open) return c.json({ open: false });
  await settleExpired(c.env, me.id);
  const intro = await c.env.DB
    .prepare("SELECT 1 AS ok FROM wallet_notice_acks WHERE user_id = ? AND context = 'cointrip_intro' LIMIT 1")
    .bind(me.id)
    .first();
  return c.json({
    open: true,
    pick_radius_m: s.pickRadiusM,
    precise_radius_m: s.preciseRadiusM,
    finder_multiplier: s.finderMultiplier,
    union_max: s.unionMax,
    wallet_kinds: walletKinds(me),
    quantarium_wallet: me.wallet_address,
    ext_wallet_address: me.ext_wallet_address,
    sol_wallet_address: me.sol_wallet_address,
    phone_verified: phoneVerified(me),
    intro_acked: !!intro,
    dud_penalty_qta: s.dudPenaltyQta,
    penalty: await pendingPenalty(c.env, me.id, s),
    union: await unionOf(c.env, me.id),
  });
});

app.post('/ack', async (c) => {
  const b = await body(c);
  const context = String(b.context ?? '');
  if (!['cointrip_intro', 'ext_wallet', 'sol_wallet', 'withdraw'].includes(context)) return c.json({ error: 'bad context' }, 400);
  await logAck(c.env, c.get('user')!.id, context, null);
  return c.json({ ok: true });
});

// ── 일반 코인 지갑 주소 (Ethereum·BNB·Polygon = 0x 하나, Solana = 따로) ──────────
const EXTRA_WALLETS = {
  evm: {
    path: '/ext-wallet', col: 'ext_wallet_address', at: 'ext_wallet_set_at', ack: 'ext_wallet', kinds: ['general', 'evm'],
    valid: isEvmAddress,
    bad: (c: C) => tr(c, '지갑 주소가 올바르지 않아요 (0x 로 시작하는 42자리)', 'ウォレットアドレスが正しくありません（0xで始まる42桁）', 'Invalid wallet address (42 characters starting with 0x)'),
  },
  solana: {
    path: '/sol-wallet', col: 'sol_wallet_address', at: 'sol_wallet_set_at', ack: 'sol_wallet', kinds: ['solana'],
    valid: isSolanaAddress,
    bad: (c: C) => tr(c, '솔라나 지갑 주소가 올바르지 않아요', 'Solanaウォレットアドレスが正しくありません', 'Invalid Solana wallet address'),
  },
} as const;

for (const w of Object.values(EXTRA_WALLETS)) {
  app.put(w.path, async (c) => {
    const me = c.get('user')!;
    const b = await body(c);
    const address = String(b.address ?? '').trim();
    if (!w.valid(address)) return c.json({ error: w.bad(c) }, 400);
    if (b.ack !== true) {
      return c.json({ error: tr(c, '책임 안내를 확인해 주세요', '責任に関するご案内を確認してください', 'Please confirm the responsibility notice'), code: 'ack_required' }, 400);
    }
    await c.env.DB.batch([
      c.env.DB
        .prepare(`UPDATE users SET ${w.col} = ?, ${w.at} = datetime('now'), updated_at = datetime('now') WHERE id = ?`)
        .bind(address, me.id),
      c.env.DB
        .prepare('INSERT INTO wallet_notice_acks (user_id, context, detail) VALUES (?, ?, ?)')
        .bind(me.id, w.ack, address),
    ]);
    return c.json({ ok: true, [w.col]: address });
  });

  app.delete(w.path, async (c) => {
    const me = c.get('user')!;
    const pending = await c.env.DB
      .prepare(
        `SELECT 1 FROM ct_withdrawals WHERE user_id = ? AND wallet_kind IN (${w.kinds.map(() => '?').join(',')})
            AND status IN ('requested','processing') LIMIT 1`,
      )
      .bind(me.id, ...w.kinds)
      .first();
    if (pending) {
      return c.json({ error: tr(c, '진행 중인 출금이 있어 지금은 지울 수 없어요', '処理中の出金があるため削除できません', 'You cannot remove it while a withdrawal is in progress') }, 409);
    }
    await c.env.DB
      .prepare(`UPDATE users SET ${w.col} = NULL, ${w.at} = NULL, updated_at = datetime('now') WHERE id = ?`)
      .bind(me.id)
      .run();
    return c.json({ ok: true });
  });
}

// ── 지도 ─────────────────────────────────────────────────────────────
/** 멀리 있는 코인은 이 칸(약 550m)의 가운데로만 알려준다. */
const CELL_DEG = 0.005;

app.get('/drops', async (c) => {
  const g = await guard(c);
  if (g instanceof Response) return g;
  const { s, me } = g;
  const lat = Number(c.req.query('lat'));
  const lng = Number(c.req.query('lng'));
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return c.json({ error: 'lat/lng required' }, 400);
  }
  const kinds = walletKinds(me);
  if (!kinds.length) return c.json({ need_wallet: true, drops: [] });

  const radius = Math.min(20_000, Math.max(100, Number(c.req.query('radius_m')) || 5_000));
  const dLat = radius / 111_320;
  const dLng = radius / (111_320 * Math.max(0.1, Math.cos((lat * Math.PI) / 180)));
  const rs = await c.env.DB
    .prepare(
      `SELECT d.id, d.lat, d.lng, d.amount_micro, d.is_black,
              k.id AS coin_id, k.symbol, k.name, k.color
         FROM ct_drops d JOIN ct_coins k ON k.id = d.coin_id
        WHERE d.status = 'active' AND k.active = 1
          AND (d.expires_at IS NULL OR d.expires_at > datetime('now'))
          AND ${WALLET_KEY_SQL} IN (${kinds.map(() => '?').join(',')})
          AND d.lat BETWEEN ? AND ? AND d.lng BETWEEN ? AND ?
        LIMIT 2000`,
    )
    .bind(...kinds, lat - dLat, lat + dLat, lng - dLng, lng + dLng)
    .all<{
      id: string; lat: number; lng: number; amount_micro: number; is_black: number;
      coin_id: string; symbol: string; name: string; color: string;
    }>();

  const drops = [];
  for (const d of rs.results || []) {
    const dist = distanceM(lat, lng, d.lat, d.lng);
    if (dist > radius) continue;
    const precise = dist <= s.preciseRadiusM;
    const black = d.is_black === 1;
    drops.push({
      id: d.id,
      precise,
      lat: precise ? d.lat : (Math.floor(d.lat / CELL_DEG) + 0.5) * CELL_DEG,
      lng: precise ? d.lng : (Math.floor(d.lng / CELL_DEG) + 0.5) * CELL_DEG,
      // 멀리 있으면 거리도 대략 (100m 단위)
      distance_m: precise ? Math.round(dist) : Math.round(dist / 100) * 100,
      is_black: black,
      // 지도에서는 모든 코인이 같은 황금 동전 — 종류·수량은 주워야 안다 (비싼 것만 골라 줍지 않게, 사장님 지시).
      coin: null,
      amount: null,
    });
  }
  drops.sort((a, b) => a.distance_m - b.distance_m);
  return c.json({ need_wallet: false, drops: drops.slice(0, 500) });
});

// ── 줍기 ─────────────────────────────────────────────────────────────
app.post('/drops/:id/pick', async (c) => {
  const g = await guard(c);
  if (g instanceof Response) return g;
  const { s, me } = g;
  const b = await body(c);
  const lat = Number(b.lat);
  const lng = Number(b.lng);
  const accuracy = Number(b.accuracy ?? 0);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return c.json({ error: 'lat/lng required' }, 400);
  if (b.mocked === true) {
    return c.json({ error: tr(c, '위치 조작 앱이 켜져 있으면 주울 수 없어요', '位置偽装アプリがオンのときは拾えません', 'You cannot pick up coins while a fake-location app is on'), code: 'mocked' }, 403);
  }
  if (!phoneVerified(me)) {
    return c.json({ error: tr(c, '휴대폰 인증을 마쳐야 주울 수 있어요', '携帯電話認証を完了すると拾えます', 'Verify your phone number to pick up coins'), code: 'phone_required' }, 403);
  }
  await settleExpired(c.env, me.id);
  const pendingPen = await pendingPenalty(c.env, me.id, s);
  if (pendingPen) {
    return c.json({ error: tr(c, '먼저 꽝을 정리해 주세요 (광고 보기 또는 QTA 내기)', '先にハズレを精算してください（広告を見るかQTAを払う）', 'Settle your dud first (watch an ad or pay QTA)'), code: 'dud_pending', penalty: pendingPen }, 409);
  }
  if (Number.isFinite(accuracy) && accuracy > 100) {
    return c.json({ error: tr(c, '위치가 정확하지 않아요. 밖으로 나가 잠시 뒤 다시 해 주세요', '位置が正確ではありません。屋外で少し待ってから再度お試しください', 'Your location is not accurate. Go outside and try again shortly'), code: 'low_accuracy' }, 400);
  }

  const d = await c.env.DB
    .prepare(
      `SELECT d.id, d.lat, d.lng, d.amount_micro, d.is_black, d.is_dud, d.status, d.expires_at,
              k.id AS coin_id, k.symbol, k.name, k.color, k.wallet_kind, k.network, k.active
         FROM ct_drops d JOIN ct_coins k ON k.id = d.coin_id WHERE d.id = ?`,
    )
    .bind(c.req.param('id'))
    .first<{
      id: string; lat: number; lng: number; amount_micro: number; is_black: number; is_dud: number; status: string;
      expires_at: string | null; coin_id: string; symbol: string; name: string; color: string;
      wallet_kind: string; network: string; active: number;
    }>();
  const gone = () => c.json({ error: tr(c, '이미 누군가 주웠거나 사라진 코인이에요', 'すでに誰かが拾ったか、消えたコインです', 'Someone already picked up this coin, or it is gone'), code: 'gone' }, 409);
  if (!d || d.status !== 'active' || !d.active) return gone();
  if (d.expires_at && new Date(d.expires_at.replace(' ', 'T') + 'Z').getTime() < Date.now()) return gone();
  const key = walletKeyOf(d);
  if (!addressFor(me, key)) {
    // 받을 지갑이 없는 회원에게는 지도에도 안 보내지만, 직접 요청해도 막는다.
    return gone();
  }
  const dist = distanceM(lat, lng, d.lat, d.lng);
  if (dist > s.pickRadiusM) {
    return c.json({
      error: tr(c, `${s.pickRadiusM}m 안으로 가까이 가야 주울 수 있어요`, `${s.pickRadiusM}m以内に近づくと拾えます`, `Get within ${s.pickRadiusM}m to pick it up`),
      code: 'too_far',
      distance_m: Math.round(dist),
    }, 400);
  }

  // 순간이동 막기 — 바로 전에 주운 곳에서 시속 150km 보다 빨리 왔으면 거절. 줍기는 5초에 한 번.
  const last = await c.env.DB
    .prepare("SELECT pick_lat, pick_lng, picked_at FROM ct_drops WHERE picked_by = ? AND status = 'picked' ORDER BY picked_at DESC LIMIT 1")
    .bind(me.id)
    .first<{ pick_lat: number | null; pick_lng: number | null; picked_at: string }>();
  if (last && last.pick_lat != null && last.pick_lng != null) {
    const sec = Math.max(1, (Date.now() - new Date(last.picked_at.replace(' ', 'T') + 'Z').getTime()) / 1000);
    if (sec < 5) return c.json({ error: tr(c, '잠시 뒤에 다시 해 주세요', '少し待ってから再度お試しください', 'Please try again in a moment'), code: 'slow_down' }, 429);
    const kmh = (distanceM(last.pick_lat, last.pick_lng, lat, lng) / sec) * 3.6;
    if (kmh > 150) {
      return c.json({ error: tr(c, '이동 속도가 너무 빨라요. 잠시 뒤에 다시 해 주세요', '移動速度が速すぎます。少し待ってから再度お試しください', 'You are moving too fast. Please try again later'), code: 'too_fast' }, 429);
    }
  }

  // 먼저 터치한 사람이 가져간다 — status 조건으로 한 사람만 성공.
  const claim = await c.env.DB
    .prepare(
      `UPDATE ct_drops SET status = 'picked', picked_by = ?, picked_at = datetime('now'), pick_lat = ?, pick_lng = ?
        WHERE id = ? AND status = 'active'`,
    )
    .bind(me.id, lat, lng, d.id)
    .run();
  if (!claim.meta.changes) return gone();

  // 블랙코인 — is_dud 1 = 꽝 (아무것도 없음), 2 = 벌칙 (광고를 보거나 QTA 를 내놓는다).
  if (d.is_black === 1 && d.is_dud === 1) {
    return c.json({ ok: true, empty: true });
  }
  if (d.is_black === 1 && d.is_dud === 2) {
    const pen = await openPenalty(c.env, me.id, d.id, s);
    return c.json({ ok: true, dud: true, penalty: pen });
  }

  // 연합 나눔 — 이 코인을 받을 지갑이 있는 연합원에게만.
  const union = await unionOf(c.env, me.id);
  let others: { id: string; nickname: string; market: string | null }[] = [];
  if (union && union.members.length > 1) {
    const col = walletColumn(key);
    const rs = await c.env.DB
      .prepare(
        `SELECT u.id, u.nickname, u.market FROM ct_union_members m JOIN users u ON u.id = m.user_id
          WHERE m.union_id = ? AND u.id != ? AND u.${col} IS NOT NULL AND u.${col} != ''`,
      )
      .bind(union.id, me.id)
      .all<{ id: string; nickname: string; market: string | null }>();
    others = rs.results || [];
  }
  const shares = splitShares(d.amount_micro, me.id, others.map((o) => o.id), s.finderMultiplier);

  const stmts = [];
  for (const [uid, micro] of shares) {
    const reason = uid === me.id ? 'pick' : 'share';
    stmts.push(
      c.env.DB
        .prepare('INSERT INTO ct_ledger (id, user_id, coin_id, amount_micro, reason, drop_id) VALUES (?, ?, ?, ?, ?, ?)')
        .bind(crypto.randomUUID(), uid, d.coin_id, micro, reason, d.id),
      c.env.DB
        .prepare(
          `INSERT INTO ct_balances (user_id, coin_id, amount_micro) VALUES (?, ?, ?)
           ON CONFLICT(user_id, coin_id) DO UPDATE SET amount_micro = amount_micro + excluded.amount_micro, updated_at = datetime('now')`,
        )
        .bind(uid, d.coin_id, micro),
    );
  }
  try {
    await c.env.DB.batch(stmts);
  } catch (e) {
    console.error('[cointrip] credit failed', e);
    await c.env.DB
      .prepare("UPDATE ct_drops SET status = 'active', picked_by = NULL, picked_at = NULL, pick_lat = NULL, pick_lng = NULL WHERE id = ? AND picked_by = ?")
      .bind(d.id, me.id)
      .run();
    return c.json({ error: tr(c, '잠시 뒤에 다시 해 주세요', '少し待ってから再度お試しください', 'Please try again in a moment') }, 500);
  }

  // 연합원 알림함에 남긴다 (실패해도 줍기는 끝남).
  if (others.length) {
    const byId = new Map(shares);
    c.executionCtx.waitUntil(
      addNotifications(
        c.env,
        others
          .filter((o) => (byId.get(o.id) ?? 0) > 0)
          .map((o) => {
            const lang = marketLang(o.market);
            return {
              userId: o.id,
              type: 'cointrip_share',
              title: trl(lang, '연합원이 코인을 주웠어요', '連合メンバーがコインを拾いました', 'A union member picked up a coin'),
              body: trl(
                lang,
                `${me.nickname} · ${d.symbol} ${fromMicro(byId.get(o.id)!)} 나눠 받음`,
                `${me.nickname} · ${d.symbol} ${fromMicro(byId.get(o.id)!)} を受け取りました`,
                `${me.nickname} · you received ${d.symbol} ${fromMicro(byId.get(o.id)!)}`,
              ),
            };
          }),
      ).catch((e) => console.error('[cointrip] inbox failed', e)),
    );
  }

  const nick = new Map(others.map((o) => [o.id, o.nickname]));
  return c.json({
    ok: true,
    was_black: d.is_black === 1,
    coin: { id: d.coin_id, symbol: d.symbol, name: d.name, color: d.color },
    total: fromMicro(d.amount_micro),
    mine: fromMicro(shares[0][1]),
    shared: shares.slice(1).map(([uid, micro]) => ({ nickname: nick.get(uid) ?? '', amount: fromMicro(micro) })),
  });
});

// ── 앱 지갑 ──────────────────────────────────────────────────────────
// ── 블랙코인 꽝: 광고 보기 또는 QTA 내기 ───────────────────────────────
const PENALTY_MINUTES = 10;

interface PenaltyRow { id: string; qta: number; status: string; expires_at: string }

function penaltyOut(p: PenaltyRow, s: CtSettings) {
  return {
    id: p.id,
    qta: p.qta,
    status: p.status,
    expires_at: p.expires_at,
    ad_unit: s.rewardedAdUnit,
    ad_verify: s.adVerify,
  };
}

async function openPenalty(env: Env, userId: string, dropId: string, s: CtSettings) {
  const id = crypto.randomUUID();
  await env.DB
    .prepare(
      `INSERT INTO ct_dud_penalties (id, user_id, drop_id, qta, expires_at)
       VALUES (?, ?, ?, ?, datetime('now', '+${PENALTY_MINUTES} minutes'))`,
    )
    .bind(id, userId, dropId, s.dudPenaltyQta)
    .run();
  const p = await env.DB.prepare('SELECT id, qta, status, expires_at FROM ct_dud_penalties WHERE id = ?').bind(id).first<PenaltyRow>();
  return penaltyOut(p!, s);
}

async function pendingPenalty(env: Env, userId: string, s: CtSettings) {
  const p = await env.DB
    .prepare("SELECT id, qta, status, expires_at FROM ct_dud_penalties WHERE user_id = ? AND status = 'pending' ORDER BY created_at LIMIT 1")
    .bind(userId)
    .first<PenaltyRow>();
  return p ? penaltyOut(p, s) : null;
}

/** QTA 내기로 확정 (한 번만). 실제로 뺀 수량을 돌려준다. */
async function payPenalty(env: Env, userId: string, penaltyId: string): Promise<number | null> {
  const p = await env.DB
    .prepare("SELECT id, qta FROM ct_dud_penalties WHERE id = ? AND user_id = ? AND status = 'pending'")
    .bind(penaltyId, userId)
    .first<{ id: string; qta: number }>();
  if (!p) return null;
  const done = await env.DB
    .prepare("UPDATE ct_dud_penalties SET status = 'paid', resolved_at = datetime('now') WHERE id = ? AND status = 'pending'")
    .bind(p.id)
    .run();
  if (!done.meta.changes) return null;
  const taken = await deductCointripDud(env, userId, p.id, p.qta);
  await env.DB.prepare('UPDATE ct_dud_penalties SET deducted = ? WHERE id = ?').bind(taken, p.id).run();
  return taken;
}

/** 10분 안에 광고를 안 본 꽝은 QTA 내기로 처리. */
async function settleExpired(env: Env, userId: string): Promise<void> {
  const rs = await env.DB
    .prepare("SELECT id FROM ct_dud_penalties WHERE user_id = ? AND status = 'pending' AND expires_at <= datetime('now')")
    .bind(userId)
    .all<{ id: string }>();
  for (const p of rs.results || []) await payPenalty(env, userId, p.id);
}

/** 광고를 끝까지 봤다 → 아무것도 안 낸다. */
export async function markAdWatched(env: Env, userId: string, penaltyId: string): Promise<boolean> {
  const r = await env.DB
    .prepare("UPDATE ct_dud_penalties SET status = 'ad', resolved_at = datetime('now') WHERE id = ? AND user_id = ? AND status = 'pending'")
    .bind(penaltyId, userId)
    .run();
  return !!r.meta.changes;
}

app.get('/penalty', async (c) => {
  const me = c.get('user')!;
  const s = await loadSettings(c.env);
  await settleExpired(c.env, me.id);
  return c.json({ penalty: await pendingPenalty(c.env, me.id, s) });
});

app.post('/penalties/:id/pay', async (c) => {
  const me = c.get('user')!;
  const taken = await payPenalty(c.env, me.id, c.req.param('id'));
  if (taken === null) return c.json({ error: tr(c, '이미 정리된 꽝이에요', 'すでに精算済みです', 'Already settled'), code: 'settled' }, 409);
  return c.json({ ok: true, deducted: taken });
});

/** 앱이 "광고 끝까지 봄"을 알린다 — 설정이 client 일 때만 인정 (ssv 면 AdMob 서버 확인을 기다린다). */
app.post('/penalties/:id/ad-watched', async (c) => {
  const me = c.get('user')!;
  const s = await loadSettings(c.env);
  const id = c.req.param('id');
  if (s.adVerify === 'client') {
    if (!(await markAdWatched(c.env, me.id, id))) {
      return c.json({ error: tr(c, '이미 정리된 꽝이에요', 'すでに精算済みです', 'Already settled'), code: 'settled' }, 409);
    }
    return c.json({ ok: true, status: 'ad' });
  }
  const p = await c.env.DB.prepare('SELECT status FROM ct_dud_penalties WHERE id = ? AND user_id = ?').bind(id, me.id).first<{ status: string }>();
  return c.json({ ok: p?.status === 'ad', status: p?.status ?? 'unknown' });
});

app.get('/wallet', async (c) => {
  const me = await loadMe(c);
  const rs = await c.env.DB
    .prepare(
      `SELECT k.id, k.symbol, k.name, k.color, k.wallet_kind, k.network, k.withdraw_min_micro,
              COALESCE(b.amount_micro, 0) AS amount_micro
         FROM ct_coins k LEFT JOIN ct_balances b ON b.coin_id = k.id AND b.user_id = ?
        WHERE b.amount_micro > 0
           OR k.id IN (SELECT coin_id FROM ct_withdrawals WHERE user_id = ?)
        ORDER BY k.created_at`,
    )
    .bind(me.id, me.id)
    .all<{
      id: string; symbol: string; name: string; color: string; wallet_kind: string; network: string;
      withdraw_min_micro: number; amount_micro: number;
    }>();
  const ws = await c.env.DB
    .prepare(
      `SELECT w.id, w.coin_id, k.symbol, w.amount_micro, w.wallet_address, w.status, w.requested_at, w.tx_hash, w.reject_reason
         FROM ct_withdrawals w JOIN ct_coins k ON k.id = w.coin_id
        WHERE w.user_id = ? ORDER BY w.requested_at DESC LIMIT 30`,
    )
    .bind(me.id)
    .all<{
      id: string; coin_id: string; symbol: string; amount_micro: number; wallet_address: string; status: string;
      requested_at: string; tx_hash: string | null; reject_reason: string | null;
    }>();
  return c.json({
    quantarium_wallet: me.wallet_address,
    ext_wallet_address: me.ext_wallet_address,
    sol_wallet_address: me.sol_wallet_address,
    balances: (rs.results || []).map((r) => ({
      coin: { id: r.id, symbol: r.symbol, name: r.name, color: r.color },
      wallet_kind: walletKeyOf(r),
      network: r.network,
      amount: fromMicro(r.amount_micro),
      withdraw_min: fromMicro(r.withdraw_min_micro),
      address: addressFor(me, walletKeyOf(r)),
    })),
    withdrawals: (ws.results || []).map((w) => ({
      id: w.id,
      symbol: w.symbol,
      amount: fromMicro(w.amount_micro),
      wallet_address: w.wallet_address,
      status: w.status,
      requested_at: w.requested_at,
      tx_hash: w.tx_hash,
      reject_reason: w.reject_reason,
    })),
  });
});

app.get('/ledger', async (c) => {
  const rs = await c.env.DB
    .prepare(
      `SELECT l.id, l.amount_micro, l.reason, l.created_at, k.symbol, k.color
         FROM ct_ledger l JOIN ct_coins k ON k.id = l.coin_id
        WHERE l.user_id = ? ORDER BY l.created_at DESC LIMIT 100`,
    )
    .bind(c.get('user')!.id)
    .all<{ id: string; amount_micro: number; reason: string; created_at: string; symbol: string; color: string }>();
  return c.json({
    items: (rs.results || []).map((r) => ({
      id: r.id, amount: fromMicro(r.amount_micro), reason: r.reason, created_at: r.created_at, symbol: r.symbol, color: r.color,
    })),
  });
});

app.post('/withdrawals', async (c) => {
  const me = await loadMe(c);
  const b = await body(c);
  if (b.ack !== true) {
    return c.json({ error: tr(c, '책임 안내를 확인해 주세요', '責任に関するご案内を確認してください', 'Please confirm the responsibility notice'), code: 'ack_required' }, 400);
  }
  const amount = toMicro(b.amount);
  if (!amount || amount <= 0) return c.json({ error: tr(c, '수량을 확인해 주세요', '数量を確認してください', 'Please check the amount') }, 400);
  const k = await c.env.DB
    .prepare('SELECT id, symbol, wallet_kind, network, withdraw_min_micro FROM ct_coins WHERE id = ?')
    .bind(String(b.coin_id ?? ''))
    .first<{ id: string; symbol: string; wallet_kind: string; network: string; withdraw_min_micro: number }>();
  if (!k) return c.json({ error: 'coin not found' }, 404);
  if (amount < k.withdraw_min_micro) {
    const min = fromMicro(k.withdraw_min_micro);
    return c.json({ error: tr(c, `최소 ${min} ${k.symbol} 부터 출금할 수 있어요`, `${min} ${k.symbol} 以上から出金できます`, `The minimum withdrawal is ${min} ${k.symbol}`), code: 'below_min' }, 400);
  }
  const wkey = walletKeyOf(k);
  const address = addressFor(me, wkey);
  if (!address) {
    return c.json({
      error: wkey === 'quantarium'
        ? tr(c, '퀀타리움 월렛을 먼저 등록해 주세요', '先にQuantariumウォレットを登録してください', 'Please register your Quantarium wallet first')
        : tr(c, '받을 지갑 주소를 먼저 등록해 주세요', '先に受け取りウォレットアドレスを登録してください', 'Please register a receiving wallet address first'),
      code: 'wallet_required',
    }, 400);
  }
  const pending = await c.env.DB
    .prepare("SELECT 1 FROM ct_withdrawals WHERE user_id = ? AND coin_id = ? AND status IN ('requested','processing') LIMIT 1")
    .bind(me.id, k.id)
    .first();
  if (pending) {
    return c.json({ error: tr(c, '이 코인은 이미 출금 신청 중이에요', 'このコインはすでに出金申請中です', 'A withdrawal for this coin is already in progress'), code: 'pending' }, 409);
  }

  const id = crypto.randomUUID();
  // 잔액 조건을 건 UPDATE 로 먼저 빼고 (모자라면 0행), 기록이 실패하면 되돌려 놓는다.
  const dec = await c.env.DB
    .prepare(
      `UPDATE ct_balances SET amount_micro = amount_micro - ?, updated_at = datetime('now')
        WHERE user_id = ? AND coin_id = ? AND amount_micro >= ?`,
    )
    .bind(amount, me.id, k.id, amount)
    .run();
  if (!dec.meta.changes) {
    return c.json({ error: tr(c, '잔액이 모자라요', '残高が足りません', 'Insufficient balance'), code: 'insufficient' }, 400);
  }
  try {
    await c.env.DB.batch([
      c.env.DB
        .prepare('INSERT INTO ct_withdrawals (id, user_id, coin_id, amount_micro, wallet_kind, wallet_address) VALUES (?, ?, ?, ?, ?, ?)')
        .bind(id, me.id, k.id, amount, wkey, address),
      c.env.DB
        .prepare("INSERT INTO ct_ledger (id, user_id, coin_id, amount_micro, reason, withdrawal_id) VALUES (?, ?, ?, ?, 'withdrawal', ?)")
        .bind(crypto.randomUUID(), me.id, k.id, -amount, id),
      c.env.DB
        .prepare("INSERT INTO wallet_notice_acks (user_id, context, detail) VALUES (?, 'withdraw', ?)")
        .bind(me.id, `${k.symbol} ${fromMicro(amount)} → ${address}`),
    ]);
  } catch (e) {
    console.error('[cointrip] withdrawal insert failed', e);
    await c.env.DB
      .prepare("UPDATE ct_balances SET amount_micro = amount_micro + ?, updated_at = datetime('now') WHERE user_id = ? AND coin_id = ?")
      .bind(amount, me.id, k.id)
      .run();
    return c.json({ error: tr(c, '잠시 뒤에 다시 해 주세요', '少し待ってから再度お試しください', 'Please try again in a moment') }, 500);
  }
  return c.json({ ok: true, id, amount: fromMicro(amount), wallet_address: address });
});

// ── 친구 연합 ────────────────────────────────────────────────────────
function newCode(): string {
  const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const b = crypto.getRandomValues(new Uint8Array(8));
  return Array.from(b, (x) => abc[x % abc.length]).join('');
}

app.get('/union', async (c) => {
  return c.json({ union: await unionOf(c.env, c.get('user')!.id) });
});

app.post('/union', async (c) => {
  const g = await guard(c);
  if (g instanceof Response) return g;
  const { me } = g;
  const b = await body(c);
  const name = String(b.name ?? '').trim().slice(0, 20);
  if (name.length < 1) return c.json({ error: tr(c, '연합 이름을 넣어 주세요', '連合名を入力してください', 'Please enter a union name') }, 400);
  if (await unionOf(c.env, me.id)) {
    return c.json({ error: tr(c, '이미 연합에 들어가 있어요', 'すでに連合に参加しています', 'You are already in a union'), code: 'already' }, 409);
  }
  const id = crypto.randomUUID();
  const code = newCode();
  await c.env.DB.batch([
    c.env.DB.prepare('INSERT INTO ct_unions (id, name, code, owner_id) VALUES (?, ?, ?, ?)').bind(id, name, code, me.id),
    c.env.DB.prepare('INSERT INTO ct_union_members (union_id, user_id) VALUES (?, ?)').bind(id, me.id),
  ]);
  return c.json({ union: await unionOf(c.env, me.id) });
});

app.post('/union/join', async (c) => {
  const g = await guard(c);
  if (g instanceof Response) return g;
  const { s, me } = g;
  const b = await body(c);
  const code = String(b.code ?? '').trim().toUpperCase();
  if (await unionOf(c.env, me.id)) {
    return c.json({ error: tr(c, '이미 연합에 들어가 있어요. 먼저 나와 주세요', 'すでに連合に参加しています。先に退出してください', 'You are already in a union. Leave it first'), code: 'already' }, 409);
  }
  const u = await c.env.DB.prepare('SELECT id FROM ct_unions WHERE code = ?').bind(code).first<{ id: string }>();
  if (!u) return c.json({ error: tr(c, '초대 코드를 찾을 수 없어요', '招待コードが見つかりません', 'Invite code not found'), code: 'not_found' }, 404);
  // 인원 확인과 넣기를 한 문장으로 — 동시에 들어와도 최대 인원을 넘지 않게.
  const r = await c.env.DB
    .prepare(
      `INSERT INTO ct_union_members (union_id, user_id)
       SELECT ?, ? WHERE (SELECT COUNT(*) FROM ct_union_members WHERE union_id = ?) < ?`,
    )
    .bind(u.id, me.id, u.id, s.unionMax)
    .run();
  if (!r.meta.changes) {
    return c.json({ error: tr(c, `연합은 최대 ${s.unionMax}명이에요`, `連合は最大${s.unionMax}人です`, `A union can have up to ${s.unionMax} members`), code: 'full' }, 409);
  }
  return c.json({ union: await unionOf(c.env, me.id) });
});

app.post('/union/leave', async (c) => {
  const meId = c.get('user')!.id;
  const u = await unionOf(c.env, meId);
  if (!u) return c.json({ ok: true });
  const rest = u.members.filter((m) => m.user_id !== meId);
  if (!rest.length) {
    await c.env.DB.prepare('DELETE FROM ct_unions WHERE id = ?').bind(u.id).run();
  } else {
    const stmts = [c.env.DB.prepare('DELETE FROM ct_union_members WHERE union_id = ? AND user_id = ?').bind(u.id, meId)];
    if (u.owner_id === meId) {
      stmts.push(c.env.DB.prepare('UPDATE ct_unions SET owner_id = ? WHERE id = ?').bind(rest[0].user_id, u.id));
    }
    await c.env.DB.batch(stmts);
  }
  return c.json({ ok: true });
});

app.post('/union/kick', async (c) => {
  const meId = c.get('user')!.id;
  const b = await body(c);
  const target = String(b.user_id ?? '');
  const u = await unionOf(c.env, meId);
  if (!u || u.owner_id !== meId) return c.json({ error: 'forbidden' }, 403);
  if (target === meId) return c.json({ error: 'bad target' }, 400);
  await c.env.DB.prepare('DELETE FROM ct_union_members WHERE union_id = ? AND user_id = ?').bind(u.id, target).run();
  return c.json({ union: await unionOf(c.env, meId) });
});

export default app;
