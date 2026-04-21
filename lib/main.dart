import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_router.dart';
import 'app/theme.dart';
import 'services/auth_service.dart';
import 'services/product_service.dart';
import 'services/chat_service.dart';
import 'services/call_service.dart';

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
              // Global incoming-call overlay
              return _IncomingCallOverlay(
                router: router,
                child: child ?? const SizedBox(),
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final call = context.read<CallService>();
    final auth = context.read<AuthService>();

    // Trigger chat connection once logged in so socket is ready
    // to receive incoming call signals.
    if (!_chatConnectRequested && auth.isLoggedIn) {
      _chatConnectRequested = true;
      context.read<ChatService>().connect();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
