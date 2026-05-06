import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local notifications for incoming chat messages.
///
/// We don't use Firebase Cloud Messaging — Eggplant is anonymous and we keep
/// no Google account / FCM tokens. Instead the WebSocket (`/socket`) delivers
/// every `message` event in realtime; while the app is alive (foreground or
/// backgrounded but not killed) we surface them as a system notification via
/// `flutter_local_notifications`. Tapping the notification deep-links to the
/// chat room.
///
/// Caveat: when the OS kills the app, no notifications fire until the user
/// reopens it. That's an acceptable trade-off vs. hooking up Firebase, and it
/// matches the privacy posture of an anonymous market.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Fired when the user taps a notification. Carries the chat roomId payload.
  final StreamController<String> _onTap = StreamController<String>.broadcast();
  Stream<String> get onTap => _onTap.stream;

  bool _initialized = false;

  // ── 본문 숨김 옵션 (privacy mode) ──────────────────────────────────────
  // true 면 알림 본문에 메시지 텍스트 대신 '💬 새 메시지가 있어요' 만 표시.
  // 잠금화면/푸시 미리보기에서 대화 내용이 노출되지 않도록 하는 옵션.
  // SharedPreferences 키: 'notif_mask_body_v1' (default false).
  static const _kMaskKey = 'notif_mask_body_v1';
  bool _maskBody = false;
  bool get isMaskingBody => _maskBody;

  Future<void> _loadMask() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _maskBody = sp.getBool(_kMaskKey) ?? false;
    } catch (_) {/* SharedPreferences 못 읽어도 default false 로 동작 */}
  }

  Future<void> setMaskBody(bool value) async {
    _maskBody = value;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kMaskKey, value);
    } catch (_) {}
  }

  /// Initialize the notification channel + tap handler.
  /// Safe to call more than once.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _loadMask();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) {
          _onTap.add(payload);
        }
      },
    );

    if (Platform.isAndroid) {
      // Create the chat channel up-front so per-channel mute settings work.
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'chat_messages',
          '채팅 메시지',
          description: '새 채팅 메시지 알림',
          importance: Importance.high,
        ),
      );
      // 키워드 알림 채널 — 매너온도/사운드를 채팅과 분리해서 사용자가 채널별로 끌 수 있게.
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'keyword_alerts',
          '키워드 알림',
          description: '관심 키워드와 일치하는 새 상품 알림',
          importance: Importance.high,
        ),
      );
      // ★ 5차 푸시 핫픽스: 서버(fcm.ts)가 보내는 channel_id 와 매칭되는 채널.
      //  서버 payload: channel_id='eggplant_messages' (일반) / 'eggplant_calls' (통화)
      //  채널 사전 생성 안 하면 Android 가 fallback default 채널로 표시 → 사용자가
      //  채널별 음소거 설정 못함 + 일부 OEM 에서 알림 동작 불일치.
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'eggplant_messages',
          'Eggplant 메시지',
          description: '새 채팅 메시지 푸시 알림',
          importance: Importance.high,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          'eggplant_calls',
          'Eggplant 전화',
          description: '음성 통화 수신 알림',
          importance: Importance.max,
        ),
      );
    }
  }

  /// 키워드 알림. 탭하면 product detail 로 deep-link 되도록 productId 를 payload 로 실어 보낸다.
  /// payload 형식: 'product:<productId>' — onTap stream 측에서 prefix 로 분기.
  Future<void> showKeywordAlert({
    required String productId,
    required String title,
    required String region,
  }) async {
    if (!_initialized) {
      await init();
    }
    final maskedTitle = '🔔 새 매물 알림';
    final maskedBody = _maskBody ? '관심 키워드와 일치하는 새 상품이 있어요' : '$region · $title';
    try {
      await _plugin.show(
        ('kw_$productId').hashCode,
        maskedTitle,
        maskedBody,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'keyword_alerts',
            '키워드 알림',
            channelDescription: '관심 키워드와 일치하는 새 상품 알림',
            importance: Importance.high,
            priority: Priority.high,
            ticker: '새 매물',
            category: AndroidNotificationCategory.recommendation,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        payload: 'product:$productId',
      );
    } catch (e) {
      debugPrint('[notif] keyword alert failed: $e');
    }
  }

  /// Show a chat message notification.
  ///
  /// [roomId] is the payload that gets passed back when the user taps.
  /// We use [roomId.hashCode] as the system notification id so that consecutive
  /// messages within the same room replace one another (one notification per
  /// active chat) — matches 당근/카카오톡 behavior.
  Future<void> showChatMessage({
    required String roomId,
    required String senderNickname,
    required String text,
  }) async {
    if (!_initialized) {
      await init();
    }
    // 본문 숨김 옵션이 켜져 있으면 발신자/메시지 모두 마스킹.
    final displayTitle = _maskBody ? '💬 새 메시지가 있어요' : senderNickname;
    final displayBody = _maskBody ? '메시지를 보려면 탭하세요' : text;
    try {
      await _plugin.show(
        roomId.hashCode,
        displayTitle,
        displayBody,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'chat_messages',
            '채팅 메시지',
            channelDescription: '새 채팅 메시지 알림',
            importance: Importance.high,
            priority: Priority.high,
            ticker: '새 메시지',
            category: AndroidNotificationCategory.message,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: roomId,
      );
    } catch (e) {
      debugPrint('[notif] show failed: $e');
    }
  }

  /// Cancel any notification for this room (call when user opens the room).
  Future<void> cancelForRoom(String roomId) async {
    try {
      await _plugin.cancel(roomId.hashCode);
    } catch (_) {}
  }

  /// ★ v1.0.109 (이슈 1): 채팅방 진입 시 그동안 쌓인 FCM 푸시 알림
  ///   ('chat_messages' 채널) 을 모두 한 번에 정리. roomId.hashCode 단일 cancel
  ///   만으로는 서버 FCM 이 띄운 시스템 알림이 그대로 남는 케이스가 있어 추가.
  ///
  ///   getActiveNotifications() 로 현재 표시 중인 알림 enumerate 후
  ///   해당 채널('chat_messages') 알림을 일괄 cancel.
  ///
  ///   ★ v1.0.111 (이슈 1 보강): flutter_local_notifications 의 cancel 은
  ///   플러그인 본인이 띄운 알림만 정리한다. FCM notification payload 가 OS 에
  ///   직접 띄운 알림은 잡히지 않으므로, native MethodChannel 로
  ///   NotificationManager.cancelAll() 을 호출해 트레이를 강제 정리.
  Future<void> cancelAllChatNotifications() async {
    // 1) flutter_local_notifications 가 띄운 chat_messages 채널 알림 정리.
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final active = await androidImpl.getActiveNotifications();
        for (final n in active) {
          // chat_messages 채널 알림만 정리 (call/keyword 알림은 보존).
          if (n.channelId == 'chat_messages' && n.id != null) {
            try {
              await _plugin.cancel(n.id!);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[notif] cancelAllChatNotifications (plugin) failed: $e');
    }
    // 2) ★ v1.0.111: FCM 이 띄운 OS 트레이 알림까지 native 로 일괄 정리.
    try {
      const ch = MethodChannel('eggplant.market/notification_cleanup');
      await ch.invokeMethod<bool>('cancelAll');
    } catch (e) {
      debugPrint('[notif] native cancelAll failed: $e');
    }
  }
}
