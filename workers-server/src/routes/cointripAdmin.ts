/**
 * 코인트립 어드민 — /api/admin/cointrip/* (admin.ts 의 어드민 세션 확인을 거친 뒤).
 *
 *   GET  /settings                    PUT /settings { key: value, ... }
 *   GET  /coins                       POST /coins      PUT /coins/:id
 *   GET  /drops?status&coin_id        POST /drops      (한 곳 / 반경 안 여러 개 뿌리기)
 *   POST /drops/:id/cancel            POST /batches/:id/cancel
 *   GET  /stats
 *   GET  /withdrawals?status          POST /withdrawals/:id/processing | /complete { tx_hash } | /reject { reason }
 *   GET  /acks?user_id                - 책임 공지 확인 기록
 *   GET  /suspects?days               - 의심 회원 (위치 조작 기록 모음)
 *   GET  /flags?user_id               - 한 회원의 의심 기록
 *   POST /block { user_id, blocked }  - 코인트립 정지 / 해제
 */
import { Hono } from 'hono';
import type { Context } from 'hono';
import type { Env, Variables } from '../types';
import { MICRO, NETWORKS, SETTING_KEYS, fromMicro, loadSettings, toMicro, walletKeyOf } from '../cointrip';

type AdminVariables = Variables & { admin?: { id: string; username: string; role: string } };
type C = Context<{ Bindings: Env; Variables: AdminVariables }>;

const app = new Hono<{ Bindings: Env; Variables: AdminVariables }>();

