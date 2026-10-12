import { Hono } from 'hono';
import type { Env, UserRow, UserPublic, Variables } from '../types';
import { normalizeMarket, requestMarket, tr, trl, reqLang, type Lang, type Market } from '../market';
import { parseRegions, regionMarket } from '../regions';
import { authMiddleware, signToken, isUserBanned } from '../jwt';
import {
  hashPassword,
  verifyPassword,
  isValidWallet,
  normalizeWallet,
} from '../crypto';
import {
  grantLoginDailyBonus,
  grantReferralBonus,
  clawbackReferralsOnDelete,
  QTA_LOGIN_DAILY_MAX,
  QTA_REFERRAL_BONUS,
} from '../qta';
import {
  challengeView,
  checkChallenge,
  consumeChallenge,
  createChallenge,
  releaseChallenge,
} from '../walletProof';
import {
  linkedQrchatUid,
  resolveQrchatAccount,
  unlinkQrchat,
  verifyQrchatCredentials,
} from '../qrchatBridge';
import {
  confirmReceive,
  createReceiveChallenge,
  processReceiveSends,
  receiveView,
  type ReceiveRow,
} from '../walletReceive';
import { checkNickname } from '../prohibited';


const app = new Hono<{ Bindings: Env; Variables: Variables }>();

// ---------- Validation helpers ----------

const NICK_MIN = 2;
const NICK_MAX = 12;
const PW_MIN = 8;
const PW_MAX = 64;

function validatePassword(pw: unknown, lang: Lang = 'ko'): string | null {
  if (typeof pw !== 'string') return trl(lang, '비밀번호를 입력해주세요', 'パスワードを入力してください');
  if (pw.length < PW_MIN) return trl(lang, `비밀번호는 ${PW_MIN}자 이상이어야 해요`, `パスワードは${PW_MIN}文字以上で入力してください`);
  if (pw.length > PW_MAX) return trl(lang, `비밀번호는 ${PW_MAX}자 이하여야 해요`, `パスワードは${PW_MAX}文字以内で入力してください`);
  return null;
}

function validateNickname(n: unknown, lang: Lang = 'ko'): string | null {
  if (typeof n !== 'string') return trl(lang, '닉네임을 입력해주세요', 'ニックネームを入力してください');
  const trimmed = n.trim();
  if (trimmed.length < NICK_MIN) return trl(lang, `닉네임은 ${NICK_MIN}자 이상이어야 해요`, `ニックネームは${NICK_MIN}文字以上で入力してください`);
  if (trimmed.length > NICK_MAX) return trl(lang, `닉네임은 ${NICK_MAX}자 이하여야 해요`, `ニックネームは${NICK_MAX}文字以内で入力してください`);
  return checkNickname(trimmed, lang); // 욕설·사칭·금지어·연락처 (src/prohibited.ts)
}

/** Strip sensitive fields before returning to client. */
function sanitize(u: UserRow): UserPublic {
  return {
    id: u.id,
    nickname: u.nickname,
    device_uuid: u.device_uuid,
    wallet_address: u.wallet_address,
    region: u.region,
    region_verified_at: u.region_verified_at,
    market: u.market ?? 'kr',
    regions: parseRegions(u.regions, u.region),
    manner_score: u.manner_score,
    qta_balance: u.qta_balance ?? 0,
    verification_level: u.verification_level ?? 0,
    verified_at: u.verified_at ?? null,
    bank_registered_at: u.bank_registered_at ?? null,
    wallet_verified_at: u.wallet_verified_at ?? null,
    created_at: u.created_at,
    updated_at: u.updated_at,
  };
}

