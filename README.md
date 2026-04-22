# 🍆 Eggplant

> **QR 기반 완전 익명 중고거래 마켓**
> 전화번호도, 이메일도, 실명도 필요 없어요. QR 코드 하나면 충분합니다.

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()

## 📱 APK 다운로드 (모바일 바로 설치)

> 🔧 **첫 설정 필요**: [`_github_setup/README.md`](./_github_setup/README.md) 가이드대로 **한 번만** 워크플로우 파일을 추가하세요. (봇이 직접 `.github/workflows/` 를 만들 수 없는 GitHub 정책 때문)

그 뒤에는 이렇게 됩니다:

👉 **[최신 APK 다운로드 (Releases 페이지)](https://github.com/Stevewon/carrot-market/releases/latest)** ⭐

모바일 브라우저에서 위 링크 → `eggplant-universal-*.apk` 탭 → 설치하면 끝! 📥

<details>
<summary>📖 설치/빌드 상세 안내</summary>

- **실물 Android 폰**: `eggplant-universal-*.apk` 다운로드 (모든 기기 호환)
- **최신폰 (2019년↑)**: `eggplant-arm64-*.apk` (용량 30% 작음)
- **에뮬레이터 (x86)**: `eggplant-x86_64-*.apk`
- **자동 빌드 트리거**: `main` 브랜치에 푸시할 때마다 GitHub Actions가 자동 빌드
- **수동 빌드 실행**: Actions 탭 → 🍆 Build Android APK → Run workflow
- **서버 주소 변경**: Settings → Variables → `API_BASE` / `SOCKET_URL` 에 PC의 LAN IP (예: `http://192.168.0.15:3001`) 입력 후 재빌드

> ⚠️ 처음 설치 시 Android에서 "알 수 없는 출처 앱 허용"이 필요합니다.

</details>

---

## 🎯 Eggplant이 특별한 이유

### 🔐 완전 익명
- 전화번호, 이메일, 실명 **일체 수집 안 함**
- 닉네임 + 기기 UUID만 사용
- 거래 상대와 **QR 코드**로만 연결

### 💨 휘발성 채팅 (QRChat 방식)
- 메시지는 **서버에 저장 X**
- 메시지는 **기기에도 저장 X**
- 화면을 벗어나면 대화 내용 **증발**
- 스크린샷 방지 (Android FLAG_SECURE)

### 🏘️ 동네 기반 거래
- 지역 설정으로 내 동네 이웃과 거래
- 매너온도로 신뢰도 표시

---

## 🛠️ 기술 스택

### 📱 모바일 앱 (Flutter)
| 기술 | 용도 |
|------|------|
| **Flutter 3.22+** | 크로스플랫폼 네이티브 앱 |
| **Dart** | 언어 |
| **go_router** | 화면 라우팅 |
| **provider** | 상태 관리 |
| **mobile_scanner** | QR 스캐너 |
| **qr_flutter** | QR 생성 |
| **dio** | HTTP 클라이언트 |
| **web_socket_channel** | 실시간 채팅 (raw WebSocket) |
| **flutter_webrtc** | P2P 음성 통화 |
| **flutter_windowmanager** | 스크린샷 방지 |

### ☁️ 백엔드 (Cloudflare Workers — production)
| 기술 | 용도 |
|------|------|
| **Cloudflare Workers** | 서버리스 런타임 |
| **Hono** | REST API 라우터 |
| **D1** | SQLite (users / products / likes) |
| **R2** | 상품 이미지 저장소 |
| **Durable Objects** | WebSocket 채팅 + WebRTC 시그널링 |
| **JWT (HS256)** | 익명 인증 |

### 🖥️ 로컬 개발용 (Node.js — 레거시)
| 기술 | 용도 |
|------|------|
| **Node.js 20+ / Express / Socket.io** | 로컬 실험 전용 (Cloudflare 로 이전 완료) |

---

## 📂 프로젝트 구조

```
eggplant/
├── lib/                        # Flutter 앱 소스
│   ├── main.dart
│   ├── app/
│   │   ├── app_router.dart     # 라우팅
│   │   ├── theme.dart          # 보라색 테마
│   │   └── constants.dart
│   ├── models/                 # 데이터 모델
│   ├── services/               # 비즈니스 로직
│   │   ├── auth_service.dart   # 익명 인증
│   │   ├── product_service.dart
│   │   └── chat_service.dart   # 휘발성 채팅
│   ├── screens/                # 화면
│   └── widgets/                # 공통 위젯
│
├── workers-server/             # ☁️ Cloudflare Workers 백엔드 (production)
│   ├── src/
│   │   ├── index.ts            # Hono 라우터 + WS 업그레이드
│   │   ├── chat-hub.ts         # Durable Object (채팅/WebRTC 시그널링)
│   │   ├── jwt.ts              # JWT 서명/검증 미들웨어
│   │   ├── types.ts
│   │   └── routes/             # auth / users / products
│   ├── migrations/0001_init.sql
│   └── wrangler.toml
│
├── server/                     # Node.js 백엔드 (레거시, 로컬 전용)
│   ├── index.js
│   ├── db.js                   # SQLite 스키마
│   ├── chat.js                 # Socket.io (Cloudflare 이전 후 미사용)
│   └── routes/
│
├── android/                    # Android 네이티브 설정
├── assets/images/              # 마스코트 등 에셋
├── .github/workflows/          # GitHub Actions (APK 자동 빌드)
└── pubspec.yaml
```

---

## 🚀 빠른 시작

### 🌐 프로덕션 백엔드 (Cloudflare Workers)

APK 빌드는 기본적으로 **`https://api.eggplant.life`** (Cloudflare Workers + D1 + R2 + Durable Objects) 에 연결됩니다.

서버를 처음 배포하거나 커스텀 도메인(`eggplant.life`)을 연결할 때는 [`workers-server/README.md`](./workers-server/README.md) 의 단계별 가이드를 따르세요.

배포 요약:

```bash
cd workers-server
npm install
npx wrangler login
npx wrangler d1 create eggplant-db           # DB 생성 → wrangler.toml 에 database_id 붙여넣기
npx wrangler d1 migrations apply eggplant-db --remote
npx wrangler r2 bucket create eggplant-uploads
npx wrangler secret put JWT_SECRET           # 임의 문자열 입력
npx wrangler deploy
```

도메인 연결은 Cloudflare 대시보드에서 `eggplant.life` 을 추가 → 가비아 네임서버 교체 → `wrangler.toml` 의 `routes` 블록 주석 해제 → 재배포.

### 1️⃣ (레거시) Node.js 서버 로컬 실행

> ⚠️ Cloudflare 로 이전 완료. 로컬 실험용으로만 사용.

```bash
cd server
npm install
cp .env.example .env
npm start
```

서버가 `http://localhost:3001` 에서 시작됩니다.

### 2️⃣ Flutter 앱 실행 (로컬 개발)

#### 선행 조건
- Flutter SDK 3.22+ 설치
- Android Studio 또는 Xcode
- Android 기기 / 에뮬레이터 또는 iOS 기기 / 시뮬레이터

```bash
# 프로젝트 루트에서
flutter pub get

# Android 에뮬레이터에서 실행 (기본 API: http://10.0.2.2:3001)
flutter run

# 로컬 Workers dev 서버 (wrangler dev, 기본 포트 8787)
flutter run --dart-define=API_BASE=http://10.0.2.2:8787 \
            --dart-define=SOCKET_URL=ws://10.0.2.2:8787/socket

# 또는 실 기기에서 프로덕션 서버로 바로 붙이기 (기본값이라 생략 가능)
flutter run --dart-define=API_BASE=https://api.eggplant.life \
            --dart-define=SOCKET_URL=wss://api.eggplant.life/socket
```

### 3️⃣ APK 빌드

#### 로컬에서 빌드
```bash
flutter build apk --release
# 결과물: build/app/outputs/flutter-apk/app-release.apk
```

#### GitHub Actions로 자동 빌드 ⭐
`main` 브랜치에 푸시하면 자동으로 APK가 빌드됩니다.

1. GitHub 저장소의 **Actions** 탭으로 이동
2. 최신 빌드 선택
3. **Artifacts** 에서 `eggplant-release-apk` 다운로드
4. 또는 **Releases** 탭에서 태그별 APK 다운로드

---

## 🔐 개인정보 보호 설계

### 수집하지 않는 정보
- ❌ 전화번호
- ❌ 이메일
- ❌ 실명
- ❌ 위치 좌표 (GPS)
- ❌ 생년월일
- ❌ 성별

### 수집하는 정보 (최소한)
- ✅ 닉네임 (사용자가 직접 입력, 익명)
- ✅ 기기 UUID (자동 생성, 앱 재설치 시 초기화)
- ✅ 지역 (사용자가 선택, 구 단위만)

### 채팅 데이터
- 🚫 서버 저장 없음
- 🚫 기기 로컬 DB 저장 없음
- ✅ 메모리에만 존재 (화면 벗어나면 삭제)
- ✅ Android 스크린샷 방지

---

## 📱 주요 화면

1. **온보딩** - Eggplant 소개
2. **닉네임 가입** - 전화번호 없이 2~12자 닉네임만
3. **홈 (상품 피드)** - 카테고리별/지역별 상품 목록
4. **상품 등록** - 사진, 제목, 가격, 카테고리, 설명
5. **상품 상세** - 이미지 슬라이드, 판매자 정보, 채팅 시작
6. **QR 코드** - 내 QR 보여주기
7. **QR 스캔** - 상대 QR 스캔해서 익명 채팅 시작
8. **채팅** - 휘발성, 저장 안 됨
9. **찜 목록** - 관심 상품
10. **내 정보** - 프로필, 설정, 매너온도
11. **동네 설정** - 지역 선택

---

## 🎨 브랜드

### 로고 / 마스코트
`assets/images/eggplant-mascot.png` — 귀여운 보라색 가지 캐릭터 🍆

### 색상
- **Primary**: `#9333EA` (보라색 / eggplant-600)
- **Primary Light**: `#C084FC` (eggplant-400)
- **Background**: `#FAF5FF` (eggplant-50)
- **Accent**: `#22C55E` (잎사귀 녹색)

---

## 🧪 API 엔드포인트

### Auth
- `POST /api/auth/register` - 익명 가입 (닉네임 + 기기 UUID)
- `POST /api/auth/login` - 기기 UUID로 자동 로그인
- `GET /api/auth/me` - 내 프로필

### Products
- `GET /api/products` - 상품 목록 (필터: category, region, search)
- `GET /api/products/:id` - 상품 상세
- `POST /api/products` - 상품 등록 (multipart/form-data)
- `POST /api/products/:id/like` - 찜 토글
- `GET /api/products/my/likes` - 내 찜 목록
- `GET /api/products/my/selling` - 내 판매중 목록
- `PUT /api/products/:id/status` - 판매상태 변경
- `DELETE /api/products/:id` - 상품 삭제

### Chat (Socket.io)
- `connect` (with JWT token)
- `join_room { room_id, peer_nickname, product_id }`
- `leave_room { room_id }`
- `message { room_id, text, sender_nickname }`
- `disconnect`

---

## 🚢 배포 가이드

### Google Play Store 등록 체크리스트
- ✅ 앱 이름: **Eggplant** (상표권 안전)
- ✅ 로고/캐릭터: 자체 제작 (저작권 안전)
- ✅ 개인정보처리방침 URL 필요 (별도 작성)
- ✅ APK 서명 키 (`android/key.properties` 설정)

### 서명 키 생성
```bash
keytool -genkey -v -keystore ~/eggplant-release-key.jks \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -alias eggplant
```

---

## 📄 라이선스

MIT License © 2026 Eggplant Team

---

## 🤝 기여

Pull Request 환영합니다!

---

**🍆 Made with Eggplant**
