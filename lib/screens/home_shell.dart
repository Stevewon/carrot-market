import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/qta_service.dart';
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
      _showQtaBonusIfAny(auth);
    });
  }

  /// 가입/로그인 응답에 포함된 `qta_bonus` 가 있으면 1회 안내 스낵바.
  void _showQtaBonusIfAny(AuthService auth) {
    final bonus = auth.pendingQtaBonus;
    if (bonus == null) return;
    auth.consumeQtaBonus();

    final reason = bonus['reason']?.toString() ?? '';
    String? msg;
    if (reason == 'signup') {
      msg = '🎉 가입을 환영해요! +500 QTA 가 지급됐어요';
    } else if (reason == 'login_daily') {
      final credited = bonus['credited'] == true;
      final amount = (bonus['amount'] as num?)?.toInt() ?? 0;
      final remaining = (bonus['remaining'] as num?)?.toInt() ?? 0;
      if (credited && amount > 0) {
        final tail = remaining > 0 ? ' · 오늘 ${remaining}회 더 받을 수 있어요' : ' · 오늘 한도 끝!';
        msg = '📅 출석 보너스 +$amount QTA$tail';
      }
    }
    if (msg == null || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg!),
          backgroundColor: EggplantColors.primary,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: '내역',
            textColor: Colors.white,
            onPressed: () => context.push('/qta/ledger'),
          ),
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
  Widget build(BuildContext context) {
    final unread = context.watch<ChatService>().totalUnread;

    final tabs = <Widget>[
      const FeedTab(),
      const LikesTab(),
      const ChatListTab(),
      const MyTab(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: tabs),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/product/new'),
              backgroundColor: EggplantColors.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              icon: const Icon(Icons.edit_outlined, size: 20),
              label: const Text(
                '글쓰기',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
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
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.storefront_outlined),
            activeIcon: Icon(Icons.storefront),
            label: '홈',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            activeIcon: Icon(Icons.favorite),
            label: '찜',
          ),
          BottomNavigationBarItem(
            icon: _withBadge(const Icon(Icons.chat_bubble_outline), unread),
            activeIcon: _withBadge(const Icon(Icons.chat_bubble), unread),
            label: '채팅',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '내 정보',
          ),
        ],
      ),
    );
  }
}
