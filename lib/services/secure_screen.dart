import 'package:flutter/services.dart';

/// Controls the Android FLAG_SECURE window flag to prevent screenshots
/// and screen recording on sensitive screens (e.g. chat).
/// Implemented via a native MethodChannel instead of flutter_windowmanager
/// to avoid dependency compatibility issues with the latest AGP.
class SecureScreen {
  static const _channel = MethodChannel('eggplant.market/secure_screen');

  /// Block screenshots on the current screen.
  static Future<void> enable() async {
    try {
      await _channel.invokeMethod('enableSecure');
    } catch (_) {
      // Not available on non-Android platforms
    }
  }

  /// Allow screenshots again.
  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('disableSecure');
    } catch (_) {}
  }
}
