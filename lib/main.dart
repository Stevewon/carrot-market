import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_router.dart';
import 'app/responsive.dart';
import 'app/theme.dart';
import 'services/agora_service.dart';
import 'services/auth_service.dart';
import 'services/product_service.dart';
import 'services/chat_service.dart';
import 'services/call_service.dart';
import 'services/moderation_service.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
import 'services/search_history_service.dart';
import 'services/keyword_alert_service.dart';
import 'services/hidden_products_service.dart';
import 'services/qta_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // ── 부팅 단계 절대 데드라인 ────────────────────────────────────
  // SharedPreferences / AuthService.loadFromStorage 가 어떤 이유로 멈춰도
  // runApp() 은 무조건 호출되도록 한다. 화면이 영원히 안 뜨는 사태 차단.
  late SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance()
        .timeout(const Duration(seconds: 3));
  } catch (_) {
    // 극단적 케이스 (기기 저장소 손상 등) — 빈 prefs 로라도 앱을 띄운다.
    prefs = await SharedPreferences.getInstance();
  }

  final authService = AuthService(prefs);

  // loadFromStorage 는 더 이상 await 하지 않는다.
  // - 내부에 /api/auth/me 5초 타임아웃이 있긴 하지만,
  //   네트워크가 늦으면 runApp() 까지 영향이 갈 수 있어 fire-and-forget.
  // - SplashScreen._decide() 에 6초 절대 데드라인이 있어서, 그 안에 검증
  //   결과가 안 들어와도 자동으로 다음 화면으로 넘어간다.
  // ignore: unawaited_futures
  authService.loadFromStorage();

  // Init local notifications (system-tray push for chat messages).
  // ignore: unawaited_futures
  NotificationService.instance.init();

  // ★★★ 3차 푸시 — FCM + CallKit (placeholder 모드).
  // Firebase 미초기화 / 토큰 발급 실패 시 silent fallback (앱 실행에는 영향 없음).
  final pushService = PushService(auth: authService);
  // ignore: unawaited_futures
  pushService.init();

  runApp(EggplantApp(authService: authService, pushService: pushService));
}

class EggplantApp extends StatelessWidget {
  final AuthService authService;
  final PushService pushService;

