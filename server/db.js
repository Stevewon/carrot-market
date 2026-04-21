// Pure JavaScript database - no native compilation needed.
// Compatible API with better-sqlite3 (prepare/get/all/run) for our routes.
// Data is persisted as JSON files in ./data/

import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DATA_DIR = path.join(__dirname, 'data');
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
const DB_FILE = path.join(DATA_DIR, 'eggplant.json');

// --- In-memory store, hydrated from disk ---------------------------------
const store = {
  users: [],         // { id, nickname, device_uuid, region, manner_score, created_at, updated_at }
  products: [],      // { id, seller_id, title, description, price, category, region, images, status, view_count, like_count, chat_count, created_at, updated_at }
  product_likes: [], // { id, user_id, product_id, created_at }
  _likeSeq: 1,
};

function loadFromDisk() {
  try {
    if (fs.existsSync(DB_FILE)) {
      const raw = fs.readFileSync(DB_FILE, 'utf-8');
      const data = JSON.parse(raw);
      store.users = data.users || [];
      store.products = data.products || [];
      store.product_likes = data.product_likes || [];
      store._likeSeq = data._likeSeq || (store.product_likes.length + 1);
    }
  } catch (e) {
    console.warn('[db] failed to load existing data, starting empty:', e.message);
  }
}

let saveTimer = null;
function scheduleSave() {
  if (saveTimer) return;
  saveTimer = setTimeout(() => {
    saveTimer = null;
    try {
      fs.writeFileSync(DB_FILE, JSON.stringify(store, null, 2));
    } catch (e) {
      console.error('[db] save failed:', e.message);
    }
  }, 100); // debounce writes
}

