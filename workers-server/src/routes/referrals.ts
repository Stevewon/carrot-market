/**
 * 친구 초대 (referral) 조회 라우트.
 *
 * 적립/회수 로직은 qta.ts 가 담당하고, 여기는 read-only 통계만 제공.
 */

import { Hono } from 'hono';
import type { Env, Variables } from '../types';
import { authMiddleware } from '../jwt';
import { QTA_REFERRAL_BONUS } from '../qta';

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

// ────────────────────────────────────────────────────────────
// GET /api/referrals/me
// 내가 초대해서 가입한 친구 목록 (최대 100명) + 적립 합계
//
// 응답:
//   {
//     bonus_per_referral: 200,
//     total_count: 12,
//     granted_count: 10,         // 현재 유효(추천인 + 피추천인 둘 다 살아있는 것)
//     clawed_back_count: 2,      // 피추천인 탈퇴로 회수된 것
//     total_earned: 2000,        // 누적 (회수 분 차감 전)
//     total_clawed_back: 400,    // 회수된 합
//     net: 1600,                 // 실제 남은 referral 보너스
//     items: [
//       { referee_nickname: "친구1", status: "granted",     created_at, ... },
//       { referee_nickname: null,    status: "clawed_back", created_at, ... } // 피추천인 탈퇴
//     ]
//   }
// ────────────────────────────────────────────────────────────
app.get('/me', authMiddleware, async (c) => {
  const me = c.get('user')!;

  const rows = await c.env.DB
    .prepare(
      `SELECT r.id, r.referee_id, r.status, r.created_at, r.updated_at,
              u.nickname AS referee_nickname
         FROM referrals r
    LEFT JOIN users u ON u.id = r.referee_id
        WHERE r.inviter_id = ?
        ORDER BY r.created_at DESC
        LIMIT 100`,
    )
    .bind(me.id)
    .all<{
      id: string;
      referee_id: string;
      status: string;
      created_at: string;
      updated_at: string;
      referee_nickname: string | null;
    }>();

  const items = rows.results || [];
  let granted = 0;
  let clawed = 0;
  for (const r of items) {
    if (r.status === 'granted') granted++;
    else if (r.status === 'clawed_back') clawed++;
  }

  return c.json({
    bonus_per_referral: QTA_REFERRAL_BONUS,
    total_count: items.length,
    granted_count: granted,
    clawed_back_count: clawed,
    total_earned: granted * QTA_REFERRAL_BONUS + clawed * QTA_REFERRAL_BONUS, // 누적 발생액
    total_clawed_back: clawed * QTA_REFERRAL_BONUS,
    net: granted * QTA_REFERRAL_BONUS,
    items: items.map((r) => ({
      referee_nickname: r.referee_nickname, // null 이면 피추천인이 탈퇴함
      status: r.status,
      created_at: r.created_at,
      updated_at: r.updated_at,
    })),
  });
});

export default app;