async function audit(c: C, action: string, targetId: string | null, detail: string | null): Promise<void> {
  const admin = c.get('admin');
  if (!admin) return;
  try {
    await c.env.DB
      .prepare('INSERT INTO admin_audit_log (admin_id, action, target_type, target_id, detail, ip) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(admin.id, action, 'cointrip', targetId, detail, c.req.header('cf-connecting-ip') || '')
      .run();
  } catch {
    // 감사 로그 실패는 무시
  }
}

async function body(c: C): Promise<Record<string, unknown>> {
  try {
    return (await c.req.json()) as Record<string, unknown>;
  } catch {
    return {};
  }
}

// ── 설정 ─────────────────────────────────────────────────────────────
app.get('/settings', async (c) => {
  const rs = await c.env.DB.prepare('SELECT key, value FROM ct_settings').all<{ key: string; value: string }>();
  const out: Record<string, string> = {};
  for (const r of rs.results || []) out[r.key] = r.value;
  return c.json({ settings: out, effective: await loadSettings(c.env) });
});

app.put('/settings', async (c) => {
  const b = await body(c);
  const stmts = [];
  for (const k of SETTING_KEYS) {
    if (!(k in b)) continue;
    let v = String(b[k] ?? '').trim();
    if (k === 'enabled') v = v === '1' || v === 'true' ? '1' : '0';
    else if (k === 'ad_verify') v = v === 'ssv' ? 'ssv' : 'client';
    else if (k === 'rewarded_ad_unit') {
      if (!/^ca-app-pub-\d{16}\/\d{10}$/.test(v)) return c.json({ error: '광고 단위 ID 형식: ca-app-pub-0000000000000000/0000000000' }, 400);
    } else if (k === 'dud_penalty_qta') {
      if (!/^\d{1,6}$/.test(v)) return c.json({ error: '꽝 QTA: 0 이상 정수' }, 400);
    } else if (k === 'daily_pick_max') {
      if (!/^\d{1,6}$/.test(v)) return c.json({ error: '하루 줍기 한도: 0 이상 정수 (0 = 한도 없음)' }, 400);
    } else if (k === 'tester_ids' || k === 'blocked_ids') v = v.split(/[\s,]+/).filter((x) => /^[0-9a-f-]{36}$/i.test(x)).join(',');
    else if (!Number.isFinite(Number(v)) || Number(v) <= 0) return c.json({ error: `${k}: 숫자를 넣어 주세요` }, 400);
    stmts.push(c.env.DB.prepare('INSERT INTO ct_settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value').bind(k, v));
  }
  if (stmts.length) await c.env.DB.batch(stmts);
  await audit(c, 'cointrip_settings', null, JSON.stringify(b).slice(0, 500));
  return c.json({ ok: true, effective: await loadSettings(c.env) });
});

// ── 코인 종류 ────────────────────────────────────────────────────────
function coinOut(r: Record<string, unknown>) {
  return {
    ...r,
    withdraw_min: fromMicro(Number(r.withdraw_min_micro ?? 0)),
    budget: r.budget_micro == null ? null : fromMicro(Number(r.budget_micro)),
  };
}

app.get('/coins', async (c) => {
  const rs = await c.env.DB.prepare('SELECT * FROM ct_coins ORDER BY created_at').all();
  return c.json({ coins: (rs.results || []).map(coinOut) });
});

function readCoin(b: Record<string, unknown>, partial: boolean) {
  const out: Record<string, unknown> = {};
  const err = (m: string) => ({ error: m });
  if (!partial || 'symbol' in b) {
    const v = String(b.symbol ?? '').trim().toUpperCase();
    if (!/^[A-Z0-9]{1,12}$/.test(v)) return err('심볼은 영문 대문자·숫자 1~12자');
    out.symbol = v;
  }
  if (!partial || 'name' in b) {
    const v = String(b.name ?? '').trim();
    if (!v || v.length > 30) return err('이름은 1~30자');
    out.name = v;
  }
  // 체인을 고르면 받는 지갑 종류가 정해진다 (Quantarium → 퀀타리움 소속, 나머지 → 일반).
  if (!partial || 'network' in b) {
    const n = NETWORKS.find((x) => x.name === String(b.network ?? ''));
    if (!n) return err(`체인을 고르세요 (${NETWORKS.map((x) => x.name).join(' · ')})`);
    out.network = n.name;
    out.wallet_kind = n.kind;
  }
  if ('color' in b) {
    const v = String(b.color ?? '').trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(v)) return err('색은 #RRGGBB');
    out.color = v;
  }
  if ('withdraw_min' in b) {
    const v = toMicro(b.withdraw_min);
    if (v == null) return err('출금 최소 수량을 확인하세요 (소수 6자리까지)');
    out.withdraw_min_micro = v;
  }
  if ('budget' in b) {
    if (b.budget === null || String(b.budget).trim() === '') out.budget_micro = null;
    else {
      const v = toMicro(b.budget);
      if (v == null) return err('예산을 확인하세요');
      out.budget_micro = v;
    }
  }
  if ('active' in b) out.active = b.active === true || b.active === 1 || b.active === '1' ? 1 : 0;
  return { values: out };
}

app.post('/coins', async (c) => {
  const r = readCoin(await body(c), false);
  if ('error' in r) return c.json(r, 400);
  const id = crypto.randomUUID();
  const v = { id, ...r.values };
  const cols = Object.keys(v);
  await c.env.DB
    .prepare(`INSERT INTO ct_coins (${cols.join(',')}) VALUES (${cols.map(() => '?').join(',')})`)
    .bind(...cols.map((k) => (v as Record<string, unknown>)[k]))
    .run();
  await audit(c, 'cointrip_coin_create', id, JSON.stringify(r.values));
  return c.json({ ok: true, id });
});

