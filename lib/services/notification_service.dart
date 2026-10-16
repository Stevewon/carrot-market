import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app/l10n.dart';

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
      final t = L10n.current;
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          'chat_messages',
          t.chatChannelChatName,
          description: t.chatChannelChatDesc,
          importance: Importance.high,
        ),
      );
      // 키워드 알림 채널 — 매너온도/사운드를 채팅과 분리해서 사용자가 채널별로 끌 수 있게.
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          'keyword_alerts',
          t.chatChannelKeywordName,
          description: t.chatChannelKeywordDesc,
          importance: Importance.high,
        ),
      );
      // ★ 5차 푸시 핫픽스: 서버(fcm.ts)가 보내는 channel_id 와 매칭되는 채널.
      //  서버 payload: channel_id='eggplant_messages' (일반) / 'eggplant_calls' (통화)
      //  채널 사전 생성 안 하면 Android 가 fallback default 채널로 표시 → 사용자가
      //  채널별 음소거 설정 못함 + 일부 OEM 에서 알림 동작 불일치.
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          'eggplant_messages',
          t.chatChannelPushName,
          description: t.chatChannelPushDesc,
          importance: Importance.high,
        ),
      );
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          'eggplant_calls',
          t.chatChannelCallName,
          description: t.chatChannelCallDesc,
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
    final t = L10n.current;
    final maskedTitle = t.chatKeywordAlertTitle;
    final maskedBody = _maskBody ? t.chatKeywordAlertMaskedBody : '$region · $title';
    try {
      await _plugin.show(
        ('kw_$productId').hashCode,
        maskedTitle,
        maskedBody,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'keyword_alerts',
            t.chatChannelKeywordName,
            channelDescription: t.chatChannelKeywordDesc,
            importance: Importance.high,
            priority: Priority.high,
            ticker: t.chatKeywordTicker,
            category: AndroidNotificationCategory.recommendation,
          ),
          iOS: const DarwinNotificationDetails(
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

  /// 거래 약속 30분 전 알림 (당근식). 같은 방의 약속은 하나만 — 새로 잡으면 덮어쓴다.
  /// 이미 30분 안쪽이면 알림 없이 넘어간다. [at] 이 null 이면 그 방의 예약 알림 취소.
  Future<void> scheduleAppointmentReminder({
    required String roomId,
    DateTime? at,
    String place = '',
  }) async {
    final id = ('appt_$roomId').hashCode;
    try {
      if (!_initialized) await init();
      await _plugin.cancel(id);
      if (at == null) return;
      final fireAt = at.subtract(const Duration(minutes: 30));
      if (fireAt.isBefore(DateTime.now().add(const Duration(seconds: 30)))) return;
      final t = L10n.current;
      await _plugin.zonedSchedule(
        id,
        t.chatAppointmentReminderTitle,
        place.isEmpty ? t.chatAppointmentReminderBody : '${t.chatAppointmentReminderBody} · $place',
        tz.TZDateTime.from(fireAt.toUtc(), tz.UTC),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'chat_messages',
            t.chatChannelChatName,
            channelDescription: t.chatChannelChatDesc,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: roomId,
      );
    } catch (e) {
      debugPrint('[notif] appointment reminder failed: $e');
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
    final t = L10n.current;
    final displayTitle = _maskBody ? t.chatMaskedMessageTitle : senderNickname;
    final displayBody = _maskBody ? t.chatMaskedMessageBody : text;
    try {
      await _plugin.show(
        roomId.hashCode,
        displayTitle,
        displayBody,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'chat_messages',
            t.chatChannelChatName,
            channelDescription: t.chatChannelChatDesc,
            importance: Importance.high,
            priority: Priority.high,
            ticker: t.chatNewMessage,
            category: AndroidNotificationCategory.message,
          ),
          iOS: const DarwinNotificationDetails(
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
