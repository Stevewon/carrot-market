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
            // ★ v1.0.149 (2026-05-10): AgoraService 에 AuthService.api 주입 필수.
            //   이전 코드 `AgoraService()` 는 새 ApiClient 인스턴스를 자체 생성해
            //   AuthService.api.setToken() 으로 박힌 JWT 가 도달하지 않음 →
            //   `/api/users/agora/token` 요청 시 Authorization 헤더 비어
            //   서버 authMiddleware 가 401 'Unauthorized' 반환 → joinChannel(null)
            //   → Agora error 110 (ERR_INVALID_TOKEN). 사장님 v1.0.148 토스트로 확정.
            //   `api: authService.api` 로 같은 dio 인스턴스 공유하면 JWT 자동 반영.
            final agora = AgoraService(api: authService.api);
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
        // CallService 는 ChatService(WebSocket 시그널링) + AgoraService(미디어 토큰)
        // 두 의존성을 모두 필요로 하므로 ProxyProvider2 로 묶는다.
        // - chat: call_invite/response/cancel/end 시그널 전달
        // - agora: 채널명 생성 + RTC 토큰 발급 (HMAC-SHA256 v006)
        ChangeNotifierProxyProvider2<ChatService, AgoraService, CallService>(
          create: (ctx) {
            final call = CallService(
              auth: authService,
              chat: ctx.read<ChatService>(),
              agora: ctx.read<AgoraService>(),
            );
            // ★ P1-#11 (v1.0.127): 로그아웃 시 진행 중인 통화 자동 정리.
            authService.attachCallSink(() => call.resetOnBoot());
            return call;
          },
          update: (ctx, chat, agora, previous) =>
              previous ??
              CallService(auth: authService, chat: chat, agora: agora),
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
  // ★ v1.0.126: 앱 부팅 직후 stuck CallKit/상태 강제 정리 1회 플래그.
  bool _callBootResetDone = false;
  // ★ 당근식 자동 진입: 부팅 후 1회만 (UX — 사용자가 의도적으로 다른 화면
  //   보고 있는데 또 빼앗아 가면 안 됨).
  bool _autoEnterUnreadDone = false;
  StreamSubscription<String>? _notifTapSub;
  StreamSubscription<Map<String, dynamic>>? _callkitAcceptSub;
  StreamSubscription<Map<String, dynamic>>? _msgOpenedSub;
  StreamSubscription<Map<String, dynamic>>? _msgReceivedSub;
  // ★ v1.0.150 (2026-05-10): Native NativeIncomingCallActivity 의 받기/거절 →
  //   MainActivity 가 invokeMethod 로 깨우는 채널. 한 번만 setMethodCallHandler.
  bool _nativeCallBridgeAttached = false;
  static const MethodChannel _nativeCallBridge =
      MethodChannel('eggplant.market/native_call_bridge');

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
  ///
  ///   ★ v1.0.108 (사장님 직역 정책 — 이중 분기):
  ///   • 바탕화면 아이콘 뱃지 있음(unread > 0) → 푸시 알림 탭처럼 채팅방 직진.
  ///   • 바탕화면 아이콘 뱃지 없음(unread == 0) → 메인 페이지(피드) 그대로 둠.
  ///   FCM/WS 동기화 누락 대비: rooms 가 비어 있어도 SharedPreferences pending
  ///   큐 잔존분으로 한 번 더 시도. 그래도 0 이면 메인 유지.
  void _maybeAutoEnterUnreadRoom() {
    if (_autoEnterUnreadDone) return;
    if (!mounted) return;
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;

    // 현재 보고 있는 화면 검사 — 의도적인 사용자 흐름 깨지 않게.
    final currentPath = widget.router
        .routerDelegate.currentConfiguration.uri.toString();
    final isOnChatScreen = currentPath.startsWith('/chat/');
    final isOnCall = currentPath.startsWith('/call');
    if (isOnChatScreen || isOnCall) return;

    final chat = context.read<ChatService>();
    final unreadRooms =
        chat.rooms.where((r) => r.unreadCount > 0).toList();

    // ★ 뱃지 없음 → 메인 페이지(피드)로 보냄. 강제 라우팅은 하지 않고
    //  현재 화면 유지(앱이 처음 켜졌으면 GoRouter 의 initialLocation '/' 그대로).
    if (unreadRooms.isEmpty) {
      _autoEnterUnreadDone = true; // 한 번 평가했으면 세션 1회 제한 유지.
      return;
    }

    // 한 세션에서 1회만 발동.
    _autoEnterUnreadDone = true;

    // ★ 뱃지 있음 → 무조건 가장 최근 메시지 받은 방으로 직진.
    //  ChatService 의 rooms 는 이미 lastMessageAt desc 로 정렬돼 있음.
    try {
      unreadRooms.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      final r = unreadRooms.first;
      widget.router.push('/chat/${r.id}');
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
      // ★ v1.0.136: caller_wallet / caller_nickname 도 라우터에 동봉.
      //   fromPush=1 일 때 CallScreen 이 startCall 대신 acceptCall 을 호출해
      //   "수락"이 이미 CallKit 에서 눌린 상태임을 인지하도록 함.
      //   wallet 누락 시 acceptCall 의 _joinAgoraChannel 이 즉시 teardown 되어
      //   사장님이 본 "수락 누르자마자 꺼져버림" 증상 발생 → wallet 반드시 전달.
      final callId = data['call_id']?.toString() ?? '';
      final callerWallet = data['caller_wallet']?.toString() ?? '';
      final nickRaw = data['caller_nickname']?.toString().trim() ?? '';
      final nick = nickRaw.isEmpty ? '익명' : nickRaw;
      final peerEncoded = Uri.encodeComponent(nick);
      final walletEncoded = Uri.encodeComponent(callerWallet);

      // ★ v1.0.137 (2026-05-08): 라우터 push 직전에 CallService 의 incoming
      //   상태를 푸시 데이터로 직접 부트스트랩.
      //   v1.0.136 의 사장님 보고 증상 ("수락 → 메인 화면 진입 → 발신자 거절"):
      //   백그라운드/앱 종료 상태에서 깨워진 경우 chat.on('call_incoming') 이
      //   안 와서 _activeCallId 등이 비어 있고, CallScreen 이 5초 대기 후
      //   acceptCall 호출해도 line 358 가드에 막혀 silent return 되던 버그.
      //   여기서 미리 bootstrapIncomingFromPush 로 incoming 진입 → 라우터 push
      //   → CallScreen 의 fromPush 분기가 즉시 acceptCall 정상 진행.
      try {
        final call = ctx.read<CallService>();
        call.bootstrapIncomingFromPush(
          callId: callId,
          peerUserId: fromUserId,
          peerNickname: nick,
          peerWalletAddress: callerWallet,
        );
      } catch (e) {
        debugPrint('[callkit] bootstrap incoming failed: $e');
      }

      try {
        widget.router.push(
            '/call?peerId=$fromUserId&peer=$peerEncoded&peerWallet=$walletEncoded&incoming=1&fromPush=1');
      } catch (e) {
        debugPrint('[callkit] router push failed: $e');
      }
    });
  }

  /// ★ v1.0.150 (2026-05-10): Native (NativeIncomingCallActivity) 의 받기/거절/종료
  ///   버튼 → MainActivity.handleNativeCallIntent() → MethodChannel 로 invoke.
  ///   여기서 setMethodCallHandler 등록 1회만.
  ///
  ///   v1.0.149 까지 root cause:
  ///     1) NativeIncomingCallActivity.onAnswerClicked() 가 MainActivity 를
  ///        깨우지 않아 Flutter 가 "받음" 사실을 영영 알 수 없었음.
  ///     2) Flutter 측 setMethodCallHandler 0건. 채널은 auth_service.dart 에
  ///        선언만 돼 있고 invokeMethod (Dart→Native) 만 사용.
  ///   → 양쪽 폰 "연결 중" 무한 + 발신측 ringback 안 끊김 (chat.emit('call_response')
  ///     자체가 안 일어남).
  ///
  ///   v1.0.150 fix:
  ///     - Native onAnswerClicked() 에 MainActivity wake Intent 추가 (.kt 수정 완료)
  ///     - 여기서 onNativeAnswer / onNativeReject / onEndFromNotification 핸들러 등록
  ///     - onNativeAnswer → PushService.dispatchNativeAnswer → 기존 _callAcceptCtrl
  ///       흐름(_attachCallkitAccept) 재사용 → bootstrapIncomingFromPush + router push
  ///       → CallScreen.fromPush 분기 → CallService.acceptCall() →
  ///         chat.emit('call_response', accepted=true) ✅
  void _attachNativeCallBridge(BuildContext ctx) {
    if (_nativeCallBridgeAttached) return;
    _nativeCallBridgeAttached = true;
    _nativeCallBridge.setMethodCallHandler((call) async {
      try {
        debugPrint('[native-bridge] method=${call.method} args=${call.arguments}');
        // call.arguments 는 Map (Kotlin HashMap) 으로 들어옴.
        final raw = call.arguments;
        final data = <String, dynamic>{};
        if (raw is Map) {
          raw.forEach((k, v) {
            data[k.toString()] = v;
          });
        }
        switch (call.method) {
          case 'onNativeAnswer':
            // Native NativeIncomingCallActivity.onAnswerClicked() →
            // MainActivity.handleNativeCallIntent() → 여기로 도달.
            // 기존 CallKit accept 인프라 (_attachCallkitAccept) 가 자동으로 받음.
            try {
              ctx.read<PushService>().dispatchNativeAnswer(data);
            } catch (e) {
              debugPrint('[native-bridge] dispatchNativeAnswer failed: $e');
            }
            break;
          case 'onNativeReject':
            // Native 거절 버튼: NativeIncomingCallActivity.onRejectClicked() →
            // MainActivity 깨우기 putExtra(reject_call_from_native=true) → 여기로 invoke.
            // CallService.rejectCall() 이 chat.emit('call_response', accepted=false)
            // 까지 자동으로 처리.
            try {
              await ctx.read<CallService>().rejectCall(reason: 'declined');
            } catch (e) {
              debugPrint('[native-bridge] rejectCall failed: $e');
            }
            break;
          case 'onEndFromNotification':
            // 통화 알림의 "종료" 버튼 → endCall.
            try {
              await ctx.read<CallService>().endCall();
            } catch (e) {
              debugPrint('[native-bridge] endCall failed: $e');
            }
            break;
          default:
            debugPrint('[native-bridge] unknown method: ${call.method}');
        }
      } catch (e) {
        debugPrint('[native-bridge] handler exception: $e');
      }
      return null;
    });
    debugPrint('[native-bridge] setMethodCallHandler registered (v1.0.150)');
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
        // ★ v1.0.107: cold start 시 SharedPreferences pending push 큐 복원.
        //  background isolate(firebaseBackgroundHandler)가 받아둔 메시지를
        //  _rooms 에 합성 방으로 일괄 추가 → 메인탭 뱃지/채팅 목록/런처 뱃지
        //  즉시 동기화. 노티 탭이 아니라 아이콘만 탭한 경우에도 작동.
        try {
          final chat = context.read<ChatService>();
          // ignore: discarded_futures
          chat.applyPendingPushMessages();
        } catch (e) {
          debugPrint('[push-pending] cold-start failed: $e');
        }
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

    // ★ v1.0.158 (2026-05-11): 서버에 lifecycle 상태 송신 (presence_update).
    //   서버 chat-hub.ts 가 이 값을 보고 FCM heads-up push 발송 여부 결정:
    //     foreground → Flutter UI 가 통화 수신 처리 → FCM push 생략
    //     background → native heads-up/FSI 필요 → FCM push 발송
    //   → 이중 표시 (Flutter 풀스크린 + native 헤드업 동시) 원천 차단.
    //
    //   AppLifecycleState 매핑:
    //     resumed                 → 'foreground'
    //     paused/inactive/hidden/
    //     detached                → 'background'
    final presenceState = (state == AppLifecycleState.resumed)
        ? 'foreground'
        : 'background';
    try {
      final chat = context.read<ChatService>();
      chat.emit('presence_update', {'state': presenceState});
      debugPrint('[presence] lifecycle=$state → emit presence_update($presenceState)');
    } catch (e) {
      // ChatService 미주입 / WebSocket 미연결 시 silent skip.
      // 다음 connect 직후 chat_service.dart 가 초기 presence 를 송신함.
      debugPrint('[presence] emit skipped (lifecycle=$state): $e');
    }

    // ★ 웜 스타트 — 앱이 백그라운드에서 포어그라운드로 복귀할 때.
    //  v1.0.107 정책: 미읽음 방 1+개면 무조건 가장 최근 방 직진.
    //  부팅 후 1회 제한(_autoEnterUnreadDone)이 false 일 때만 실행.
    if (state == AppLifecycleState.resumed) {
      // ★ v1.0.107: warm resume 에도 SharedPreferences pending 큐 복원.
      //  앱이 백그라운드 상태일 때 firebaseBackgroundHandler 가 받아 큐에 쌓은
      //  푸시들을 _rooms 에 합성 방으로 추가 → 사용자가 앱 복귀 직후
      //  메인탭 뱃지/채팅 목록 즉시 보임.
      try {
        final chat = context.read<ChatService>();
        // ignore: discarded_futures
        chat.applyPendingPushMessages();
      } catch (e) {
        debugPrint('[push-pending] warm-resume failed: $e');
      }
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
      // ★ v1.0.126: 앱 부팅 직후 1회만 stuck CallKit/상태 강제 정리.
      //  비정상 종료 후 재실행 시 "이미 통화 중이에요" 토스트 방지.
      if (!_callBootResetDone) {
        _callBootResetDone = true;
        // ignore: discarded_futures
        call.resetOnBoot();
      }
    }

    // CallKit accept 이벤트 → /call 라우팅 (한 번만 attach).
    _attachCallkitAccept(context);

    // ★ v1.0.150 (2026-05-10): Native NativeIncomingCallActivity 의 받기/거절/종료 →
    //   MainActivity invokeMethod → MethodChannel 핸들러. 한 번만 attach.
    //   _attachCallkitAccept 와 동일 _callAcceptCtrl 흐름을 재사용한다.
    _attachNativeCallBridge(context);

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
// v1.0.114 rebuild trigger
