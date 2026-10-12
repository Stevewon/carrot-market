// lib/l10n/parts/*_ko.arb, *_ja.arb, *_en.arb 를 합쳐 lib/l10n/app_ko.arb, app_ja.arb, app_en.arb 를 만든다.
// 화면 묶음마다 문구 파일을 따로 두고(동시 작업 시 충돌 방지) 여기서 합친다.
//   node tool/l10n_merge.mjs && flutter gen-l10n
// 같은 키가 두 파트에 있으면 실패. ko 에 있는데 ja/en 에 없는 키(또는 그 반대)도 실패.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = 'lib/l10n';
const parts = join(dir, 'parts');
// ko 는 템플릿, 나머지는 번역본.
const langs = ['ko', 'ja', 'en'];
const others = langs.filter((l) => l !== 'ko');
const out = Object.fromEntries(langs.map((l) => [l, { '@@locale': l }]));
const owner = Object.fromEntries(langs.map((l) => [l, {}]));
const errors = [];

for (const f of readdirSync(parts).sort()) {
  const m = /^(.+)_(ko|ja|en)\.arb$/.exec(f);
  if (!m) continue;
  const lang = m[2];
  let j;
  try {
    j = JSON.parse(readFileSync(join(parts, f), 'utf8'));
  } catch (e) {
    errors.push(`${f}: JSON 오류 ${e.message}`);
    continue;
  }
  for (const [k, v] of Object.entries(j)) {
    if (k.startsWith('@@')) continue;
    if (k in out[lang] && owner[lang][k] !== f) {
      errors.push(`${f}: 키 '${k}' 가 ${owner[lang][k]} 에도 있음`);
      continue;
    }
    out[lang][k] = v;
    owner[lang][k] = f;
  }
}
for (const lang of others) {
  for (const k of Object.keys(out.ko)) {
    if (k.startsWith('@')) continue;
    if (!(k in out[lang])) errors.push(`${lang} 에 '${k}' 없음 (${owner.ko[k]})`);
  }
  for (const k of Object.keys(out[lang])) {
    if (k.startsWith('@')) continue;
    if (!(k in out.ko)) errors.push(`ko 에 '${k}' 없음 (${owner[lang][k]})`);
  }
  // 메타데이터(@key)는 ko(템플릿)에만 둔다.
  for (const k of Object.keys(out[lang])) if (k.startsWith('@') && !k.startsWith('@@')) delete out[lang][k];
}

if (errors.length) {
  console.error(errors.join('\n'));
  process.exit(1);
}
for (const lang of langs) {
  writeFileSync(join(dir, `app_${lang}.arb`), JSON.stringify(out[lang], null, 2) + '\n');
}
console.log(`l10n: ${Object.keys(out.ko).filter((k) => !k.startsWith('@')).length} keys`);
