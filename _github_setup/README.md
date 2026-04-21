# 🔨 GitHub Actions APK 빌드 설정 가이드

**📱 모바일에서 APK를 다운받아 설치하려면, 이 워크플로우를 GitHub에 한 번만 등록하세요!**

> ⚠️ GitHub App의 보안 정책 때문에 봇이 `.github/workflows/` 폴더를 직접 만들 수 없어요.
> 사용자가 직접 한 번만 워크플로우 파일을 추가하면, 그 이후로는 자동으로 APK가 빌드됩니다.

---

## 🚀 설치 방법 (1분 소요)

### ⭐ 방법 1: GitHub 웹에서 파일 생성 (가장 쉬움)

1. **이 링크로 바로 이동**: <https://github.com/Stevewon/carrot-market/new/main?filename=.github/workflows/build-apk.yml>
2. 위 링크가 GitHub의 신규 파일 작성 페이지를 열어줍니다. (파일명도 미리 채워짐)
3. 에디터에 **[`build-apk.yml`](./build-apk.yml) 파일의 내용 전체**를 복사해서 붙여넣기
4. 하단의 초록색 **"Commit changes..."** 버튼 클릭 → **"Commit changes"** 확인
5. 완료! 바로 빌드가 시작됩니다 🎉

### 방법 2: 로컬 PC에서 수동 푸시

```bash
cd C:\Users\sayto\carrot-market
git pull origin main
mkdir .github\workflows
copy _github_setup\build-apk.yml .github\workflows\build-apk.yml
git add .github/workflows/build-apk.yml
git commit -m "ci: add APK build workflow"
git push origin main
```

---

## 📥 APK 다운로드 (빌드 완료 후)

### 🥇 모바일에서 바로 설치 — **Releases 페이지** ⭐ 추천

> 🔗 <https://github.com/Stevewon/carrot-market/releases/latest>

- 모바일 브라우저에서 위 링크 열기
- Assets 섹션에서 **`eggplant-universal-*.apk`** 탭
- 다운로드 후 파일 탭 → 설치

### 🥈 GitHub 로그인 후 — **Actions Artifacts** (90일 보관)

- <https://github.com/Stevewon/carrot-market/actions>
- 최신 빌드 클릭 → 하단 "Artifacts" 에서 `eggplant-apk-*` 다운로드
- ZIP 파일 안에 4개 APK가 들어있음

---

## 📱 Android 폰에 APK 설치

1. 다운받은 `eggplant-universal-*.apk` 탭
2. 처음 설치라면 **"알 수 없는 출처 앱 설치 허용"** 설정 켜기
   - Android 8+ : 설치 시 팝업에서 "설정" → "이 출처 허용" 토글
   - Android 7 이하: 설정 → 보안 → "알 수 없는 출처" 체크
3. 설치 완료 → 🍆 Eggplant 앱 아이콘 탭 → 실행!

---

## 🌐 서버 주소 변경 (실물 폰용 필수 설정)

기본 APK는 **Android 에뮬레이터** 전용 주소(`10.0.2.2:3001`)를 바라봅니다.
**실물 폰**에서 쓰려면 PC의 LAN IP로 바꿔야 해요.

### ① PC의 IP 확인

Windows PowerShell:
```powershell
ipconfig | findstr /i "IPv4"
```
예) `IPv4 주소. . . . . . . . . . : 192.168.0.15`

### ② GitHub Variables 설정 (재빌드 시 자동 반영)

1. <https://github.com/Stevewon/carrot-market/settings/variables/actions>
2. **"New repository variable"** 클릭
3. 두 개 추가:
   - Name: `API_BASE`, Value: `http://192.168.0.15:3001`
   - Name: `SOCKET_URL`, Value: `http://192.168.0.15:3001`
4. Actions 탭 → "🍆 Build Android APK" → **Run workflow** → 새 APK 다운로드

### ③ PC 방화벽 허용 (한 번만)

PowerShell 관리자 권한:
```powershell
New-NetFirewallRule -DisplayName "Eggplant 3001" -Direction Inbound -Protocol TCP -LocalPort 3001 -Action Allow -Profile Any
```

### ④ 폰과 PC가 같은 Wi‑Fi인지 확인
폰 Wi‑Fi = PC Wi‑Fi 여야 합니다. (모바일 데이터/VPN 꺼주세요)

---

## ✅ 워크플로우 동작 방식

- **언제 빌드되나요?**
  - `main` 브랜치에 코드 푸시될 때마다 (README, server 변경은 제외)
  - Actions 탭 → "Run workflow" 수동 실행
- **무엇이 빌드되나요?**
  - `eggplant-universal-*.apk` (모든 기기) ← 실물 폰용 추천
  - `eggplant-arm64-*.apk` (최신 폰, 용량 작음)
  - `eggplant-arm32-*.apk` (2018년 이전 폰)
  - `eggplant-x86_64-*.apk` (에뮬레이터)
- **빌드 시간**: 약 6‑10분 (Flutter SDK 다운로드 포함)

---

## 🛠️ 문제 해결

| 증상 | 해결 |
|------|------|
| "앱이 설치되지 않음" | 기존 앱 삭제 후 재설치 (서명 다름) |
| 앱 실행 시 "연결 실패" | 서버 주소 확인 (위 ③ 섹션) / 같은 Wi‑Fi인지 확인 |
| Actions 빌드 실패 | Actions 탭에서 로그 확인 후 이슈 공유 |
| "출처를 알 수 없는 앱" 경고 | Google Play Store가 아니므로 정상, 허용하면 됨 |