app.put('/coins/:id', async (c) => {
  const r = readCoin(await body(c), true);
  if ('error' in r) return c.json(r, 400);
  const cols = Object.keys(r.values);
  if (!cols.length) return c.json({ ok: true });
  // 받는 주소 종류(체인)는 출금 대기·잔액이 있으면 바꾸지 않는다 (엉뚱한 주소로 나갈 수 있다).
  if ('network' in r.values) {
    const used = await c.env.DB
      .prepare(
        `SELECT 1 FROM ct_balances WHERE coin_id = ?1 AND amount_micro > 0
         UNION SELECT 1 FROM ct_withdrawals WHERE coin_id = ?1 AND status IN ('requested','processing') LIMIT 1`,
      )
      .bind(c.req.param('id'))
      .first();
    const cur = await c.env.DB
      .prepare('SELECT wallet_kind, network FROM ct_coins WHERE id = ?')
      .bind(c.req.param('id'))
      .first<{ wallet_kind: string; network: string }>();
    const next = { wallet_kind: String(r.values.wallet_kind), network: String(r.values.network) };
    if (used && cur && walletKeyOf(cur) !== walletKeyOf(next)) {
      return c.json({ error: '이미 회원 잔액·출금이 있는 코인은 받는 주소가 다른 체인으로 바꿀 수 없어요' }, 409);
    }
  }
  await c.env.DB
    .prepare(`UPDATE ct_coins SET ${cols.map((k) => `${k} = ?`).join(', ')} WHERE id = ?`)
    .bind(...cols.map((k) => r.values[k]), c.req.param('id'))
    .run();
  await audit(c, 'cointrip_coin_update', c.req.param('id'), JSON.stringify(r.values));
  return c.json({ ok: true });
});

// ── 뿌리기 ───────────────────────────────────────────────────────────
app.get('/drops', async (c) => {
  const status = c.req.query('status') || 'active';
  // 사라지는 시간이 지난 코인은 회원 지도에 안 나온다 — '깔려 있음'에서 빼고 '시간 지나 사라짐'으로 따로 본다.
  const timeCond =
    status === 'active'
      ? "AND (d.expires_at IS NULL OR d.expires_at > datetime('now'))"
      : status === 'expired'
        ? "AND d.expires_at IS NOT NULL AND d.expires_at <= datetime('now')"
        : '';
  const coin = c.req.query('coin_id') || '';
  const limit = Math.min(Number(c.req.query('limit')) || 200, 1000);
  const rs = await c.env.DB
    .prepare(
      `SELECT d.id, d.coin_id, k.symbol, k.color, d.amount_micro, d.lat, d.lng, d.is_black, d.is_dud, d.status,
              d.batch_id, d.created_at, d.expires_at, d.picked_at, u.nickname AS picked_by_nickname
         FROM ct_drops d JOIN ct_coins k ON k.id = d.coin_id LEFT JOIN users u ON u.id = d.picked_by
        WHERE d.status = ? AND (? = '' OR d.coin_id = ?) ${timeCond}
        ORDER BY COALESCE(d.picked_at, d.created_at) DESC LIMIT ?`,
    )
    .bind(status === 'expired' ? 'active' : status, coin, coin, limit)
    .all<Record<string, unknown>>();
  return c.json({ drops: (rs.results || []).map((d) => ({ ...d, amount: fromMicro(Number(d.amount_micro)) })) });
});

/**
 * { coin_id, lat, lng, radius_m (0 = 그 자리 1개), count, amount_min, amount_max, black_percent, expires_hours }
 * 수량은 amount_min~amount_max 사이에서 고르게 (같으면 고정).
 */
