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
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'launcher_badge.dart';

/// ★ 7차 푸시(이슈 1/2/3 통합): background isolate 와 main isolate 가 공유하는
/// pending push 큐 SharedPreferences 키. JSON 배열 (최대 50개).
/// firebaseBackgroundHandler 가 채워두고, 앱 부팅/재개 시 ChatService 가 비움.
const String kPendingPushQueueKey = 'pending_push_messages_v1';
const int kPendingPushQueueMax = 50;

/// Top-level entry-point — FCM SDK 가 isolate 에서 직접 호출한다.
/// 클래스 메서드로 만들면 isolate 진입점으로 등록할 수 없으니 반드시 top-level.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // ★ 백그라운드/앱 종료 상태에서만 호출됨. UI thread 가 없으므로
  //   가능한 작업은 (1) CallKit 시스템 UI, (2) SharedPreferences 큐 저장,
  //   (3) MethodChannel 으로 native 런처 뱃지 갱신.
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
    // ★ v1.0.142 (Eggplant native call port):
    //   type='incoming_call' (신규 native FCM 형식) 은 Android native 의
    //   EggplantFirebaseMessagingService 가 manifest 등록 우선순위로 먼저
    //   가져가서 처리하므로, Dart background isolate 에는 도달하지 않는다.
    //   혹시 도달했다면 (race / iOS 등) silent skip — 이중 표시 방지.
    if (type == 'incoming_call') {
      return;
    }
    // ★ Legacy (v1.0.141 이하): type='call_invite' 는 Dart CallKit 으로 fallback.
    //   v1.0.142 서버는 두 형식을 동시 발사하지 않으므로 (incoming_call 만 보냄)
    //   실제로는 거의 호출 안 됨. 다만 push_service 가 FCM SDK 에 register 된
    //   상태이므로 silent skip 처리만 하면 안전.
    if (type == 'call_invite') {
      // 신규 native call 흐름에선 Dart CallKit 안 띄움. native 가 처리.
      // (구버전 클라이언트에서 받은 잔존 푸시 대비 silent return)
      return;
    }
    // ★ v1.0.124 핵심 핫픽스 (2026-05-07 사장님 보고):
    //   발신자가 통화 끊으면 서버가 call_cancel data-only 푸시를 발사한다.
    //   background isolate 가 이걸 받아 FlutterCallkitIncoming.endCall(callId)
    //   를 호출 → 잠금화면/홈화면에 떠있던 통화 UI 와 벨소리 즉시 종료.
    //   v1.0.142 에서도 유지 — native side 는 자체 ACTION_CANCEL_INCOMING
    //   broadcast 로 처리하지만, 구버전 잔존 CallKit UI 가 떠있을 수 있어
    //   Dart endCall 도 같이 호출 (양쪽 cleanup 보장).
    if (type == 'call_cancel') {
      await _dismissIncomingCall(data);
      return;
    }
    // ★ v1.0.107: type == 'message' 일 때 SharedPreferences pending 큐에 추가.
    //   background isolate 는 ChatService 인스턴스 접근 불가 → 큐에 넣어두면
    //   다음 앱 부팅/재개 시 main.dart 가 chat.applyPendingPushMessages() 로
    //   일괄 복원. 메인탭 뱃지/채팅 목록/런처 뱃지 모두 즉시 동기화됨.
    if (type == 'message') {
      await _enqueuePendingPush(data);
    }
  } catch (e) {
    debugPrint('[push-bg] handler error: $e');
  }
}

/// ★ v1.0.124: 발신자가 끊었을 때 수신측 단말의 CallKit UI 강제 종료.
///   data['call_id'] 로 식별. 단말에 CallKit 이 떠있지 않으면 silent no-op.
Future<void> _dismissIncomingCall(Map<String, dynamic> data) async {
  final callId = data['call_id']?.toString() ?? '';
  if (callId.isEmpty) return;
  try {
    await FlutterCallkitIncoming.endCall(callId);
  } catch (e) {
    // 알려진 callId 가 없을 수 있음 (사용자가 이미 받았거나 거절). silent.
    debugPrint('[push-bg] dismiss call failed: $e');
    // 안전장치: 어떤 통화든 모두 닫기 (구버전 OS 동작 차이 방어).
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }
}

