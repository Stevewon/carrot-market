// 금지 품목 판정 테스트 — src/prohibited.ts 를 esbuild 로 묶어 node 로 실행한다.
//   cd workers-server && node scripts/prohibited_test.mjs
// 실패가 있으면 종료 코드 1.
import { build } from 'esbuild';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = mkdtempSync(join(tmpdir(), 'prohibited-test-'));
const file = join(out, 'prohibited.mjs');
await build({
  entryPoints: [join(root, 'src/prohibited.ts')],
  bundle: true,
  format: 'esm',
  platform: 'node',
  outfile: file,
  logLevel: 'error',
});
const { checkProductText, checkNickname, PROHIBITED_GUIDE } = await import(pathToFileURL(file).href);
rmSync(out, { recursive: true, force: true });

let fail = 0;
const product = (title) => checkProductText({ title });
/** [제목, 기대 action, 기대 규칙 id(선택)] */
function expectAction(title, action, ruleId) {
  const r = product(title);
  const ok = r.action === action && (!ruleId || r.hits.some((h) => h.ruleId === ruleId));
  if (!ok) {
    fail++;
    console.log(`FAIL  "${title}" → ${r.action} [${r.hits.map((h) => `${h.ruleId}:${h.term}`).join(', ')}] (기대 ${action}${ruleId ? ' ' + ruleId : ''})`);
  }
}

// ── 한국 (기존 동작 유지) ──
expectAction('필로폰 팝니다', 'block', 'narcotics');
expectAction('대마도 여행 가이드북', 'allow');
expectAction('참이슬 소주 한 박스', 'block', 'alcohol');
expectAction('와인잔 세트', 'allow');
expectAction('전자담배 액상', 'block', 'tobacco');
expectAction('물총 장난감', 'allow');
expectAction('종량제봉투 20L', 'block', 'misc');
expectAction('아이폰 15 프로 팝니다', 'allow');
expectAction('마약베개 새상품', 'allow');

// ── 일본 (기존 동작 유지) ──
expectAction('大麻 売ります', 'block', 'narcotics');
expectAction('ワイングラス 2客', 'allow');

// ── 필리핀: 차단 ──
expectAction('Shabu for sale', 'block', 'narcotics');
expectAction('marijuana 1g', 'block', 'narcotics');
expectAction('Mariwana kush', 'block', 'narcotics');
expectAction('ganja available', 'block', 'narcotics');
expectAction('Cytotec pampalaglag', 'block', 'medicine');
expectAction('Biogesic paracetamol 100 tabs', 'block', 'medicine');
expectAction('Amoxicillin 500mg', 'block', 'medicine');
expectAction('Tanduay rhum 1L', 'block', 'alcohol');
expectAction('Lambanog 750ml', 'block', 'alcohol');
expectAction('Red Horse beer 1 case', 'block', 'alcohol');
expectAction('Sigarilyo Marlboro 1 ream', 'block', 'tobacco');
expectAction('yosi mura', 'block', 'tobacco');
expectAction('Disposable vape 5000 puffs', 'block', 'tobacco');
expectAction('RELX pods', 'block', 'tobacco');
expectAction('Baril 9mm for sale', 'block', 'weapon');
expectAction('Benta baril .45', 'block', 'weapon');
expectAction('Glock 17', 'block', 'weapon');
expectAction('paltik na sumpak', 'block', 'weapon');
expectAction('Paputok for New Year', 'block', 'fireworks');
expectAction('Super Lolo firecracker', 'block', 'fireworks');
expectAction('Goodbye Philippines 1 box', 'block', 'fireworks');
expectAction('Registered SIM Globe', 'block', 'account');
expectAction('PhilSys National ID', 'block', 'account');
expectAction("Driver's license LTO", 'block', 'account');
expectAction('Fully verified GCash for sale', 'block', 'account');
expectAction('Mobile Legends account mythic', 'block', 'account');
expectAction('Class A copy Louis Vuitton', 'block', 'counterfeit');
expectAction('mirror grade Rolex', 'block', 'counterfeit');
expectAction('Puppies for sale shih tzu', 'block', 'animal');
expectAction('Pawikan eggs', 'block', 'animal');
expectAction('PNP uniform complete', 'block', 'military');
expectAction('Kidney for sale', 'block', 'body');
expectAction('Cash loan fast approval', 'block', 'cash');
expectAction('spy camera pen', 'block', 'spycam');