// ================================================================
// SSO: 퀀타리움 지갑주소 = Universal User ID
//
// POST /api/auth/sso/exchange
// Body: {
//   wallet_address: '0x...',     // 필수
//   provider: 'qrchat',          // 'qrchat' / 'eggplant_self'
//   external_token?: '...',      // QRChat 발급 토큰 (선택)
//   nickname?: '...',            // 신규 가입 시 사용 (선택, 없으면 자동 생성)
//   device_uuid: '...'           // 필수
// }
//
// 동작:
//   1) wallet_address 로 가지 users 조회
//   2) 있으면 → token_version 그대로, device_uuid 만 갱신, 가지 JWT 발급
//   3) 없으면 → 신규 user 생성 (password_hash NULL = SSO-only 계정),
//      가입 보너스 +500 QTA 지급, 가지 JWT 발급
//   4) sso_links 에 (provider, user_id, wallet, device) 기록/갱신
//
// 보안:
//   - 현재는 external_token 의 형식만 점검(미래 QRChat 공개키 검증 자리 마련).
//     QRChat 측 SDK 가 공개되면 jwks 로 서명 검증 추가.
//   - SSO-only 계정은 password 로 직접 로그인 불가 (NULL hash → verifyPassword 실패).
// ================================================================
app.post('/sso/exchange', async (c) => {
  // external_token 서명 검증이 아직 없어서, 열어두면 공개된 지갑주소만으로
  // 남의 계정 JWT 를 발급받을 수 있다. 검증 구현 전까지 기본 차단.
  // (앱은 현재 이 엔드포인트를 호출하지 않는다.)
  if (c.env.ALLOW_UNVERIFIED_SSO !== '1') {
    return c.json({ error: tr(c, 'SSO 로그인은 아직 준비 중이에요', 'SSOログインは現在準備中です'), code: 'sso_disabled' }, 503);
  }

  let body: {
    wallet_address?: string;
    provider?: string;
    external_token?: string;
    external_id?: string;
    nickname?: string;
    device_uuid?: string;
    region?: string;
    market?: string;
  } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです') }, 400);
  }

  const { wallet_address, provider, external_token, external_id, device_uuid } =
    body;

  if (!wallet_address || !isValidWallet(wallet_address)) {
    return c.json(
      { error: tr(c, '퀀타리움 지갑주소 형식을 확인해주세요 (0x + 40자리)', 'Quantariumウォレットアドレスの形式をご確認ください（0x + 40桁）') },
      400,
    );
  }
  if (!device_uuid || typeof device_uuid !== 'string' || device_uuid.length < 8) {
    return c.json({ error: tr(c, '기기 정보가 올바르지 않아요', '端末情報が正しくありません') }, 400);
  }
  const prov = (provider ?? 'qrchat').trim().toLowerCase();
  if (!/^[a-z0-9_]{2,32}$/.test(prov)) {
    return c.json({ error: tr(c, '잘못된 provider', 'providerが正しくありません') }, 400);
  }

  // QRChat 토큰 검증 자리. 현재는 형식만 확인(64~2048 글자).
  // QRChat SDK 의 공개키/JWKS 가 확정되면 여기서 jwt.verify 추가.
  if (external_token != null) {
    if (typeof external_token !== 'string' ||
        external_token.length < 8 ||
        external_token.length > 4096) {
      return c.json({ error: tr(c, '외부 토큰 형식이 올바르지 않아요', '外部トークンの形式が正しくありません') }, 400);
    }
  }

  const walletNorm = normalizeWallet(wallet_address);

  // 1) 기존 user 조회.
  let user = await c.env.DB
    .prepare('SELECT * FROM users WHERE wallet_address = ? COLLATE NOCASE')
    .bind(walletNorm)
    .first<UserRow>();

  let createdNew = false;
  let signupBonusGranted = false;

  if (!user) {
    // 2) 신규 가입 — SSO-only 계정 (password_hash = NULL).
    let nick = (body.nickname ?? '').trim();
    if (!nick) {
      // 닉네임 미지정 시 walletAddress 끝 6자리로 자동 생성.
      const tail = walletNorm.slice(-6).toLowerCase();
      nick = `사용자${tail}`;
    } else {
      const ne = validateNickname(nick, reqLang(c));
      if (ne) return c.json({ error: ne }, 400);
    }
    // 닉네임 중복 시 뒤에 접미사 자동 추가 (최대 5회 시도).
    let finalNick = nick;
    for (let i = 0; i < 5; i++) {
      const taken = await c.env.DB
        .prepare('SELECT id FROM users WHERE nickname = ? COLLATE NOCASE')
        .bind(finalNick)
        .first<{ id: string }>();
      if (!taken) break;
      const tail = walletNorm.slice(-4 - i, -1).toLowerCase();
      finalNick = `${nick}_${tail}`;
    }

    const id = crypto.randomUUID();
    try {
      // device_uuid 가 다른 계정에 묶여 있으면 token_version 만 bump 해서 풀어준다.
      await c.env.DB
        .prepare(
          `UPDATE users
              SET device_uuid = 'released:' || id,
                  token_version = token_version + 1,
                  updated_at = datetime('now')
            WHERE device_uuid = ? AND id != ?`,
        )
        .bind(device_uuid, id)
        .run();
    } catch (e) {
      console.error('[auth/sso] device cleanup failed', e);
    }

    const ssoMarket: Market = normalizeMarket(body.market) ?? requestMarket(c);
    // 없는 지역이나 다른 시장 지역은 저장하지 않는다 (가입 후 지역 선택 화면에서 고른다).
    const ssoRegion = body.region && regionMarket(body.region) === ssoMarket ? body.region : null;
    let insertedNew = false;
    try {
      await c.env.DB
        .prepare(
          `INSERT INTO users
             (id, nickname, device_uuid, wallet_address, password_hash, region, token_version, market, manner_score)
           VALUES (?, ?, ?, ?, NULL, ?, 1, ?, 365)`,
        )
        .bind(id, finalNick, device_uuid, walletNorm, ssoRegion, ssoMarket)
        .run();
      insertedNew = true;
    } catch (e) {
      const msg = String((e as Error)?.message || e);
      console.error('[auth/sso] INSERT failed:', msg);
      if (/UNIQUE constraint failed: users\.wallet_address/i.test(msg)) {
        // race — 같은 지갑이 동시에 들어왔으면 다시 조회.
        const fetched = await c.env.DB
          .prepare('SELECT * FROM users WHERE wallet_address = ? COLLATE NOCASE')
          .bind(walletNorm)
          .first<UserRow>();
        if (!fetched) return c.json({ error: tr(c, 'SSO 처리 중 오류', 'SSO処理中にエラーが発生しました') }, 500);
        user = fetched;
      } else {
        return c.json({ error: tr(c, 'SSO 가입 중 오류가 발생했어요', 'SSOでの会員登録中にエラーが発生しました') }, 500);
      }
    }

    if (insertedNew) {
      // 가입 보너스는 없다 — 1·2단계 인증을 마치면 +1,000 QTA (users.ts /me/verify/phone).
      const fetched = await c.env.DB
        .prepare('SELECT * FROM users WHERE id = ?')
        .bind(id)
        .first<UserRow>();
      if (!fetched) return c.json({ error: tr(c, '사용자 생성 실패', 'ユーザーの作成に失敗しました') }, 500);
      user = fetched;
      createdNew = true;
    }
  } else {
    // 3) 기존 user — device_uuid 갱신 (다른 기기에서 로그인하면 자연 교체).
    if (user.device_uuid !== device_uuid) {
      const existingId = user.id;
      try {
        // 다른 계정이 이 device_uuid 를 들고 있으면 풀어준다.
        await c.env.DB
          .prepare(
            `UPDATE users
                SET device_uuid = 'released:' || id,
                    token_version = token_version + 1,
                    updated_at = datetime('now')
              WHERE device_uuid = ? AND id != ?`,
          )
          .bind(device_uuid, existingId)
          .run();
        await c.env.DB
          .prepare(
            `UPDATE users
                SET device_uuid = ?,
                    token_version = token_version + 1,
                    updated_at = datetime('now')
              WHERE id = ?`,
          )
          .bind(device_uuid, existingId)
          .run();
        const fetched = await c.env.DB
          .prepare('SELECT * FROM users WHERE id = ?')
          .bind(existingId)
          .first<UserRow>();
        if (!fetched) return c.json({ error: tr(c, 'SSO 갱신 실패', 'SSOの更新に失敗しました') }, 500);
        user = fetched;
      } catch (e) {
        console.error('[auth/sso] device update failed', e);
      }
    }
  }

  // 여기까지 오면 user 는 반드시 채워져 있어야 한다 (모든 분기에서 보장).
  // TS narrowing 보강용 명시적 가드.
  if (!user) return c.json({ error: tr(c, 'SSO 처리 실패', 'SSO処理に失敗しました') }, 500);
  const finalUser: UserRow = user;

  // 4) sso_links 기록/갱신 (멱등 upsert by provider+user).
  try {
    await c.env.DB
      .prepare(
        `INSERT INTO sso_links
           (id, user_id, provider, external_id, wallet_address, device_uuid, last_seen_at)
         VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
         ON CONFLICT(provider, user_id) DO UPDATE SET
           external_id    = COALESCE(excluded.external_id, sso_links.external_id),
           wallet_address = excluded.wallet_address,
           device_uuid    = excluded.device_uuid,
           last_seen_at   = datetime('now')`,
      )
      .bind(
        crypto.randomUUID(),
        finalUser.id,
        prov,
        external_id ?? null,
        walletNorm,
        device_uuid,
      )
      .run();
  } catch (e) {
    console.error('[auth/sso] sso_links upsert failed', e);
  }

  // 5) 일일 로그인 보너스 (가입 직후엔 패스, 기존 사용자만).
  let loginBonus: { credited: boolean; remaining: number } | null = null;
  if (!createdNew) {
    try {
      const r = await grantLoginDailyBonus(c.env, finalUser.id);
      loginBonus = { credited: r.credited, remaining: r.remaining };
    } catch (e) {
      console.error('[auth/sso] login bonus failed', e);
    }
  }

  const token = await signToken(finalUser, c.env.JWT_SECRET);
  return c.json({
    token,
    user: sanitize(finalUser),
    sso: {
      provider: prov,
      created_new: createdNew,
      signup_bonus_granted: signupBonusGranted,
    },
    login_bonus: loginBonus,
  });
});

