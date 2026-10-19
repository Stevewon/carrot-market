import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'l10n.dart';
import '../services/auth_service.dart';
import '../screens/splash_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/find_account_screen.dart';
import '../screens/home_shell.dart';
import '../screens/my_products_screen.dart';
import '../screens/my_purchases_screen.dart';
import '../screens/product_edit_screen.dart';
import '../screens/product_detail_screen.dart';
import '../screens/product_create_screen.dart';
import '../screens/qr_screen.dart';
import '../screens/qr_scan_screen.dart';
import '../screens/peer_link_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/call_screen.dart';
import '../screens/region_select_screen.dart';
import '../screens/user_profile_screen.dart';
import '../screens/keyword_alerts_screen.dart';
import '../screens/hidden_products_screen.dart';
import '../screens/qta_ledger_screen.dart';
import '../screens/qta_mining_screen.dart';
import '../screens/qta_withdraw_screen.dart';
import '../screens/referrals_screen.dart';
import '../screens/account_delete_screen.dart';
import '../screens/profile_verify_screen.dart';
import '../screens/profile_edit_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/recent_viewed_screen.dart';
import '../screens/cointrip_wallet_screen.dart';
import '../screens/cointrip_ext_wallet_screen.dart';
import '../screens/cointrip_union_screen.dart';
import '../screens/cointrip_union_chat_screen.dart';

