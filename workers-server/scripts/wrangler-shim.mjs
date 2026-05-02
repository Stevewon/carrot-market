#!/usr/bin/env node
/**
 * wrangler-shim.mjs
 * ──────────────────────────────────────────────────────────────────────────
 * node_modules/.bin/wrangler 가 이 스크립트를 호출한다.
 * 워크플로의 `Apply D1 migrations` / `Deploy` step 의 env: 블록 덕분에
 * 이 시점에는 CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID 가 환경변수로 들어와 있다.
 *
 * 동작:
 *   1) secret 정제 (공백/줄바꿈/BOM/zero-width/따옴표 제거)
 *   2) 토큰 유효성 + 계정 접근 권한 검증 (Cloudflare API 직접 호출)
 *   3) eggplant-db 조회/생성 → wrangler.toml 의 database_id 자동 패치
 *   4) 정제된 환경변수와 함께 진짜 wrangler 실행
 *
 * 한 번 검증되면 동일 job 안의 후속 wrangler 호출에선 재검증을 생략한다.
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const WORKERS_DIR = resolve(__dirname, '..');
const WRANGLER_TOML = join(WORKERS_DIR, 'wrangler.toml');
const REAL_WRANGLER_PATH_FILE = join(__dirname, '.real-wrangler-path');
const SENTINEL = '/tmp/.auto-fix-deploy.done';

const log  = (...a) => console.log('[wrangler-shim]', ...a);
const warn = (...a) => console.warn('[wrangler-shim] ⚠', ...a);
const die  = (msg) => { console.error(`::error::${msg}`); process.exit(1); };

function sanitize(raw) {
  if (raw == null) return '';
  return String(raw)
    .replace(/[\u200B-\u200D\uFEFF]/g, '')
    .replace(/[\r\n\t]/g, '')
    .trim()
    .replace(/^["']|["']$/g, '');
}

async function cf(token, path, init = {}) {
  const res = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
    ...init,
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = { success: false, raw: text }; }
  return { status: res.status, json };
}

async function preflight() {
  const RAW_TOKEN   = process.env.CLOUDFLARE_API_TOKEN || '';
  const RAW_ACCOUNT = process.env.CLOUDFLARE_ACCOUNT_ID || '';
  const TOKEN   = sanitize(RAW_TOKEN);
  const ACCOUNT = sanitize(RAW_ACCOUNT);

  log(`token   raw_len=${RAW_TOKEN.length} clean_len=${TOKEN.length}`);
  log(`account raw_len=${RAW_ACCOUNT.length} clean_len=${ACCOUNT.length}`);

  if (!TOKEN || !ACCOUNT) {
    warn('CLOUDFLARE_API_TOKEN or CLOUDFLARE_ACCOUNT_ID is empty in this step — skipping preflight; wrangler will likely fail.');
    return { TOKEN: RAW_TOKEN, ACCOUNT: RAW_ACCOUNT };
  }

  // 마스킹
  console.log(`::add-mask::${TOKEN}`);
  console.log(`::add-mask::${ACCOUNT}`);

  // 1) 토큰 검증
  log('verifying token...');
  const tv = await cf(TOKEN, '/user/tokens/verify');
  log(`token verify status=${tv.status} success=${tv.json.success}`);
  if (!tv.json.success) {
    console.error(JSON.stringify(tv.json, null, 2));
    die(
      `CLOUDFLARE_API_TOKEN rejected by Cloudflare even after sanitizing.\n` +
      `errors=${JSON.stringify(tv.json.errors || [])}.\n` +
      `→ GitHub Secret 의 토큰 값이 잘못 저장됐거나 Cloudflare 에서 폐기/만료된 토큰입니다.`
    );
  }

  // 2) 계정 접근 검증
  log('verifying account access...');
  const ac = await cf(TOKEN, `/accounts/${ACCOUNT}`);
  log(`account access status=${ac.status} success=${ac.json.success}`);
  if (!ac.json.success) {
    console.error(JSON.stringify(ac.json, null, 2));
    die(
      `Token is valid but cannot access account ${ACCOUNT}.\n` +
      `→ Account ID 가 다른 계정 것이거나, 토큰의 Account Resources 에 이 계정이 포함되지 않았습니다.`
    );
  }

  // 3) D1 조회/생성 + wrangler.toml 패치
  log('listing D1 databases on this account...');
  const list = await cf(TOKEN, `/accounts/${ACCOUNT}/d1/database?per_page=100`);
  if (!list.json.success) {
    console.error(JSON.stringify(list.json, null, 2));
    die('failed to list D1 databases (token may lack D1:Read).');
  }
  const found = (list.json.result || []).find(d => d.name === 'eggplant-db');
  let dbId = found?.uuid ?? found?.id ?? '';

  if (!dbId) {
    log('eggplant-db not found — creating it now...');
    const created = await cf(TOKEN, `/accounts/${ACCOUNT}/d1/database`, {
      method: 'POST',
      body: JSON.stringify({ name: 'eggplant-db' }),
    });
    if (!created.json.success) {
      console.error(JSON.stringify(created.json, null, 2));
      die('failed to create eggplant-db (token may lack D1:Edit).');
    }
    dbId = created.json.result?.uuid ?? created.json.result?.id ?? '';
    if (!dbId) die('D1 created but UUID missing in response.');
    log(`created eggplant-db uuid=${dbId}`);
  } else {
    log(`found existing eggplant-db uuid=${dbId}`);
  }

  if (!existsSync(WRANGLER_TOML)) die(`wrangler.toml not found at ${WRANGLER_TOML}`);
  const before = readFileSync(WRANGLER_TOML, 'utf8');
  const after = before.replace(/^database_id\s*=\s*".*"$/m, `database_id = "${dbId}"`);
  if (before !== after) {
    writeFileSync(WRANGLER_TOML, after);
    log(`patched wrangler.toml database_id -> ${dbId}`);
  } else {
    log('wrangler.toml already had matching database_id (or pattern didnt match).');
  }

  log('preflight OK.');
  return { TOKEN, ACCOUNT };
}

async function main() {
  let TOKEN = process.env.CLOUDFLARE_API_TOKEN || '';
  let ACCOUNT = process.env.CLOUDFLARE_ACCOUNT_ID || '';

  // 같은 job 안의 두 번째 호출(`Deploy` step) 에선 preflight 생략
  if (!existsSync(SENTINEL)) {
    const r = await preflight();
    TOKEN = r.TOKEN;
    ACCOUNT = r.ACCOUNT;
    try { writeFileSync(SENTINEL, '1'); } catch {}
  } else {
    log('sentinel found — skipping preflight (already done in this job).');
    TOKEN = sanitize(TOKEN);
    ACCOUNT = sanitize(ACCOUNT);
  }

  // 진짜 wrangler 실행
  if (!existsSync(REAL_WRANGLER_PATH_FILE)) {
    die(`real wrangler path file not found: ${REAL_WRANGLER_PATH_FILE}. shim install may have failed.`);
  }
  const realWrangler = readFileSync(REAL_WRANGLER_PATH_FILE, 'utf8').trim();
  if (!existsSync(realWrangler)) {
    die(`real wrangler binary not found at ${realWrangler}.`);
  }

  log(`exec: node ${realWrangler} ${process.argv.slice(2).join(' ')}`);
  const result = spawnSync(process.execPath, [realWrangler, ...process.argv.slice(2)], {
    stdio: 'inherit',
    env: {
      ...process.env,
      CLOUDFLARE_API_TOKEN: TOKEN,
      CLOUDFLARE_ACCOUNT_ID: ACCOUNT,
    },
  });
  process.exit(result.status ?? 1);
}

main().catch(e => {
  console.error('[wrangler-shim] fatal:', e);
  process.exit(1);
});
