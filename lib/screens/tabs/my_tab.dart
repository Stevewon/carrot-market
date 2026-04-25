import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '../../services/moderation_service.dart';
import '../../services/product_service.dart';
import '../../services/search_history_service.dart';
import '../../services/keyword_alert_service.dart';
import '../../services/hidden_products_service.dart';

class MyTab extends StatefulWidget {
  const MyTab({super.key});

  @override
  State<MyTab> createState() => _MyTabState();
}

String _shortenWallet(String w) {
  if (w.length <= 12) return w;
  return '${w.substring(0, 6)}...${w.substring(w.length - 4)}';
}

class _MyTabState extends State<MyTab> {
  @override
  void initState() {
    super.initState();
    // Prime the caches once; everything else auto-refreshes via notifyListeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = context.read<ProductService>();
      svc.fetchMyProducts(silent: svc.mySellingLoaded);
      svc.fetchMyLikes(silent: svc.myLikesLoaded);
    });
  }

  Future<void> _refresh() async {
    final svc = context.read<ProductService>();
    await Future.wait([
      svc.fetchMyProducts(silent: true),
      svc.fetchMyLikes(silent: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final svc = context.watch<ProductService>();
    final user = auth.user;
    if (user == null) return const SizedBox.shrink();

    final sellingCount = svc.mySelling.length;
    final likeCount = svc.myLikes.length;

    return Scaffold(
      appBar: AppBar(title: const Text('나의 Eggplant')),
      body: RefreshIndicator(
        color: EggplantColors.primary,
        onRefresh: _refresh,
        child: ListView(
          children: [
            // Profile Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: EggplantColors.background,
                      border: Border.all(color: EggplantColors.primary, width: 2),
                    ),
                    child: ClipOval(
                      child: Image.asset('assets/images/eggplant-mascot.png',
                          fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.nickname,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('매너온도 ${user.mannerScore}.5°C',
                            style: const TextStyle(
                                fontSize: 13,
                                color: EggplantColors.primary,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(user.region ?? '동네 미설정',
                            style: const TextStyle(
                                fontSize: 12,
                                color: EggplantColors.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code, color: EggplantColors.primary),
                    onPressed: () => context.push('/qr'),
                  ),
                ],
              ),
            ),

            // Quick stats row
            _StatsRow(
              selling: sellingCount,
              likes: likeCount,
              onSellingTap: () => context.push('/my/products'),
              onLikesTap: () => context.go('/?tab=1'),
            ),

            const Divider(height: 1),

            _MenuTile(
              icon: Icons.shopping_bag_outlined,
              title: '내가 판매중인 상품',
              trailing: svc.mySellingLoading && !svc.mySellingLoaded
                  ? '…'
                  : '$sellingCount',
              onTap: () => context.push('/my/products'),
            ),
            _MenuTile(
              icon: Icons.favorite_border,
              title: '찜한 상품',
              trailing: svc.myLikesLoading && !svc.myLikesLoaded
                  ? '…'
                  : '$likeCount',
              onTap: () => context.go('/?tab=1'),
            ),
            _MenuTile(
              icon: Icons.chat_bubble_outline,
              title: '채팅',
              onTap: () => context.go('/?tab=2'),
            ),
            _MenuTile(
              icon: Icons.location_on_outlined,
              title: '내 동네 설정',
              trailing: user.region ?? '설정 필요',
              onTap: () => context.push('/region'),
            ),
            if (user.walletAddress != null && user.walletAddress!.isNotEmpty)
              _MenuTile(
                icon: Icons.account_balance_wallet_outlined,
                title: '지갑주소',
                subtitle: _shortenWallet(user.walletAddress!),
                onTap: () async {
                  await Clipboard.setData(
                      ClipboardData(text: user.walletAddress!));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('지갑주소를 복사했어요')),
                  );
                },
              ),
            _MenuTile(
              icon: Icons.qr_code_2,
              title: '내 QR 코드',
              subtitle: '친구에게 보여주고 대화 시작',
              onTap: () => context.push('/qr'),
            ),
            const Divider(height: 1),
            _MenuTile(
              icon: Icons.notifications_active_outlined,
              title: '키워드 알림',
              subtitle: '관심 키워드 등록하고 새 매물 알림 받기',
              onTap: () => context.push('/alerts/keywords'),
            ),
            _MenuTile(
              icon: Icons.visibility_off_outlined,
              title: '숨긴 게시물',
              subtitle: '내가 가린 게시물 다시 보기',
              onTap: () => context.push('/hidden'),
            ),
            const Divider(height: 1),
            _MenuTile(
              icon: Icons.shield_outlined,
              title: '개인정보 보호',
              subtitle: '채팅·통화 절대 저장 안 함 · 한 번 흘러간 메시지는 영구 소실',
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('🔐 개인정보 보호'),
                    content: const Text(
                      'Eggplant는 다음을 수집하지 않아요:\n\n'
                      '• 전화번호 · 이메일 · 실명\n'
                      '• 정확한 GPS (동네 인증 시 즉시 폐기)\n'
                      '• 채팅 내용 (DB 저장 0)\n'
                      '• 통화 내용 (P2P, 서버 미경유)\n\n'
                      '채팅은 휘발성이에요. 한 번 흘러간 메시지는 양쪽 기기 어디에도 '
                      '복원되지 않아요. 앱을 종료하거나 다른 기기로 로그인하면 '
                      '모든 대화가 빈 상태에서 시작돼요 💨',
                      style: TextStyle(height: 1.6),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('확인'),
                      ),
                    ],
                  ),
                );
              },
            ),
            _MenuTile(
              icon: Icons.info_outline,
              title: '앱 정보',
              trailing: 'v0.1.0',
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'Eggplant 🍆',
                  applicationVersion: '0.1.0',
                  applicationLegalese: '© 2026 Eggplant Team\n익명으로 안전한 중고거래',
                );
              },
            ),
            const Divider(height: 1),
            _MenuTile(
              icon: Icons.logout,
              title: '로그아웃',
              titleColor: EggplantColors.error,
              onTap: () async {
                // Wipe cached lists so next user starts fresh.
                context.read<ProductService>().clearCaches();
                context.read<ModerationService>().clear();
                context.read<KeywordAlertService>().clear();
                context.read<HiddenProductsService>().clear();
                // ignore: unawaited_futures
                context.read<SearchHistoryService>().clear();
                await context.read<AuthService>().logout();
                if (context.mounted) context.go('/onboarding');
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int selling;
  final int likes;
  final VoidCallback onSellingTap;
  final VoidCallback onLikesTap;

  const _StatsRow({
    required this.selling,
    required this.likes,
    required this.onSellingTap,
    required this.onLikesTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.shopping_bag_outlined,
              label: '판매중',
              value: '$selling',
              onTap: onSellingTap,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              icon: Icons.favorite_border,
              label: '찜',
              value: '$likes',
              onTap: onLikesTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EggplantColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            children: [
              Icon(icon, color: EggplantColors.primary, size: 22),
              const SizedBox(width: 10),
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: EggplantColors.textSecondary)),
              const Spacer(),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: EggplantColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback onTap;
  final Color? titleColor;

  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: titleColor ?? EggplantColors.textSecondary),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: titleColor ?? EggplantColors.textPrimary,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12)),
      trailing: trailing == null
          ? const Icon(Icons.chevron_right, color: EggplantColors.textTertiary)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(trailing!,
                    style: const TextStyle(
                        fontSize: 13, color: EggplantColors.textSecondary)),
                const Icon(Icons.chevron_right,
                    color: EggplantColors.textTertiary),
              ],
            ),
      onTap: onTap,
    );
  }
}
