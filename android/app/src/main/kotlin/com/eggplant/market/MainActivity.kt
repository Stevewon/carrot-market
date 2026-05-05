package com.eggplant.market

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "eggplant.market/secure_screen"
    // ★ 7차 푸시(이슈 2): 런처 아이콘 뱃지 native 채널.
    //   flutter_app_badger 1.5.0 이 AGP 8.x namespace 비호환 → MethodChannel 직접 구현.
    //   Samsung/Sony/Xiaomi/Huawei/LG 런처 OEM intent broadcast 직접 전송.
    private val BADGE_CHANNEL = "eggplant.market/launcher_badge"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableSecure" -> {
                        runOnUiThread {
                            window.setFlags(
                                WindowManager.LayoutParams.FLAG_SECURE,
                                WindowManager.LayoutParams.FLAG_SECURE
                            )
                        }
                        result.success(true)
                    }
                    "disableSecure" -> {
                        runOnUiThread {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ★ 7차 푸시(이슈 2): 런처 뱃지 native 핸들러.
        //  setBadge(count: int) — 0 이면 제거, 그 이상이면 OEM 별 intent broadcast 전송.
        //  isSupported() — 지원 단말 판별 (try/catch 로 결과 반환).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BADGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setBadge" -> {
                        val count = (call.argument<Int>("count") ?: 0).coerceAtLeast(0)
                        try {
                            applyLauncherBadge(count)
                            result.success(true)
                        } catch (e: Exception) {
                            // 실패해도 앱 동작에는 영향 X — 로그만 남기고 false.
                            result.success(false)
                        }
                    }
                    "isSupported" -> {
                        // 시도 자체가 실패 안 함 (intent 보내는 행위는 항상 성공),
                        // 실제 표시 여부는 OEM 런처 설정에 달림 → 항상 true 반환.
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// OEM 별 런처 뱃지 broadcast 전송. 단말에 없는 OEM intent 는 무시되므로
    /// 모든 broadcast 를 한 번에 보내도 안전.
    private fun applyLauncherBadge(count: Int) {
        val pkg = packageName
        val launcherClass = try {
            packageManager.getLaunchIntentForPackage(pkg)?.component?.className
                ?: "$pkg.MainActivity"
        } catch (_: Exception) {
            "$pkg.MainActivity"
        }

        // 1) Samsung (TouchWiz / OneUI) — BadgeProvider broadcast.
        try {
            val intent = Intent("android.intent.action.BADGE_COUNT_UPDATE")
            intent.putExtra("badge_count", count)
            intent.putExtra("badge_count_package_name", pkg)
            intent.putExtra("badge_count_class_name", launcherClass)
            sendBroadcast(intent)
        } catch (_: Exception) {}

        // 2) Sony — provider write (PROVIDER_INSERT_OR_UPDATE 권한 필요할 수 있음).
        try {
            val intent = Intent("com.sonyericsson.home.action.UPDATE_BADGE")
            intent.putExtra("com.sonyericsson.home.intent.extra.badge.SHOW_MESSAGE", count > 0)
            intent.putExtra("com.sonyericsson.home.intent.extra.badge.MESSAGE", count.toString())
            intent.putExtra("com.sonyericsson.home.intent.extra.badge.PACKAGE_NAME", pkg)
            intent.putExtra("com.sonyericsson.home.intent.extra.badge.ACTIVITY_NAME", launcherClass)
            sendBroadcast(intent)
        } catch (_: Exception) {}

        // 3) HTC.
        try {
            val intent = Intent("com.htc.launcher.action.UPDATE_SHORTCUT")
            intent.putExtra("packagename", pkg)
            intent.putExtra("count", count)
            sendBroadcast(intent)
        } catch (_: Exception) {}

        // 4) Huawei / Honor.
        try {
            val intent = Intent("android.intent.action.BADGE_COUNT_UPDATE")
            val extras = Bundle()
            extras.putString("package", pkg)
            extras.putString("class", launcherClass)
            extras.putInt("badgenumber", count)
            intent.putExtras(extras)
            sendBroadcast(intent)
        } catch (_: Exception) {}

        // 5) LG.
        try {
            val intent = Intent("android.intent.action.BADGE_COUNT_UPDATE")
            intent.putExtra("badge_count", count)
            intent.putExtra("badge_count_package_name", pkg)
            intent.putExtra("badge_count_class_name", launcherClass)
            sendBroadcast(intent)
        } catch (_: Exception) {}

        // 6) Xiaomi (MIUI) — Notification reflection 방식이 필요하지만 권한 이슈가 있어
        //    intent broadcast 만 보내고 무시되면 OEM 기본 동작에 의존.
        try {
            val intent = Intent("android.intent.action.APPLICATION_MESSAGE_UPDATE")
            intent.putExtra("android.intent.extra.update_application_component_name",
                "$pkg/$launcherClass")
            intent.putExtra("android.intent.extra.update_application_message_text",
                if (count > 0) count.toString() else "")
            sendBroadcast(intent)
        } catch (_: Exception) {}
    }
}
