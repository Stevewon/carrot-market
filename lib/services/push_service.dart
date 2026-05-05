// ============================================================
// push_service.dart — FCM (Firebase Cloud Messaging) 통합
// ============================================================
// 정책:
//   1) 사장님 결정 (c): Firebase 프로젝트 신규 생성 후 키 등록 예정.
//      placeholder google-services.json 으로도 빌드 통과되도록
//      모든 Firebase 호출을 try/catch 로 감싸 graceful fallback.
//
//   2) 익명성 유지: FCM 토큰은 OS 발급 디바이스 식별자라 Google 계정과 무관.
//      서버는 토큰만 저장(0024 마이그레이션), 푸시 본문/이력은 D1 미저장.
//
//   3) 백그라운드 메시지 핸들러는 entry-point 함수로 분리(top-level).
//      flutter_callkit_incoming 으로 전화 수신 UI 트리거.
//
//   4) Firebase 미초기화 / 토큰 발급 실패 시:
//        - 빌드 통과 ✅
//        - 앱 실행 ✅ (silent fallback, 크래시 없음)
//        - 메시지/통화는 WebSocket 으로 정상 동작 (포그라운드 한정)
//        - 백그라운드 푸시만 비활성 (사장님이 진짜 키로 교체 시 즉시 활성화)
// ============================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'api_client.dart';
import 'auth_service.dart';

/// Top-level entry-point — FCM SDK 가 isolate 에서 직접 호출한다.
/// 클래스 메서드로 만들면 isolate 진입점으로 등록할 수 없으니 반드시 top-level.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // ★ 백그라운드/앱 종료 상태에서만 호출됨. UI thread 가 없으므로
  //   가능한 작업은 (1) CallKit 시스템 UI 띄우기, (2) 로컬 푸시 표시 정도.
  try {
    // Firebase 가 초기화 안 되어 있을 수 있음 (placeholder 모드 / cold start).
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp();
      } catch (_) {
        // placeholder google-services.json 또는 미생성 → silent fail.
        return;
      }
    }
    final data = message.data;
    final type = data['type']?.toString();
    if (type == 'call_invite') {
      await _showIncomingCall(data);
    }
    // type == 'message' 의 경우 OS 가 이미 trayNotification 을 띄워줌
    // (FCM HTTP v1 의 notification 필드 효과). 추가 작업 불필요.
  } catch (e) {
    debugPrint('[push-bg] handler error: $e');
  }
}

/// CallKit 으로 시스템 전화 수신 UI 띄우기 (Android: full-screen intent).
Future<void> _showIncomingCall(Map<String, dynamic> data) async {
  final callId = data['call_id']?.toString() ?? '';
  final fromUserId = data['from_user_id']?.toString() ?? '';
  if (callId.isEmpty) return;

  final params = CallKitParams(
    id: callId,
    nameCaller: '익명',
    appName: 'Eggplant',
    handle: fromUserId, // 익명: user_id 만 (지갑주소/닉네임 노출 X)
    type: 0, // 0 = audio call (1 = video)
    duration: 30000, // 30 초 안에 안 받으면 자동 종료
    textAccept: '받기',
    textDecline: '거절',
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: '부재중 전화',
    ),
    extra: <String, dynamic>{
      'call_id': callId,
      'from_user_id': fromUserId,
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#7B2CBF', // Eggplant primary
      actionColor: '#FFB300',
      incomingCallNotificationChannelName: '전화 수신',
      missedCallNotificationChannelName: '부재중 전화',
    ),
  );
  try {
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  } catch (e) {
    debugPrint('[push-bg] callkit show error: $e');
  }
}

/// 포그라운드 / 앱 실행 중 푸시·통화 수신 통합 매니저.
class PushService extends ChangeNotifier {
  final AuthService auth;
  // ApiClient 는 AuthService 가 들고 있는 인스턴스를 공유한다.
  // (1) 로그인 토큰이 setToken() 으로 자동 주입되어 별도 헤더 처리 불필요
  // (2) 401 token_revoked 인터셉터도 그대로 적용
  // → push_service 내부에서는 _api 로 호출만 하면 됨.
  ApiClient get _api => auth.api;

  PushService({required this.auth}) {
    auth.addListener(_onAuthChanged);
  }