// ── 필리핀: 검토 (등록은 허용) ──
expectAction('damo for sale', 'review', 'narcotics_review');
expectAction('alak sale', 'review', 'alcohol_review');
expectAction('Piccolo 1 box', 'review', 'fireworks_review');
expectAction('Fireworks set', 'review', 'fireworks_review');
expectAction('Airsoft rifle', 'block', 'weapon');
expectAction('Gel blaster', 'review', 'weapon_review');
expectAction('Tarsier', 'review', 'animal_review');
expectAction('peke na bag', 'review', 'counterfeit_review');
expectAction('Pautang 5k', 'review', 'cash_review');
expectAction('Smart SIM card', 'review', 'account_review');

// ── 필리핀: 오탐 방지 (허용) ──
expectAction('Shabu-shabu hot pot', 'allow');
expectAction('Shabu shabu pot 2-in-1', 'allow');
expectAction('Bato garden stones', 'allow');
expectAction('Malakas na electric fan', 'allow');
expectAction('Bariles na plastic 200L', 'allow');
expectAction('Baril-barilan toy for kids', 'allow');
expectAction('Barilla pasta 500g', 'allow');
expectAction('Balat ng sapatos, balance board', 'allow');
expectAction('Bahala na, sale lahat', 'allow');
expectAction('National ID holder lanyard', 'allow');
expectAction("Driver's license holder wallet", 'allow');
expectAction('LTO driver\'s license reviewer book', 'allow');
expectAction('Payment via GCash or Maya', 'allow');
expectAction('Glue gun for sale', 'allow');
expectAction('Massage gun for sale', 'allow');
expectAction('Orange juice dispenser', 'allow');
expectAction('Beer mug set', 'allow');
expectAction('SIM card tray ejector pin', 'allow');
expectAction('Humidifier with UMID display', 'allow');
expectAction('Tinidor at kutsara set', 'allow');
expectAction('Kabayo figurine, red horse statue', 'allow');
expectAction('Ginebra San Miguel jersey', 'allow');
expectAction('First class aircon', 'allow');
expectAction('Damong ligaw cutter', 'allow');
expectAction('Maging bilog ang mesa', 'allow');
expectAction('Dama de noche plant', 'allow');
expectAction('Vapor rub for kids', 'allow');
expectAction('Tuba (brass instrument)', 'allow');
// ── 필리핀 외부 연락처 ──expectAction('iPhone 12, PM me for details', 'block', 'contact_messenger');expectAction('Rice cooker - viber me 0917', 'block', 'contact_messenger');expectAction('Sofa set, message me on FB', 'block', 'contact_messenger');expectAction('Bike for sale, whatsapp me', 'block', 'contact_messenger');expectAction('Laptop, contact via Viber', 'review', 'contact_messenger_review');expectAction('Leather messenger bag', 'allow');expectAction('Context menu keyboard', 'allow');expectAction('Small meter box', 'allow');
expectAction('Selling TV call 0917 123 4567', 'block');expectAction('Selling TV +63 917 123 4567', 'block');

// ── 닉네임 ──
if (checkNickname('shabuking', 'en') == null) { fail++; console.log('FAIL  nickname shabuking 허용됨'); }
if (checkNickname('juan_dela_cruz', 'en') != null) { fail++; console.log('FAIL  nickname juan_dela_cruz 차단됨'); }

// ── 안내 목록: 필리핀 항목에는 영어 이름·예시가 있다 ──
const ph = PROHIBITED_GUIDE.filter((g) => !g.markets || g.markets.includes('ph'));
if (ph.length !== 16 || ph.some((g) => !g.labelEn || !g.examplesEn)) { fail++; console.log('FAIL  PROHIBITED_GUIDE ph 항목', ph.length); }
if (ph.some((g) => g.label === '종량제 봉투')) { fail++; console.log('FAIL  필리핀 안내에 종량제 봉투'); }

if (fail) {
  console.log(`\n${fail} failed`);
  process.exit(1);
}
console.log('prohibited: all passed');
