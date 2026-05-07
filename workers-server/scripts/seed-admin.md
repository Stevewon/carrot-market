# 어드민 계정 시드 가이드

## 1) 마이그레이션 적용 (최초 1회)

```bash
cd workers-server
npx wrangler d1 migrations apply eggplant-db --remote
```

## 2) 어드민 계정 비밀번호 해시 생성

PBKDF2-SHA256(100,000) 해시를 생성하려면 워커 환경에서 실행해야 합니다.
편의를 위해 임시 워커 엔드포인트를 사용하거나, 아래 Node.js 스크립트를 사용합니다.

### 방법 A: 임시 등록 라우트 (가장 쉬움)

`/api/admin/login` 으로 처음 로그인할 어드민이 없으면 접근 불가 →
**최초 1회만** D1 콘솔에서 직접 INSERT 합니다.

### 방법 B: Cloudflare D1 콘솔에서 직접 INSERT

1. Cloudflare Dashboard → Workers & Pages → D1 → eggplant-db → Console
2. 아래 SQL 실행 (`<password_hash>` 자리에 해시 문자열을 넣음)

```sql
INSERT INTO admins (id, username, password_hash, email, role, is_active, must_change_pw)
VALUES (
  'a0000001-0000-0000-0000-000000000001',
  'quantarium_admin',
  '<password_hash>',
  'quantarium1004@gmail.com',
  'super_admin',
  1,
  1
);
```

### 비밀번호 해시 생성 (Node.js 18+)

`workers-server/scripts/hash.mjs`:

```bash
node workers-server/scripts/hash.mjs "원하는임시비밀번호"
```

출력된 `pbkdf2$100000$<salt>$<hash>` 문자열을 위 SQL `<password_hash>` 자리에 넣습니다.

## 3) 첫 로그인

1. https://eggplant.life/admin/login.html
2. 아이디: `quantarium_admin`
3. 임시 비밀번호: 위에서 정한 것
4. `must_change_pw = 1` 이므로 즉시 새 비밀번호로 변경 강제

## 4) 보안 권고

- 임시 비밀번호는 1회용 — 첫 로그인 후 즉시 변경
- 어드민 토큰은 12시간 TTL — 만료 시 재로그인
- 의심스러운 세션은 D1 콘솔에서 `UPDATE admin_sessions SET revoked_at = datetime('now') WHERE admin_id = ?` 으로 강제 종료
- 모든 액션은 `admin_audit_log` 에 기록됨 — 정기 점검 권장