// ================================================================
// 지갑 소유 증명 (소액 송금) — src/walletProof.ts, migration 0027
//
// POST /api/auth/wallet-challenge
//   Body: { wallet_address, device_uuid, purpose: 'register' | 'reset' }
//   → { challenge_id, amount: '0.0042', send_to, alt_send_to, expires_at, ... }
//
// POST /api/auth/wallet-challenge/:id/check
//   Body: { device_uuid }
//   → 200 { verified: true } | 404 code='not_found_yet' (잠시 후 다시)
// ================================================================
app.post('/wallet-challenge', async (c) => {
  let body: { wallet_address?: string; device_uuid?: string; purpose?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです') }, 400);
  }
  const { wallet_address, device_uuid } = body;
  const purpose = body.purpose === 'reset' ? 'reset' : body.purpose === 'register' ? 'register' : null;
  if (!purpose) return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです') }, 400);
  if (!wallet_address || !isValidWallet(wallet_address)) {
    return c.json({ error: tr(c, '퀀타리움 지갑주소 형식을 확인해주세요 (0x + 40자리)', 'Quantariumウォレットアドレスの形式をご確認ください（0x + 40桁）') }, 400);
  }
  if (!device_uuid || typeof device_uuid !== 'string' || device_uuid.length < 8) {
    return c.json({ error: tr(c, '기기 정보가 올바르지 않아요', '端末情報が正しくありません') }, 400);
  }

  const walletNorm = normalizeWallet(wallet_address);
  const taken = await c.env.DB
    .prepare('SELECT id FROM users WHERE wallet_address = ? COLLATE NOCASE')
    .bind(walletNorm)
    .first<{ id: string }>();
  if (purpose === 'register' && taken) {
    return c.json(
      {
        error: tr(
          c,
          '이미 가입된 지갑주소예요. 본인 지갑인데 가입한 적이 없다면 '
            + "'계정 찾기 → 비밀번호 재설정' 에서 지갑 인증으로 계정을 되찾을 수 있어요",
          'このウォレットアドレスはすでに登録されています。ご自身のウォレットで登録した覚えがない場合は、'
            + '「アカウントを探す → パスワード再設定」からウォレット認証でアカウントを取り戻せます',
        ),
        code: 'wallet_taken',
      },
      409,
    );
  }
  if (purpose === 'reset' && !taken) {
    return c.json({ error: tr(c, '가입되지 않은 지갑주소예요', '登録されていないウォレットアドレスです') }, 404);
  }

  const ip = c.req.header('cf-connecting-ip') || '';
  const created = await createChallenge(c.env, walletNorm.toLowerCase(), purpose, device_uuid, ip, reqLang(c));
  if (!created.ok) return c.json({ error: created.error, code: created.code }, created.status);
  const row = created.row;
  return c.json(challengeView(row, c.env));
});

app.post('/wallet-challenge/:id/check', async (c) => {
  let body: { device_uuid?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです') }, 400);
  }
  if (!body.device_uuid) return c.json({ error: tr(c, '기기 정보가 올바르지 않아요', '端末情報が正しくありません') }, 400);

  const r = await checkChallenge(c.env, c.req.param('id'), body.device_uuid, reqLang(c));
  if (!r.ok) return c.json({ verified: false, error: r.error, code: r.code }, r.status);
  return c.json({ verified: true, ...challengeView(r.row, c.env) });
});

// ================================================================
// 계정 찾기(비밀번호 재설정) 지갑 인증 — 본사가 보내고, 회원이 받은 수량을 입력.
//
// POST /api/auth/reset-wallet-receive              { wallet_address, device_uuid }
//   1차: 입력한 지갑주소가 가입 때 등록한 지갑과 일치하는지 확인 (아니면 404).
//   맞으면 본사 지갑이 그 지갑으로 소수점 6자리 임의 수량을 보낸다 (금액은 안 알려줌).
// GET  /api/auth/reset-wallet-receive/:id?device_uuid=  → 송금 상태
// POST /api/auth/reset-wallet-receive/:id/confirm  { device_uuid, amount }
//   2차: 지갑에 들어온 수량이 맞으면 verified → /reset-password 에 wallet_challenge_id 로 쓴다.
// ================================================================
app.post('/reset-wallet-receive', async (c) => {
  let body: { wallet_address?: string; device_uuid?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです') }, 400);
  }
  const { wallet_address, device_uuid } = body;
  if (!wallet_address || !isValidWallet(wallet_address)) {
    return c.json({ error: tr(c, '퀀타리움 지갑주소 형식을 확인해주세요 (0x + 40자리)', 'Quantariumウォレットアドレスの形式をご確認ください（0x + 40桁）') }, 400);
  }
  if (!device_uuid || typeof device_uuid !== 'string' || device_uuid.length < 8) {
    return c.json({ error: tr(c, '기기 정보가 올바르지 않아요', '端末情報が正しくありません') }, 400);
  }
  const walletNorm = normalizeWallet(wallet_address);
  const user = await c.env.DB
    .prepare('SELECT id FROM users WHERE wallet_address = ? COLLATE NOCASE')
    .bind(walletNorm)
    .first<{ id: string }>();
  if (!user) {
    return c.json(
      { error: tr(c, '가입할 때 등록한 지갑주소와 일치하지 않아요', '登録時のウォレットアドレスと一致しません'), code: 'wallet_mismatch' },
      404,
    );
  }
  if (await isUserBanned(c.env.DB, user.id)) {
    return c.json({ error: tr(c, '이용이 정지된 계정이에요. 고객센터로 문의해주세요', 'このアカウントは利用停止中です。お問い合わせ窓口までご連絡ください'), code: 'banned' }, 403);
  }
  const r = await createReceiveChallenge(
    c.env, user.id, device_uuid, walletNorm.toLowerCase(), c.req.header('cf-connecting-ip') || '', reqLang(c), 'reset',
  );
  if (!r.ok) return c.json({ error: r.error, code: r.code }, r.status);
  if (r.row.send_status === 'queued') {
    c.executionCtx.waitUntil(processReceiveSends(c.env).catch((e) => console.error('[reset-receive] tick', e)));
  }
  return c.json(receiveView(r.row, c.env));
});

