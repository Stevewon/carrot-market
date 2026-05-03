# Eggplant Admin Console

PC 전용 웹 어드민 (Cloudflare Pages 정적 배포).

## 구조
```
admin-web/
├── index.html          # 단일 HTML (PC 가드 + 사이드바)
├── style.css           # 데스크탑 UI
├── app.js              # 라우터 + API 헬퍼 + 토큰 관리
├── pages/
│   ├── dashboard.js    # ④ 매출/통계
│   ├── users.js        # ① 사용자 관리
│   ├── products.js     # ② 상품 관리
│   ├── qkey.js         # ③ QKEY 거래 원장
│   ├── notices.js      # ⑤ 공지/푸시 발송
│   ├── reports.js      # ⑥ 신고 처리
│   └── audit.js        # 감사 로그
└── README.md
```

## 보안 정책
- **PC 전용**: 화면폭 1024px 미만이면 안내 화면만 표시
- **별도 토큰**: Workers Secrets `ADMIN_TOKEN` 과 `Authorization: Admin <token>` 헤더로 통신
- **세션 저장**: `sessionStorage` (탭 닫으면 자동 삭제)
- **모든 액션 감사 로그**: `admin_audit` 테이블에 IP/UA 기록

## 배포 (Cloudflare Pages)

### 신규 프로젝트 생성
```bash
# 1. Cloudflare Pages 에 정적 사이트 생성
# Cloudflare Dashboard → Pages → Create a project → Direct Upload
# 프로젝트명: admin-eggplant
# 빌드 설정: 빌드 명령 없음 / 출력 디렉터리: admin-web/

# 2. 또는 wrangler 로 배포 (권장)
npx wrangler pages deploy admin-web --project-name=admin-eggplant
```

### 도메인 연결 (선택)
```
admin.eggplant.life → admin-eggplant.pages.dev
```

### 환경별 API base override
프로덕션 외 환경에서 사용 시 `admin-web/config.js` 추가:
```js
window.__ADMIN_API_BASE__ = 'https://staging-api.eggplant.life';
```
그리고 `index.html` 의 `app.js` 위에 `<script src="./config.js"></script>` 추가.

## 백엔드 사전 작업

### 1) ADMIN_TOKEN 발급
```bash
cd workers-server
# 32자 랜덤 hex 생성 후 입력
openssl rand -hex 32
npx wrangler secret put ADMIN_TOKEN
```

### 2) D1 마이그레이션 적용
```bash
cd workers-server
npx wrangler d1 migrations apply eggplant-db --remote
```

### 3) Workers 배포
```bash
cd workers-server
npx wrangler deploy
```

## 사용법
1. `https://admin.eggplant.life` 접속 (PC 브라우저)
2. ADMIN_TOKEN 입력 → 접속
3. 좌측 사이드바에서 6대 기능 선택
4. 모든 액션은 자동으로 `admin_audit` 에 기록됨

## 보안 권고
- 토큰 노출 시 즉시 `wrangler secret put ADMIN_TOKEN` 으로 교체
- 토큰은 32자 이상의 랜덤 문자열 사용
- 어드민 페이지 URL을 외부에 공개하지 않기
- 정기적으로 감사 로그 확인 (예상치 못한 IP/UA 체크)