  bool _initialized = false;
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// CallKit accept 콜백 (사장님이 채팅화면/통화화면에서 listen).
  /// data['call_id'], data['from_user_id'] 포함.
  final StreamController<Map<String, dynamic>> _callAcceptCtrl =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get onCallAccepted => _callAcceptCtrl.stream;

  /// ★ 5차 푸시: 메시지 알림 tap → 채팅방 자동 라우팅용.
  /// data['room_id'], data['sender_id']?, data['sender_nickname']? 포함.
  /// main.dart 의 _IncomingCallOverlay 가 listen 해서 router.push('/chat/<roomId>') 수행.
  final StreamController<Map<String, dynamic>> _messageOpenedCtrl =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get onMessageOpened => _messageOpenedCtrl.stream;

  /// ★ 7차 푸시 (이슈 3): foreground 에서 FCM message 수신 시에도
  /// ChatService 에 합성 방을 추가하기 위한 stream.
  /// _handleForeground 가 type=='message' 일 때 흘려준다 (라우팅은 안 함).
  /// main.dart 가 listen 해서 chat.applyIncomingPushMessage(...) 호출.
  final StreamController<Map<String, dynamic>> _messageReceivedCtrl =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get onMessageReceived =>
      _messageReceivedCtrl.stream;

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;
  StreamSubscription<dynamic>? _callkitEventSub;

  /// 앱 부팅 직후 한 번 호출. main.dart 에서 await 안 한 채 fire-and-forget.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // ── 1) Firebase 초기화 ─────────────────────────────
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (e) {
      debugPrint('[push] Firebase init failed (placeholder mode?): $e');
      // 그래도 CallKit 이벤트 리스너는 attach (백그라운드 핸들러 ↔ 포그라운드 라우팅).
      _attachCallkitListener();
      return;
    }

    // ── 2) 푸시 권한 (Android 13+ / iOS) ───────────────
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {/* ignore */}

