// 필리핀 지역(Province → City/Municipality) 목록 생성기.
//   node tool/gen_ph_regions.mjs                    — tool/ph_data/ 의 원본으로 생성
//   node tool/gen_ph_regions.mjs --fetch-wikidata   — 좌표 원본(wikidata_coords.csv)을 새로 받은 뒤 생성
//
// 입력 (저장소에 그대로 둔다 — 같은 입력이면 항상 같은 출력):
//   tool/ph_data/psgc_2026q2.csv
//     PSA PSGC 2026 2분기(2026-06-30 기준) 지역 코드·이름. npm @aivangogh/ph-address@2026.2.4 (MIT,
//     PSA 공식 PSGC 엑셀을 옮긴 것) 의 getAllRegions/getAllProvinces/getAllMunicipalities 를 CSV 로 내보냄.
//     열: level(region|province|citymun), psgc(10자리), name, parent(상위 코드)
//   tool/ph_data/wikidata_coords.csv
//     Wikidata(CC0) 의 시·군 좌표 (P625, 보통 시청·poblacion 위치). 아래 WIKIDATA_QUERY 결과 그대로.
// 출력:
//   workers-server/src/regions_ph.ts  — 서버 좌표표 (동네 인증)
//   lib/app/regions_ph.dart           — 앱 2단계 선택 목록
// 이름 규칙: '<Province> · <City/Municipality>' (예: 'Cebu · Cebu City', 'Metro Manila · Makati City').
//   구분자 ' · ' (가운뎃점 U+00B7) 는 PSGC 이름에 나오지 않는다 — 이름에 공백이 많아 ' ' 는 못 쓴다.
//   NCR 은 Province 가 없어 'Metro Manila' 로 묶고, HUC·ICC 는 PSGC 가 붙인 지리상 Province 아래에 둔다
//   (Isabela City 만 PSGC 상 Province 가 없어 Basilan 에 둔다). BARMM 특별지역 8곳은 'Special Geographic Area'.
//   마닐라(Manila City)는 PSGC sub-municipality(구) 14곳으로 나눈다 — 이름 'Metro Manila · Manila (<구>)'
//   (예: 'Metro Manila · Manila (Tondo)', 'Metro Manila · Manila (Sampaloc)'). 괄호로 묶어 목록에서 함께 정렬된다.
//   PSGC CSV(@aivangogh/ph-address)에는 sub-municipality 가 없어 아래 MANILA_DISTRICTS 를 손으로 둔다.
//   예전 이름 'Metro Manila · Manila City' 는 서버 PH_REGION_ALIASES 에만 남긴다 (저장된 값 유효, 앱 목록엔 없음).
// 좌표 찾기: ① PSGC 10자리 코드 ② 예전 9자리·예전 지역 코드(NIR←06/07, BARMM←15/12, Sulu 09↔19)
//   ③ 이름 + 같은 Province 의 다른 시·군 평균 위치에서 가장 가까운 것(200 km 안). 그래도 없으면 실패.
import { readFileSync, writeFileSync } from 'node:fs';

const DATA = 'tool/ph_data/';
const WIKIDATA_QUERY = `SELECT DISTINCT ?item ?psgc ?coord ?label ?parentLabel WHERE {
  { ?item wdt:P31/wdt:P279* wd:Q104157 } UNION { ?item wdt:P31/wdt:P279* wd:Q24764 }
  UNION { ?item wdt:P988 ?p0 FILTER(REGEX(?p0, "000$")) }
  ?item wdt:P625 ?coord .
  OPTIONAL { ?item wdt:P988 ?psgc }
  OPTIONAL { ?item rdfs:label ?label FILTER(LANG(?label)="en") }
  OPTIONAL { ?item wdt:P131 ?parent . ?parent rdfs:label ?parentLabel FILTER(LANG(?parentLabel)="en") }
}`;

