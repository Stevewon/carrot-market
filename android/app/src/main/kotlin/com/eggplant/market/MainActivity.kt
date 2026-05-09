package com.eggplant.market

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
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
    // ★ v1.0.111 (이슈 1): FCM 서버 푸시 알림 native 정리 채널.
    //   flutter_local_notifications 의 cancelAll() 은 플러그인이 띄운 알림만
    //   정리하므로, FCM notification payload 가 OS 에 직접 띄운 알림이 그대로
    //   남는다. NotificationManager.cancelAll() 을 native 에서 직접 호출.
    private val NOTIF_CHANNEL = "eggplant.market/notification_cleanup"
    // ★ v1.0.142 (Phase 2-9): Native 통화 브리지 채널.
    //   Flutter auth_service 가 로그인/로그아웃 시 JWT + wallet 을 native SP 에 미러링.
    //   AgoraTokenService 가 SP("eggplant_native_call") 의 jwt_token / wallet_address 를 읽어 사용.
    //   또한 Native (NativeIncomingCallActivity / CallActionReceiver / CallEndFromNotificationReceiver)
    //   에서 발생한 reject / end / native_answer 이벤트를 Flutter call_service 로 전달.
    private val NATIVE_CALL_BRIDGE_CHANNEL = "eggplant.market/native_call_bridge"

    // Flutter 측이 등록한 MethodChannel 핸들 — onResume / onNewIntent 에서 이벤트 invoke 시 사용
    private var nativeCallBridge: MethodChannel? = null

    companion object {
        private const val TAG = "Eggplant.Main"

        // ================================================================
        //  Native 통화 수락 진행 중 플래그 (NativeIncomingCallActivity / CallActionReceiver 가 set)
        //  Flutter IncomingCallScreen 이중 표시 차단용.
        //  AgoraCallActivity.start() 호출 직전 true 로 set,
        //  Flutter call_service 가 acceptCall 처리 후 false 로 reset.
        // ================================================================
        @Volatile
        var nativeAnswerInProgress: Boolean = false

        // ================================================================
        //  Native 수락 시 Flutter 로 전달할 통화 정보 (cold-start 방어).
        //  NativeIncomingCallActivity.onAnswerClicked() 에서 set.
        //  MainActivity.onResume() 에서 MethodChannel 로 Flutter 에 invoke 후 null reset.
        // ================================================================
        @Volatile
        var pendingNativeAnswerData: Map<String, String>? = null

        // SharedPreferences 이름 — AgoraTokenService 와 동일해야 함
        const val NATIVE_CALL_PREFS = "eggplant_native_call"
        const val KEY_JWT = "jwt_token"
        const val KEY_WALLET = "wallet_address"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 인텐트로 들어온 native call 이벤트를 Flutter engine 준비 후 처리
        handleNativeCallIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // CallActionReceiver / CallEndFromNotificationReceiver / NativeIncomingCallActivity
        // 로부터 들어오는 새 인텐트 처리
        handleNativeCallIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        EggplantFirebaseMessagingService.isAppForeground = true
        Log.d(TAG, "[MAIN] onResume — isAppForeground=true")

        // pendingNativeAnswerData 가 있으면 Flutter 로 전달 (cold-start 시 인텐트 extras 가 누락된 경우 보완)
        flushPendingNativeAnswerToFlutter()
    }

    override fun onPause() {
        super.onPause()
        EggplantFirebaseMessagingService.isAppForeground = false
        Log.d(TAG, "[MAIN] onPause — isAppForeground=false")
    }

    /**
     * Native 측에서 들어온 인텐트 extras 를 검사하여 Flutter MethodChannel 로 전달.
     * 처리 가능한 케이스:
     *   - reject_call_from_native=true   → Flutter call_service 가 reject 응답 (WebSocket call_response=rejected)
     *   - end_call_from_notification=true → Flutter call_service 가 endCall (WebSocket call_end)
     *   - from_native_answer=true        → Flutter call_service 에 native 측이 이미 수락했음을 통보
     */
    private fun handleNativeCallIntent(intent: Intent?) {
        if (intent == null) return

        val rejectFromNative = intent.getBooleanExtra("reject_call_from_native", false)
        val endFromNotification = intent.getBooleanExtra("end_call_from_notification", false)
        val fromNativeAnswer = intent.getBooleanExtra("from_native_answer", false)

        if (!rejectFromNative && !endFromNotification && !fromNativeAnswer) return

        val sessionId = intent.getStringExtra("sessionId") ?: ""
        Log.e(TAG, "[MAIN] native call intent: reject=$rejectFromNative end=$endFromNotification answer=$fromNativeAnswer session=$sessionId")

        // intent 의 extras 를 한 번 사용한 후 제거 — onNewIntent 재진입 시 중복 처리 방지
        intent.removeExtra("reject_call_from_native")
        intent.removeExtra("end_call_from_notification")
        intent.removeExtra("from_native_answer")

        // MethodChannel 이 아직 setup 안 된 시점일 수 있음 — runOnUiThread 로 유예
        runOnUiThread {
            try {
                when {
                    rejectFromNative -> {
                        nativeCallBridge?.invokeMethod("onNativeReject", mapOf("sessionId" to sessionId))
                            ?: Log.w(TAG, "[MAIN] nativeCallBridge null on reject — Flutter not ready yet")
                    }
                    endFromNotification -> {
                        nativeCallBridge?.invokeMethod("onEndFromNotification", mapOf("sessionId" to sessionId))
                            ?: Log.w(TAG, "[MAIN] nativeCallBridge null on end — Flutter not ready yet")
                    }
                    fromNativeAnswer -> {
                        // pendingNativeAnswerData 가 있으면 그것을 우선 (NativeIncomingCallActivity 가 set 한 데이터)
                        // 없으면 인텐트 extras 에서 직접 추출
                        val data = pendingNativeAnswerData ?: mapOf(
                            "sessionId" to sessionId,
                            "callerId" to (intent.getStringExtra("callerId") ?: ""),
                            "callerNickname" to (intent.getStringExtra("callerNickname") ?: ""),
                            "callType" to (intent.getStringExtra("callType") ?: "audio"),
                            "callerProfilePhoto" to (intent.getStringExtra("callerProfilePhoto") ?: "")
                        )
                        nativeCallBridge?.invokeMethod("onNativeAnswer", data)
                            ?: Log.w(TAG, "[MAIN] nativeCallBridge null on answer — Flutter not ready yet")
                        pendingNativeAnswerData = null
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "[MAIN] handleNativeCallIntent invoke failed: ${e.message}")
            }
        }
    }

    /**
     * pendingNativeAnswerData 를 Flutter 로 flush.
     * onResume 시 호출 — Flutter engine 이 준비된 후 안전하게 전달.
     */
    private fun flushPendingNativeAnswerToFlutter() {
        val data = pendingNativeAnswerData ?: return
        Log.e(TAG, "[MAIN] flushing pendingNativeAnswerData session=${data["sessionId"]}")
        try {
            nativeCallBridge?.invokeMethod("onNativeAnswer", data)
                ?: Log.w(TAG, "[MAIN] nativeCallBridge null on flush — will retry on next event")
            pendingNativeAnswerData = null
        } catch (e: Exception) {
            Log.e(TAG, "[MAIN] flushPendingNativeAnswerToFlutter failed: ${e.message}")
        }
    }

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

        // ★ v1.0.111 (이슈 1): FCM notification payload 가 띄운 시스템 알림을
        //  native NotificationManager.cancelAll() 로 일괄 정리. 채팅방 진입 시
        //  호출해서 푸시 트레이를 깨끗하게 정리한다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cancelAll" -> {
                        try {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            nm.cancelAll()
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ★ v1.0.142 (Phase 2-9): Native 통화 브리지 채널.
        //   Flutter → Native:
        //     - setAuth(jwt, walletAddress)         : 로그인 후 JWT + wallet SP 미러링
        //     - clearAuth()                         : 로그아웃 시 SP 비우기
        //     - clearNativeAnswerInProgress()       : Flutter 가 acceptCall 처리 완료 후 flag reset
        //     - consumePendingNativeAnswer()        : SharedPreferences pending_native_answer 소비 (cold-start)
        //     - isNativeAnswerInProgress()          : 현재 native 수락 진행 중인지 조회
        //   Native → Flutter (invokeMethod):
        //     - onNativeReject(sessionId)           : 알림 reject 또는 NativeIncomingCallActivity reject
        //     - onEndFromNotification(sessionId)    : ongoing notification End call
        //     - onNativeAnswer(data)                : NativeIncomingCallActivity 수락 (Flutter 측 상태 동기화용)
        nativeCallBridge = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_CALL_BRIDGE_CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAuth" -> {
                        val jwt = call.argument<String>("jwt") ?: ""
                        val wallet = call.argument<String>("walletAddress") ?: ""
                        try {
                            val prefs = getSharedPreferences(NATIVE_CALL_PREFS, Context.MODE_PRIVATE)
                            prefs.edit().apply {
                                if (jwt.isNotEmpty()) putString(KEY_JWT, jwt)
                                if (wallet.isNotEmpty()) putString(KEY_WALLET, wallet.lowercase())
                                apply()
                            }
                            Log.d(TAG, "[MAIN] setAuth: jwtLen=${jwt.length} walletLen=${wallet.length}")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "[MAIN] setAuth failed: ${e.message}")
                            result.success(false)
                        }
                    }
                    "clearAuth" -> {
                        try {
                            val prefs = getSharedPreferences(NATIVE_CALL_PREFS, Context.MODE_PRIVATE)
                            prefs.edit().apply {
                                remove(KEY_JWT)
                                remove(KEY_WALLET)
                                apply()
                            }
                            Log.d(TAG, "[MAIN] clearAuth: SP wiped")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "[MAIN] clearAuth failed: ${e.message}")
                            result.success(false)
                        }
                    }
                    "clearNativeAnswerInProgress" -> {
                        nativeAnswerInProgress = false
                        pendingNativeAnswerData = null
                        Log.d(TAG, "[MAIN] clearNativeAnswerInProgress: flag reset")
                        result.success(true)
                    }
                    "isNativeAnswerInProgress" -> {
                        result.success(nativeAnswerInProgress)
                    }
                    "consumePendingNativeAnswer" -> {
                        // SharedPreferences 의 pending_native_answer (60s TTL, consume-and-delete)
                        val data = CallNotificationHelper.consumePendingNativeAnswer(this@MainActivity)
                        if (data == null) {
                            result.success(null)
                        } else {
                            result.success(data)
                        }
                    }
                    "isNativeIncomingActive" -> {
                        result.success(CallNotificationHelper.isNativeIncomingActive(this@MainActivity))
                    }
                    "clearNativeIncomingActive" -> {
                        CallNotificationHelper.clearNativeIncomingActive(this@MainActivity)
                        result.success(true)
                    }
                    "stopRingtone" -> {
                        CallNotificationHelper.stopRingtone()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // engine 준비 완료 — onCreate 에서 잡아둔 인텐트가 있으면 다시 한 번 시도
        // (configureFlutterEngine 은 onCreate 후 호출되므로 nativeCallBridge null 이슈 방지)
        runOnUiThread {
            handleNativeCallIntent(intent)
            flushPendingNativeAnswerToFlutter()
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
