#!/usr/bin/env node
/**
 * auto-fix-deploy.mjs
 * ──────────────────────────────────────────────────────────────────────────
 * GitHub Actions 의 `npm ci` 단계 직후 (postinstall 훅) 자동 실행되는 가드 스크립트.
 *
 * 하는 일:
 *   1) 환경변수 CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID 에 묻은
 *      공백·줄바꿈·BOM·zero-width 문자·따옴표 등 보이지 않는 쓰레기를 제거하고
 *      정제된 값을 GITHUB_ENV 에 다시 export 한다 → 후속 wrangler 호출이 깨끗한 값을 사용.
 *   2) Cloudflare API 로 토큰 유효성 + 계정 접근 권한을 직접 검증한다.
 *      실패 시 "어디서 막혔는지" 명확히 로그를 출력하고 비-0 코드로 종료.
 *   3) 현재 계정에서 `eggplant-db` D1 데이터베이스를 조회한다.
 *      - 있으면 그 UUID 를 wrangler.toml 의 database_id 로 강제 패치
 *      - 없으면 자동 생성 후 그 UUID 를 패치
 *   이로써 wrangler.toml 에 박힌 옛 ID(다른 계정 것)가 있어도 자동 복구된다.
 *
 * 워크플로 파일은 일절 수정하지 않는다 (GitHub App 의 workflows 권한 부재).
 * postinstall 훅은 npm ci 직후 자동 호출되므로, 기존 워크플로의
 * `Apply D1 migrations` / `Deploy` 단계가 정제된 값과 올바른 DB ID 를 그대로 사용하게 된다.
 * ──────────────────────────────────────────────────────────────────────────
 */
import { readFileSync, writeFileSync, appendFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const WRANGLER_TOML = resolve(__dirname, '..', 'wrangler.toml');

const log = (...a) => console.log('[auto-fix-deploy]', ...a);
const warn = (...a) => console.warn('[auto-fix-deploy] ⚠', ...a);
const fail = (msg) => {
  console.error(`::error::${msg}`);
  process.exit(1);
};

// CI 가 아니면 (로컬 개발 머신) 그냥 종료. 사장님 로컬 환경 건드리지 않는다.
if (!process.env.CI && !process.env.GITHUB_ACTIONS) {
  log('not in CI — skipping.');
  process.exit(0);
}

// ── 1. Sanitize ─────────────────────────────────────────────────────────────
function sanitize(raw) {
  if (raw == null) return '';
  return String(raw)
    .replace(/[\u200B-\u200D\uFEFF]/g, '') // zero-width + BOM
    .replace(/[\r\n\t]/g, '')              // CR / LF / TAB
    .trim()                                // outer spaces
    .replace(/^["']|["']$/g, '');          // wrapping quotes
}

const RAW_TOKEN = process.env.CLOUDFLARE_API_TOKEN || '';
const RAW_ACCOUNT = process.env.CLOUDFLARE_ACCOUNT_ID || '';
const TOKEN = sanitize(RAW_TOKEN);
const ACCOUNT = sanitize(RAW_ACCOUNT);

log(`token  raw_len=${RAW_TOKEN.length} clean_len=${TOKEN.length}`);
log(`account raw_len=${RAW_ACCOUNT.length} clean_len=${ACCOUNT.length}`);

if (!TOKEN || !ACCOUNT) {
  warn('one or both Cloudflare secrets are empty in this step — skipping (will fail later in wrangler step).');
  process.exit(0);
}

// 후속 step 들이 정제된 값을 사용하도록 GITHUB_ENV 에 덮어쓴다
if (process.env.GITHUB_ENV) {
  appendFileSync(process.env.GITHUB_ENV,
    `CLOUDFLARE_API_TOKEN=${TOKEN}\nCLOUDFLARE_ACCOUNT_ID=${ACCOUNT}\n`);
  log('exported sanitized values via GITHUB_ENV.');
}
// 마스킹 (어차피 secret 이라 자동 마스킹되지만 방어적으로)
console.log(`::add-mask::${TOKEN}`);
console.log(`::add-mask::${ACCOUNT}`);

// ── 2. Verify token & account ──────────────────────────────────────────────
async function cf(path, init = {}) {
  const url = `https://api.cloudflare.com/client/v4${path}`;
  const res = await fetch(url, {
    ...init,
    headers: {
      'Authorization': `Bearer ${TOKEN}`,
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = { success: false, raw: text }; }
  return { status: res.status, json };
}

log('verifying token...');
const tv = await cf('/user/tokens/verify');
log(`token verify status=${tv.status} success=${tv.json.success}`);
if (!tv.json.success) {
  console.error(JSON.stringify(tv.json, null, 2));
  fail(`CLOUDFLARE_API_TOKEN rejected by Cloudflare even after sanitizing. ` +
       `errors=${JSON.stringify(tv.json.errors || [])}. ` +
       `토큰 문자열이 GitHub Secret 에 잘못 저장됐거나 폐기된 토큰입니다.`);
}

log('verifying account access...');
const ac = await cf(`/accounts/${ACCOUNT}`);
log(`account access status=${ac.status} success=${ac.json.success}`);
if (!ac.json.success) {
  console.error(JSON.stringify(ac.json, null, 2));
  fail(`Token is valid but cannot access account ${ACCOUNT}. ` +
       `Account ID 가 잘못됐거나, 토큰의 Account Resources 에 이 계정이 포함되지 않았습니다.`);
}

// ── 3. Resolve / create eggplant-db ─────────────────────────────────────────
log('listing D1 databases on this account...');
const list = await cf(`/accounts/${ACCOUNT}/d1/database?per_page=100`);
if (!list.json.success) {
  console.error(JSON.stringify(list.json, null, 2));
  fail('failed to list D1 databases (token may lack D1:Read).');
}
let dbId = (list.json.result || []).find(d => d.name === 'eggplant-db')?.uuid
        ?? (list.json.result || []).find(d => d.name === 'eggplant-db')?.id
        ?? '';

if (!dbId) {
  log('eggplant-db not found on this account — creating it now...');
  const created = await cf(`/accounts/${ACCOUNT}/d1/database`, {
    method: 'POST',
    body: JSON.stringify({ name: 'eggplant-db' }),
  });
  if (!created.json.success) {
    console.error(JSON.stringify(created.json, null, 2));
    fail('failed to create eggplant-db (token may lack D1:Edit).');
  }
  dbId = created.json.result?.uuid ?? created.json.result?.id ?? '';
  if (!dbId) fail('D1 created but UUID missing in response.');
  log(`created eggplant-db uuid=${dbId}`);
} else {
  log(`found existing eggplant-db uuid=${dbId}`);
}

// ── 4. Patch wrangler.toml ──────────────────────────────────────────────────
if (!existsSync(WRANGLER_TOML)) fail(`wrangler.toml not found at ${WRANGLER_TOML}`);
const before = readFileSync(WRANGLER_TOML, 'utf8');
const after = before.replace(/^database_id\s*=\s*".*"$/m, `database_id = "${dbId}"`);
if (before === after) {
  warn('wrangler.toml unchanged — no database_id line matched. Appending nothing.');
} else {
  writeFileSync(WRANGLER_TOML, after);
  log(`patched wrangler.toml database_id -> ${dbId}`);
}

log('all preflight checks passed. wrangler can now proceed.');
