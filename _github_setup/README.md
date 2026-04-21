# 🔨 GitHub Actions 설정 가이드

이 폴더에는 **GitHub App 권한 제한**으로 자동 푸시가 불가능한 워크플로우 파일이 들어있어요.
GitHub 웹사이트에서 직접 추가해주세요. 한 번만 하면 돼요!

## 📋 `.github/workflows/build-apk.yml` 추가하기

### 방법 1: GitHub 웹에서 파일 생성 ⭐ 쉬움

1. **GitHub 저장소로 이동**: https://github.com/Stevewon/carrot-market
2. 초록색 **"Add file" → "Create new file"** 클릭
3. 파일명에 다음 입력 (슬래시가 폴더를 만들어요):
   ```
   .github/workflows/build-apk.yml
   ```
4. 에디터에 아래 `build-apk.yml` 파일 내용 **전부 복사/붙여넣기**
5. 하단 **"Commit new file"** 클릭

### 방법 2: 로컬에서 커밋 & 푸시

본인 PC에서 저장소를 클론 후:
```bash
git clone https://github.com/Stevewon/carrot-market.git
cd carrot-market
mkdir -p .github/workflows
cp _github_setup/build-apk.yml .github/workflows/
git add .github/workflows/build-apk.yml
git commit -m "ci: Add Android APK build workflow"
git push
```

## ✅ 추가 완료 후

- `main` 브랜치에 **푸시할 때마다** APK가 자동으로 빌드돼요
- GitHub 저장소의 **Actions** 탭에서 빌드 상태 확인
- **Artifacts** 에서 `eggplant-release-apk` 다운로드
- **Releases** 탭에서 버전별 APK 다운로드 가능

## 📱 APK를 Android에 설치

1. 다운받은 `app-release.apk` 파일을 Android 폰으로 전송
2. "출처를 알 수 없는 앱 설치 허용" 설정 켜기
3. APK 파일 탭 → 설치
4. Eggplant 앱 실행! 🍆