/// ★ v1.0.107: background isolate 에서 pending 큐에 푸시 추가 + 런처 뱃지 갱신.
///   같은 room_id + sent_at 조합은 dedup. 큐 길이 = 런처 뱃지 숫자 (대략적).
Future<void> _enqueuePendingPush(Map<String, dynamic> data) async {
  try {
    final roomId = data['room_id']?.toString() ?? '';
    if (roomId.isEmpty) return;

    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(kPendingPushQueueKey) ?? '[]';
    List<dynamic> list;
    try {
      list = (jsonDecode(raw) as List?) ?? <dynamic>[];
    } catch (_) {
      list = <dynamic>[];
    }

    final entry = <String, dynamic>{
      'room_id': roomId,
      'sender_id': data['sender_id']?.toString() ?? '',
      'sender_nickname': data['sender_nickname']?.toString() ?? '',
      'text': data['text']?.toString() ?? '',
      'received_at': DateTime.now().toUtc().toIso8601String(),
    };

    // dedup: 같은 room_id + received_at(초 단위) 중복 push 방지.
    final isDup = list.any((e) {
      if (e is! Map) return false;
      return e['room_id'] == roomId &&
          e['received_at']?.toString().substring(0, 19) ==
              entry['received_at']!.toString().substring(0, 19);
    });
    if (!isDup) {
      list.add(entry);
      // 최대 길이 초과 시 오래된 것부터 drop.
      while (list.length > kPendingPushQueueMax) {
        list.removeAt(0);
      }
      await sp.setString(kPendingPushQueueKey, jsonEncode(list));
    }

    // ★ v1.0.107: background isolate 에서도 native MethodChannel 호출 가능.
    //   pending 큐 길이 만큼 런처 뱃지 표시. 단말 OEM 런처가 자동 해석.
    //   (앱이 부팅되면 ChatService 가 totalUnread 기준으로 다시 갱신함)
    try {
      await LauncherBadge.set(list.length);
    } catch (_) {/* silent */}
  } catch (e) {
    debugPrint('[push-bg] enqueue failed: $e');
  }
}

