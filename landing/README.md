# 🍆 Eggplant Landing — eggplant.life

회사 홈페이지(랜딩 페이지) — 정적 사이트.
Cloudflare Pages 에 배포되어 https://eggplant.life/ 루트로 서비스됩니다.

## 구성
- `index.html` — 메인 페이지 (Hero / Features / QTA / How / Trust / Download / FAQ / Footer)
- `style.css`  — 모바일 우선 반응형 (≥360 dp), 720/1024/1280 px 브레이크포인트
- `main.js`    — 햄버거 메뉴, 스크롤 nav, 부드러운 앵커, IntersectionObserver 페이드인
- `assets/eggplant-mascot.png` — 가지 마스코트
- `_headers`   — Cloudflare Pages 보안 헤더 + 캐시 정책
- `robots.txt` / `sitemap.xml` — SEO

## 차별화 기능 강조
1. 완전 익명 (전화·이메일·실명 0건)
2. QR 한 번에 채팅·거래 시작
3. 휘발성 채팅 (서버·기기 모두 보존 0)
4. QTA 토큰 채굴 + 출금
5. 동네 기반 거래 + 매너온도
6. 스크린샷 차단 (FLAG_SECURE)

## 모바일/PC 최적화
- 모바일 우선 (360 dp 최소 폭 보장)
- 720 px+ 태블릿 그리드 2열
- 1024 px+ PC 와이드 (nav 풀메뉴, hero 2단, features 3열, trust 4열)
- 터치 영역 ≥ 48 dp, 폰트 14~17 본문, 24~56 헤딩
- prefers-reduced-motion 대응

## 배포
Cloudflare Pages 프로젝트 (root: `landing/`) → eggplant.life 커스텀 도메인.
