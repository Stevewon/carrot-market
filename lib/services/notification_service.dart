import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  /// Initialize the notification channel + tap handler.
  /// Safe to call more than once.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

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
    try {
      await _plugin.show(
        ('kw_$productId').hashCode,
        '🔔 새 매물 알림',
        '$region · $title',
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
    try {
      await _plugin.show(
        roomId.hashCode,
        senderNickname,
        text,
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
}