/** 계정 찾기 요청을 그 요청을 만든 기기에서만 본다. */
async function resetReceiveRow(c: { env: Env }, id: string, deviceUuid: string) {
  if (!deviceUuid) return null;
  return c.env.DB
    .prepare(
      `SELECT * FROM wallet_challenges
        WHERE id = ? AND direction = 'to_user' AND purpose = 'reset' AND device_uuid = ?`,
    )
    .bind(id, deviceUuid)
    .first<ReceiveRow>();
}

app.get('/reset-wallet-receive/:id', async (c) => {
  const row = await resetReceiveRow(c, c.req.param('id'), c.req.query('device_uuid') || '');
  if (!row) return c.json({ error: tr(c, '인증 요청을 찾을 수 없어요', '認証リクエストが見つかりません'), code: 'not_found' }, 404);
  return c.json(receiveView(row, c.env));
});

app.post('/reset-wallet-receive/:id/confirm', async (c) => {
  let body: { device_uuid?: string; amount?: string | number } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです') }, 400);
  }
  const row = await resetReceiveRow(c, c.req.param('id'), String(body.device_uuid || ''));
  if (!row) return c.json({ verified: false, error: tr(c, '인증 요청을 찾을 수 없어요', '認証リクエストが見つかりません'), code: 'not_found' }, 404);
  const r = await confirmReceive(c.env, row.user_id, row.id, String(body.amount ?? ''), reqLang(c), 'reset');
  if (!r.ok) {
    return c.json({ verified: false, error: r.error, code: r.code, attempts_left: r.attempts_left }, r.status);
  }
  return c.json({ verified: true, challenge_id: r.row.id });
});

