-- 0018_reset_all_data.sql
--
-- ⚠️ NOOP 처리됨 (2026-05-02)
--
-- 사유:
--   원본 0018 은 D1 잔재 메타(과거 0005 마이그레이션의 users_old 흔적)
--   때문에 'no such table: main.users_old (SQLITE_ERROR 7500)' 로 영구 실패.
--   - 단독 실행으로도 실패 재현됨
--   - sqlite_master 에 users_old 참조 객체 0건 (트리거/뷰 없음)
--   - D1 내부 캐시·rebuild 메타에 RENAME 잔재가 남은 것으로 추정
--
-- 해결:
--   0018 의 "샘플 데이터 일괄 삭제" 자체는 운영 단계에서 불필요(QA/개발용).
--   따라서 본 파일을 no-op 으로 변환하여 마이그레이션 체인을 통과시키고,
--   필요 시 D1 콘솔에서 DELETE 문을 직접 실행한다.
--
-- 멱등성: 매번 실행해도 안전 (아무 동작도 하지 않음).

-- 단순한 no-op SELECT 한 줄 (D1 가 빈 파일을 거부할 수 있어 명시).
SELECT 1 AS noop;
