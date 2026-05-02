import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '../../services/moderation_service.dart';
import '../../services/product_service.dart';
import '../../services/search_history_service.dart';
import '../../services/keyword_alert_service.dart';
import '../../services/hidden_products_service.dart';
import '../../services/notification_service.dart';
import '../../services/qta_service.dart';
import '../../models/user.dart';

class MyTab extends StatefulWidget {
  const MyTab({super.key});

  @override
  State<MyTab> createState() => _MyTabState();
}

class _MyTabState extends State<MyTab> {
  /// 앱 버전 표기 — 사장님 지시 형식 'v1.0.<빌드번호>'.
  /// 예) 빌드 #55 → 'v1.0.55'
  /// GitHub Actions 의 --build-number=N 이 PackageInfo.buildNumber 로 들어옴.
  String _appVersionLabel = 'v…';

  @override
  void initState() {
    super.initState();
    // Prime the caches once; everything else auto-refreshes via notifyListeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = context.read<ProductService>();
      svc.fetchMyProducts(silent: svc.mySellingLoaded);
      svc.fetchMyLikes(silent: svc.myLikesLoaded);
      // QTA 잔액 + 최근 내역 1회 로드 (이후 보너스 수령 시 갱신).
      final qta = context.read<QtaService>();
      qta.load();
      // 오늘 둘러보기 채굴 현황도 함께 로드.
      qta.loadBrowseMining();
    });
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      // 사장님 지시 표기 형식: v1.0.<빌드번호>
      // 예) buildNumber='55'  →  'v1.0.55'
      // buildNumber 가 비어있으면 (개발 중) 'v1.0.0' 으로 폴백.
      final b = info.buildNumber.isEmpty ? '0' : info.buildNumber;
      setState(() {
        _appVersionLabel = 'v1.0.$b';
      });
    } catch (_) {/* 못 읽어도 'v…' 그대로 — 앱 동작에는 영향 없음 */}
  }

  Future<void> _refresh() async {
    final svc = context.read<ProductService>();
    final qta = context.read<QtaService>();
    await Future.wait([
      svc.fetchMyProducts(silent: true),
      svc.fetchMyLikes(silent: true),
      qta.load(force: true),
      qta.loadBrowseMining(force: true),
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
      // 태블릿/폴드 펼침에서 600dp 가운데 정렬.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.maxFeedWidth),
          child: RefreshIndicator(
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(user.nickname,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 6),
                            _VerificationBadge(level: user.verificationLevel),
                          ],
                        ),
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

            // 인증 단계 CTA 카드 (Lv0/1 일 때만 노출)
            if (user.verificationLevel != VerificationLevel.bankAccount)
              _VerificationCta(level: user.verificationLevel),

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
            // QTA 지갑 카드 (지갑주소 마스킹 + 복사 + 잔액)
            if (user.walletAddress != null && user.walletAddress!.isNotEmpty)
              _QtaWalletCard(walletAddress: user.walletAddress!),

            // 오늘 둘러보기 채굴 현황 (X/10개 → +10 QTA)
            const _BrowseMiningCard(),

            _MenuTile(
              icon: Icons.qr_code_2,
              title: '내 QR 코드',
              subtitle: '친구에게 보여주고 대화 시작',
              onTap: () => context.push('/qr'),
            ),
            const Divider(height: 1),
            _MenuTile(
              icon: Icons.card_giftcard_outlined,
              title: '친구 초대 (+200 QTA)',
              subtitle: '친구가 가입할 때 내 닉네임을 입력하면 +200 QTA · 무제한',
              onTap: () => context.push('/referrals'),
            ),
            _MenuTile(
              icon: Icons.notifications_active_outlined,
              title: '키워드 알림',
              subtitle: '관심 키워드 등록하고 새 매물 알림 받기',
              onTap: () => context.push('/alerts/keywords'),
            ),
            const _MaskBodySwitchTile(),
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
              trailing: _appVersionLabel,
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'Eggplant 🍆',
                  applicationVersion: _appVersionLabel,
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
            _MenuTile(
              icon: Icons.delete_forever_outlined,
              title: '계정 영구 삭제 (탈퇴)',
              subtitle: '한 번 사라지면 복구되지 않아요 · 잔여 QTA·추천 보너스 즉시 회수',
              titleColor: EggplantColors.error,
              onTap: () => context.push('/account/delete'),
            ),
            const SizedBox(height: 40),
          ],
        ),
          ),
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

/// 지갑주소(마스킹) + QTA 잔액 + 복사 버튼이 들어간 큰 카드.
/// 사용자에게 "내 지갑주소를 복사해서 닉네임/비밀번호 찾기에 쓰세요" 라는
/// 흐름을 시각적으로 안내한다.
class _QtaWalletCard extends StatefulWidget {
  final String walletAddress;
  const _QtaWalletCard({required this.walletAddress});

  @override
  State<_QtaWalletCard> createState() => _QtaWalletCardState();
}

class _QtaWalletCardState extends State<_QtaWalletCard> {
  bool _revealed = false;

