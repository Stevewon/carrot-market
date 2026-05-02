import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_router.dart';
import 'app/responsive.dart';
import 'app/theme.dart';
import 'services/auth_service.dart';
import 'services/product_service.dart';
import 'services/chat_service.dart';
import 'services/call_service.dart';
import 'services/moderation_service.dart';
import 'services/notification_service.dart';
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

  runApp(EggplantApp(authService: authService));
}

class EggplantApp extends StatelessWidget {
  final AuthService authService;

  const EggplantApp({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
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

class _IncomingCallOverlayState extends State<_IncomingCallOverlay> {
  CallService? _callService;
  CallState _lastState = CallState.idle;
  bool _chatConnectRequested = false;
  StreamSubscription<String>? _notifTapSub;

  @override
  void initState() {
    super.initState();
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
    _callService?.removeListener(_onCallChange);
    _notifTapSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