app.post('/drops', async (c) => {
  const b = await body(c);
  const coin = await c.env.DB
    .prepare('SELECT id, symbol, budget_micro FROM ct_coins WHERE id = ?')
    .bind(String(b.coin_id ?? ''))
    .first<{ id: string; symbol: string; budget_micro: number | null }>();
  if (!coin) return c.json({ error: '코인을 고르세요' }, 400);
  const lat = Number(b.lat);
  const lng = Number(b.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return c.json({ error: '위도·경도를 확인하세요' }, 400);
  }
  const radius = Math.max(0, Math.min(50_000, Number(b.radius_m) || 0));
  const count = radius === 0 ? 1 : Math.max(1, Math.min(500, Math.round(Number(b.count) || 1)));
  // 코인 수량은 정수 개만 (사장님 지시 — 소수점 없이).
  const isInt = (v: unknown) => /^\d{1,12}$/.test(String(v ?? '').trim());
  const maxIn = String(b.amount_max ?? '').trim() === '' ? b.amount_min : b.amount_max;
  if (!isInt(b.amount_min) || !isInt(maxIn)) return c.json({ error: '수량은 1 이상 정수로 넣어 주세요 (소수점 없이)' }, 400);
  const minC = Number(String(b.amount_min).trim());
  const maxC = Number(String(maxIn).trim());
  if (minC < 1 || maxC < minC) return c.json({ error: '수량을 확인하세요 (1 ≤ 최소 ≤ 최대)' }, 400);
  const blackPct = Math.max(0, Math.min(100, Number(b.black_percent) || 0));
  // 블랙코인 안의 결과: 꽝(아무것도 없음) % · 벌칙(광고 또는 QTA 내기) % · 나머지는 좋은 코인.
  const dudPct = Math.max(0, Math.min(100, Number(b.dud_percent) || 0));
  const penaltyPct = Math.max(0, Math.min(100 - dudPct, Number(b.penalty_percent) || 0));
  // 광고 보고 열기 % — 광고를 끝까지 봐야 받는 좋은 코인 (예산에 들어간다).
  const revealPct = Math.max(0, Math.min(100 - dudPct - penaltyPct, Number(b.reveal_percent) || 0));
  const hours = Number(b.expires_hours) || 0;

  const rand = () => crypto.getRandomValues(new Uint32Array(1))[0] / 0xffffffff;
  const items: { amt: number; black: number; dud: number }[] = [];
  for (let i = 0; i < count; i++) {
    const black = rand() * 100 < blackPct ? 1 : 0;
    const roll = rand() * 100;
    const dud = !black ? 0 : roll < dudPct ? 1 : roll < dudPct + penaltyPct ? 2 : roll < dudPct + penaltyPct + revealPct ? 3 : 0;
    items.push({ amt: (minC + Math.min(maxC - minC, Math.floor(rand() * (maxC - minC + 1)))) * MICRO, black, dud });
  }
  const duds = items.filter((x) => x.dud === 1).length;
  const penalties = items.filter((x) => x.dud === 2).length;
  const reveals = items.filter((x) => x.dud === 3).length;
  // 꽝은 지급이 없으니 예산에 넣지 않는다.
  // 꽝·벌칙은 지급이 없어 예산에 넣지 않는다 (광고 보고 열기는 지급되니 넣는다).
  const total = items.reduce((a, x) => a + (x.dud === 1 || x.dud === 2 ? 0 : x.amt), 0);
  if (coin.budget_micro != null) {
    const used = await c.env.DB
      .prepare("SELECT COALESCE(SUM(amount_micro), 0) AS n FROM ct_drops WHERE coin_id = ? AND is_dud IN (0, 3) AND status IN ('active','picked')")
      .bind(coin.id)
      .first<{ n: number }>();
    if ((used?.n ?? 0) + total > coin.budget_micro) {
      return c.json({
        error: `예산을 넘어요 — 예산 ${fromMicro(coin.budget_micro)}, 이미 뿌림 ${fromMicro(used?.n ?? 0)}, 이번 ${fromMicro(total)} ${coin.symbol}`,
      }, 400);
    }
  }

  const batchId = crypto.randomUUID();
  const adminId = c.get('admin')?.id ?? null;
  const stmt = c.env.DB.prepare(
    `INSERT INTO ct_drops (id, coin_id, amount_micro, lat, lng, is_black, is_dud, batch_id, created_by, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ${hours > 0 ? `datetime('now', '+${Math.round(hours)} hours')` : 'NULL'})`,
  );
  const stmts = [];
  for (const it of items) {
    // 원 안에 고르게: 반지름은 √u 배.
    const [u1, u2] = [rand(), rand()];
    const r = radius * Math.sqrt(u1);
    const t = 2 * Math.PI * u2;
    const pLat = lat + (r * Math.cos(t)) / 111_320;
    const pLng = lng + (r * Math.sin(t)) / (111_320 * Math.max(0.1, Math.cos((lat * Math.PI) / 180)));
    stmts.push(stmt.bind(crypto.randomUUID(), coin.id, it.amt, pLat, pLng, it.black, it.dud, batchId, adminId));
  }
  for (let i = 0; i < stmts.length; i += 100) await c.env.DB.batch(stmts.slice(i, i + 100));
  await audit(c, 'cointrip_drop', batchId, `${coin.symbol} x${count} total ${fromMicro(total)} @${lat.toFixed(5)},${lng.toFixed(5)} r${radius} black ${items.filter((x) => x.black).length} dud ${duds} penalty ${penalties}`);
  return c.json({ ok: true, batch_id: batchId, count, black: items.filter((x) => x.black).length, duds, penalties, reveals, total: fromMicro(total) });
});

