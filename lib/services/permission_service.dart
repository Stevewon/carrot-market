import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Requests all runtime permissions the app needs **once** during onboarding
/// (GCON / 당근 style). After the first successful pass we remember it in
/// SharedPreferences so later flows never prompt again.
///
/// If the user denies or partially denies, we still record the attempt so we
/// don't nag on every chat/call screen — we surface a friendly snackbar and
/// a settings shortcut instead.
class PermissionService {
  static const _kAskedAllKey = 'perm_asked_all_v1';
  // ★ v1.0.161 (2026-05-12): FSI 권한 자동 요청 — 사장님 한 세션당 1회만 안내 (영구 OFF 시 다시 묻지 않음)
  static const _kFsiAskedKey = 'perm_fsi_asked_v1';
  static const MethodChannel _fsiChannel = MethodChannel('eggplant.market/fsi_permission');

  /// All permissions the app ever needs, grouped for the user-facing dialog.
  static List<Permission> get _all {
    final perms = <Permission>[
      Permission.camera,       // QR scan, product photos, record video
      Permission.microphone,   // Voice call (WebRTC)
      Permission.photos,       // iOS photos / Android READ_MEDIA_IMAGES
      Permission.videos,       // Android READ_MEDIA_VIDEO (no-op on older APIs)
      Permission.notification, // Chat/call alerts
    ];
    return perms;
  }

