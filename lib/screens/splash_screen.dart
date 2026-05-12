import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/moderation_service.dart';
import '../services/permission_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    // 스플래시 절대 데드라인 — 어떤 비동기가 멈춰도 6초 뒤엔 무조건 다음 화면.
    // (loadFromStorage / refreshFromServer 자체는 각 5초 타임아웃이 있지만,
    //  플랫폼 채널 이슈 등으로 await 가 안 풀리는 케이스를 안전하게 차단.)
    bool navigated = false;
    void goSafe(String path) {
      if (navigated || !mounted) return;
      navigated = true;
      context.go(path);
    }

    // Hard deadline.
    Future.delayed(const Duration(seconds: 6), () {
      if (navigated || !mounted) return;
      final auth = context.read<AuthService>();
      goSafe(auth.isLoggedIn ? '/' : '/onboarding');
    });

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted || navigated) return;
    final auth = context.read<AuthService>();

    // Upgrade path: existing users who installed before the bulk-permission
    // flow never saw the explainer. Prompt them once, right after splash.
    if (auth.isLoggedIn && !await PermissionService.hasAskedBefore()) {
      await PermissionService.requestAll();
    }

    // ★ v1.0.161 (2026-05-12): FSI(Full-Screen Intent) 권한 자동 안내.
    //   Android 14+ 부터 USE_FULL_SCREEN_INTENT 가 기본 OFF 라서
    //   잠금화면 incoming call 풀스크린이 안 뜨는 문제 해결.
    //   - 권한 ON 이면 조용히 통과 (Android 13 이하 포함)
    //   - 권한 OFF 이면 사장님 친화 다이얼로그 → "권한 허용" 1탭으로 시스템 설정 직행
    //   - 같은 세션에서는 1회만 안내 (사장님 동선 보호)
    if (mounted && auth.isLoggedIn) {
      // ignore: unawaited_futures
      PermissionService.ensureFullScreenIntentOrGuide(context);
    }

    if (!mounted || navigated) return;
    if (auth.isLoggedIn) {
      // 서버에서 사용자가 이미 삭제됐거나 (운영자 reset / 본인 탈퇴 / DB
      // 마이그레이션 0018) 토큰이 만료된 경우 401 인터셉터가 _localLogout 을
      // 호출해서 isLoggedIn 이 false 가 된다. 그 경우 즉시 온보딩으로 보낸다.
      // refreshFromServer 자체에 5초 타임아웃이 있고, 추가 4초 안전망까지 건다.
      try {
        await auth.refreshFromServer().timeout(const Duration(seconds: 4));
      } catch (_) {
        /* 네트워크/타임아웃 이슈는 무시 — 다음 실 API 호출에서 재검증된다 */
      }
      if (!mounted || navigated) return;
      if (!auth.isLoggedIn) {
        goSafe('/onboarding');
        return;
      }
      // Warm up the block cache so feed/chat filtering works on first load.
      // Fire-and-forget; failure is non-fatal.
      // ignore: unawaited_futures
      context.read<ModerationService>().fetchBlocks();
      goSafe('/');
    } else {
      goSafe('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EggplantColors.background,
      body: SafeArea(
        child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/eggplant-mascot.png',
              width: 160,
              height: 160,
            ),
            const SizedBox(height: 24),
            const Text(
              'Eggplant',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: EggplantColors.primary,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '익명으로 안전한 중고거래 🍆',
              style: TextStyle(
                fontSize: 15,
                color: EggplantColors.textSecondary,
              ),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: EggplantColors.primary,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
