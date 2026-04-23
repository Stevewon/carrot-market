import 'dart:io';

import 'package:flutter/material.dart';
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
}