// ================================================================
// POST /api/auth/register
// Body: { nickname, password, password_confirm, device_uuid, region?,
//         wallet_address?, wallet_challenge_id? }
// 지갑은 선택 — 지갑이 없어도 가입한다. 지갑은 가입 후 '지갑 인증'(본사 지갑으로
// 랜덤 소액 송금)으로 등록한다. 인증 없이 보낸 지갑주소는 저장하지 않는다
// (남의 지갑 선점 방지).
// ================================================================
app.post('/register', async (c) => {
  let body: {
    wallet_address?: string;
    nickname?: string;
    password?: string;
    password_confirm?: string;
    device_uuid?: string;
    region?: string;
    market?: string;
    referrer_nickname?: string; // 친구 초대 — 추천인 닉네임 (선택)
    wallet_challenge_id?: string; // 지갑 소유 증명 (POST /wallet-challenge → check)
  } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです') }, 400);
  }

  const { wallet_address, nickname, password, password_confirm, device_uuid, region, referrer_nickname, wallet_challenge_id } = body;

  // --- Validate ---
  // 지갑은 인증(wallet_challenge_id)과 함께 왔을 때만 쓴다.
  const withWallet = !!wallet_challenge_id && typeof wallet_challenge_id === 'string';
  if (withWallet && (!wallet_address || !isValidWallet(wallet_address))) {
    return c.json({ error: tr(c, '퀀타리움 지갑주소 형식을 확인해주세요 (0x + 40자리)', 'Quantariumウォレットアドレスの形式をご確認ください（0x + 40桁）') }, 400);
  }
  // 한국/일본 시장 — 앱이 기기 언어로 보낸다. 지역은 같은 시장 것만.
  const market: Market = normalizeMarket(body.market) ?? requestMarket(c);
  if (region && !regionMarket(region)) {
    return c.json({ error: tr(c, '없는 지역이에요', '存在しない地域です'), code: 'region_unknown' }, 400);
  }
  if (region && regionMarket(region) !== market) {
    return c.json({ error: tr(c, '선택할 수 없는 지역이에요', '選択できない地域です'), code: 'region_market' }, 400);
  }

  const nickErr = validateNickname(nickname, reqLang(c));
  if (nickErr) return c.json({ error: nickErr }, 400);

  const pwErr = validatePassword(password, reqLang(c));
  if (pwErr) return c.json({ error: pwErr }, 400);
  if (password !== password_confirm) {
    return c.json({ error: tr(c, '비밀번호가 일치하지 않아요', 'パスワードが一致しません') }, 400);
  }

  if (!device_uuid || typeof device_uuid !== 'string' || device_uuid.length < 8) {
    return c.json({ error: tr(c, '기기 정보가 올바르지 않아요', '端末情報が正しくありません') }, 400);
  }

  const walletNorm = withWallet ? normalizeWallet(wallet_address!) : null;
  const cleanNick = nickname!.trim();

  // --- Duplicate checks ---
  if (walletNorm) {
    const walletTaken = await c.env.DB
      .prepare('SELECT id FROM users WHERE wallet_address = ? COLLATE NOCASE')
      .bind(walletNorm)
      .first<{ id: string }>();
    if (walletTaken) {
      return c.json({ error: tr(c, '이미 가입된 지갑주소예요', 'このウォレットアドレスはすでに登録されています') }, 409);
    }
  }

  const nickTaken = await c.env.DB
    .prepare('SELECT id FROM users WHERE nickname = ? COLLATE NOCASE')
    .bind(cleanNick)
    .first<{ id: string }>();
  if (nickTaken) {
    return c.json({ error: tr(c, '이미 사용 중인 닉네임이에요', 'このニックネームはすでに使われています') }, 409);
  }

  // --- 지갑 소유 증명 (남의 지갑 선점 방지) ---
  // 다른 검증을 모두 통과한 뒤에 1회 사용 처리한다. 아래 INSERT 가 실패하면
  // releaseChallenge 로 되돌려 같은 인증으로 다시 시도할 수 있게 한다.
  const consumed = !walletNorm || await consumeChallenge(
    c.env, wallet_challenge_id!, walletNorm.toLowerCase(), 'register', device_uuid,
  );
  if (!consumed) {
    return c.json(
      { error: tr(c, '지갑 인증이 확인되지 않았거나 만료됐어요. 지갑 인증을 다시 진행해주세요', 'ウォレット認証が確認できないか、有効期限が切れています。もう一度ウォレット認証を行ってください'), code: 'wallet_proof_invalid' },
      400,
    );
  }

  // --- Create ---
  const hash = await hashPassword(password!);
  const id = crypto.randomUUID();

  // Safety net: if migration 0005 hasn't been applied yet and this device_uuid
  // was previously bound to some other wallet, free it up by nulling the old
  // binding and bumping that user's token_version so their session dies on the
  // next request. (Post-0005 this is a no-op because the column isn't UNIQUE.)
  try {
    await c.env.DB
      .prepare(`
        UPDATE users
           SET device_uuid = 'released:' || id,
               token_version = token_version + 1,
               updated_at = datetime('now')
         WHERE device_uuid = ? AND id != ?
      `)
      .bind(device_uuid, id)
      .run();
  } catch (e) {
    // Ignore — this is best-effort cleanup.
    console.error('[auth/register] device_uuid cleanup:', e);
  }

  try {
    await c.env.DB
      .prepare(`
        INSERT INTO users
          (id, nickname, device_uuid, wallet_address, password_hash, region, token_version,
           wallet_verified_at, market, manner_score)
        VALUES (?, ?, ?, ?, ?, ?, 1, CASE WHEN ? IS NULL THEN NULL ELSE datetime('now') END, ?, 365)
      `)
      .bind(id, cleanNick, device_uuid, walletNorm, hash, region || null, walletNorm, market)
      .run();
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    console.error('[auth/register] INSERT failed:', msg);
    if (walletNorm) await releaseChallenge(c.env, wallet_challenge_id!).catch(() => {});
    // Surface the common schema-level failures with friendly Korean messages.
    if (/UNIQUE constraint failed: users\.wallet_address/i.test(msg)) {
      return c.json({ error: tr(c, '이미 가입된 지갑주소예요', 'このウォレットアドレスはすでに登録されています') }, 409);
    }
    if (/UNIQUE constraint failed: users\.nickname/i.test(msg)) {
      return c.json({ error: tr(c, '이미 사용 중인 닉네임이에요', 'このニックネームはすでに使われています') }, 409);
    }
    if (/UNIQUE constraint failed: users\.device_uuid/i.test(msg)) {
      return c.json(
        { error: tr(c, '이 기기에 다른 계정이 남아있어요. 앱을 재설치하거나 관리자에게 문의해주세요.', 'この端末には別のアカウントが残っています。アプリを再インストールするか、運営までお問い合わせください。') },
        409,
      );
    }
    return c.json({ error: tr(c, '가입 중 오류가 발생했어요', '会員登録中にエラーが発生しました') }, 500);
  }

  // 가입 보너스는 없다 — 1단계 지갑 + 2단계 휴대폰 인증을 마치면 +1,000 QTA (users.ts).
  const signupBonusGranted = false;

  // ── 친구 초대 보너스 (추천인에게 +200 QTA, 무제한, best-effort) ──
  let referralResult: { credited: boolean; inviter_nickname?: string; reason?: string } | null = null;
  if (referrer_nickname && typeof referrer_nickname === 'string' && referrer_nickname.trim()) {
    const refTrim = referrer_nickname.trim();
    if (refTrim.toLowerCase() === cleanNick.toLowerCase()) {
      referralResult = { credited: false, reason: 'self_referral' };
    } else {
      try {
        const inviter = await c.env.DB
          .prepare('SELECT id, nickname FROM users WHERE nickname = ? COLLATE NOCASE')
          .bind(refTrim)
          .first<{ id: string; nickname: string }>();
        if (!inviter) {
          referralResult = { credited: false, reason: 'inviter_not_found' };
        } else {
          const r = await grantReferralBonus(c.env, inviter.id, id);
          referralResult = { credited: r.credited, inviter_nickname: inviter.nickname, reason: r.reason };
        }
      } catch (e) {
        console.error('[auth/register] referral grant failed', e);
        referralResult = { credited: false, reason: 'error' };
      }
    }
  }

  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(id)
    .first<UserRow>();
  if (!user) return c.json({ error: tr(c, '사용자 생성 실패', 'ユーザーの作成に失敗しました') }, 500);

  const token = await signToken(user, c.env.JWT_SECRET);
  return c.json({
    token,
    user: sanitize(user),
    qta_bonus: signupBonusGranted ? { reason: 'signup', amount: 500 } : null,
    referral: referralResult
      ? {
          credited: referralResult.credited,
          inviter_nickname: referralResult.inviter_nickname ?? null,
          inviter_bonus: referralResult.credited ? QTA_REFERRAL_BONUS : 0,
          reason: referralResult.reason ?? null,
        }
      : null,
  }, 201);
});