/// CallKit 으로 시스템 전화 수신 UI 띄우기 (Android: full-screen intent).
/// ★ v1.0.124 핫픽스 (2026-05-07):
///   1) nameCaller: '익명' 하드코딩 → 서버에서 보낸 caller_nickname 사용
///   2) isCustomNotification: true → false (기본 시스템 통화 UI = 헤드업/풀스크린 정상)
///   3) handle 에 닉네임 노출 (user_id 대신 — 사장님 지시: 닉네임 표시)
Future<void> _showIncomingCall(Map<String, dynamic> data) async {
  final callId = data['call_id']?.toString() ?? '';
  final fromUserId = data['from_user_id']?.toString() ?? '';
  // 서버 chat-hub.ts 가 caller_nickname 을 데이터에 실어 보냄.
  // 빈 값/누락 대비 fallback 으로만 '익명' 사용.
  final callerNickname = (data['caller_nickname']?.toString().trim().isNotEmpty ?? false)
      ? data['caller_nickname']!.toString().trim()
      : '익명';
  // ★ v1.0.136: caller_wallet 도 보존. acceptCall 시 main isolate 로 전달돼
  //   Agora 채널명(eggplant_<sortedPair>) 산정에 사용됨. 누락되면 채널 join
  //   직전 "통화 정보를 불러올 수 없어요" 로 즉시 teardown 되어 사장님이 본
  //   "수락 누르자마자 꺼져버림" 증상 발생. 서버 fcm payload 의 data.caller_wallet
  //   에 들어와 있음.
  final callerWallet = data['caller_wallet']?.toString() ?? '';
  if (callId.isEmpty) return;

  final params = CallKitParams(
    id: callId,
    nameCaller: callerNickname,
    appName: '가지마켓',
    handle: callerNickname, // 닉네임을 통화 헤더에 표시
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
      'caller_nickname': callerNickname,
      // ★ v1.0.136: extra 는 CallKit accept 이벤트 body 로 흘러가 main isolate
      //   가 그대로 받음. _attachCallkitListener 가 caller_wallet 도 같이 stream 으로 발사.
      'caller_wallet': callerWallet,
    },
    android: const AndroidParams(
      // ★ false 로 변경: Android 기본 통화 알림 사용 → 헤드업/풀스크린 자동 트리거.
      // true 인 경우 커스텀 노티 사용 → 잠금화면에서 받기/거절 버튼이 안 뜨고
      // 작은 노티 줄로만 표시되어 사장님이 보신 화면 같이 깨짐.
      isCustomNotification: false,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#7B2CBF', // Eggplant primary
      actionColor: '#FFB300',
      // ★ v1.0.140 (2026-05-09): 헤드업 배너가 안 뜨고 벨소리만 나는 증상 핫픽스.
      //   원인: v1.0.124~v1.0.139 기간 동안 '전화 수신' 채널이 한 번이라도
      //   IMPORTANCE_DEFAULT 로 등록되면 Android 가 그 importance 를 영구
      //   캐시 (코드로 못 올림) → 사운드만 재생되고 배너 push 안 함.
      //   해결책 1) 채널 이름을 '전화 수신' → '전화 수신 (V2)' 로 변경 →
      //   Android 가 신규 채널로 인식 → 라이브러리 native side 가
      //   IMPORTANCE_HIGH 로 재생성.
      //   해결책 2) isShowFullLockedScreen + isImportant 명시 → 라이브러리가
      //   Notification.Builder 에 setFullScreenIntent + Person.setImportant
      //   를 적용하도록 강제.
      incomingCallNotificationChannelName: '전화 수신 (V2)',
      missedCallNotificationChannelName: '부재중 전화 (V2)',
      // 잠금화면 위에 풀스크린 인텐트로 띄움 (USE_FULL_SCREEN_INTENT 권한 필요).
      isShowFullLockedScreen: true,
      isImportant: true,
      isShowCallID: false,
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

    // ── 8) ★ v1.0.140 (2026-05-09): Android 14+ FSI 권한 사전 점검 ──
    //   Android 14 부터 USE_FULL_SCREEN_INTENT 권한이 calling/alarm 앱에만
    //   기본 부여되고, 사용자가 설정에서 끌 수 있음. 꺼져 있으면 풀스크린
    //   인텐트가 안 떠 헤드업 배너만 짧게 보이거나(또는 안 보이고) 벨소리만
    //   재생됨. canUseFullScreenIntent() 로 점검만 해 두고, 거부 상태면
    //   debug 로그만 (사용자에게 권한 설정 페이지를 강제로 띄우면 매번
    //   설정창이 뜨는 사장님 보고된 UX 이슈 발생 → 점검만, 강제 요청 X).
    try {
      final canUseFsi =
          await FlutterCallkitIncoming.canUseFullScreenIntent();
      debugPrint('[push] canUseFullScreenIntent = $canUseFsi');
    } catch (e) {
      // Android 13 이하 또는 라이브러리 미지원 — 무시.
      debugPrint('[push] canUseFullScreenIntent unsupported: $e');
    }
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
          // ★ v1.0.136: caller_wallet / caller_nickname 도 함께 전달 — main isolate 의
          //   _attachCallkitAccept 이 router.push('/call?...&peerWallet=...&peer=...')
          //   로 사용. 누락 시 acceptCall 단계에서 채널명 산정 실패 → 즉시 teardown.
          _callAcceptCtrl.add({
            'call_id': extra['call_id']?.toString() ?? '',
            'from_user_id': extra['from_user_id']?.toString() ?? '',
            'caller_wallet': extra['caller_wallet']?.toString() ?? '',
            'caller_nickname': extra['caller_nickname']?.toString() ?? '익명',
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
    // ★ v1.0.142 (Eggplant native call port):
    //   포그라운드에서 type='incoming_call' 푸시가 들어오면 native FCM
    //   서비스가 Route 1 (foreground) 분기로 처리 — 알림만 띄우고 ChatService
    //   WebSocket 의 call_incoming 이 main.dart 의 _IncomingCallOverlay 로
    //   in-app UI 트리거. Dart 측은 CallKit 띄우지 않고 silent skip.
    if (type == 'incoming_call') {
      return;
    }
    // Legacy: 구버전 클라이언트 잔존 푸시 — Dart CallKit 띄우지 않음.
    if (type == 'call_invite') {
      return;
    }
    // call_cancel 은 native 가 ACTION_CANCEL_INCOMING broadcast 로 처리하지만
    // foreground 에서도 CallKit 잔존 가능성 있으므로 endCall 보강.
    if (type == 'call_cancel') {
      await _dismissIncomingCall(data);
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
    // ★ v1.0.142 (Eggplant native call port):
    //   type='incoming_call' 푸시 tap 은 native NativeIncomingCallActivity
    //   가 받아서 직접 AgoraCallActivity 로 진입시키므로 Dart 측 라우팅 불필요.
    //   이 경로(onMessageOpenedApp)는 알림 tap → 앱 부팅 케이스인데,
    //   native FCM 서비스가 우선 처리하므로 Dart 에는 거의 도달 안 함.
    //   silent skip — 중복 라우팅 방지.
    if (type == 'incoming_call') {
      return;
    }
    if (type == 'call_invite') {
      // ★ Legacy (v1.0.141 이하): caller_wallet / caller_nickname 동봉 —
      //   _attachCallkitAccept 가 동일 stream 으로 듣고 라우팅. v1.0.142
      //   서버는 신규 형식만 보내므로 거의 도달 안 하지만 안전 보존.
      _callAcceptCtrl.add({
        'call_id': data['call_id']?.toString() ?? '',
        'from_user_id': data['from_user_id']?.toString() ?? '',
        'caller_wallet': data['caller_wallet']?.toString() ?? '',
        'caller_nickname': data['caller_nickname']?.toString() ?? '익명',
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
