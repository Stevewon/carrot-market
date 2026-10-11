// 일본 지역(都道府県 → 市区町村) 목록 생성기.
//   node tool/gen_jp_regions.mjs <ja.json>
// 입력: geolonia japanese-addresses-v2 의 api/ja.json
//   (https://japanese-addresses-v2.geoloniamaps.com/api/ja.json, 좌표는 시구정촌 役所 위치)
// 출력:
//   workers-server/src/regions_jp.ts  — 서버 좌표표 (동네 인증)
//   lib/app/regions_jp.dart           — 앱 2단계 선택 목록 (이름 + 읽기 가나)
// 이름 규칙: '<都道府県> <市区町村>' — 政令市는 行政区까지 붙여 쓴다 ('大阪府 大阪市北区').
// 北方領土 6村(色丹村 등)은 좌표가 실제 役場가 아니라서 제외.
import { readFileSync, writeFileSync } from 'node:fs';

const src = process.argv[2];
if (!src) { console.error('usage: node tool/gen_jp_regions.mjs <ja.json>'); process.exit(1); }
const j = JSON.parse(readFileSync(src, 'utf8'));

// 北方領土 (code 01695~01700, 검사숫자 포함 6자리)
const EXCLUDE = new Set([16951, 16969, 16977, 16985, 16993, 17001]);
const NAME_RE = /^[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}ー々ヶ]+$/u;
const KANA_RE = /^[\p{Script=Katakana}ー・]*$/u;

// 예전 앱 버전의 政令市 통째 이름 — 저장된 회원 데이터가 있어 별칭으로 유지(예전 좌표 그대로).
const LEGACY_ALIASES = {
  '神奈川県 横浜市': { lat: 35.4437, lng: 139.6380 },
  '神奈川県 川崎市': { lat: 35.5308, lng: 139.7029 },
  '埼玉県 さいたま市': { lat: 35.8617, lng: 139.6455 },
  '千葉県 千葉市': { lat: 35.6073, lng: 140.1063 },
  '大阪府 大阪市': { lat: 34.6937, lng: 135.5023 },
  '大阪府 堺市': { lat: 34.5733, lng: 135.4830 },
  '京都府 京都市': { lat: 35.0116, lng: 135.7681 },
  '兵庫県 神戸市': { lat: 34.6901, lng: 135.1955 },
  '愛知県 名古屋市': { lat: 35.1815, lng: 136.9066 },
  '福岡県 福岡市': { lat: 33.5902, lng: 130.4017 },
  '北海道 札幌市': { lat: 43.0618, lng: 141.3545 },
  '宮城県 仙台市': { lat: 38.2682, lng: 140.8694 },
  '広島県 広島市': { lat: 34.3853, lng: 132.4553 },
};

const fail = (m) => { console.error('ERROR: ' + m); process.exit(1); };
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : fail('bad number ' + v));
const r6 = (v) => Math.round(v * 1e6) / 1e6;

if (!Array.isArray(j.data) || j.data.length !== 47) fail('expected 47 prefectures');
const prefs = [];
const all = new Map();
for (const p of [...j.data].sort((a, b) => a.code - b.code)) {
  const pref = String(p.pref);
  if (!NAME_RE.test(pref)) fail('bad pref ' + pref);
  const cities = [];
  for (const c of p.cities) {
    if (EXCLUDE.has(c.code)) continue;
    const short = String(c.city) + String(c.ward ?? '');
    const kana = String(c.city_k ?? '') + String(c.ward_k ?? '');
    if (!NAME_RE.test(short)) fail('bad city ' + short);
    if (!KANA_RE.test(kana)) fail('bad kana ' + kana);
    const [lng, lat] = c.point ?? [];
    num(lat); num(lng);
    if (lat < 20 || lat > 46 || lng < 122 || lng > 154) fail('outside Japan ' + short);
    const name = `${pref} ${short}`;
    if (all.has(name)) fail('dup ' + name);
    const e = { name, short, kana, lat: r6(lat), lng: r6(lng) };
    all.set(name, e);
    cities.push(e);
  }
  prefs.push({ pref, cities });
}
for (const a of Object.keys(LEGACY_ALIASES)) if (all.has(a)) fail('alias collides ' + a);

const total = all.size;
const head = '// 자동 생성 — 직접 고치지 말 것. node tool/gen_jp_regions.mjs <ja.json>\n'
  + '// 출처: geolonia japanese-addresses-v2 (api/ja.json, 市区町村役所 좌표). '
  + `都道府県 ${prefs.length} · 市区町村 ${total}\n`;

// --- server ---
let ts = head + '\n/** 일본 都道府県 (JIS 코드 순). */\n'
  + `export const JP_PREFECTURES: readonly string[] = ${JSON.stringify(prefs.map((p) => p.pref))};\n\n`
  + '/** 일본 지역 중심 좌표. 이름은 앱 lib/app/regions_jp.dart 와 같아야 한다. */\n'
  + 'export const JP_REGION_CENTERS: Record<string, { lat: number; lng: number }> = {\n';
for (const p of prefs) {
  ts += `  // ${p.pref}\n`;
  for (const e of p.cities) ts += `  ${JSON.stringify(e.name)}: { lat: ${e.lat}, lng: ${e.lng} },\n`;
}
ts += '};\n\n/** 예전 앱의 政令市 통째 이름 — 저장된 회원 데이터 호환용. 새로 고를 수는 없다. */\n'
  + 'export const JP_REGION_ALIASES: Record<string, { lat: number; lng: number }> = {\n';
for (const [k, v] of Object.entries(LEGACY_ALIASES)) ts += `  ${JSON.stringify(k)}: { lat: ${v.lat}, lng: ${v.lng} },\n`;
ts += '};\n';
writeFileSync('workers-server/src/regions_jp.ts', ts);

// --- app ---
const q = (s) => `'${s}'`; // NAME_RE/KANA_RE 로 따옴표·$·\ 없음 보장
let dart = head + '\n/// 일본 지역 데이터. 이름은 서버 workers-server/src/regions_jp.ts 와 같아야 한다.\n'
  + '/// 전체 이름은 \'<都道府県> <市区町村>\' (예: \'大阪府 大阪市北区\').\n'
  + 'class JpRegionData {\n  JpRegionData._();\n\n'
  + '  /// 都道府県 → [(市区町村, 읽기 가타카나)].\n'
  + '  static const Map<String, List<(String, String)>> byPrefecture = {\n';
for (const p of prefs) {
  dart += `    ${q(p.pref)}: [\n`;
  for (const e of p.cities) dart += `      (${q(e.short)}, ${q(e.kana)}),\n`;
  dart += '    ],\n';
}
dart += '  };\n}\n';
writeFileSync('lib/app/regions_jp.dart', dart);
console.log(`prefectures ${prefs.length}, municipalities ${total}, aliases ${Object.keys(LEGACY_ALIASES).length}`);