// ================================================================
// POST /api/auth/login
// Body: { nickname, password, device_uuid }
//
// Nickname is the display name AND the login ID (unique, COLLATE NOCASE).
// Wallet address is only used for signup and for recovery (finding
// nickname / resetting password).
//
// On success:
//  - If the new device_uuid differs from the one on file, we *replace* it
//    and bump token_version. This invalidates the previous device's JWT.
// ================================================================
app.post('/login', async (c) => {
  let body: { nickname?: string; password?: string; device_uuid?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです') }, 400);
  }

  const { nickname, password, device_uuid } = body;
  if (!nickname || typeof nickname !== 'string' || !nickname.trim()) {
    return c.json({ error: tr(c, '닉네임을 입력해주세요', 'ニックネームを入力してください') }, 400);
  }
  if (!password || typeof password !== 'string') {
    return c.json({ error: tr(c, '비밀번호를 입력해주세요', 'パスワードを入力してください') }, 400);
  }
  if (!device_uuid || typeof device_uuid !== 'string' || device_uuid.length < 8) {
    return c.json({ error: tr(c, '기기 정보가 올바르지 않아요', '端末情報が正しくありません') }, 400);
  }

  const nickTrim = nickname.trim();
  const found = await c.env.DB
    .prepare('SELECT * FROM users WHERE nickname = ? COLLATE NOCASE')
    .bind(nickTrim)
    .first<UserRow>();

  // Intentionally same error for "not found" vs "wrong password" to avoid
  // leaking which nicknames are registered.
  const ok = found && found.password_hash
    ? await verifyPassword(password, found.password_hash)
    : false;

  // 가지 계정으로 안 맞으면 → 큐알쳇 회원인지 확인 (src/qrchatBridge.ts).
  // 큐알쳇 닉네임·비밀번호가 맞으면 연결된 가지 계정으로 로그인 (없으면 자동 생성).
  let user: UserRow | null = ok ? found : null;
  let qrchatLogin: { created: boolean; bonusGranted: boolean } | null = null;

  // 큐알쳇과 연결된 계정은 비밀번호의 기준이 큐알쳇이다. 가지에 저장된 해시는
  // 마지막 로그인 때 비밀번호라, 큐알쳇에서 비밀번호를 바꾼 뒤에도 옛 비밀번호가
  // 통하면 안 된다 → 큐알쳇 uid 로 다시 확인. 큐알쳇 서버 장애 때만 가지 해시로 허용.
  const linkedUid = found ? await linkedQrchatUid(c.env, found.id) : null;
  if (found && linkedUid) {
    const q = await verifyQrchatCredentials(c.env, { uid: linkedUid }, password);
    if (q.ok) {
      // 큐알쳇 비밀번호가 맞음 → 로그인 + 가지 해시도 최신 비밀번호로 맞춤 (탈퇴 확인용).
      const r = await resolveQrchatAccount(c.env, q, password, device_uuid, false, reqLang(c));
      if (!r.ok) return c.json({ error: r.error, code: r.code }, r.status);
      user = r.user;
      qrchatLogin = { created: false, bonusGranted: false };
    } else if (q.reason === 'locked') {
      return c.json(
        { error: tr(c, '비밀번호를 여러 번 틀려 잠시 잠겼어요. 10분 후 다시 시도해주세요', 'パスワードを複数回間違えたため、一時的にロックされました。10分後に再度お試しください'), code: 'locked' },
        401,
      );
    } else if (q.reason === 'banned') {
      return c.json({ error: tr(c, '큐알쳇에서 이용이 정지된 계정이에요', 'QRChatで利用停止となっているアカウントです'), code: 'banned' }, 403);
    } else if (q.reason === 'invalid') {
      // 큐알쳇이 아니라고 하면 가지 해시가 맞아도 거부 (옛 비밀번호).
      return c.json({ error: tr(c, '닉네임 또는 비밀번호가 올바르지 않아요', 'ニックネームまたはパスワードが正しくありません') }, 401);
    }
    // unavailable/disabled: 큐알쳇 확인 불가 → 위에서 계산한 가지 해시 결과(user) 그대로.
  }

  if (!user) {
    const q = await verifyQrchatCredentials(c.env, { nickname: nickTrim }, password);
    if (q.ok) {
      const r = await resolveQrchatAccount(c.env, q, password, device_uuid, false, reqLang(c));
      if (!r.ok) return c.json({ error: r.error, code: r.code }, r.status);
      user = r.user;
      qrchatLogin = { created: r.created, bonusGranted: r.bonusGranted };
    } else if (q.reason === 'locked') {
      return c.json(
        { error: tr(c, '비밀번호를 여러 번 틀려 잠시 잠겼어요. 10분 후 다시 시도해주세요', 'パスワードを複数回間違えたため、一時的にロックされました。10分後に再度お試しください'), code: 'locked' },
        401,
      );
    } else if (q.reason === 'banned') {
      return c.json({ error: tr(c, '큐알쳇에서 이용이 정지된 계정이에요', 'QRChatで利用停止となっているアカウントです'), code: 'banned' }, 403);
    }
  }
  if (!user) {
    return c.json({ error: tr(c, '닉네임 또는 비밀번호가 올바르지 않아요', 'ニックネームまたはパスワードが正しくありません') }, 401);
  }
  if (await isUserBanned(c.env.DB, user.id)) {
    return c.json({ error: tr(c, '이용이 정지된 계정이에요. 고객센터로 문의해주세요', 'このアカウントは利用停止中です。お問い合わせ窓口までご連絡ください'), code: 'banned' }, 403);
  }

  // If logging in from a new device, kick the old device out.
  let tokenVersion = user.token_version ?? 1;
  if (user.device_uuid !== device_uuid) {
    tokenVersion += 1;
    await c.env.DB
      .prepare("UPDATE users SET device_uuid = ?, token_version = ?, updated_at = datetime('now') WHERE id = ?")
      .bind(device_uuid, tokenVersion, user.id)
      .run();
    user.device_uuid = device_uuid;
    user.token_version = tokenVersion;
  }

  // ── 일일 로그인 보너스 +10 QTA (하루 3회) ─────────────────────
  let qtaBonus: { credited: boolean; count: number; remaining: number; amount: number } | null = null;
  try {
    const r = await grantLoginDailyBonus(c.env, user.id);
    qtaBonus = { ...r, amount: r.credited ? 10 : 0 };
    if (r.credited) {
      // 응답 sanitize 가 정확한 잔액을 반영하도록 row 다시 읽기.
      const fresh = await c.env.DB
        .prepare('SELECT qta_balance FROM users WHERE id = ?')
        .bind(user.id)
        .first<{ qta_balance: number }>();
      if (fresh) user.qta_balance = fresh.qta_balance;
    }
  } catch (e) {
    console.error('[auth/login] login bonus failed', e);
  }

  const token = await signToken(user, c.env.JWT_SECRET);
  return c.json({
    token,
    user: sanitize(user),
    qta_bonus: qtaBonus
      ? {
          reason: 'login_daily',
          credited: qtaBonus.credited,
          amount: qtaBonus.amount,
          today_count: qtaBonus.count,
          today_max: QTA_LOGIN_DAILY_MAX,
          remaining: qtaBonus.remaining,
        }
      : null,
    // 큐알쳇 닉네임·비밀번호로 들어온 경우 (created=true 면 가지 계정을 방금 만들고 가입 보너스 지급)
    qrchat_login: qrchatLogin
      ? { linked: true, created: qrchatLogin.created, signup_bonus: qrchatLogin.bonusGranted ? 500 : 0 }
      : null,
  });
});

