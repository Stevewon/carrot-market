import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/auth_service.dart';
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
  }

  @override
  Widget build(BuildContext context) {
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
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront_outlined),
            activeIcon: Icon(Icons.storefront),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            activeIcon: Icon(Icons.favorite),
            label: '찜',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: '채팅',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '내 정보',
          ),
        ],
      ),
    );
  }
}
