import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import '../services/permission_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _requesting = false;

  Future<void> _startFlow({required String target}) async {
    if (_requesting) return;

    // If we've already bulk-asked on this device, skip straight to target.
    if (await PermissionService.hasAskedBefore()) {
      if (!mounted) return;
      context.push(target);
      return;
    }

    // Show a clean explainer first so users know WHY we ask for perms.
    final proceed = await _showPermissionExplainer();
    if (!mounted || proceed != true) return;

    setState(() => _requesting = true);
    try {
      // One system-level burst: camera, mic, photos, videos, notifications.
      await PermissionService.requestAll();
    } finally {
      if (mounted) setState(() => _requesting = false);
    }

    if (!mounted) return;
    context.push(target);
  }

  Future<bool?> _showPermissionExplainer() {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: EggplantColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '원활한 사용을 위해\n아래 권한이 필요해요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: EggplantColors.textPrimary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '한 번만 허용하면 다시 묻지 않아요.',
              style: TextStyle(
                fontSize: 13,
                color: EggplantColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            const _PermRow(
              emoji: '📷',
              title: '카메라',
              desc: 'QR 스캔 · 상품 사진/영상 촬영',
            ),
            const SizedBox(height: 10),
            const _PermRow(
              emoji: '🎙️',
              title: '마이크',
              desc: '익명 음성통화 (상대방에게만 전달)',
            ),
            const SizedBox(height: 10),
            const _PermRow(
              emoji: '🖼️',
              title: '사진 / 동영상',
              desc: '갤러리에서 상품 사진 선택',
            ),
            const SizedBox(height: 10),
            const _PermRow(
              emoji: '🔔',
              title: '알림',
              desc: '새 채팅 · 통화 알림',
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('확인하고 계속', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  '나중에 하기',
                  style: TextStyle(color: EggplantColors.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EggplantColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              Image.asset(
                'assets/images/eggplant-mascot.png',
                width: 200,
                height: 200,
              ),
              const SizedBox(height: 32),
              const Text(
                'Eggplant',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: EggplantColors.primary,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '전화번호 없이, 완전 익명으로\n안전하게 중고거래하세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: EggplantColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              const _FeatureRow(
                emoji: '🔐',
                title: 'QR 코드로만 연결',
                desc: '전화번호·이메일 없이 완벽한 익명',
              ),
              const SizedBox(height: 16),
              const _FeatureRow(
                emoji: '💬',
                title: '우리끼리 대화',
                desc: '채팅은 언제든 나가면 완전 삭제',
              ),
              const SizedBox(height: 16),
              const _FeatureRow(
                emoji: '🍆',
                title: '우리 동네 거래',
                desc: '내 동네 이웃과 안전하게',
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _requesting ? null : () => _startFlow(target: '/register'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _requesting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('회원가입',
                            style: TextStyle(fontSize: 17)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed:
                      _requesting ? null : () => _startFlow(target: '/login'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: EggplantColors.primary,
                    side: const BorderSide(color: EggplantColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('이미 계정이 있어요 · 로그인',
                      style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '퀀타리움 지갑주소로 가입해요 🍆',
                style: TextStyle(
                  fontSize: 12,
                  color: EggplantColors.textTertiary,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String desc;

  const _PermRow({required this.emoji, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: EggplantColors.textPrimary,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 13,
                  color: EggplantColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String desc;

  const _FeatureRow({required this.emoji, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EggplantColors.border),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: EggplantColors.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text(desc,
                    style: const TextStyle(
                      fontSize: 13,
                      color: EggplantColors.textSecondary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