function nowIso() {
  // SQLite-style "YYYY-MM-DD HH:MM:SS"
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}`;
}

// --- SQL-ish statement executors ----------------------------------------
// We only implement the exact queries our routes use.
// Each prepared statement is identified by normalized SQL text.

function normalize(sql) {
  return sql.replace(/\s+/g, ' ').trim();
}

function likeToRegex(pattern) {
  // Convert SQL LIKE '%foo%' to RegExp
  const esc = pattern
    .replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    .replace(/%/g, '.*')
    .replace(/_/g, '.');
  return new RegExp('^' + esc + '$', 'i');
}

// Query handlers return { get(...args), all(...args), run(...args) }
const handlers = [
  // ---------- USERS ----------
  {
    match: /^SELECT \* FROM users WHERE device_uuid = \?$/i,
    get: (uuid) => store.users.find((u) => u.device_uuid === uuid) || undefined,
  },
  {
    match: /^SELECT \* FROM users WHERE id = \?$/i,
    get: (id) => store.users.find((u) => u.id === id) || undefined,
  },
  {
    match: /^SELECT nickname, manner_score FROM users WHERE id = \?$/i,
    get: (id) => {
      const u = store.users.find((x) => x.id === id);
      return u ? { nickname: u.nickname, manner_score: u.manner_score } : undefined;
    },
  },
  {
    match: /^INSERT INTO users \(id, nickname, device_uuid, region\) VALUES \(\?, \?, \?, \?\)$/i,
    run: (id, nickname, device_uuid, region) => {
      const now = nowIso();
      store.users.push({
        id,
        nickname,
        device_uuid,
        region: region ?? null,
        manner_score: 36,
        created_at: now,
        updated_at: now,
      });
      scheduleSave();
      return { changes: 1 };
    },
  },

  // ---------- PRODUCTS ----------
  {
    match: /^SELECT \* FROM products WHERE id = \?$/i,
    get: (id) => {
      const p = store.products.find((x) => x.id === id);
      return p ? { ...p } : undefined;
    },
  },
  {
    match: /^INSERT INTO products \(id, seller_id, title, description, price, category, region, images\) VALUES \(\?, \?, \?, \?, \?, \?, \?, \?\)$/i,
    run: (id, seller_id, title, description, price, category, region, images) => {
      const now = nowIso();
      store.products.push({
        id,
        seller_id,
        title,
        description,
        price: Number(price) || 0,
        category,
        region,
        images: images || '',
        status: 'sale',
        view_count: 0,
        like_count: 0,
        chat_count: 0,
        created_at: now,
        updated_at: now,
      });
      scheduleSave();
      return { changes: 1 };
    },
  },
  {
    match: /^UPDATE products SET view_count = view_count \+ 1 WHERE id = \?$/i,
    run: (id) => {
      const p = store.products.find((x) => x.id === id);
      if (p) { p.view_count += 1; scheduleSave(); return { changes: 1 }; }
      return { changes: 0 };
    },
  },
  {
    match: /^UPDATE products SET like_count = MAX\(like_count - 1, 0\) WHERE id = \?$/i,
    run: (id) => {
      const p = store.products.find((x) => x.id === id);
      if (p) { p.like_count = Math.max(p.like_count - 1, 0); scheduleSave(); return { changes: 1 }; }
      return { changes: 0 };
    },
  },
  {
    match: /^UPDATE products SET like_count = like_count \+ 1 WHERE id = \?$/i,
    run: (id) => {
      const p = store.products.find((x) => x.id === id);
      if (p) { p.like_count += 1; scheduleSave(); return { changes: 1 }; }
      return { changes: 0 };
    },
  },
  {
    match: /^UPDATE products SET status = \?, updated_at = datetime\('now'\) WHERE id = \?$/i,
    run: (status, id) => {
      const p = store.products.find((x) => x.id === id);
      if (p) { p.status = status; p.updated_at = nowIso(); scheduleSave(); return { changes: 1 }; }
      return { changes: 0 };
    },
  },
  {
    match: /^DELETE FROM products WHERE id = \?$/i,
    run: (id) => {
      const before = store.products.length;
      store.products = store.products.filter((p) => p.id !== id);
      // cascade likes
      store.product_likes = store.product_likes.filter((l) => l.product_id !== id);
      const changes = before - store.products.length;
      if (changes) scheduleSave();
      return { changes };
    },
  },

  // Dynamic SELECT with filters, LIMIT/OFFSET
  {
    match: /^SELECT \* FROM products( WHERE .+)? ORDER BY created_at DESC LIMIT \? OFFSET \?$/i,
    all: function (...args) {
      // Reconstruct WHERE clause from the original SQL captured at prepare time
      const sql = this._sql;
      const whereMatch = sql.match(/WHERE (.+?) ORDER BY/i);
      let rows = [...store.products];
      const paramsForWhere = args.slice(0, args.length - 2);
      const limit = args[args.length - 2];
      const offset = args[args.length - 1];

      if (whereMatch) {
        const whereExpr = whereMatch[1];
        rows = rows.filter((p) => evalProductWhere(whereExpr, p, [...paramsForWhere]));
      }
      rows.sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
      return rows.slice(offset, offset + limit).map((r) => ({ ...r }));
    },
  },

  // My selling
  {
    match: /^SELECT \* FROM products WHERE seller_id = \? ORDER BY created_at DESC$/i,
    all: (sellerId) => {
      return store.products
        .filter((p) => p.seller_id === sellerId)
        .sort((a, b) => (a.created_at < b.created_at ? 1 : -1))
        .map((r) => ({ ...r }));
    },
  },

  // My likes (JOIN)
  {
    match: /^SELECT p\.\* FROM products p JOIN product_likes l ON l\.product_id = p\.id WHERE l\.user_id = \? ORDER BY l\.created_at DESC$/i,
    all: (userId) => {
      const likes = store.product_likes
        .filter((l) => l.user_id === userId)
        .sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
      const result = [];
      for (const l of likes) {
        const p = store.products.find((x) => x.id === l.product_id);
        if (p) result.push({ ...p });
      }
      return result;
    },
  },

  // ---------- PRODUCT_LIKES ----------
  {
    match: /^SELECT 1 FROM product_likes WHERE user_id = \? AND product_id = \?$/i,
    get: (userId, productId) => {
      const l = store.product_likes.find((x) => x.user_id === userId && x.product_id === productId);
      return l ? { 1: 1 } : undefined;
    },
  },
  {
    match: /^SELECT id FROM product_likes WHERE user_id = \? AND product_id = \?$/i,
    get: (userId, productId) => {
      const l = store.product_likes.find((x) => x.user_id === userId && x.product_id === productId);
      return l ? { id: l.id } : undefined;
    },
  },
  {
    match: /^INSERT INTO product_likes \(user_id, product_id\) VALUES \(\?, \?\)$/i,
    run: (userId, productId) => {
      const id = store._likeSeq++;
      store.product_likes.push({ id, user_id: userId, product_id: productId, created_at: nowIso() });
      scheduleSave();
      return { changes: 1, lastInsertRowid: id };
    },
  },
  {
    match: /^DELETE FROM product_likes WHERE id = \?$/i,
    run: (id) => {
      const before = store.product_likes.length;
      store.product_likes = store.product_likes.filter((l) => l.id !== id);
      const changes = before - store.product_likes.length;
      if (changes) scheduleSave();
      return { changes };
    },
  },

  // ---------- Dynamic UPDATE users SET ... WHERE id = ? ----------
  {
    // Catches both `UPDATE users SET region = ?, updated_at = datetime('now') WHERE id = ?` etc.
    match: /^UPDATE users SET (.+) WHERE id = \?$/i,
    run: function (...args) {
      const sql = this._sql;
      const setMatch = sql.match(/SET (.+?) WHERE id = \?$/i);
      if (!setMatch) return { changes: 0 };
      const setClauses = splitTopLevel(setMatch[1], ',').map((s) => s.trim());
      const id = args[args.length - 1];
      const setValues = args.slice(0, args.length - 1);
      const u = store.users.find((x) => x.id === id);
      if (!u) return { changes: 0 };
      let vi = 0;
      for (const clause of setClauses) {
        const m = clause.match(/^(\w+)\s*=\s*(.+)$/);
        if (!m) continue;
        const col = m[1];
        const rhs = m[2].trim();
        if (rhs === '?') {
          u[col] = setValues[vi++];
        } else if (/^datetime\('now'\)$/i.test(rhs)) {
          u[col] = nowIso();
        }
      }
      scheduleSave();
      return { changes: 1 };
    },
  },
];

function splitTopLevel(str, sep) {
  // simple split - we only use commas in SET clauses, none nested
  return str.split(sep);
}

// Evaluate a WHERE expression for products with AND-joined conditions like
// "category = ? AND region = ? AND (title LIKE ? OR description LIKE ?)"
function evalProductWhere(expr, product, params) {
  // Split on top-level AND
  const parts = splitAnd(expr);
  for (const part of parts) {
    const trimmed = part.trim();
    if (!evalCondition(trimmed, product, params)) return false;
  }
  return true;
}

function splitAnd(expr) {
  const parts = [];
  let depth = 0;
  let current = '';
  const tokens = expr.split(/(\s+AND\s+)/i);
  for (const t of tokens) {
    if (/^\s+AND\s+$/i.test(t) && depth === 0) {
      parts.push(current);
      current = '';
    } else {
      for (const ch of t) {
        if (ch === '(') depth++;
        if (ch === ')') depth--;
      }
      current += t;
    }
  }
  if (current) parts.push(current);
  return parts;
}

function evalCondition(cond, product, params) {
  // Strip wrapping parens
  let c = cond.trim();
  while (c.startsWith('(') && c.endsWith(')')) c = c.slice(1, -1).trim();

  // Handle OR
  if (/\s+OR\s+/i.test(c)) {
    const ors = c.split(/\s+OR\s+/i);
    return ors.some((o) => evalCondition(o, product, params));
  }

  // "col = ?" or "col LIKE ?"
  let m = c.match(/^(\w+)\s*=\s*\?$/i);
  if (m) {
    const val = params.shift();
    return product[m[1]] === val;
  }
  m = c.match(/^(\w+)\s+LIKE\s+\?$/i);
  if (m) {
    const val = params.shift();
    const re = likeToRegex(val);
    return re.test(String(product[m[1]] ?? ''));
  }
  return true;
}

// --- Public API (better-sqlite3-like) -----------------------------------
const db = {
  prepare(sql) {
    const norm = normalize(sql);
    for (const h of handlers) {
      if (h.match.test(norm)) {
        const bound = { _sql: norm };
        if (h.get) bound.get = (...args) => h.get.call(bound, ...args);
        if (h.all) bound.all = (...args) => h.all.call(bound, ...args);
        if (h.run) bound.run = (...args) => h.run.call(bound, ...args);
        // Fill in defaults so code calling .get/.all/.run never crashes
        if (!bound.get) bound.get = () => undefined;
        if (!bound.all) bound.all = () => [];
        if (!bound.run) bound.run = () => ({ changes: 0 });
        return bound;
      }
    }
    // Fallback - unknown query just no-ops (shouldn't happen)
    console.warn('[db] unhandled SQL:', norm);
    return {
      get: () => undefined,
      all: () => [],
      run: () => ({ changes: 0 }),
    };
  },
  // No-op for pragma/exec in schema init
  pragma() {},
  exec() {},
};

loadFromDisk();
console.log('[db] schema initialized ✅ (pure-JS, no native build required)');

export default db;