app.post('/drops/:id/cancel', async (c) => {
  const r = await c.env.DB
    .prepare("UPDATE ct_drops SET status = 'cancelled' WHERE id = ? AND status = 'active'")
    .bind(c.req.param('id'))
    .run();
  await audit(c, 'cointrip_drop_cancel', c.req.param('id'), null);
  return c.json({ ok: true, cancelled: r.meta.changes });
});

app.post('/batches/:id/cancel', async (c) => {
  const r = await c.env.DB
    .prepare("UPDATE ct_drops SET status = 'cancelled' WHERE batch_id = ? AND status = 'active'")
    .bind(c.req.param('id'))
    .run();
  await audit(c, 'cointrip_batch_cancel', c.req.param('id'), String(r.meta.changes));
  return c.json({ ok: true, cancelled: r.meta.changes });
});

// ── 현황 ─────────────────────────────────────────────────────────────
app.get('/stats', async (c) => {
  const rs = await c.env.DB
    .prepare(
      `SELECT k.id, k.symbol, k.name, k.color, k.wallet_kind, k.budget_micro, k.active,
              (SELECT COUNT(*) FROM ct_drops d WHERE d.coin_id = k.id AND d.status = 'active'
                 AND (d.expires_at IS NULL OR d.expires_at > datetime('now'))) AS active_count,
              (SELECT COALESCE(SUM(amount_micro),0) FROM ct_drops d WHERE d.coin_id = k.id AND d.status = 'active'
                 AND (d.expires_at IS NULL OR d.expires_at > datetime('now'))) AS active_micro,
              (SELECT COUNT(*) FROM ct_drops d WHERE d.coin_id = k.id AND d.status = 'picked' AND d.is_dud IN (0, 3)) AS picked_count,
              (SELECT COALESCE(SUM(amount_micro),0) FROM ct_drops d WHERE d.coin_id = k.id AND d.status = 'picked' AND d.is_dud IN (0, 3)) AS picked_micro,
              (SELECT COALESCE(SUM(amount_micro),0) FROM ct_balances b WHERE b.coin_id = k.id) AS balance_micro,
              (SELECT COALESCE(SUM(amount_micro),0) FROM ct_withdrawals w WHERE w.coin_id = k.id AND w.status IN ('requested','processing')) AS pending_micro,
              (SELECT COALESCE(SUM(amount_micro),0) FROM ct_withdrawals w WHERE w.coin_id = k.id AND w.status = 'completed') AS paid_micro
         FROM ct_coins k ORDER BY k.created_at`,
    )
    .all<Record<string, number | string | null>>();
  const f = (v: unknown) => fromMicro(Number(v ?? 0));
  const today = await c.env.DB
    .prepare("SELECT COUNT(*) AS n, COUNT(DISTINCT picked_by) AS u FROM ct_drops WHERE status = 'picked' AND picked_at >= datetime('now', '-1 day')")
    .first<{ n: number; u: number }>();
  const unions = await c.env.DB.prepare('SELECT COUNT(*) AS n FROM ct_unions').first<{ n: number }>();
  const duds = await c.env.DB
    .prepare("SELECT SUM(status = 'ad') AS ad, SUM(status = 'paid') AS paid, SUM(status = 'pending') AS pending, COALESCE(SUM(deducted), 0) AS qta FROM ct_dud_penalties")
    .first<{ ad: number | null; paid: number | null; pending: number | null; qta: number }>();
  return c.json({
    coins: (rs.results || []).map((r) => ({
      id: r.id, symbol: r.symbol, name: r.name, color: r.color, wallet_kind: r.wallet_kind, active: r.active,
      budget: r.budget_micro == null ? null : f(r.budget_micro),
      active_count: r.active_count, active_amount: f(r.active_micro),
      picked_count: r.picked_count, picked: f(r.picked_micro),
      balance: f(r.balance_micro), pending: f(r.pending_micro), paid: f(r.paid_micro),
    })),
    picks_24h: today?.n ?? 0,
    pickers_24h: today?.u ?? 0,
    unions: unions?.n ?? 0,
    duds: { ad: duds?.ad ?? 0, paid: duds?.paid ?? 0, pending: duds?.pending ?? 0, qta: duds?.qta ?? 0 },
  });
});

