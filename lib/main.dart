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

  final prefs = await SharedPreferences.getInstance();
  final authService = AuthService(prefs);
  await authService.loadFromStorage();

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
        ChangeNotifierProvider(create: (_) => QtaService(authService)),
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
    if (!_chatConnectRequested && auth.isLoggedIn) {
      _chatConnectRequested = true;
      context.read<ChatService>().connect();
      // ignore: unawaited_futures
      context.read<ModerationService>().fetchBlocks();
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
