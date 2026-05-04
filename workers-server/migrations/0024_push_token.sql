-- ============================================================
-- 0024_push_token.sql — FCM 푸시 토큰 컬럼 추가 (3차 푸시)
-- ============================================================
-- 정책:
--   1) 사장님 결정 (c): Firebase 프로젝트 신규 생성 후 키 등록 예정.
--      코드는 placeholder 모드로 깔아두고, 키 등록 시 즉시 활성화.
--
--   2) FCM 토큰만 저장 — 푸시 이력은 D1 에 절대 저장하지 않음 (휘발성).
--      0022 챗 정책과 동일: 메시지 본문/통화 내용/푸시 본문 0건 저장.
--
--   3) 익명성 유지: fcm_token 은 OS 가 발급한 디바이스 식별자이며,
--      Google 계정과 무관. 토큰 = 푸시 받을 채널 주소일 뿐.
--
--   4) iOS APNs 컬럼은 만들지 않음. 현재 코드베이스에 iOS 빌드 자체가
--      없으므로 Android FCM 만 지원. 추후 iOS 추가 시 별도 마이그레이션.
-- ============================================================

ALTER TABLE users ADD COLUMN fcm_token TEXT;
ALTER TABLE users ADD COLUMN push_updated_at TEXT;

-- 토큰별 조회는 거의 없지만 디버깅/중복 토큰 검증용 인덱스.
CREATE INDEX IF NOT EXISTS idx_users_fcm_token ON users(fcm_token);