// ── 출금 ─────────────────────────────────────────────────────────────
app.get('/withdrawals', async (c) => {
  const status = c.req.query('status') || 'open';
  const rs = await c.env.DB
    .prepare(
      `SELECT w.*, k.symbol, k.network, u.nickname,
              (SELECT COUNT(*) FROM ct_flags f WHERE f.user_id = w.user_id AND f.kind != 'limit'
                 AND f.created_at >= datetime('now', '-30 days')) AS flag_count
         FROM ct_withdrawals w JOIN ct_coins k ON k.id = w.coin_id LEFT JOIN users u ON u.id = w.user_id
        WHERE (?1 = 'open' AND w.status IN ('requested','processing')) OR w.status = ?1
        ORDER BY w.requested_at ${status === 'open' ? 'ASC' : 'DESC'} LIMIT 300`,
    )
    .bind(status)
    .all<Record<string, unknown>>();
  return c.json({ rows: (rs.results || []).map((w) => ({ ...w, amount: fromMicro(Number(w.amount_micro)) })) });
});

app.post('/withdrawals/:id/processing', async (c) => {
  const r = await c.env.DB
    .prepare("UPDATE ct_withdrawals SET status = 'processing', processed_at = datetime('now') WHERE id = ? AND status = 'requested'")
    .bind(c.req.param('id'))
    .run();
  if (!r.meta.changes) return c.json({ error: '대기 중인 신청이 아니에요' }, 409);
  await audit(c, 'cointrip_withdraw_processing', c.req.param('id'), null);
  return c.json({ ok: true });
});

app.post('/withdrawals/:id/complete', async (c) => {
  const tx = String((await body(c)).tx_hash ?? '').trim();
  if (tx.length < 10 || tx.length > 120) return c.json({ error: '트랜잭션 해시를 넣어 주세요' }, 400);
  const r = await c.env.DB
    .prepare("UPDATE ct_withdrawals SET status = 'completed', tx_hash = ?, processed_at = datetime('now') WHERE id = ? AND status IN ('requested','processing')")
    .bind(tx, c.req.param('id'))
    .run();
  if (!r.meta.changes) return c.json({ error: '처리할 수 없는 상태예요' }, 409);
  await audit(c, 'cointrip_withdraw_complete', c.req.param('id'), tx);
  return c.json({ ok: true });
});

app.post('/withdrawals/:id/reject', async (c) => {
  const reason = String((await body(c)).reason ?? '').trim().slice(0, 200);
  if (!reason) return c.json({ error: '거부 사유를 넣어 주세요' }, 400);
  const w = await c.env.DB
    .prepare("SELECT id, user_id, coin_id, amount_micro FROM ct_withdrawals WHERE id = ? AND status IN ('requested','processing')")
    .bind(c.req.param('id'))
    .first<{ id: string; user_id: string; coin_id: string; amount_micro: number }>();
  if (!w) return c.json({ error: '처리할 수 없는 상태예요' }, 409);
  const done = await c.env.DB
    .prepare("UPDATE ct_withdrawals SET status = 'rejected', reject_reason = ?, processed_at = datetime('now') WHERE id = ? AND status IN ('requested','processing')")
    .bind(reason, w.id)
    .run();
  if (!done.meta.changes) return c.json({ error: '처리할 수 없는 상태예요' }, 409);
  await c.env.DB.batch([
    c.env.DB
      .prepare(
        `INSERT INTO ct_balances (user_id, coin_id, amount_micro) VALUES (?, ?, ?)
         ON CONFLICT(user_id, coin_id) DO UPDATE SET amount_micro = amount_micro + excluded.amount_micro, updated_at = datetime('now')`,
      )
      .bind(w.user_id, w.coin_id, w.amount_micro),
    c.env.DB
      .prepare("INSERT INTO ct_ledger (id, user_id, coin_id, amount_micro, reason, withdrawal_id) VALUES (?, ?, ?, ?, 'withdrawal_refund', ?)")
      .bind(crypto.randomUUID(), w.user_id, w.coin_id, w.amount_micro, w.id),
  ]);
  await audit(c, 'cointrip_withdraw_reject', w.id, reason);
  return c.json({ ok: true });
});

