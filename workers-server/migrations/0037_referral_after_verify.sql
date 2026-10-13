-- 0037: 친구 초대 보상은 3단계(가입·지갑·휴대폰)를 마친 뒤에만.
-- 가입 때는 누가 초대했는지만 users.referred_by 에 적어 두고, 초대한 사람과
-- 초대받은 사람이 둘 다 인증을 마친 순간 +200 QTA 를 지급한다 (qta.ts settleReferrals).
ALTER TABLE users ADD COLUMN referred_by TEXT;
CREATE INDEX IF NOT EXISTS idx_users_referred_by ON users(referred_by);
