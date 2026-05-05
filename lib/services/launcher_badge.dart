// ============================================================
// launcher_badge.dart — 런처 아이콘 뱃지 native 채널 wrapper
// ============================================================
// 정책:
//   1) flutter_app_badger 1.5.0 은 AGP 8.x namespace 비호환 → MethodChannel 직접 구현.
//   2) MainActivity.kt 의 'eggplant.market/launcher_badge' 채널과 매칭.
//   3) iOS 는 Eggplant 가 Android-only 라 native 코드 없음 — Platform 분기로 안전 처리.
//   4) 모든 호출은 try/catch 로 감싸 실패해도 앱 동작에 영향 X (silent fallback).
// ============================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 바탕화면 런처 아이콘 위 숫자 뱃지 제어.
///
/// Samsung/Sony/Xiaomi/Huawei/LG/HTC OEM intent broadcast 를 한 번에 전송 →
/// 단말의 OEM 런처가 자체적으로 해석. 지원 안 하는 OEM 은 broadcast 무시.
class LauncherBadge {
  LauncherBadge._();

  static const MethodChannel _channel =
      MethodChannel('eggplant.market/launcher_badge');

  /// 뱃지 숫자를 [count] 로 설정. 0 이면 뱃지 제거.
  /// Android 가 아니면 no-op (iOS native 미구현 — Eggplant Android-only).
  static Future<void> set(int count) async {
    if (!Platform.isAndroid) return;
    try {
      final safe = count < 0 ? 0 : count;
      await _channel.invokeMethod<bool>('setBadge', {'count': safe});
    } catch (e) {
      debugPrint('[launcher-badge] set($count) failed: $e');
    }
  }

  /// 뱃지 제거 (count=0 동등).
  static Future<void> clear() => set(0);

  /// 단말 지원 여부. Android 면 true, 그 외엔 false.
  /// (실제 OEM 런처가 표시 안 해도 broadcast 자체는 실패 안 함)
  static Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isSupported');
      return res ?? false;
    } catch (e) {
      debugPrint('[launcher-badge] isSupported failed: $e');
      return false;
    }
  }
}