  /// Returns true if we've already run the bulk prompt at least once.
  static Future<bool> hasAskedBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAskedAllKey) ?? false;
  }

  /// Mark the bulk prompt as done so later screens don't re-prompt.
  static Future<void> markAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAskedAllKey, true);
  }

  /// Request every permission in one system-level burst.
  /// Returns the result map for the caller to inspect if needed.
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    final result = await _all.request();
    await markAsked();
    return result;
  }

  /// True if mic is already granted (checked without prompting).
  static Future<bool> hasMic() async {
    return Permission.microphone.isGranted;
  }

  /// True if camera is already granted.
  static Future<bool> hasCamera() async {
    return Permission.camera.isGranted;
  }

  /// Idempotent mic check — call right before starting a WebRTC call.
  /// Does NOT re-prompt unless the user has never been asked.
  static Future<bool> ensureMicOrToast(BuildContext context) async {
    if (await Permission.microphone.isGranted) return true;
    // Only ask again if onboarding somehow didn't run.
    if (!await hasAskedBefore()) {
      final r = await Permission.microphone.request();
      if (r.isGranted) return true;
    }
    _showDenied(context, '마이크 권한이 필요해요', '설정 > 앱 > Eggplant에서 마이크를 켜주세요.');
    return false;
  }

  /// Same for camera (QR scan / photo capture).
  static Future<bool> ensureCameraOrToast(BuildContext context) async {
    if (await Permission.camera.isGranted) return true;
    if (!await hasAskedBefore()) {
      final r = await Permission.camera.request();
      if (r.isGranted) return true;
    }
    _showDenied(context, '카메라 권한이 필요해요', '설정 > 앱 > Eggplant에서 카메라를 켜주세요.');
    return false;
  }

  /// Photos/videos for image_picker gallery mode.
  static Future<bool> ensureGalleryOrToast(BuildContext context) async {
    // On iOS & Android 13+ this is Permission.photos.
    // On older Android (<33) READ_EXTERNAL_STORAGE is handled by the picker itself,
    // so we treat it as granted.
    if (Platform.isAndroid) {
      // image_picker handles legacy storage internally, so skip here unless 13+.
      final photos = await Permission.photos.status;
      if (photos.isGranted || photos.isLimited) return true;
      // isDenied on older Android means "not applicable" — image_picker still works.
      if (photos.isPermanentlyDenied) {
        _showDenied(context, '갤러리 권한이 필요해요', '설정 > 앱 > Eggplant에서 사진/동영상 권한을 켜주세요.');
        return false;
      }
      return true;
    }
    final status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) return true;
    _showDenied(context, '갤러리 권한이 필요해요', '설정 > Eggplant에서 사진 권한을 켜주세요.');
    return false;
  }

  /// Android 13+ POST_NOTIFICATIONS / iOS UN authorization 친절 가이드.
  ///
  /// 채팅방 입장 등에서 호출. 이미 허용돼 있으면 조용히 true.
  /// 거부 상태라면 (a) 한 번도 묻지 않은 상태면 다시 묻고, (b) 그래도 거부면
  /// AlertDialog 로 "왜 알림이 필요한지 + 설정 바로가기" 를 안내한다.
  static Future<bool> ensureNotificationOrGuide(BuildContext context) async {
    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    // 첫 진입(또는 onboarding 누락) 이면 시스템 다이얼로그로 한 번 더 시도.
    if (status.isDenied && !status.isPermanentlyDenied) {
      final r = await Permission.notification.request();
      if (r.isGranted) return true;
    }

    if (!context.mounted) return false;
    final goSetting = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🔔 알림 권한이 꺼져 있어요'),
        content: const Text(
          '알림이 꺼져 있으면 새 메시지·통화·키워드 매물 알림을 놓칠 수 있어요.\n\n'
          '설정에서 알림을 켜시겠어요?\n\n'
          '※ Eggplant는 알림 본문을 잠금화면에서 가리는 옵션도 제공해요. '
          '"나의 Eggplant > 알림 본문 가리기" 에서 켤 수 있어요.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('나중에'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('설정 열기'),
          ),
        ],
      ),
    );
    if (goSetting == true) {
      await openAppSettings();
    }
    return false;
  }

  static void _showDenied(BuildContext context, String title, String body) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title\n$body'),
        action: SnackBarAction(
          label: '설정 열기',
          onPressed: () => openAppSettings(),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ============================================================
  // ★ v1.0.161 (2026-05-12): FSI (Full-Screen Intent) 권한 자동 요청
  // ----------------------------------------------------------
  // Android 14 (API 34) 부터 USE_FULL_SCREEN_INTENT 권한이 기본 OFF.
  // 잠금화면에서 incoming call 풀스크린이 안 뜨는 진짜 원인.
  // 앱이 런타임에 NotificationManager.canUseFullScreenIntent() 체크 후
  // false 면 사장님 친화 다이얼로그를 띄우고 1탭으로 시스템 설정 직행.
  // 단말 OS 가 Android 13 이하면 항상 true 반환 (조용히 통과).
  // ============================================================

  /// FSI 권한이 켜져있는지 native 측에 조회.
  /// Android 14 미만 또는 체크 실패 시 보수적으로 true.
  static Future<bool> canUseFullScreenIntent() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _fsiChannel.invokeMethod<bool>('canUseFullScreenIntent');
      return result ?? true;
    } catch (e) {
      // 채널 미연결/메서드 미구현 시 통화 동선 차단 방지를 위해 true.
      return true;
    }
  }

  /// 시스템 설정 화면(앱별 전체화면 알림 권한) 직행.
  /// Android 13 이하면 일반 앱 설정 화면으로 fallback.
  static Future<bool> openFullScreenIntentSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _fsiChannel.invokeMethod<bool>('openFullScreenIntentSettings');
      return result ?? false;
    } catch (e) {
      // 채널 실패 시 일반 앱 설정으로 fallback
      await openAppSettings();
      return false;
    }
  }

  /// 현재 세션에서 사장님께 FSI 권한 안내를 이미 띄웠는지.
  /// (한 번 안내한 뒤로는 같은 세션에서 다시 띄우지 않음 — 사용자 동선 보호)
  static Future<bool> hasAskedFsi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kFsiAskedKey) ?? false;
  }

  static Future<void> markAskedFsi() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFsiAskedKey, true);
  }

  /// FSI 권한 OFF 일 때 사장님 친화 다이얼로그 표시 후
  /// "권한 허용" 버튼 클릭 시 시스템 설정 화면으로 직행.
  ///
  /// 호출 위치:
  ///   1) 앱 시작 시 (lib/main.dart 의 _RootGate.initState) — 한 번만
  ///   2) 통화 발신/수신 진입 시 (call_service.startCall / 알림 수락 시점)
  ///
  /// 반환값:
  ///   true  = 권한 이미 켜져있음 OR Android 14 미만
  ///   false = 권한 OFF (사용자가 설정 화면으로 이동했거나 나중에 선택)
  static Future<bool> ensureFullScreenIntentOrGuide(
    BuildContext context, {
    bool oncePerSession = true,
  }) async {
    if (!Platform.isAndroid) return true;
    final allowed = await canUseFullScreenIntent();
    if (allowed) return true;

    // 한 세션에 1번만 안내 (사장님 동선 보호 — 매 통화마다 팝업 금지)
    if (oncePerSession && await hasAskedFsi()) return false;

    if (!context.mounted) return false;
    final goSetting = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🔒 잠금화면 통화 알림 권한'),
        content: const Text(
          '잠금화면에서 통화 수신을 표시하려면\n'
          '"전체 화면 알림" 권한이 필요해요.\n\n'
          '권한이 꺼져 있으면 잠금화면에서는\n'
          '벨소리만 울리고 통화 화면이 뜨지 않아요.\n\n'
          '한 번만 설정하면 끝나요.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('나중에'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('권한 허용'),
          ),
        ],
      ),
    );
    await markAskedFsi();
    if (goSetting == true) {
      await openFullScreenIntentSettings();
    }
    return false;
  }
}