// ================================================================
// POST /api/auth/recover/nickname
// Body: { wallet_address }
// Returns: { nickname }  (safe: nickname is public info)
// ================================================================
app.post('/recover/nickname', async (c) => {
  let body: { wallet_address?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです') }, 400);
  }
  if (!body.wallet_address || !isValidWallet(body.wallet_address)) {
    return c.json({ error: tr(c, '지갑주소 형식을 확인해주세요 (0x + 40자리)', 'ウォレットアドレスの形式をご確認ください（0x + 40桁）') }, 400);
  }

  const walletNorm = normalizeWallet(body.wallet_address);
  const row = await c.env.DB
    .prepare('SELECT nickname FROM users WHERE wallet_address = ? COLLATE NOCASE')
    .bind(walletNorm)
    .first<{ nickname: string }>();

  if (!row) return c.json({ error: tr(c, '가입되지 않은 지갑주소예요', '登録されていないウォレットアドレスです') }, 404);
  return c.json({ nickname: row.nickname });
});

// ================================================================
// POST /api/auth/reset-password
// Body: { wallet_address, new_password, new_password_confirm, device_uuid }
//
// 지갑주소는 상품 상세 등에서 공개되는 값이라 "소유 증명" 이 될 수 없다.
// 그래서 계정에 현재 등록된 기기(device_uuid)에서 요청할 때만 재설정한다.
// 다른 기기·앱 재설치 후에는 지갑 소유 증명(소액 송금, purpose=reset)으로 재설정한다.
// Bumps token_version so any still-active sessions are invalidated.
// Returns a fresh token for the caller's device.
// ================================================================
app.post('/reset-password', async (c) => {
  let body: {
    wallet_address?: string;
    new_password?: string;
    new_password_confirm?: string;
    device_uuid?: string;
    wallet_challenge_id?: string; // 지갑 소유 증명 (purpose=reset)
  } = {};
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: tr(c, '잘못된 요청', '不正なリクエストです') }, 400);
  }

  const { wallet_address, new_password, new_password_confirm, device_uuid, wallet_challenge_id } = body;
  if (!wallet_address || !isValidWallet(wallet_address)) {
    return c.json({ error: tr(c, '지갑주소 형식을 확인해주세요 (0x + 40자리)', 'ウォレットアドレスの形式をご確認ください（0x + 40桁）') }, 400);
  }
  const pwErr = validatePassword(new_password, reqLang(c));
  if (pwErr) return c.json({ error: pwErr }, 400);
  if (new_password !== new_password_confirm) {
    return c.json({ error: tr(c, '비밀번호가 일치하지 않아요', 'パスワードが一致しません') }, 400);
  }
  if (!device_uuid || typeof device_uuid !== 'string' || device_uuid.length < 8) {
    return c.json({ error: tr(c, '기기 정보가 올바르지 않아요', '端末情報が正しくありません') }, 400);
  }

  const walletNorm = normalizeWallet(wallet_address);
  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE wallet_address = ? COLLATE NOCASE')
    .bind(walletNorm)
    .first<UserRow>();
  if (!user) return c.json({ error: tr(c, '가입되지 않은 지갑주소예요', '登録されていないウォレットアドレスです') }, 404);
  if (await isUserBanned(c.env.DB, user.id)) {
    return c.json({ error: tr(c, '이용이 정지된 계정이에요. 고객센터로 문의해주세요', 'このアカウントは利用停止中です。お問い合わせ窓口までご連絡ください'), code: 'banned' }, 403);
  }

  // 재설정 허용 조건 (둘 중 하나):
  //   1) 이 계정이 등록된 기기에서 요청
  //   2) 지갑 소유 증명(소액 송금, purpose='reset') 완료 — 앱 재설치/기기 변경,
  //      그리고 남이 내 지갑으로 먼저 가입(선점)한 계정을 되찾는 경로.
  const sameDevice = !!user.device_uuid && user.device_uuid === device_uuid;
  let walletProven = false;
  if (!sameDevice) {
    if (wallet_challenge_id && typeof wallet_challenge_id === 'string') {
      walletProven = await consumeChallenge(
        c.env, wallet_challenge_id, walletNorm.toLowerCase(), 'reset', device_uuid,
      );
    }
    if (!walletProven) {
      return c.json(
        {
          error: tr(c, '다른 기기에서는 지갑 인증(소액 송금) 후에 비밀번호를 재설정할 수 있어요.', '別の端末からは、ウォレット認証（少額送金）後にパスワードを再設定できます。'),
          code: 'wallet_proof_required',
        },
        403,
      );
    }
  }

  const hash = await hashPassword(new_password!);
  const newVersion = (user.token_version ?? 1) + 1;

  await c.env.DB
    .prepare(`
      UPDATE users
      SET password_hash = ?, token_version = ?, device_uuid = ?, updated_at = datetime('now'),
          wallet_verified_at = CASE WHEN ? = 1 THEN datetime('now') ELSE wallet_verified_at END
      WHERE id = ?
    `)
    .bind(hash, newVersion, device_uuid, walletProven ? 1 : 0, user.id)
    .run();

  // 비밀번호를 재설정했으면 큐알쳇 연결을 끊는다 (경로 무관).
  //   - 지갑 증명으로 되찾은 경우: 큐알쳇도 지갑 소유 증명이 없어, 선점자가 큐알쳇
  //     로그인으로 다시 들어오는 것을 막는다.
  //   - 같은 기기에서 재설정한 경우: 연결이 남아 있으면 로그인 때 큐알쳇 비밀번호로만
  //     확인되어, 새 가지 비밀번호로 로그인할 수 없었다.
  await unlinkQrchat(c.env, user.id);

  user.password_hash = hash;
  user.token_version = newVersion;
  user.device_uuid = device_uuid;

  const token = await signToken(user, c.env.JWT_SECRET);
  return c.json({ token, user: sanitize(user) });
});

// ================================================================
// POST /api/auth/logout
// Bumps token_version so the current token (and any other active ones)
// are invalidated immediately.
// ================================================================
app.post('/logout', authMiddleware, async (c) => {
  const authUser = c.get('user')!;
  await c.env.DB
    .prepare("UPDATE users SET token_version = token_version + 1, updated_at = datetime('now') WHERE id = ?")
    .bind(authUser.id)
    .run();
  return c.json({ ok: true });
});

// ================================================================
// GET /api/auth/me
// ================================================================
app.get('/me', authMiddleware, async (c) => {
  const authUser = c.get('user')!;
  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(authUser.id)
    .first<UserRow>();
  if (!user) return c.json({ error: 'User not found' }, 404);
  return c.json({ user: sanitize(user) });
});