GoRouter createRouter(AuthService auth) {
  return GoRouter(
    // 처음부터 로그인 상태에 맞는 화면으로 바로 보낸다.
    // (splash 위젯의 비동기 로직에 의존하지 않음 — 무한 splash 차단)
    initialLocation: auth.isLoggedIn ? '/' : '/onboarding',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isLoggedIn;
      final path = state.matchedLocation;
      final onAuthPages = path == '/login' ||
          path == '/onboarding' ||
          path == '/register' ||
          path == '/find';

      // splash 경로는 더 이상 안 쓴다. 들어와도 즉시 알맞은 화면으로 redirect.
      if (path == '/splash') {
        return loggedIn ? '/' : '/onboarding';
      }
      if (!loggedIn && !onAuthPages) return '/onboarding';
      if (loggedIn && onAuthPages) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      // 친구 초대 링크 (eggplant://app/register?ref=<닉네임>) → 추천인 칸이 채워진다.
      GoRoute(
        path: '/register',
        builder: (_, state) => RegisterScreen(referrer: state.uri.queryParameters['ref']),
      ),
      GoRoute(path: '/find', builder: (_, __) => const FindAccountScreen()),
      GoRoute(
        path: '/',
        builder: (_, state) => HomeShell(
          initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0,
        ),
      ),
      GoRoute(
        path: '/product/new',
        builder: (_, __) => const ProductCreateScreen(),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (_, state) => ProductDetailScreen(
          productId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/product/:id/edit',
        builder: (_, state) => ProductEditScreen(
          productId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/my/products',
        builder: (_, __) => const MyProductsScreen(),
      ),
      GoRoute(
        path: '/my/purchases',
        builder: (_, __) => const MyPurchasesScreen(),
      ),
      GoRoute(path: '/qr', builder: (_, __) => const QrScreen()),
      GoRoute(path: '/qr/scan', builder: (_, __) => const QrScanScreen()),
      // 내 QR 링크 (eggplant://app/u/<id>?n=<닉네임>) → 그 회원과 익명 채팅
      GoRoute(
        path: '/u/:id',
        builder: (_, state) => PeerLinkScreen(
          userId: state.pathParameters['id']!,
          nickname: state.uri.queryParameters['n'] ?? '',
        ),
      ),
      GoRoute(
        path: '/chat/:roomId',
        builder: (_, state) => ChatScreen(
          roomId: state.pathParameters['roomId']!,
          peerNickname: state.uri.queryParameters['peer'] ?? L10n.current.homeAnonymous,
          productTitle: state.uri.queryParameters['product'],
          peerUserId: state.uri.queryParameters['peerId'],
          productId: state.uri.queryParameters['productId'],
        ),
      ),
      GoRoute(
        path: '/region',
        builder: (_, __) => const RegionSelectScreen(),
      ),
      GoRoute(
        path: '/user/:id',
        builder: (_, state) => UserProfileScreen(
          userId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/call',
        builder: (_, state) => CallScreen(
          peerUserId: state.uri.queryParameters['peerId'] ?? '',
          peerNickname: state.uri.queryParameters['peer'] ?? L10n.current.homeAnonymous,
          // ★ Agora 채널명 산정에 양쪽 지갑주소가 필요 (sorted pair).
          //  발신자: 상대방 프로필 → /call?peerWallet=0x... 로 전달.
          //  수신자: incoming=1 일 때는 CallService 가 이미 시그널링 페이로드에서
          //          caller_wallet 을 _peerWalletAddress 로 들고 있어 비어 있어도 OK.
          //  ★ v1.0.136: fromPush=1 (CallKit accept) 케이스에서는 push 데이터로
          //   peerWallet 이 들어와야 acceptCall 의 _joinAgoraChannel 이 채널명
          //   산정 가능. main.dart 의 _attachCallkitAccept 가 동봉해 보냄.
          peerWalletAddress: state.uri.queryParameters['peerWallet'] ?? '',
          startImmediately: state.uri.queryParameters['incoming'] != '1',
          // ★ v1.0.136: CallKit 에서 사장님이 이미 "받기"를 누른 상태로 진입한 경우
          //   CallScreen 이 자동으로 acceptCall 호출. 사용자가 다시 "수락" 버튼
          //   누를 필요 없음. 사용자 흐름 단축 + 즉시 음성 연결.
          fromPush: state.uri.queryParameters['fromPush'] == '1',
        ),
      ),
      GoRoute(
        path: '/alerts/keywords',
        builder: (_, __) => const KeywordAlertsScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/recent',
        builder: (_, __) => const RecentViewedScreen(),
      ),
      GoRoute(
        path: '/cointrip/wallet',
        builder: (_, __) => const CointripWalletScreen(),
      ),
      GoRoute(
        path: '/cointrip/ext-wallet',
        builder: (_, __) => const CointripExtWalletScreen(),
      ),
      GoRoute(
        path: '/cointrip/sol-wallet',
        builder: (_, __) => const CointripExtWalletScreen(solana: true),
      ),
      GoRoute(
        path: '/cointrip/union',
        // 연합 초대 링크 (eggplant://app/cointrip/union?code=<코드>) → 코드가 채워진다.
        builder: (_, state) => CointripUnionScreen(code: state.uri.queryParameters['code']),
      ),
      GoRoute(
        path: '/cointrip/union/chat',
        builder: (_, __) => const CointripUnionChatScreen(),
      ),
      GoRoute(
        path: '/hidden',
        builder: (_, __) => const HiddenProductsScreen(),
      ),
      GoRoute(
        path: '/qta/ledger',
        builder: (_, __) => const QtaLedgerScreen(),
      ),
      GoRoute(
        path: '/qta/mining',
        builder: (_, __) => const QtaMiningScreen(),
      ),
      GoRoute(
        path: '/qta/withdraw',
        builder: (_, __) => const QtaWithdrawScreen(),
      ),
      GoRoute(
        path: '/referrals',
        builder: (_, __) => const ReferralsScreen(),
      ),
      GoRoute(
        path: '/account/delete',
        builder: (_, __) => const AccountDeleteScreen(),
      ),
      GoRoute(
        path: '/profile/verify',
        builder: (_, __) => const ProfileVerifyScreen(),
      ),
      // ★ v1.0.112: 프로필 등록 / 닉네임 수정.
      GoRoute(
        path: '/profile/edit',
        builder: (_, __) => const ProfileEditScreen(),
      ),
    ],
    // 모르는 링크 (예: 예전 QR 링크 eggplant://<id>/<닉네임>) — 오류 문장 대신 안내 + 홈으로.
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.homeLinkBroken,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.45)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.go('/'), child: Text(context.l10n.homeGoHome)),
            ],
          ),
        ),
      ),
    ),
  );
}