app.get('/acks', async (c) => {
  const uid = c.req.query('user_id') || '';
  const rs = await c.env.DB
    .prepare(
      `SELECT a.id, a.user_id, u.nickname, a.context, a.detail, a.created_at
         FROM wallet_notice_acks a LEFT JOIN users u ON u.id = a.user_id
        WHERE (? = '' OR a.user_id = ?) ORDER BY a.created_at DESC LIMIT 300`,
    )
    .bind(uid, uid)
    .all();
  return c.json({ rows: rs.results || [] });
});

// ── 의심 회원 (위치 조작) ─────────────────────────────────────────────
// limit (하루 한도 닿음) 은 열심히 하는 회원도 닿으니 참고용 — 의심 점수에는 넣지 않는다.
app.get('/suspects', async (c) => {
  const days = Math.min(90, Math.max(1, Number(c.req.query('days')) || 7));
  const rs = await c.env.DB
    .prepare(
      `SELECT f.user_id, u.nickname,
              SUM(f.kind = 'mocked') AS mocked, SUM(f.kind = 'jump') AS jump, SUM(f.kind = 'too_fast') AS too_fast,
              SUM(f.kind = 'too_far') AS too_far, SUM(f.kind = 'limit') AS limit_days,
              SUM(f.kind != 'limit') AS score, MAX(f.created_at) AS last_at,
              (SELECT COUNT(*) FROM ct_drops d WHERE d.picked_by = f.user_id AND d.status = 'picked'
                 AND d.picked_at >= datetime('now', '-' || ?1 || ' days')) AS picks
         FROM ct_flags f LEFT JOIN users u ON u.id = f.user_id
        WHERE f.created_at >= datetime('now', '-' || ?1 || ' days')
        GROUP BY f.user_id
        ORDER BY score DESC, last_at DESC LIMIT 300`,
    )
    .bind(days)
    .all<Record<string, unknown>>();
  const blocked = new Set((await loadSettings(c.env)).blockedIds);
  return c.json({ days, rows: (rs.results || []).map((r) => ({ ...r, blocked: blocked.has(String(r.user_id)) })) });
});

app.get('/flags', async (c) => {
  const uid = c.req.query('user_id') || '';
  const rs = await c.env.DB
    .prepare('SELECT id, kind, detail, lat, lng, created_at FROM ct_flags WHERE user_id = ? ORDER BY created_at DESC LIMIT 200')
    .bind(uid)
    .all();
  return c.json({ rows: rs.results || [] });
});

app.post('/block', async (c) => {
  const b = await body(c);
  const uid = String(b.user_id ?? '').trim();
  if (!/^[0-9a-f-]{36}$/i.test(uid)) return c.json({ error: '회원 id 를 확인해 주세요' }, 400);
  const ids = new Set((await loadSettings(c.env)).blockedIds);
  if (b.blocked === true) ids.add(uid);
  else ids.delete(uid);
  await c.env.DB
    .prepare("INSERT INTO ct_settings (key, value) VALUES ('blocked_ids', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
    .bind([...ids].join(','))
    .run();
  await audit(c, b.blocked === true ? 'cointrip_block' : 'cointrip_unblock', uid, null);
  return c.json({ ok: true, blocked: ids.has(uid) });
});

export default app;