// ================================================================
// GET /api/auth/check-nickname?nickname=...
// 추천인 닉네임 입력 시 존재 여부 확인 (회원가입 전 사용)
// ================================================================
app.get('/check-nickname', async (c) => {
  const nick = (c.req.query('nickname') || '').trim();
  if (!nick) return c.json({ exists: false });
  const row = await c.env.DB
    .prepare('SELECT nickname FROM users WHERE nickname = ? COLLATE NOCASE')
    .bind(nick)
    .first<{ nickname: string }>();
  return c.json({ exists: !!row, nickname: row?.nickname ?? null });
});

// ================================================================
// DELETE /api/auth/me
// 본인 계정 탈퇴 — "한 번 사라진 건 영구 보관 X"
// Body: { password } (재인증)
//
// 처리 흐름:
//   1) 비밀번호 재확인 (실수 방지)
//   2) 친구 초대 보너스 즉시 회수 (clawbackReferralsOnDelete)
//      - 탈퇴자가 inviter 였으면 탈퇴자 본인에게서 -200 each (어차피 행 삭제되지만 ledger 일관성)
//      - 탈퇴자가 referee 였으면 추천인에게서 -200 회수
//   3) users 행 DELETE → ON DELETE CASCADE 로
//      qta_ledger / qta_daily_login / referrals / hidden_products /
//      keyword_alerts / user_blocks(따로 정리) 등이 자동 정리됨
//   4) 탈퇴자 데이터는 서버에 흔적 없음 (개인정보·잔여 QTA 모두 사라짐)
// ================================================================
app.delete('/me', authMiddleware, async (c) => {
  const authUser = c.get('user')!;
  let body: { password?: string } = {};
  try {
    body = await c.req.json();
  } catch {
    // 비밀번호 없이도 시도 가능하지만 권장 X — 기본 차단.
    return c.json({ error: tr(c, '비밀번호를 입력해주세요', 'パスワードを入力してください') }, 400);
  }

  const { password } = body;
  if (!password || typeof password !== 'string') {
    return c.json({ error: tr(c, '비밀번호를 입력해주세요', 'パスワードを入力してください') }, 400);
  }

  const user = await c.env.DB
    .prepare('SELECT * FROM users WHERE id = ?')
    .bind(authUser.id)
    .first<UserRow>();
  if (!user) return c.json({ error: tr(c, '계정을 찾을 수 없어요', 'アカウントが見つかりません') }, 404);

  const ok = user.password_hash
    ? await verifyPassword(password, user.password_hash)
    : false;
  if (!ok) {
    return c.json({ error: tr(c, '비밀번호가 올바르지 않아요', 'パスワードが正しくありません') }, 401);
  }

  // 0) 진행 중인 출금이 있으면 탈퇴 보류 — 운영자가 송금하는 중에 계정·출금 기록이
  //    지워지면 처리할 근거가 사라진다. 완료되거나 취소된 뒤 탈퇴하도록 안내.
  const pendingWithdrawal = await c.env.DB
    .prepare(`SELECT id FROM qta_withdrawals WHERE user_id = ? AND status IN ('requested','processing') LIMIT 1`)
    .bind(user.id)
    .first<{ id: string }>();
  if (pendingWithdrawal) {
    return c.json(
      { error: tr(c, '진행 중인 출금 신청이 있어 지금은 탈퇴할 수 없어요. 출금이 끝나거나 취소한 뒤 다시 시도해주세요', '処理中の出金申請があるため、現在は退会できません。出金の完了またはキャンセル後に再度お試しください'), code: 'withdrawal_pending' },
      409,
    );
  }

  // 1) referral 보너스 즉시 회수
  let clawback = { inviter_clawbacks: 0, referee_clawbacks: 0 };
  try {
    clawback = await clawbackReferralsOnDelete(c.env, user.id);
  } catch (e) {
    console.error('[auth/delete] clawback failed', e);
  }

  // 2) 사용자 컨텐츠 best-effort 정리 (CASCADE 가 없는 테이블 대비)
  //    - products 의 lat/lng 는 무관하지만 본인 게시물은 즉시 삭제
  //    - user_blocks (양방향) 정리
  try {
    await c.env.DB.batch([
      // FK 에 CASCADE 가 없는 테이블들 — 남아 있으면 users(또는 products) DELETE 가
      // FK 제약으로 실패해 "탈퇴 처리 중 오류" 가 났다 (특히 본인인증을 한 사용자).
      //   verification_audit / pass_verifications (0021): users FK
      //   escrow_transactions (0020): users(buyer/seller) + products FK → products 보다 먼저
      c.env.DB.prepare('DELETE FROM verification_audit WHERE user_id = ?').bind(user.id),
      c.env.DB.prepare('DELETE FROM pass_verifications WHERE user_id = ?').bind(user.id),
      c.env.DB.prepare(
        `DELETE FROM escrow_transactions
          WHERE buyer_id = ? OR seller_id = ?
             OR product_id IN (SELECT id FROM products WHERE seller_id = ?)`,
      ).bind(user.id, user.id, user.id),
      c.env.DB.prepare('DELETE FROM products WHERE seller_id = ?').bind(user.id),
      c.env.DB.prepare('DELETE FROM user_blocks WHERE blocker_id = ? OR blocked_id = ?')
        .bind(user.id, user.id),
      // sso_links 는 ON DELETE CASCADE 가 없어 남아 있으면 users DELETE 가 FK 로 실패한다
      // (큐알쳇 로그인으로 만든 계정 등).
      c.env.DB.prepare('DELETE FROM sso_links WHERE user_id = ?').bind(user.id),
    ]);
  } catch (e) {
    console.error('[auth/delete] cleanup non-cascade tables failed', e);
  }

  // 3) users 행 DELETE → ON DELETE CASCADE 가 ledger 등을 즉시 청소.
  //    휴대폰 번호(phone_vault, FK 없음)는 탈퇴 즉시 파기 — 같은 batch 라 둘 다 지워지거나 둘 다 남는다.
  try {
    await c.env.DB.batch([
      c.env.DB.prepare('DELETE FROM phone_vault WHERE user_id = ?').bind(user.id),
      c.env.DB.prepare('DELETE FROM users WHERE id = ?').bind(user.id),
    ]);
  } catch (e) {
    console.error('[auth/delete] DELETE users failed', e);
    return c.json({ error: tr(c, '탈퇴 처리 중 오류가 발생했어요', '退会処理中にエラーが発生しました') }, 500);
  }

  return c.json({
    ok: true,
    message: tr(c, '계정이 영구 삭제되었어요. 모든 흔적이 즉시 사라졌습니다.', 'アカウントを完全に削除しました。すべてのデータは直ちに消去されました。'),
    referral_clawback: clawback,
  });
});

export default app;
