import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/cointrip_service.dart';
import '../services/qta_service.dart';
import 'tabs/cointrip_tab.dart';
import 'tabs/feed_tab.dart';
import 'tabs/likes_tab.dart';
import 'tabs/chat_list_tab.dart';
import 'tabs/my_tab.dart';

class HomeShell extends StatefulWidget {
  final int initialTab;
  const HomeShell({super.key, this.initialTab = 0});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
    // Start the chat WS + room list ASAP so the bottom-tab badge is accurate
    // even before the user visits the chat tab. Doing it here (rather than
    // only inside ChatListTab.initState) means a push notification or QR
    // chat invite reaches the user with the badge already updating.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatService>();
      chat.connect();
      chat.fetchRooms(silent: true);

      // QTA 잔액 첫 로드 + 가입/로그인 보너스 안내 스낵바.
      final auth = context.read<AuthService>();
      final qta = context.read<QtaService>();
      // ignore: discarded_futures
      qta.load();
      // 코인트립이 열려 있는 회원에게만 하단 가운데 탭이 생긴다.
      // ignore: discarded_futures
      context.read<CointripService>().loadStatus();
      _showQtaBonusIfAny(auth);
    });
  }

  /// ★ v1.0.111 (이슈 2): '/'?tab=N 으로 재이동 시 GoRouter 가 같은 라우트라
  ///  HomeShell 을 새로 만들지 않을 수 있다. didUpdateWidget 으로 initialTab
  ///  변경을 감지해 _currentIndex 를 동기화 → 찜한 상품 메뉴 → /?tab=1 이
  ///  실제로 찜 탭으로 전환되도록 보장.
  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != _currentIndex) {
      // 다음 프레임에 setState — build 도중 setState 금지.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _currentIndex = widget.initialTab);
      });
    }
  }

  /// 가입/로그인 응답에 포함된 `qta_bonus` 가 있으면 1회 안내 스낵바.
  void _showQtaBonusIfAny(AuthService auth) {
    final bonus = auth.pendingQtaBonus;
    if (bonus == null) return;
    auth.consumeQtaBonus();

    final reason = bonus['reason']?.toString() ?? '';
    String? msg;
    if (reason == 'signup') {
      msg = context.l10n.homeSignupBonus;
    } else if (reason == 'login_daily') {
      final credited = bonus['credited'] == true;
      final amount = (bonus['amount'] as num?)?.toInt() ?? 0;
      final remaining = (bonus['remaining'] as num?)?.toInt() ?? 0;
      if (credited && amount > 0) {
        final tail = remaining > 0
            ? context.l10n.homeLoginBonusRemaining(remaining)
            : context.l10n.homeLoginBonusLimitReached;
        msg = context.l10n.homeLoginBonus(amount, tail);
      }
    }
    if (msg == null || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 버튼(action) 달린 스낵바는 접근성 설정 등에서 안 사라지고 탭마다 따라다닌다.
      // → 버튼 없이 3초 뒤 반드시 닫히게 하고, 알림 자체를 누르면 채굴 내역으로.
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              messenger.hideCurrentSnackBar();
              context.push('/qta/mining');
            },
            child: Text('${msg!}  ›'),
          ),
          backgroundColor: EggplantColors.primary,
          duration: const Duration(seconds: 3),
          persist: false,
        ),
      );
    });
  }

  /// Wraps an icon with the standard 당근식 unread badge.
  Widget _withBadge(Widget icon, int count) {
    if (count <= 0) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -8,
          top: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: EggplantColors.error,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  /// 화면 탭 번호(0 홈 · 1 찜 · 2 채팅 · 3 나의 · 4 코인트립)는 그대로 두고 — /?tab=N 링크가 안 바뀌게 —
  /// 코인트립이 열려 있으면 하단 메뉴에서만 가운데에 끼운다.
  static const int cointripTab = 4;
  List<int> _navOrder(bool cointrip) => cointrip ? const [0, 1, cointripTab, 2, 3] : const [0, 1, 2, 3];

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<ChatService>().totalUnread;
    final cointrip = context.watch<CointripService>().open;
    final order = _navOrder(cointrip);
    // 코인트립이 닫혔는데 그 탭을 보고 있었다면 홈으로.
    final current = order.contains(_currentIndex) ? _currentIndex : 0;

    final tabs = <Widget>[
      const FeedTab(),
      const LikesTab(),
      const ChatListTab(),
      const MyTab(),
      if (cointrip) CointripTab(active: current == cointripTab) else const SizedBox.shrink(),
    ];

    final items = <int, BottomNavigationBarItem>{
      0: BottomNavigationBarItem(
        icon: const Icon(Icons.storefront_outlined),
        activeIcon: const Icon(Icons.storefront),
        label: context.l10n.homeTabHome,
      ),
      1: BottomNavigationBarItem(
        icon: const Icon(Icons.favorite_border),
        activeIcon: const Icon(Icons.favorite),
        label: context.l10n.homeTabLikes,
      ),
      2: BottomNavigationBarItem(
        icon: _withBadge(const Icon(Icons.chat_bubble_outline), unread),
        activeIcon: _withBadge(const Icon(Icons.chat_bubble), unread),
        label: context.l10n.homeTabChat,
      ),
      3: BottomNavigationBarItem(
        icon: const Icon(Icons.person_outline),
        activeIcon: const Icon(Icons.person),
        label: context.l10n.homeTabMy,
      ),
      cointripTab: BottomNavigationBarItem(
        icon: const Icon(Icons.toll_outlined),
        activeIcon: const Icon(Icons.toll),
        label: context.l10n.ctTab,
      ),
    };

    return Scaffold(
      body: IndexedStack(index: current, children: tabs),
      floatingActionButton: current == 0
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/product/new'),
              backgroundColor: EggplantColors.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              icon: const Icon(Icons.edit_outlined, size: 20),
              label: Text(
                context.l10n.homeWrite,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: order.indexOf(current),
        onTap: (pos) {
          final i = order[pos];
          // 탭을 옮기면 떠 있던 안내 알림은 닫는다 (페이지마다 따라다니지 않게).
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          setState(() => _currentIndex = i);
        },
        selectedItemColor: EggplantColors.primary,
        unselectedItemColor: EggplantColors.textTertiary,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        iconSize: 24,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        items: [for (final i in order) items[i]!],
      ),
    );
  }
}