  const EggplantApp({
    super.key,
    required this.authService,
    required this.pushService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        // ★ 3차 푸시 — FCM 토큰 등록 + CallKit 수신 이벤트 라우팅.
        // Firebase 미초기화 시에도 silent fallback (placeholder 모드).
        ChangeNotifierProvider<PushService>.value(value: pushService),
        // Agora 1차: 토큰 발급/UID 캐싱 + 자동 갱신 타이머.
        // AuthService.attachAgora 로 로그인/로그아웃 훅에 자동 연결한다.
        // 실제 RTM/RTC 연결은 2차/3차에서 추가.
        ChangeNotifierProvider<AgoraService>(
          create: (_) {
            final agora = AgoraService();
            authService.attachAgora(agora);
            // 앱 시작 시 이미 로그인된 상태(자동 로그인)면 즉시 prepare.
            final wallet = authService.user?.walletAddress;
            if (wallet != null && wallet.isNotEmpty) {
              // ignore: discarded_futures
              agora.prepare(walletAddress: wallet);
            }
            return agora;
          },
        ),
        ChangeNotifierProvider(create: (_) => ProductService(authService)),
        ChangeNotifierProvider(create: (_) => ChatService(authService)),
        ChangeNotifierProvider(create: (_) => ModerationService(authService)),
        ChangeNotifierProvider(
          create: (_) => SearchHistoryService(authService.prefs),
        ),
        ChangeNotifierProvider(create: (_) => KeywordAlertService(authService)),
        ChangeNotifierProvider(create: (_) => HiddenProductsService(authService)),
        // QtaService 생성 후 ProductService 의 mining 콜백을 연결.
        // 상품 상세 응답에 들어온 mining 진행도가 자동으로 QtaService 로 흘러간다.
        ChangeNotifierProxyProvider<ProductService, QtaService>(
          create: (_) => QtaService(authService),
          update: (ctx, productSvc, previous) {
            final qta = previous ?? QtaService(authService);
            productSvc.setMiningUpdateCallback(qta.applyBrowseMiningFromDetail);
            return qta;
          },
        ),
        ChangeNotifierProxyProvider<ChatService, CallService>(
          create: (ctx) => CallService(
            auth: authService,
            chat: ctx.read<ChatService>(),
          ),
          update: (ctx, chat, previous) =>
              previous ?? CallService(auth: authService, chat: chat),
        ),
      ],
      child: Consumer<AuthService>(
        builder: (context, auth, _) {
          final router = createRouter(auth);
          return MaterialApp.router(
            title: 'Eggplant 🍆',
            debugShowCheckedModeBanner: false,
            theme: eggplantTheme,
            routerConfig: router,
            builder: (context, child) {
              // Global wrappers (apply in nesting order, from outside-in):
              //   1. TextScaleClamper - 시스템 글자 크기를 1.3배까지만 허용
              //                         (접근성 모드에서 UI 깨짐 방지)
              //   2. KeyboardDismissOnTap - 빈 영역 탭하면 키보드 닫기 (모든 입력 화면 자동 적용)
              //   3. _IncomingCallOverlay - 어떤 화면에서든 통화 수신을 가로채기
              return TextScaleClamper(
                child: KeyboardDismissOnTap(
                  child: _IncomingCallOverlay(
                    router: router,
                    child: child ?? const SizedBox(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Listens to CallService and navigates to /call when an incoming call arrives,
/// no matter what screen the user is on.
class _IncomingCallOverlay extends StatefulWidget {
  final Widget child;
  final GoRouter router;
  const _IncomingCallOverlay({required this.child, required this.router});

  @override
  State<_IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<_IncomingCallOverlay>
    with WidgetsBindingObserver {
  CallService? _callService;
  CallState _lastState = CallState.idle;
  bool _chatConnectRequested = false;
  bool _coldStartHandled = false;
  // ★ 당근식 자동 진입: 부팅 후 1회만 (UX — 사용자가 의도적으로 다른 화면
  //   보고 있는데 또 빼앗아 가면 안 됨).
  bool _autoEnterUnreadDone = false;
  StreamSubscription<String>? _notifTapSub;
  StreamSubscription<Map<String, dynamic>>? _callkitAcceptSub;
  StreamSubscription<Map<String, dynamic>>? _msgOpenedSub;
  StreamSubscription<Map<String, dynamic>>? _msgReceivedSub;

  @override
  void initState() {
    super.initState();
    // 앱 라이프사이클(백그라운드 ↔ 포어그라운드) 감지를 위해 observer 등록.
    // 웜 스타트(resumed) 시 미읽음 채팅방 자동 진입 트리거.
    WidgetsBinding.instance.addObserver(this);

    // When a chat / keyword notification is tapped, deep-link to the right screen.
    // payload 형식:
    //   - 채팅 메시지   → roomId 그대로
    //   - 키워드 알림   → 'product:<productId>'
    _notifTapSub = NotificationService.instance.onTap.listen((payload) {
      if (payload.isEmpty) return;
      try {
        if (payload.startsWith('product:')) {
          final productId = payload.substring('product:'.length);
          if (productId.isNotEmpty) {
            widget.router.push('/product/$productId');
          }
        } else {
          widget.router.push('/chat/$payload');
        }
      } catch (e) {
        debugPrint('[notif] router push failed: $e');
      }
    });
  }

  /// ★ 5차 푸시 보강 — 당근마켓 동등 자동 진입 로직.
  ///   트리거: 콜드 스타트 (FCM getInitialMessage 가 null = 노티 탭 아닌 경우)
  ///         + 웜 스타트 (AppLifecycleState.resumed)
  ///   분기: 미읽음 방 0개 → 라우팅 안 함
  ///         미읽음 방 1개 → /chat/<roomId> 자동 진입
  ///         미읽음 방 2+개 → /?tab=2 (채팅 목록 탭)
  ///   제외: 이미 채팅방/목록/통화 화면 보고 있으면 자동 라우팅 안 함
  ///   1회 제한: _autoEnterUnreadDone 플래그로 부팅 후 1회만.
  void _maybeAutoEnterUnreadRoom() {
    if (_autoEnterUnreadDone) return;
    if (!mounted) return;
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;

    // 현재 보고 있는 화면 검사 — 의도적인 사용자 흐름 깨지 않게.
    final currentPath = widget.router
        .routerDelegate.currentConfiguration.uri.toString();
    final isOnChatScreen = currentPath.startsWith('/chat/');
    final isOnChatList =
        currentPath == '/' || currentPath.startsWith('/?tab=2');
    final isOnCall = currentPath.startsWith('/call');
    if (isOnChatScreen || isOnCall) return;

    final chat = context.read<ChatService>();
    final unreadRooms =
        chat.rooms.where((r) => r.unreadCount > 0).toList();
    if (unreadRooms.isEmpty) return;

    // 한 세션에서 1회만 발동.
    _autoEnterUnreadDone = true;

    try {
      if (unreadRooms.length == 1) {
        // 미읽음 방 1개 → 그 방으로 직진 (당근식).
        final r = unreadRooms.first;
        widget.router.push('/chat/${r.id}');
      } else {
        // 미읽음 방 2개 이상 → 채팅 목록 탭으로 진입.
        // 이미 홈에 있는데 다른 탭 보고 있으면 채팅 탭으로 바꿔준다.
        if (isOnChatList) {
          // 홈 루트에 있으면 탭만 바꿔서 push.
          widget.router.go('/?tab=2');
        } else {
          widget.router.go('/?tab=2');
        }
      }
    } catch (e) {
      debugPrint('[auto-enter] router push failed: $e');
    }
  }

  /// CallKit (백그라운드/앱종료 상태에서 수신한) 받기 버튼 → 통화 화면으로 라우팅.
  /// PushService.onCallAccepted 가 call_id, from_user_id 를 흘려준다.
  void _attachCallkitAccept(BuildContext ctx) {
    if (_callkitAcceptSub != null) return;
    final push = ctx.read<PushService>();
    _callkitAcceptSub = push.onCallAccepted.listen((data) {
      final fromUserId = data['from_user_id']?.toString() ?? '';
      if (fromUserId.isEmpty) return;
      // 익명: 닉네임은 서버에서 다시 받아오므로 placeholder.
      final peer = Uri.encodeComponent('익명');
      try {
        widget.router.push(
            '/call?peerId=$fromUserId&peer=$peer&incoming=1&fromPush=1');
      } catch (e) {
        debugPrint('[callkit] router push failed: $e');
      }
    });
  }

  /// ★ 7차 푸시 (이슈 3): foreground FCM 메시지 수신 → ChatService 합성 방 추가.
  ///   PushService.onMessageReceived 가 room_id/sender 정보를 흘려준다.
  ///   라우팅은 안 함 (사용자가 다른 화면 보는 중일 수 있음). 메인탭 채팅 뱃지 +
  ///   런처 아이콘 뱃지 + 채팅 목록 즉시 갱신용.
  void _attachMessageReceived(BuildContext ctx) {
    if (_msgReceivedSub != null) return;
    final push = ctx.read<PushService>();
    _msgReceivedSub = push.onMessageReceived.listen((data) {
      final roomId = data['room_id']?.toString() ?? '';
      if (roomId.isEmpty) return;
      try {
        final chat = ctx.read<ChatService>();
        chat.applyIncomingPushMessage(
          roomId: roomId,
          senderId: data['sender_id']?.toString(),
          senderNickname: data['sender_nickname']?.toString(),
          text: data['text']?.toString(),
        );
      } catch (e) {
        debugPrint('[push-msg-recv] applyIncomingPushMessage failed: $e');
      }
    });
  }

  /// ★ 5차 푸시: FCM 메시지 알림 tap → 채팅방 자동 라우팅.
  ///   PushService.onMessageOpened 가 room_id 를 흘려준다.
  ///   백그라운드 + 콜드 스타트(getInitialMessage) 모두 같은 Stream 으로 들어온다.
  void _attachMessageOpened(BuildContext ctx) {
    if (_msgOpenedSub != null) return;
    final push = ctx.read<PushService>();
    _msgOpenedSub = push.onMessageOpened.listen((data) {
      final roomId = data['room_id']?.toString() ?? '';
      if (roomId.isEmpty) return;
      // ★ 7차 푸시 (이슈 3): 알림 탭 → 채팅방 진입 직전,
      //  WS 가 끊긴 상태였더라도 ChatService 에 합성 방을 즉시 추가.
      //  사용자가 바탕화면 아이콘으로 켜는 경우(자동 라우팅 X) 에도
      //  메인탭 뱃지/채팅 목록에 반영되도록 동일 로직을 _handleForeground 에서도 호출.
      try {
        final chat = ctx.read<ChatService>();
        chat.applyIncomingPushMessage(
          roomId: roomId,
          senderId: data['sender_id']?.toString(),
          senderNickname: data['sender_nickname']?.toString(),
          text: data['text']?.toString(),
        );
      } catch (e) {
        debugPrint('[push-msg] applyIncomingPushMessage failed: $e');
      }
      // 익명 정책: 닉네임은 ChatScreen 진입 후 서버에서 재조회.
      try {
        widget.router.push('/chat/$roomId');
      } catch (e) {
        debugPrint('[push-msg] router push failed: $e');
      }
    });

    // 콜드 스타트 — 앱 종료 상태에서 알림 tap 으로 부팅된 경우, listener 가
    // attach 된 다음 프레임에 한 번 호출하면 getInitialMessage() 가 깨운다.
    // 노티 탭이 아니라 일반 부팅이면 _autoEnterUnreadDone 플래그가 false 이므로
    // 잠깐 기다렸다가(초기 ChatService.connect 후 rooms 로딩 시간) 미읽음 방
    // 자동 진입 로직 시도.
    if (!_coldStartHandled) {
      _coldStartHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // ignore: discarded_futures
        push.handleColdStartFromNotification();
        // 노티 탭이면 _handleOpenedFromPush 가 먼저 /chat/<roomId> 로 push 해서
        // _autoEnterUnreadDone 가 true 가 되거나 isOnChatScreen 체크에서 걸러진다.
        // 일반 부팅이면 ChatService.rooms 가 채워질 때까지 ~1.5초 대기 후 시도.
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          _maybeAutoEnterUnreadRoom();
        });
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // ★ 웜 스타트 — 앱이 백그라운드에서 포어그라운드로 복귀할 때.
    //  당근식 자동 진입: 미읽음 방 1개면 직진, 2+개면 채팅 목록 탭.
    //  부팅 후 1회 제한(_autoEnterUnreadDone)이 false 일 때만 실행.
    if (state == AppLifecycleState.resumed) {
      // ChatService 가 백그라운드 동안 끊긴 WebSocket 을 재연결하고
      // rooms unread 카운트를 갱신할 시간을 약간 준다.
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        _maybeAutoEnterUnreadRoom();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final call = context.read<CallService>();
    final auth = context.read<AuthService>();

    // Trigger chat connection once logged in so socket is ready
    // to receive incoming call signals. We also warm the block cache
    // here so feed / chat filtering works before the user navigates.
    //
    // [FIX] didChangeDependencies는 자식 push 시에도 재호출되므로,
    // 메인 isolate를 점유하지 않도록 다음 프레임 + microtask로 양보한다.
    // 이전엔 첫 상세 진입 시 ChatService.connect() + fetchBlocks()가
    // 동기적으로 발사돼 ProductDetailScreen._load()의 await가 hang됐다.
    if (!_chatConnectRequested && auth.isLoggedIn) {
      _chatConnectRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.microtask(() {
          if (!mounted) return;
          context.read<ChatService>().connect();
          // ignore: unawaited_futures
          context.read<ModerationService>().fetchBlocks();
        });
      });
    }

    if (_callService != call) {
      _callService?.removeListener(_onCallChange);
      _callService = call;
      _callService!.addListener(_onCallChange);
    }

    // CallKit accept 이벤트 → /call 라우팅 (한 번만 attach).
    _attachCallkitAccept(context);

    // ★ 5차 푸시: FCM 메시지 알림 tap → /chat/<roomId> 라우팅 (한 번만 attach).
    //   콜드 스타트 처리도 이 안에서 1회만 호출됨.
    _attachMessageOpened(context);

    // ★ 7차 푸시 (이슈 3): foreground FCM 'message' 수신 → ChatService 합성 방
    //   추가 (라우팅 X). 메인탭 뱃지/런처 뱃지/채팅 목록 즉시 갱신용.
    _attachMessageReceived(context);
  }

  void _onCallChange() {
    final call = _callService;
    if (call == null) return;
    final s = call.state;
    if (s == CallState.incoming && _lastState != CallState.incoming) {
      // Navigate to the call screen in "incoming" mode
      final peerId = call.peerUserId ?? '';
      final peer = Uri.encodeComponent(call.peerNickname ?? '익명');
      widget.router.push('/call?peerId=$peerId&peer=$peer&incoming=1');
    }
    _lastState = s;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callService?.removeListener(_onCallChange);
    _notifTapSub?.cancel();
    _callkitAcceptSub?.cancel();
    _msgOpenedSub?.cancel();
    _msgReceivedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
