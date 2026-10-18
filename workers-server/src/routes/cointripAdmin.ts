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
 */
import { Hono } from 'hono';
import type { Context } from 'hono';
import type { Env, Variables } from '../types';
import { NETWORKS, SETTING_KEYS, fromMicro, loadSettings, toMicro, walletKeyOf } from '../cointrip';

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
    else if (k === 'tester_ids') v = v.split(/[\s,]+/).filter((x) => /^[0-9a-f-]{36}$/i.test(x)).join(',');
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
  const coin = c.req.query('coin_id') || '';
  const limit = Math.min(Number(c.req.query('limit')) || 200, 1000);
  const rs = await c.env.DB
    .prepare(
      `SELECT d.id, d.coin_id, k.symbol, k.color, d.amount_micro, d.lat, d.lng, d.is_black, d.status,
              d.batch_id, d.created_at, d.expires_at, d.picked_at, u.nickname AS picked_by_nickname
         FROM ct_drops d JOIN ct_coins k ON k.id = d.coin_id LEFT JOIN users u ON u.id = d.picked_by
        WHERE d.status = ? AND (? = '' OR d.coin_id = ?)
        ORDER BY COALESCE(d.picked_at, d.created_at) DESC LIMIT ?`,
    )
    .bind(status, coin, coin, limit)
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
  const min = toMicro(b.amount_min);
  const max = toMicro(b.amount_max ?? b.amount_min);
  if (!min || !max || max < min) return c.json({ error: '수량을 확인하세요 (최소 ≤ 최대, 소수 6자리까지)' }, 400);
  const blackPct = Math.max(0, Math.min(100, Number(b.black_percent) || 0));
  const hours = Number(b.expires_hours) || 0;

  const amounts: number[] = [];
  for (let i = 0; i < count; i++) {
    const r = crypto.getRandomValues(new Uint32Array(1))[0] / 0xffffffff;
    amounts.push(min + Math.floor(r * (max - min + 1)));
  }
  const total = amounts.reduce((a, x) => a + x, 0);
  if (coin.budget_micro != null) {
    const used = await c.env.DB
      .prepare("SELECT COALESCE(SUM(amount_micro), 0) AS n FROM ct_drops WHERE coin_id = ? AND status IN ('active','picked')")
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
    `INSERT INTO ct_drops (id, coin_id, amount_micro, lat, lng, is_black, batch_id, created_by, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ${hours > 0 ? `datetime('now', '+${Math.round(hours)} hours')` : 'NULL'})`,
  );
  const stmts = [];
  for (const amt of amounts) {
    // 원 안에 고르게: 반지름은 √u 배.
    const [u1, u2, u3] = Array.from(crypto.getRandomValues(new Uint32Array(3)), (x) => x / 0xffffffff);
    const r = radius * Math.sqrt(u1);
    const t = 2 * Math.PI * u2;
    const pLat = lat + (r * Math.cos(t)) / 111_320;
    const pLng = lng + (r * Math.sin(t)) / (111_320 * Math.max(0.1, Math.cos((lat * Math.PI) / 180)));
    stmts.push(stmt.bind(crypto.randomUUID(), coin.id, amt, pLat, pLng, u3 * 100 < blackPct ? 1 : 0, batchId, adminId));
  }
  for (let i = 0; i < stmts.length; i += 100) await c.env.DB.batch(stmts.slice(i, i + 100));
  await audit(c, 'cointrip_drop', batchId, `${coin.symbol} x${count} total ${fromMicro(total)} @${lat.toFixed(5)},${lng.toFixed(5)} r${radius}`);
  return c.json({ ok: true, batch_id: batchId, count, total: fromMicro(total) });
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
              (SELECT COUNT(*) FROM ct_drops d WHERE d.coin_id = k.id AND d.status = 'picked') AS picked_count,
              (SELECT COALESCE(SUM(amount_micro),0) FROM ct_drops d WHERE d.coin_id = k.id AND d.status = 'picked') AS picked_micro,
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
  });
});

// ── 출금 ─────────────────────────────────────────────────────────────
app.get('/withdrawals', async (c) => {
  const status = c.req.query('status') || 'open';
  const rs = await c.env.DB
    .prepare(
      `SELECT w.*, k.symbol, k.network, u.nickname
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

export default app;
