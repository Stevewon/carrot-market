import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/product_service.dart';

class MyTab extends StatefulWidget {
  const MyTab({super.key});

  @override
  State<MyTab> createState() => _MyTabState();
}

class _MyTabState extends State<MyTab> {
  List<Product> _selling = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await context.read<ProductService>().fetchMyProducts();
    if (!mounted) return;
    setState(() {
      _selling = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('나의 Eggplant')),
      body: ListView(
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
                    child: Image.asset('assets/images/eggplant-mascot.png', fit: BoxFit.cover),
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
                              fontSize: 13, color: EggplantColors.primary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(user.region ?? '동네 미설정',
                          style: const TextStyle(
                              fontSize: 12, color: EggplantColors.textSecondary)),
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
          const Divider(height: 1),

          _MenuTile(
            icon: Icons.shopping_bag_outlined,
            title: '내가 판매중인 상품',
            trailing: _loading ? '-' : '${_selling.length}',
            onTap: () {
              // TODO: my products screen
            },
          ),
          _MenuTile(
            icon: Icons.favorite_border,
            title: '찜한 상품',
            onTap: () => context.go('/?tab=1'),
          ),
          _MenuTile(
            icon: Icons.location_on_outlined,
            title: '내 동네 설정',
            trailing: user.region ?? '설정 필요',
            onTap: () => context.push('/region'),
          ),
          _MenuTile(
            icon: Icons.qr_code_2,
            title: '내 QR 코드',
            subtitle: '친구에게 보여주고 대화 시작',
            onTap: () => context.push('/qr'),
          ),
          const Divider(height: 1),
          _MenuTile(
            icon: Icons.shield_outlined,
            title: '개인정보 보호',
            subtitle: '전화/이메일 수집 X · 채팅 저장 X',
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('🔐 개인정보 보호'),
                  content: const Text(
                    'Eggplant는 다음을 수집하지 않아요:\n\n'
                    '• 전화번호\n'
                    '• 이메일\n'
                    '• 실명\n'
                    '• 위치 좌표\n\n'
                    '또한 채팅 메시지는 서버와 기기 어디에도 저장되지 않습니다. '
                    '화면을 벗어나면 대화가 사라져요 💨',
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
              await context.read<AuthService>().logout();
              if (context.mounted) context.go('/onboarding');
            },
          ),
          const SizedBox(height: 40),
        ],
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
                const Icon(Icons.chevron_right, color: EggplantColors.textTertiary),
              ],
            ),
      onTap: onTap,
    );
  }
}
