/**
 * 큐알쳇 회원 자동 로그인 (migration 0028).
 *
 * 가지 로그인에서 가지 계정 비밀번호가 맞지 않을 때, 같은 닉네임·비밀번호를
 * 큐알쳇 서버(eggplantVerifyHttp)에 확인한다. 맞으면 그 큐알쳇 계정(uid)에
 * 연결된 가지 계정으로 로그인시키고, 없으면 큐알쳇 닉네임·지갑으로 만든다.
 *
 * 보안 원칙
 *   - 연결 키는 큐알쳇 uid (sso_links provider='qrchat_pw'). 닉네임은 바뀔 수 있어 키로 쓰지 않는다.
 *   - 큐알쳇도 지갑 소유 증명이 없다(먼저 등록한 사람이 소유). 그래서 같은 지갑으로
 *     이미 가지 계정이 있으면 자동으로 합치지 않는다 — 큐알쳇 쪽이 선점자일 수 있다.
 *   - 진짜 지갑 주인이 소액 송금 인증으로 계정을 되찾으면(reset-password) 이 연결을
 *     끊는다 → 선점자가 큐알쳇으로 다시 들어올 수 없다.
 *   - 비밀번호는 큐알쳇에 그대로 넘기기만 하고 로그에 남기지 않는다. 확인에 성공하면
 *     가지 계정에도 같은 비밀번호 해시를 저장해 탈퇴(비밀번호 확인)가 가능하게 한다.
 */

import type { Env, UserRow } from './types';
import { hashPassword, isValidWallet, normalizeWallet } from './crypto';
import { trl, type Lang } from './market';

const DEFAULT_URL = 'https://asia-northeast3-qrchat-b7a67.cloudfunctions.net/eggplantVerifyHttp';
export const QRCHAT_PROVIDER = 'qrchat_pw';

export type QrchatVerify =
  | { ok: true; uid: string; nickname: string; walletAddress: string }
  | { ok: false; reason: 'disabled' | 'invalid' | 'locked' | 'banned' | 'unavailable' };

export async function verifyQrchatCredentials(
  env: Env,
  ident: { nickname: string } | { uid: string },
  password: string,
): Promise<QrchatVerify> {
  const key = (env.QRCHAT_BRIDGE_KEY || '').trim();
  if (!key) return { ok: false, reason: 'disabled' };
  try {
    const res = await fetch(env.QRCHAT_BRIDGE_URL || DEFAULT_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-eggplant-key': key },
      body: JSON.stringify({ ...ident, password }),
      signal: AbortSignal.timeout(8000),
    });
    const j = (await res.json().catch(() => ({}))) as {
      ok?: boolean; uid?: string; nickname?: string; walletAddress?: string; error?: string;
    };
    if (res.ok && j.ok && j.uid) {
      return { ok: true, uid: j.uid, nickname: j.nickname || ('nickname' in ident ? ident.nickname : ''), walletAddress: j.walletAddress || '' };
    }
    if (j.error === 'locked') return { ok: false, reason: 'locked' };
    if (j.error === 'banned') return { ok: false, reason: 'banned' };
    if (res.status === 401 && j.error === 'invalid_credentials') return { ok: false, reason: 'invalid' };
    console.error('[qrchat-bridge] unexpected response', res.status, j.error);
    return { ok: false, reason: 'unavailable' };
  } catch (e) {
    console.error('[qrchat-bridge] request failed', String((e as Error)?.message || e));
    return { ok: false, reason: 'unavailable' };
  }
}

export type ResolveResult =
  | { ok: true; user: UserRow; created: boolean; bonusGranted: boolean }
  | { ok: false; status: 400 | 409 | 500; error: string; code: string };

/** 가지 닉네임 규칙(2~12자)에 맞추고, 겹치면 접미사를 붙인다. */
async function pickNickname(env: Env, raw: string, uid: string): Promise<string> {
  let base = raw.trim().replace(/\s+/g, '').slice(0, 12);
  if (base.length < 2) base = `큐알${uid.slice(0, 4)}`;
  let nick = base;
  for (let i = 0; i < 6; i++) {
    const taken = await env.DB
      .prepare('SELECT id FROM users WHERE nickname = ? COLLATE NOCASE')
      .bind(nick)
      .first<{ id: string }>();
    if (!taken) return nick;
    const suffix = `_${crypto.randomUUID().slice(0, 3 + Math.min(i, 3))}`;
    nick = base.slice(0, 12 - suffix.length) + suffix;
  }
  return nick;
}

/**
 * 확인된 큐알쳇 계정 → 가지 계정. 연결이 있으면 그 계정, 없으면 새로 만든다.
 * 어느 경우든 가지 비밀번호 해시를 방금 확인된 비밀번호로 맞춘다.
 */
