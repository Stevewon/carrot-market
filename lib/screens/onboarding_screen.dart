import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/responsive.dart';
import '../app/theme.dart';
import '../services/permission_service.dart';

/// 당근마켓 스타일 온보딩.
///
/// 좌우 스와이프 페이지뷰 (3페이지) + 하단 인디케이터 점 + 우상단 건너뛰기.
/// 마지막 페이지에서만 [시작하기] 버튼 노출.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageCtl = PageController();
  int _currentPage = 0;
  bool _requesting = false;

  static const _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      headline: '전화번호 없이\n익명으로 거래해요',
      desc: '닉네임 하나면 충분해요.\n개인정보 노출 걱정 없이 안전하게.',
      bgColor: Color(0xFFFAF5FF),
    ),
    _OnboardingPageData(
      headline: '우리 동네\n이웃과 거래해요',
      desc: '내 동네 인증된 사람들과만 만나요.\nQR 코드로 안심하고 직거래!',
      bgColor: Color(0xFFF5F3FF),
    ),
    _OnboardingPageData(
      headline: '쓸수록 쌓이는\nQTA 토큰 보상',
      desc: '가입만 해도 +500 QTA,\n친구 초대마다 +200 QTA × 무제한!',
      bgColor: Color(0xFFFAF5FF),
    ),
  ];

  @override
  void dispose() {
    _pageCtl.dispose();
    super.dispose();
  }

  Future<void> _startFlow({required String target}) async {
    if (_requesting) return;

    if (await PermissionService.hasAskedBefore()) {
      if (!mounted) return;
      context.push(target);
      return;
    }

    final proceed = await _showPermissionExplainer();
    if (!mounted || proceed != true) return;

    setState(() => _requesting = true);
    try {
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

  void _goNextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageCtl.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _startFlow(target: '/register');
    }
  }

  void _skipToEnd() {
    _pageCtl.animateToPage(
      _pages.length - 1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: _pages[_currentPage].bgColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Responsive.maxContentWidth,
            ),
            child: Column(
              children: [
                // ────────────────────────────────────────
                // 우상단: 건너뛰기 (마지막 페이지에서는 숨김)
                // ────────────────────────────────────────
                SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!isLastPage)
                          TextButton(
                            onPressed: _skipToEnd,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              '건너뛰기',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: EggplantColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // ────────────────────────────────────────
                // 메인: 좌우 스와이프 페이지뷰
                // ────────────────────────────────────────
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtl,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (_, i) => _OnboardingPage(data: _pages[i]),
                  ),
                ),

                // ────────────────────────────────────────
                // 인디케이터 점
                // ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 24, top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? EggplantColors.primary
                              : EggplantColors.primary.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),

                // ────────────────────────────────────────
                // 하단 버튼: 다음/시작하기 + 로그인 링크
                // ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _requesting ? null : _goNextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: EggplantColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _requesting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  isLastPage ? '시작하기' : '다음',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '이미 계정이 있어요?',
                            style: TextStyle(
                              fontSize: 13,
                              color: EggplantColors.textSecondary,
                            ),
                          ),
                          TextButton(
                            onPressed: _requesting
                                ? null
                                : () => _startFlow(target: '/login'),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: const Size(0, 0),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              '로그인',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: EggplantColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 한 페이지의 데이터.
class _OnboardingPageData {
  final String headline;
  final String desc;
  final Color bgColor;

  const _OnboardingPageData({
    required this.headline,
    required this.desc,
    required this.bgColor,
  });
}

/// 한 페이지: 마스코트(상단) + 헤드라인 + 설명.
class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;
  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),
          // 마스코트 — 모든 페이지 공통, 부드럽게 떠있는 듯 가벼운 그림자
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: EggplantColors.primary.withOpacity(0.08),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Image.asset(
              'assets/images/eggplant-mascot.png',
              fit: BoxFit.contain,
            ),
          ),
          const Spacer(flex: 2),
          // 헤드라인 — 큰 폰트, 진한 색
          Text(
            data.headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: EggplantColors.textPrimary,
              height: 1.3,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          // 보조 설명 — 회색, 두 줄
          Text(
            data.desc,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: EggplantColors.textSecondary,
              height: 1.6,
            ),
          ),
          const Spacer(flex: 3),
        ],
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
