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
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final auth = context.read<AuthService>();

    // Upgrade path: existing users who installed before the bulk-permission
    // flow never saw the explainer. Prompt them once, right after splash.
    if (auth.isLoggedIn && !await PermissionService.hasAskedBefore()) {
      await PermissionService.requestAll();
    }

    if (!mounted) return;
    if (auth.isLoggedIn) {
      // Warm up the block cache so feed/chat filtering works on first load.
      // Fire-and-forget; failure is non-fatal.
      // ignore: unawaited_futures
      context.read<ModerationService>().fetchBlocks();
      context.go('/');
    } else {
      context.go('/onboarding');
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