    // ── 3) 백그라운드 핸들러 등록 ──────────────────────
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    } catch (_) {/* ignore */}

    // ── 4) 포그라운드 메시지 ───────────────────────────
    _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForeground);

    // ── 5) 푸시 tap → 앱 부팅 ──────────────────────────
    _onMessageOpenedSub =
        FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedFromPush);

    // ── 6) 토큰 발급 + 서버 등록 ───────────────────────
    try {
      _fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint('[push] FCM token: '
          '${_fcmToken == null ? "null (placeholder?)" : _fcmToken!.substring(0, 12) + "..."}');
      if (_fcmToken != null) {
        await _registerToken(_fcmToken!);
      }
      // 토큰 갱신 시 자동 재등록.
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _fcmToken = t;
        _registerToken(t);
      });
    } catch (e) {
      debugPrint('[push] getToken failed (placeholder?): $e');
    }

    // ── 7) CallKit 이벤트 리스너 (accept/decline) ──────
    _attachCallkitListener();
    notifyListeners();
  }

  void _attachCallkitListener() {
    try {
      _callkitEventSub = FlutterCallkitIncoming.onEvent.listen((event) {
        if (event == null) return;
        final body = event.body as Map?;
        // event.event 예: "ACTION_CALL_ACCEPT", "ACTION_CALL_DECLINE", "ACTION_CALL_TIMEOUT"
        final name = event.event.toString();
        if (name.contains('ACCEPT')) {
          final extra = (body?['extra'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          _callAcceptCtrl.add({
            'call_id': extra['call_id']?.toString() ?? '',
            'from_user_id': extra['from_user_id']?.toString() ?? '',
          });
        }
        // DECLINE/TIMEOUT 는 CallKit 이 자동으로 UI 정리. 추가 처리 불필요.
      });
    } catch (e) {
      debugPrint('[push] callkit listener attach failed: $e');
    }
  }

  Future<void> _handleForeground(RemoteMessage message) async {
    final data = message.data;
    final type = data['type']?.toString();
    if (type == 'call_invite') {
      // 포그라운드라도 사용자가 다른 화면에 있을 수 있으니 CallKit UI 띄움.
      await _showIncomingCall(data);
      return;
    }
    // ★ 7차 푸시 (이슈 3): type == 'message' 면 ChatService 에 합성 방 추가
    //  요청을 stream 으로 흘려보낸다. WS 가 살아있으면 곧 동일 메시지가 'message'
    //  이벤트로 들어와 dedup 되지만, WS 가 끊긴 상태에서는 이 경로가 유일한
    //  메인탭 뱃지/채팅 목록 갱신 트리거. 라우팅은 하지 않음 (사용자 흐름 보존).
    if (type == 'message') {
      final roomId = data['room_id']?.toString() ?? '';
      if (roomId.isNotEmpty) {
        _messageReceivedCtrl.add({
          'room_id': roomId,
          'sender_id': data['sender_id']?.toString() ?? '',
          'sender_nickname': data['sender_nickname']?.toString() ?? '',
          'text': data['text']?.toString() ?? '',
        });
      }
    }
  }

  Future<void> _handleOpenedFromPush(RemoteMessage message) async {
    final data = message.data;
    final type = data['type']?.toString();
    if (type == 'call_invite') {
      _callAcceptCtrl.add({
        'call_id': data['call_id']?.toString() ?? '',
        'from_user_id': data['from_user_id']?.toString() ?? '',
      });
      return;
    }
    // ★ 5차 푸시: 일반 메시지 알림 tap → 채팅방 자동 라우팅.
    //  서버는 chat-hub.ts 에서 data: { type:'message', room_id } 형태로 보낸다.
    //  Stream 에 event 흘려서 main.dart 의 router.push('/chat/<roomId>') 가
    //  채팅방으로 이동하도록 한다.
    if (type == 'message') {
      final roomId = data['room_id']?.toString() ?? '';
      if (roomId.isNotEmpty) {
        _messageOpenedCtrl.add({
          'room_id': roomId,
          'sender_id': data['sender_id']?.toString() ?? '',
          'sender_nickname': data['sender_nickname']?.toString() ?? '익명',
        });
      }
    }
  }

  /// ★ 5차 푸시: 콜드 스타트(앱 종료 상태) 처리.
  ///   사용자가 종료된 앱의 푸시 알림을 tap → OS 가 앱을 새로 부팅 →
  ///   FirebaseMessaging.instance.getInitialMessage() 로 그 알림을 가져올 수 있음.
  ///   main.dart 가 부팅 후 한 번만 호출 → 채팅방/통화화면 자동 진입.
  Future<void> handleColdStartFromNotification() async {
    try {
      final RemoteMessage? msg =
          await FirebaseMessaging.instance.getInitialMessage();
      if (msg == null) return; // 일반 부팅 — 노티 tap 아님.
      // 동일 핸들러로 위임. listener 가 이미 attach 된 시점이어야 한다.
      await _handleOpenedFromPush(msg);
    } catch (e) {
      debugPrint('[push] cold-start initial message failed: $e');
    }
  }

  /// 서버에 FCM 토큰 등록. AuthService 토큰이 있을 때만 동작.
  Future<void> _registerToken(String token) async {
    if (auth.token == null) {
      // 로그인 전 — auth listener 가 다시 호출해줌.
      return;
    }
    try {
      await _api.dio.post(
        '/api/users/me/push-token',
        data: <String, dynamic>{'fcm_token': token, 'platform': 'android'},
      );
    } catch (e) {
      debugPrint('[push] register token failed: $e');
      // 0024 마이그레이션 미적용 / 네트워크 오류 → silent (다음 갱신 때 재시도).
    }
  }

  /// AuthService 상태 변경 시 — 로그인 직후 토큰 재등록, 로그아웃 시 토큰 폐기.
  Future<void> _onAuthChanged() async {
    if (!_initialized) return;
    if (auth.isLoggedIn && _fcmToken != null) {
      await _registerToken(_fcmToken!);
    } else if (!auth.isLoggedIn) {
      // 로그아웃: 서버에 빈 토큰 보내 NULL 처리 (다른 디바이스로 푸시 안 가도록).
      try {
        await _api.dio.post(
          '/api/users/me/push-token',
          data: <String, dynamic>{'fcm_token': '', 'platform': 'android'},
        );
      } catch (_) {/* ignore */}
    }
  }

  /// 디버깅용 — 현재 토큰을 사람이 읽기 쉬운 JSON 으로.
  String debugDump() => jsonEncode({
        'initialized': _initialized,
        'fcm_token_prefix':
            _fcmToken == null ? null : '${_fcmToken!.substring(0, 12)}...',
      });

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    _onMessageSub?.cancel();
    _onMessageOpenedSub?.cancel();
    _callkitEventSub?.cancel();
    _callAcceptCtrl.close();
    _messageOpenedCtrl.close();
    _messageReceivedCtrl.close();
    super.dispose();
  }
}
