// 앱 지역 목록과 서버 좌표표가 정확히 같은지 확인.
//   node tool/check_regions.mjs
// 한국: lib/app/regions.dart AppRegions.kr  ↔  workers-server/src/regions.ts REGION_CENTERS
// 일본: lib/app/regions_jp.dart (都道府県 + 市区町村) ↔ workers-server/src/regions_jp.ts JP_REGION_CENTERS
//       예전 이름(JP_REGION_ALIASES)은 서버에만 있고 새 목록과 겹치면 안 된다.
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(p, 'utf8').replace(/\r\n/g, '\n');
const errors = [];

/** `name = {` 또는 `name: T = {` 부터 짝 맞는 `};` 까지의 블록. */
function block(src, startRe) {
  const m = startRe.exec(src);
  if (!m) throw new Error('block not found: ' + startRe);
  const end = src.indexOf('\n};', m.index);
  return src.slice(m.index, end);
}
const tsKeys = (b) => [...b.matchAll(/^\s*['"]([^'"]+)['"]\s*:\s*\{\s*lat:\s*(-?[\d.]+),\s*lng:\s*(-?[\d.]+)/gm)]
  .map((m) => ({ name: m[1], lat: +m[2], lng: +m[3] }));

function compare(label, app, server) {
  const a = new Set(app), s = new Set(server);
  if (a.size !== app.length) errors.push(`${label}: 앱 목록에 중복`);
  if (s.size !== server.length) errors.push(`${label}: 서버 목록에 중복`);
  for (const x of a) if (!s.has(x)) errors.push(`${label}: 앱에만 있음 '${x}'`);
  for (const x of s) if (!a.has(x)) errors.push(`${label}: 서버에만 있음 '${x}'`);
  if (app.join('\n') !== server.join('\n')) {
    if (a.size === s.size && [...a].every((x) => s.has(x))) errors.push(`${label}: 순서가 다름`);
  }
  console.log(`${label}: 앱 ${app.length} · 서버 ${server.length}`);
}

// --- 한국 ---
const krTs = tsKeys(block(read('workers-server/src/regions.ts'), /export const REGION_CENTERS\b/));
const krDartBlock = /static const List<String> kr = \[([\s\S]*?)\];/.exec(read('lib/app/regions.dart'))[1];
const krDart = [...krDartBlock.matchAll(/'([^']+)'/g)].map((m) => m[1]);
compare('KR', krDart, krTs.map((e) => e.name));

// --- 일본 ---
const jpTsSrc = read('workers-server/src/regions_jp.ts');
const jpTs = tsKeys(block(jpTsSrc, /export const JP_REGION_CENTERS\b/));
const aliases = tsKeys(block(jpTsSrc, /export const JP_REGION_ALIASES\b/)).map((e) => e.name);
const prefTs = JSON.parse(/export const JP_PREFECTURES[^=]*=\s*(\[[^\]]*\])/.exec(jpTsSrc)[1]);

const jpDart = [];
const prefDart = [];
let cur = null;
for (const line of read('lib/app/regions_jp.dart').split('\n')) {
  let m;
  if ((m = /^    '([^']+)': \[$/.exec(line))) { cur = m[1]; prefDart.push(cur); continue; }
  if ((m = /^      \('([^']+)', '([^']*)'\),$/.exec(line))) {
    if (!cur) errors.push('dart: 都道府県 밖의 항목 ' + m[1]);
    jpDart.push(`${cur} ${m[1]}`);
  }
}
compare('JP 都道府県', prefDart, prefTs);
compare('JP 市区町村', jpDart, jpTs.map((e) => e.name));
if (prefDart.length !== 47) errors.push(`JP: 都道府県이 47이 아님 (${prefDart.length})`);

for (const a of aliases) if (jpDart.includes(a)) errors.push(`JP 별칭 '${a}' 가 새 목록과 겹침`);
for (const e of jpTs) {
  if (!(e.lat >= 20 && e.lat <= 46 && e.lng >= 122 && e.lng <= 154)) errors.push(`JP 좌표가 일본 밖 '${e.name}'`);
  const pref = e.name.split(' ')[0];
  if (!prefTs.includes(pref)) errors.push(`JP 알 수 없는 都道府県 '${e.name}'`);
}

// 예전 앱의 37개 이름은 계속 유효해야 한다 (새 목록 또는 별칭).
const legacy = [
  '東京都 千代田区', '東京都 中央区', '東京都 港区', '東京都 新宿区', '東京都 文京区', '東京都 台東区',
  '東京都 墨田区', '東京都 江東区', '東京都 品川区', '東京都 目黒区', '東京都 大田区', '東京都 世田谷区',
  '東京都 渋谷区', '東京都 中野区', '東京都 杉並区', '東京都 豊島区', '東京都 北区', '東京都 荒川区',
  '東京都 板橋区', '東京都 練馬区', '東京都 足立区', '東京都 葛飾区', '東京都 江戸川区',
  '神奈川県 横浜市', '神奈川県 川崎市', '埼玉県 さいたま市', '千葉県 千葉市', '大阪府 大阪市', '大阪府 堺市',
  '京都府 京都市', '兵庫県 神戸市', '愛知県 名古屋市', '福岡県 福岡市', '北海道 札幌市', '宮城県 仙台市',
  '広島県 広島市', '沖縄県 那覇市',
];
const valid = new Set([...jpTs.map((e) => e.name), ...aliases]);
for (const n of legacy) if (!valid.has(n)) errors.push(`예전 이름 '${n}' 이 더 이상 유효하지 않음`);
console.log(`JP 별칭 ${aliases.length} · 예전 이름 ${legacy.length}개 모두 확인`);

if (errors.length) {
  console.error('FAIL\n' + errors.join('\n'));
  process.exit(1);
}
console.log('OK — 앱과 서버 지역 목록이 같습니다.');