export async function resolveQrchatAccount(
  env: Env,
  q: { uid: string; nickname: string; walletAddress: string },
  password: string,
  deviceUuid: string,
  retried = false,
  lang: Lang = 'ko',
): Promise<ResolveResult> {
  const pwHash = await hashPassword(password);

  const link = await env.DB
    .prepare('SELECT user_id FROM sso_links WHERE provider = ? AND external_id = ?')
    .bind(QRCHAT_PROVIDER, q.uid)
    .first<{ user_id: string }>();
  if (link) {
    const user = await env.DB
      .prepare('SELECT * FROM users WHERE id = ?')
      .bind(link.user_id)
      .first<UserRow>();
    if (user) {
      await env.DB
        .prepare(
          `UPDATE users SET password_hash = ?, updated_at = datetime('now') WHERE id = ?`,
        )
        .bind(pwHash, user.id)
        .run();
      user.password_hash = pwHash;
      await env.DB
        .prepare(`UPDATE sso_links SET last_seen_at = datetime('now'), device_uuid = ? WHERE provider = ? AND external_id = ?`)
        .bind(deviceUuid, QRCHAT_PROVIDER, q.uid)
        .run();
      return { ok: true, user, created: false, bonusGranted: false };
    }
    // 가지 계정이 탈퇴로 사라진 연결 — 정리하고 새로 만든다.
    await env.DB
      .prepare('DELETE FROM sso_links WHERE provider = ? AND external_id = ?')
      .bind(QRCHAT_PROVIDER, q.uid)
      .run();
  }

  // 큐알쳇에 지갑이 없어도 가입은 시킨다 — 지갑은 나중에 '지갑 인증' 으로 등록.
  const wallet = q.walletAddress && isValidWallet(q.walletAddress) ? normalizeWallet(q.walletAddress) : null;
  const walletTaken = wallet
    ? await env.DB
      .prepare('SELECT id FROM users WHERE wallet_address = ? COLLATE NOCASE')
      .bind(wallet)
      .first<{ id: string }>()
    : null;
  if (walletTaken) {
    return {
      ok: false,
      status: 409,
      error: trl(
        lang,
        '이 큐알쳇 계정의 지갑주소로 이미 가지 계정이 있어요. 가지 닉네임·비밀번호로 로그인해주세요. '
          + "기억나지 않으면 '계정 찾기' 에서 지갑 인증으로 되찾을 수 있어요",
        'このQRChatアカウントのウォレットアドレスで登録済みのアカウントがすでにあります。登録済みのニックネームとパスワードでログインしてください。'
          + 'お忘れの場合は「アカウントを探す」からウォレット認証で復元できます',
        'An Eggplant account already exists with this QRChat wallet address. Please log in with your Eggplant nickname and password. '
          + "If you forgot them, you can recover your account with wallet verification under 'Find account'",
      ),
      code: 'qrchat_wallet_conflict',
    };
  }

  const id = crypto.randomUUID();
  const nickname = await pickNickname(env, q.nickname, q.uid);
  try {
    await env.DB
      .prepare(
        `INSERT INTO users (id, nickname, device_uuid, wallet_address, password_hash, token_version, manner_score)
         VALUES (?, ?, ?, ?, ?, 1, 365)`,
      )
      .bind(id, nickname, deviceUuid, wallet, pwHash)
      .run();
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    console.error('[qrchat-bridge] user insert failed', msg);
    if (/UNIQUE.*wallet_address/i.test(msg)) {
      // 같은 큐알쳇 계정의 동시 첫 로그인 — 다른 요청이 방금 계정을 만들고 있다.
      // 잠깐 기다렸다 연결을 다시 조회해 그 계정을 쓴다 (1회만).
      if (!retried) {
        await new Promise((r) => setTimeout(r, 400));
        return resolveQrchatAccount(env, q, password, deviceUuid, true, lang);
      }
      return { ok: false, status: 409, error: trl(lang, '이 지갑주소로 이미 가지 계정이 있어요', 'このウォレットアドレスで登録済みのアカウントがすでにあります', 'An Eggplant account already exists with this wallet address'), code: 'qrchat_wallet_conflict' };
    }
    return { ok: false, status: 500, error: trl(lang, '계정 연결 중 오류가 발생했어요', 'アカウント連携中にエラーが発生しました', 'Something went wrong while linking your account'), code: 'qrchat_link_failed' };
  }

  try {
    await env.DB
      .prepare(
        `INSERT INTO sso_links (id, user_id, provider, external_id, wallet_address, device_uuid)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .bind(crypto.randomUUID(), id, QRCHAT_PROVIDER, q.uid, wallet || '', deviceUuid)
      .run();
  } catch (e) {
    // 동시 로그인 경쟁 — 다른 요청이 먼저 연결함. 방금 만든 계정은 지우고 그쪽을 쓴다.
    await env.DB.prepare('DELETE FROM users WHERE id = ?').bind(id).run();
    if (/UNIQUE/i.test(String((e as Error)?.message || e))) {
      return resolveQrchatAccount(env, q, password, deviceUuid, true, lang);
    }
    return { ok: false, status: 500, error: trl(lang, '계정 연결 중 오류가 발생했어요', 'アカウント連携中にエラーが発生しました', 'Something went wrong while linking your account'), code: 'qrchat_link_failed' };
  }

  // 가입 보너스는 없다 — 1·2단계 인증을 마치면 +1,000 QTA (users.ts /me/verify/phone).
  const bonusGranted = false;
  const user = await env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first<UserRow>();
  if (!user) return { ok: false, status: 500, error: trl(lang, '계정 연결 중 오류가 발생했어요', 'アカウント連携中にエラーが発生しました', 'Something went wrong while linking your account'), code: 'qrchat_link_failed' };
  return { ok: true, user, created: true, bonusGranted };
}

/** 이 가지 계정이 연결된 큐알쳇 uid (없으면 null). */
export async function linkedQrchatUid(env: Env, userId: string): Promise<string | null> {
  const row = await env.DB
    .prepare('SELECT external_id FROM sso_links WHERE provider = ? AND user_id = ?')
    .bind(QRCHAT_PROVIDER, userId)
    .first<{ external_id: string | null }>();
  return row?.external_id ?? null;
}

/** 지갑 소유 증명으로 계정을 되찾을 때 — 큐알쳇 연결을 끊는다. */
export async function unlinkQrchat(env: Env, userId: string): Promise<void> {
  await env.DB
    .prepare('DELETE FROM sso_links WHERE provider = ? AND user_id = ?')
    .bind(QRCHAT_PROVIDER, userId)
    .run();
}