  String get _masked {
    final w = widget.walletAddress;
    if (w.length <= 12) return w;
    return '${w.substring(0, 6)}…${w.substring(w.length - 4)}';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.walletAddress));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('지갑주소를 복사했어요. 닉네임·비밀번호 찾기에 붙여넣을 수 있어요.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qta = context.watch<QtaService>();
    final balance = qta.balance;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF6E3CC4),
              Color(0xFF9559E0),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6E3CC4).withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // QTA 잔액
            Row(
              children: [
                const Text('🍆',
                    style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                const Text(
                  'QTA 잔액',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => context.push('/qta/ledger'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          '내역',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right,
                            size: 16, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatNumber(balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'QTA',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 지갑주소 (마스킹/공개 토글)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _revealed ? widget.walletAddress : _masked,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: _revealed ? '가리기' : '전체 보기',
                    icon: Icon(
                      _revealed
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _revealed = !_revealed),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  IconButton(
                    tooltip: '복사',
                    icon: const Icon(Icons.copy_rounded,
                        color: Colors.white, size: 18),
                    onPressed: _copy,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 출금 신청 버튼 (5,000 QTA 이상)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withOpacity(0.15),
                  side: BorderSide(color: Colors.white.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => context.push('/qta/withdraw'),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  balance >= 5000
                      ? '지갑으로 출금 신청'
                      : '출금하려면 5,000 QTA 이상 필요해요',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '닉네임·비밀번호 분실 시 이 지갑주소로 복구할 수 있어요.\n'
              '5,000 QTA 부터 5,000 단위로 본인 지갑으로 출금할 수 있어요.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 알림 본문 마스킹 토글. SwitchListTile 로 _MenuTile 흐름에 맞춰 보여줌.
/// 켜면 잠금화면/푸시 미리보기에 메시지 본문 대신 '💬 새 메시지가 있어요' 만 노출.
class _MaskBodySwitchTile extends StatefulWidget {
  const _MaskBodySwitchTile();

  @override
  State<_MaskBodySwitchTile> createState() => _MaskBodySwitchTileState();
}

class _MaskBodySwitchTileState extends State<_MaskBodySwitchTile> {
  bool _value = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // NotificationService.init() 이 SharedPreferences 를 읽어 _maskBody 를 채워둠.
    await NotificationService.instance.init();
    if (!mounted) return;
    setState(() {
      _value = NotificationService.instance.isMaskingBody;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: _loaded ? _value : false,
      onChanged: _loaded
          ? (v) async {
              setState(() => _value = v);
              await NotificationService.instance.setMaskBody(v);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(v
                      ? '알림 본문이 가려져요. 잠금화면에서 안전하게 사용하세요 🔒'
                      : '알림 본문이 표시돼요'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          : null,
      activeColor: EggplantColors.primary,
      secondary: const Icon(
        Icons.lock_outline,
        color: EggplantColors.textSecondary,
      ),
      title: const Text(
        '알림 본문 가리기',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text(
        '잠금화면/푸시 미리보기에 메시지 내용 대신 "새 메시지가 있어요" 표시',
        style: TextStyle(fontSize: 12, color: EggplantColors.textSecondary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

String _formatNumber(int n) {
  // 12,345 형태.
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return n < 0 ? '-$buf' : buf.toString();
}

/// 닉네임 옆에 붙는 작은 인증 배지.
class _VerificationBadge extends StatelessWidget {
  final VerificationLevel level;
  const _VerificationBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    if (level == VerificationLevel.none) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('미인증',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280))),
      );
    }
    final isLv2 = level == VerificationLevel.bankAccount;
    final color = isLv2
        ? EggplantColors.primary
        : const Color(0xFF22C55E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 11, color: color),
          const SizedBox(width: 3),
          Text(isLv2 ? 'Lv2' : 'Lv1',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }
}

/// 인증 CTA 카드 — 프로필 헤더 아래, 통계행 위에 노출.
class _VerificationCta extends StatelessWidget {
  final VerificationLevel level;
  const _VerificationCta({required this.level});

  @override
  Widget build(BuildContext context) {
    final isLv0 = level == VerificationLevel.none;
    final title = isLv0 ? '본인 인증하고 거래 시작하기' : '계좌 등록하고 QTA 출금하기';
    final desc = isLv0
        ? '인증해도 채팅·통화는 익명 그대로 유지돼요.'
        : 'QTA 출금을 위해 본인 명의 계좌 등록이 필요합니다.';
    final icon = isLv0
        ? Icons.verified_user_outlined
        : Icons.account_balance_outlined;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/profile/verify'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF5FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEDE9FE)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: EggplantColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    color: EggplantColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: EggplantColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text(desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            color: EggplantColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: EggplantColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 오늘(KST) 둘러보기 채굴 현황 카드.
///
/// - 상품 상세를 10개 이상 조회하면 자동으로 +10 QTA 적립.
/// - 자기 상품·중복 조회는 카운트되지 않음 (백엔드 PK 보장).
/// - 카운트는 KST 자정 기준 매일 0으로 리셋.
class _BrowseMiningCard extends StatelessWidget {
  const _BrowseMiningCard();

  @override
  Widget build(BuildContext context) {
    final qta = context.watch<QtaService>();
    final count = qta.browseCount;
    final threshold = qta.browseThreshold;
    final credited = qta.browseCredited;
    final progress = qta.browseProgress;

    final accent = credited
        ? const Color(0xFF22C55E)
        : EggplantColors.primary;
    final title = credited
        ? '오늘 채굴 보너스 받았어요!'
        : '오늘 둘러보기 채굴';
    final subtitle = credited
        ? '내일 자정(KST)에 다시 시작돼요.'
        : '상품 $threshold개 보면 +10 QTA 적립';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    credited ? Icons.check_circle : Icons.bolt_outlined,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: EggplantColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12,
                              color: EggplantColors.textSecondary)),
                    ],
                  ),
                ),
                Text('$count/$threshold',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: accent)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: const Color(0xFFF3F4F6),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            if (!credited) ...[
              const SizedBox(height: 8),
              Text(
                count == 0
                    ? '홈 탭에서 상품을 둘러보세요 🛍️'
                    : (threshold - count > 0
                        ? '${threshold - count}개 더 보면 +10 QTA!'
                        : '곧 적립돼요…'),
                style: const TextStyle(
                    fontSize: 11.5,
                    color: EggplantColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