if (process.argv.includes('--fetch-wikidata')) {
  const res = await fetch('https://query.wikidata.org/sparql', {
    method: 'POST',
    headers: { Accept: 'text/csv', 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': 'eggplant-regions-gen/1.0' },
    body: new URLSearchParams({ query: WIKIDATA_QUERY }),
  });
  if (!res.ok) { console.error('wikidata ' + res.status); process.exit(1); }
  writeFileSync(DATA + 'wikidata_coords.csv', (await res.text()).replace(/\r\n/g, '\n'));
}

const fail = (m) => { console.error('ERROR: ' + m); process.exit(1); };
const r6 = (v) => Math.round(v * 1e6) / 1e6;

function csv(text) {
  const rows = [];
  for (const line of text.replace(/\r/g, '').trim().split('\n')) {
    const out = []; let cur = '', q = false;
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (q) {
        if (ch === '"') { if (line[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += ch;
      } else if (ch === '"') q = true;
      else if (ch === ',') { out.push(cur); cur = ''; } else cur += ch;
    }
    out.push(cur);
    rows.push(out);
  }
  return rows.slice(1);
}

// PSGC 이름의 대문자 표기 실수 바로잡기 (공식 표기: PSA PSGC).
const NAME_FIX = {
  'Abra De Ilog': 'Abra de Ilog', 'Anini-Y': 'Anini-y', 'Cagayan De Oro City': 'Cagayan de Oro City',
  'Can-Avid': 'Can-avid', 'Lal-Lo': 'Lal-lo', 'Laua-An': 'Laua-an', 'Lope De Vega': 'Lope de Vega',
  'Ma-Ayon': 'Ma-ayon', 'Matag-Ob': 'Matag-ob', 'San Jose De Buan': 'San Jose de Buan',
  'San Jose Del Monte City': 'San Jose del Monte City', 'Sapi-An': 'Sapi-an',
  'Sultan Sa Barongis': 'Sultan sa Barongis', 'Tagana-An': 'Tagana-an', 'Tagapul-An': 'Tagapul-an',
};
// 이름이 바뀌어 Wikidata 에 예전 이름으로만 있는 곳 (좌표 찾기용).
const FORMER_NAME = { Pagagawan: 'Datu Montawal' };
const METRO_MANILA = 'Metro Manila';
const SGA = 'Special Geographic Area';
const GROUP_BY_CODE = { '1300000000': METRO_MANILA, '1999900000': SGA, '0990100000': 'Basilan' };
const NAME_RE = /^[A-Za-z0-9ñÑ .'\-/()]+$/; // ' · ' · " · $ · \ 없음
const SEP = ' · ';

const ps = csv(readFileSync(DATA + 'psgc_2026q2.csv', 'utf8'));
const provName = new Map(ps.filter((r) => r[0] === 'province').map((r) => [r[1], r[2]]));
if (provName.size !== 82) fail('expected 82 provinces, got ' + provName.size);

// 마닐라 sub-municipality (CSV 에 있으면 13806xx000) 는 아래 손으로 둔 표를 쓰므로 CSV 쪽은 제외.
const MANILA_CITY = '1380600000';
const isSubMun = (code) => /^13806\d\d000$/.test(code) && code !== MANILA_CITY;
// PSA PSGC 'City of Manila' 의 sub-municipality 14곳 (코드 13806xx000). PSGC 공식 이름은 'Tondo I / II' 지만
// 앱에는 'Tondo' 로 보인다. San Andres(Bukid) 는 PSGC sub-municipality 가 아니다 (넣지 않음).
// 좌표: Wikidata 가 아니라 손으로 넣은 구 안쪽 대표 위치 (대략의 중심 — 수백 m 정밀도).
const MANILA_DISTRICTS = [
  ['1380601000', 'Tondo', 14.619, 120.968],
  ['1380602000', 'Binondo', 14.6004, 120.9746],
  ['1380603000', 'Quiapo', 14.5994, 120.985],
  ['1380604000', 'San Nicolas', 14.6025, 120.968],
  ['1380605000', 'Santa Cruz', 14.615, 120.984],
  ['1380606000', 'Sampaloc', 14.611, 120.998],
  ['1380607000', 'San Miguel', 14.5945, 120.9925],
  ['1380608000', 'Ermita', 14.582, 120.983],
  ['1380609000', 'Intramuros', 14.5906, 120.975],
  ['1380610000', 'Malate', 14.57, 120.99],
  ['1380611000', 'Paco', 14.58, 120.998],
  ['1380612000', 'Pandacan', 14.59, 121.008],
  ['1380613000', 'Port Area', 14.586, 120.968],
  ['1380614000', 'Santa Ana', 14.578, 121.014],
];
const groups = new Map();
for (const [level, code, rawName, parent] of ps) {
  if (level !== 'citymun' || isSubMun(code)) continue;
  const group = GROUP_BY_CODE[parent] ?? provName.get(parent) ?? fail('no province for ' + rawName + ' ' + code);
  const short = NAME_FIX[rawName] ?? rawName;
  if (!NAME_RE.test(short) || !NAME_RE.test(group)) fail('bad name ' + group + ' / ' + short);
  if (!groups.has(group)) groups.set(group, []);
  groups.get(group).push({ code, short, group, name: group + SEP + short });
}
if (!groups.get(METRO_MANILA)?.some((e) => e.code === MANILA_CITY)) fail('Manila City not in PSGC');
for (const [code, d, lat, lng] of MANILA_DISTRICTS) {
  const short = `Manila (${d})`;
  if (!NAME_RE.test(short)) fail('bad name ' + short);
  groups.get(METRO_MANILA).push({ code, short, group: METRO_MANILA, name: METRO_MANILA + SEP + short, lat, lng, fixed: true });
}

// --- 좌표 ---
const wd = csv(readFileSync(DATA + 'wikidata_coords.csv', 'utf8')).map(([item, psgc, coord, label, parentLabel]) => {
  const m = /^Point\((-?[\d.]+) (-?[\d.]+)\)$/.exec(coord) ?? fail('bad coord ' + coord);
  return { item, psgc, label, parentLabel, lng: +m[1], lat: +m[2] };
}).filter((w) => w.lat > 4 && w.lat < 22 && w.lng > 114 && w.lng < 127.5);
const byCode = new Map();
for (const w of wd) if (w.psgc && !byCode.has(w.psgc)) byCode.set(w.psgc, w);

function codeCandidates(code) {
  const RR = code.slice(0, 2), PPP = code.slice(2, 5), rest = code.slice(5);
  const regs = [RR, ...({ '18': ['06', '07'], '19': ['15', '12', '09'], '09': ['19', '15'] }[RR] ?? [])];
  const out = [code];
  for (const r of regs) { out.push(r + PPP + rest); if (PPP[0] === '0') out.push(r + PPP.slice(1) + rest); }
  return out;
}
const ABBR = { 'gen.': 'general', 'sto.': 'santo', 'sta.': 'santa', 'pres.': 'president', 'sen.': 'senator', 'dr.': 'doctor', 's.k.': 'salipada k.' };
const norm = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
  .split(' ').map((w) => ABBR[w] ?? w).join(' ')
  .replace(/^(science |island garden )?city of /, '').replace(/ city$/, '').replace(/[^a-z0-9]/g, '');
const provNorms = new Set([...provName.values()].map(norm));
const isProvinceRow = (w) => provNorms.has(norm(w.label)) && /00000$/.test(w.psgc);
const byNorm = new Map();
for (const w of wd) {
  if (!w.label || isProvinceRow(w)) continue;
  const k = norm(w.label);
  if (!byNorm.has(k)) byNorm.set(k, []);
  byNorm.get(k).push(w);
}
const km = (a, b) => {
  const R = 6371, t = (d) => (d * Math.PI) / 180;
  const h = Math.sin(t(b.lat - a.lat) / 2) ** 2 + Math.sin(t(b.lng - a.lng) / 2) ** 2 * Math.cos(t(a.lat)) * Math.cos(t(b.lat));
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
};

const all = [...groups.values()].flat();
const how = { code: 0, name: 0 };
const missing = [];
for (const e of all) {
  if (e.fixed) continue;
  const w = codeCandidates(e.code).map((c) => byCode.get(c)).find(Boolean);
  if (w) { e.lat = w.lat; e.lng = w.lng; how.code++; if (process.env.DEBUG && w.label && norm(w.label) !== norm(e.short)) console.log(`code: ${e.name} ← ${w.label} (${w.psgc})`); }
}
for (const [group, list] of groups) {
  let known = list.filter((e) => e.lat != null);
  if (!known.length) {
    // 코드가 하나도 안 맞는 Province (새로 나뉜 Maguindanao del Sur 등) — 전국에서 이름이 하나뿐인 시·군으로 기준점을 잡는다.
    for (const e of list) {
      const c = byNorm.get(norm(e.short)) ?? [];
      if (c.length === 1) { e.lat = c[0].lat; e.lng = c[0].lng; how.name++; if (process.env.DEBUG) console.log(`unique: ${e.name} ← ${c[0].label} / ${c[0].parentLabel}`); }
    }
    known = list.filter((e) => e.lat != null);
    if (!known.length) fail('no coordinates at all in ' + group);
  }
  const c = { lat: known.reduce((s, e) => s + e.lat, 0) / known.length, lng: known.reduce((s, e) => s + e.lng, 0) / known.length };
  for (const e of list) {
    if (e.lat != null) continue;
    const near = (byNorm.get(norm(FORMER_NAME[e.short] ?? e.short)) ?? []).map((w) => ({ w, d: km(c, w) })).filter((x) => x.d < 200).sort((a, b) => a.d - b.d);
    if (!near.length) { missing.push(`${e.name} (${e.code})`); continue; }
    e.lat = near[0].w.lat; e.lng = near[0].w.lng; how.name++;
    if (process.env.DEBUG) console.log(`name: ${e.name} ← ${near[0].w.label} / ${near[0].w.parentLabel} ${Math.round(near[0].d)} km (${near.length})`);
  }
}
if (missing.length) fail('no coordinate for\n  ' + missing.join('\n  '));
// 같은 Province 안 이웃과 너무 먼 좌표는 데이터 오류일 가능성 — 확인용 경고.
for (const [group, list] of groups) {
  for (const e of list) {
    const others = list.filter((o) => o !== e);
    if (!others.length) continue;
    const nearest = Math.min(...others.map((o) => km(e, o)));
    if (nearest > 80) console.warn(`warn: ${e.name} 이웃과 ${Math.round(nearest)} km`);
  }
}

// Manila City 통째 이름은 좌표만 구해 두고 목록에서 뺀다 → 서버 별칭 (PH_REGION_ALIASES).
const mmList = groups.get(METRO_MANILA);
const legacyManila = mmList.splice(mmList.findIndex((e) => e.code === MANILA_CITY), 1)[0];
all.splice(all.indexOf(legacyManila), 1);
const aliases = [legacyManila];

// --- 정렬·중복 ---
const sortName = (a, b) => a.localeCompare(b, 'en');
const order = [METRO_MANILA, ...[...groups.keys()].filter((g) => g !== METRO_MANILA).sort(sortName)];
const seen = new Set();
for (const g of order) {
  groups.get(g).sort((a, b) => sortName(a.short, b.short));
  for (const e of groups.get(g)) {
    if (seen.has(e.name)) fail('dup ' + e.name);
    seen.add(e.name);
    e.lat = r6(e.lat); e.lng = r6(e.lng);
  }
}

const total = all.length;
const head = '// 자동 생성 — 직접 고치지 말 것. node tool/gen_ph_regions.mjs\n'
  + '// 출처: PSA PSGC 2026Q2 (tool/ph_data/psgc_2026q2.csv) + Wikidata 좌표 (CC0, tool/ph_data/wikidata_coords.csv). '
  + `Province ${order.length} · City/Municipality ${total}\n`;

// --- server ---
let ts = head + '\n/** 필리핀 Province (Metro Manila 먼저, 나머지 알파벳 순). */\n'
  + `export const PH_PROVINCES: readonly string[] = ${JSON.stringify(order)};\n\n`
  + `/** 전체 이름의 Province 구분자. */\nexport const PH_SEP = ${JSON.stringify(SEP)};\n\n`
  + '/** 필리핀 지역 중심 좌표. 이름은 앱 lib/app/regions_ph.dart 와 같아야 한다. */\n'
  + 'export const PH_REGION_CENTERS: Record<string, { lat: number; lng: number }> = {\n';
for (const g of order) {
  ts += `  // ${g}\n`;
  for (const e of groups.get(g)) ts += `  ${JSON.stringify(e.name)}: { lat: ${e.lat}, lng: ${e.lng} },\n`;
}
ts += '};\n\n'
  + '/** 예전 이름 → 좌표. 앱 목록에는 없지만 이미 저장된 값이 서버에서 계속 유효하도록 (구로 나누기 전의 마닐라 통째 이름). */\n'
  + 'export const PH_REGION_ALIASES: Record<string, { lat: number; lng: number }> = {\n';
for (const e of aliases) {
  if (seen.has(e.name)) fail('alias overlaps ' + e.name);
  ts += `  ${JSON.stringify(e.name)}: { lat: ${r6(e.lat)}, lng: ${r6(e.lng)} },\n`;
}
ts += '};\n';
writeFileSync('workers-server/src/regions_ph.ts', ts);

// --- app --- (NAME_RE 로 $ · \ 없음 보장 → 작은따옴표만 \' 로 이스케이프)
const q = (s) => `'${s.replace(/'/g, "\\'")}'`;
let dart = head + '\n/// 필리핀 지역 데이터. 이름은 서버 workers-server/src/regions_ph.ts 와 같아야 한다.\n'
  + `/// 전체 이름은 '<Province>${SEP}<City/Municipality>' (예: 'Cebu${SEP}Cebu City').\n`
  + 'class PhRegionData {\n  PhRegionData._();\n\n'
  + `  /// 전체 이름의 Province 구분자.\n  static const String sep = ${q(SEP)};\n\n`
  + '  /// Province → [City/Municipality].\n'
  + '  static const Map<String, List<String>> byProvince = {\n';
for (const g of order) {
  dart += `    ${q(g)}: [\n`;
  for (const e of groups.get(g)) dart += `      ${q(e.short)},\n`;
  dart += '    ],\n';
}
dart += '  };\n}\n';
writeFileSync('lib/app/regions_ph.dart', dart);
console.log(`provinces ${order.length}, cities/municipalities ${total} (coords by PSGC code ${how.code}, by name ${how.name}, Manila districts by hand ${MANILA_DISTRICTS.length}), aliases ${aliases.length}`);
