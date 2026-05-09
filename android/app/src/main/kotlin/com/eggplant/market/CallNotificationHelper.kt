package com.eggplant.market

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.PowerManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person

/**
 * Eggplant v1.0.142 — QRChat v4.0.270 native call notification helper port.
 *
 * Architecture (Q3=생략 — NativeAcceptCallActivity branch removed):
 *
 * +------------------------------------------------------------+
 * | showHeadsUpNotification() -- Route 2                        |
 * |   (Screen ON + unlocked)                                    |
 * |   - CallStyle.forIncomingCall + FSI for heads-up retention  |
 * |   - Answer = PendingIntent.getActivity -> NativeIncomingCallActivity |
 * |     (then directly launches AgoraCallActivity, no Flutter flash) |
 * +------------------------------------------------------------+
 * | showHeadsUpWithFullScreenFallback() -- Route 3              |
 * |   (Screen OFF / locked)                                     |
 * |   - FSI direct send (full-screen only, NO heads-up)         |
 * |   - NativeIncomingCallActivity launched as full-screen      |
 * +------------------------------------------------------------+
 *
 * NO call records on server (CRITICAL INVARIANT).
 * SharedPreferences "eggplant_native_call":
 *   - jwt_token (mirrored from Flutter after login)
 *   - wallet_address (mirrored from Flutter after login)
 *   - pending_native_answer (60s expiry, consume-and-delete)
 *   - native_incoming_active (60s expiry guard for Flutter dual-fire)
 */
object CallNotificationHelper {

    // 새 채널 ID — Android 는 기존 채널의 importance/설정을 변경 불가 → 버전 업그레이드 시 새 ID 필요
    const val INCOMING_CHANNEL_ID = "eggplant_incoming_calls_v1"
    const val INCOMING_NOTIFICATION_ID = 9001
    const val ONGOING_CHANNEL_ID = "eggplant_ongoing_calls_silent"
    const val ONGOING_NOTIFICATION_ID = 9002

    private const val PREFS_NAME = "eggplant_native_call"

    private var mediaPlayer: MediaPlayer? = null
    private var fallbackRingtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    @Volatile private var isRingtoneActive = false

    // 외부(Dart side)에서 Kotlin 벨소리 활성 여부 조회 — 이중 벨소리 방지
    fun isRingingNow(): Boolean = isRingtoneActive
    private var audioFocusRequest: AudioFocusRequest? = null
    private var audioManagerRef: AudioManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // ==================================================
    //  SharedPreferences: pending native answer persistence
    // ==================================================

    private fun getPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun savePendingNativeAnswer(
        context: Context,
        sessionId: String,
        callerId: String,
        callerNickname: String,
        callType: String,
        callerProfilePhoto: String
    ) {
        getPrefs(context).edit().apply {
            putBoolean("pending_native_answer", true)
            putString("pending_native_answer_session_id", sessionId)
            putString("pending_native_answer_caller_id", callerId)
            putString("pending_native_answer_caller_nickname", callerNickname)
            putString("pending_native_answer_call_type", callType)
            putString("pending_native_answer_caller_photo", callerProfilePhoto)
            putLong("pending_native_answer_timestamp", System.currentTimeMillis())
            apply()
        }
        Log.e("CALL_TERM", "[CALL_TERM] pending_native_answer saved sessionId=$sessionId")
    }

    fun consumePendingNativeAnswer(context: Context): Map<String, String>? {
        val prefs = getPrefs(context)
        if (!prefs.getBoolean("pending_native_answer", false)) return null

        val ts = prefs.getLong("pending_native_answer_timestamp", 0L)
        if (System.currentTimeMillis() - ts > 60_000L) {
            clearPendingNativeAnswer(context)
            Log.e("CALL_TERM", "[CALL_TERM] pending_native_answer expired -- cleared")
            return null
        }

        val data = mapOf(
            "sessionId" to (prefs.getString("pending_native_answer_session_id", "") ?: ""),
            "callerId" to (prefs.getString("pending_native_answer_caller_id", "") ?: ""),
            "callerNickname" to (prefs.getString("pending_native_answer_caller_nickname", "") ?: ""),
            "callType" to (prefs.getString("pending_native_answer_call_type", "audio") ?: "audio"),
            "callerProfilePhoto" to (prefs.getString("pending_native_answer_caller_photo", "") ?: "")
        )

        clearPendingNativeAnswer(context)
        Log.e("CALL_TERM", "[CALL_TERM] pending native answer consumed sessionId=${data["sessionId"]}")
        return data
    }

    fun clearPendingNativeAnswer(context: Context) {
        getPrefs(context).edit().apply {
            remove("pending_native_answer")
            remove("pending_native_answer_session_id")
            remove("pending_native_answer_caller_id")
            remove("pending_native_answer_caller_nickname")
            remove("pending_native_answer_call_type")
            remove("pending_native_answer_caller_photo")
            remove("pending_native_answer_timestamp")
            apply()
        }
    }

    fun hasPendingNativeAnswer(context: Context): Boolean =
        getPrefs(context).getBoolean("pending_native_answer", false)

    // ==================================================
    //  nativeIncomingActive flag
    //  Route 2/3에서 FCM 수신 시 즉시 설정.
    //  Flutter call_service 가 동시에 fire해도 IncomingCallScreen 표시 차단.
    //  Answer/Reject/Timeout 시 해제.
    // ==================================================

    fun setNativeIncomingActive(context: Context, sessionId: String) {
        getPrefs(context).edit().apply {
            putBoolean("native_incoming_active", true)
            putString("native_incoming_session_id", sessionId)
            putLong("native_incoming_timestamp", System.currentTimeMillis())
            apply()
        }
        Log.e("CALL_PATH", "[CALL_PATH] nativeIncomingActive=true sessionId=$sessionId")
    }

    fun isNativeIncomingActive(context: Context): Boolean {
        val prefs = getPrefs(context)
        if (!prefs.getBoolean("native_incoming_active", false)) return false
        // 60초 후 자동 만료 (안전장치)
        val ts = prefs.getLong("native_incoming_timestamp", 0L)
        if (System.currentTimeMillis() - ts > 60_000L) {
            clearNativeIncomingActive(context)
            return false
        }
        return true
    }

    fun getNativeIncomingSessionId(context: Context): String {
        return getPrefs(context).getString("native_incoming_session_id", "") ?: ""
    }

    fun clearNativeIncomingActive(context: Context) {
        getPrefs(context).edit().apply {
            remove("native_incoming_active")
            remove("native_incoming_session_id")
            remove("native_incoming_timestamp")
            apply()
        }
        Log.e("CALL_PATH", "[CALL_PATH] nativeIncomingActive=false (cleared)")
    }

    // ==================================================
    //  Channels
    // ==================================================

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 이전 Eggplant 채널 정리 (이전 버전이 있었다면 잘못된 importance 캐시 제거)
        // Eggplant 는 v1.0.142 가 첫 native call 도입이므로 거의 비어있지만, 안전 차원
        for (legacy in listOf(
            "eggplant_calls",
            "eggplant_incoming_call"
        )) {
            nm.getNotificationChannel(legacy)?.let {
                nm.deleteNotificationChannel(legacy)
                Log.e("CALL_NOTI", "[CALL_NOTI] deleted legacy channel: $legacy")
            }
        }

        // 새 채널 생성 — 모든 FSI 관련 설정 명시 (Android 는 기존 채널 설정 변경 불가)
        if (nm.getNotificationChannel(INCOMING_CHANNEL_ID) == null) {
            nm.createNotificationChannel(NotificationChannel(
                INCOMING_CHANNEL_ID, "Incoming Calls", NotificationManager.IMPORTANCE_MAX
            ).apply {
                description = "Eggplant 수신 통화 (잠금화면 풀스크린 + 벨소리)"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                // 채널 자체는 무음 — MediaPlayer 로 별도 재생
                setSound(null, null)
                setShowBadge(true)
            })
            Log.e("CALL_NOTI", "[CALL_NOTI] ★ created NEW channel $INCOMING_CHANNEL_ID IMPORTANCE_MAX")
        } else {
            Log.e("CALL_NOTI", "[CALL_NOTI] channel $INCOMING_CHANNEL_ID already exists")
        }

        if (nm.getNotificationChannel(ONGOING_CHANNEL_ID) == null) {
            nm.createNotificationChannel(NotificationChannel(
                ONGOING_CHANNEL_ID, "Ongoing Calls", NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                setSound(null, null)
                setSound(null, null)
                enableVibration(false)
            })
        }
    }

    // ==================================================
    //  Route 2 ONLY: heads-up notification
    //  CallStyle.forIncomingCall + FSI for heads-up retention
    //  Answer 버튼 → NativeIncomingCallActivity (Q3=생략, 직행)
    // ==================================================

    fun showHeadsUpNotification(
        context: Context,
        sessionId: String,
        callerId: String,
        callerName: String,
        callType: String,
        callerPhoto: String?,
        agoraFlag: Boolean = true,  // Eggplant default true (always Agora)
        channelName: String = "",   // Eggplant: Agora 채널명 (FCM payload)
        walletAddress: String = "", // Eggplant: 본인 지갑주소 (보통 비움 → NativeIncomingCallActivity 가 SP fallback)
    ) {
        ensureChannels(context)

        val answerPi = makeAnswerPendingIntent(context, sessionId, callerId, callerName, callType, callerPhoto, agoraFlag, channelName, walletAddress)
        val rejectPi = makeRejectPendingIntent(context, sessionId, callerId, callerName)

        val typeText = if (callType == "video") "Video Call" else "Voice Call"

        val builder = NotificationCompat.Builder(context, INCOMING_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setTimeoutAfter(30_000)
            .setOnlyAlertOnce(false)

        // 카톡 정확 방식: FSI 를 헤드업 30초 강제 유지용으로 함께 설정
        // 잠금 해제 상태이므로 OS 가 FSI 자동 실행 안 함 — heads-up 강제 유지 신호로만 작동
        try {
            val fsi = makeFullScreenPendingIntent(
                context, sessionId, callerId, callerName, callType, callerPhoto, agoraFlag, channelName, walletAddress
            )
            builder.setFullScreenIntent(fsi, true)
            Log.e("CALL_NOTI", "[CALL_NOTI] FSI attached for heads-up retention")
        } catch (e: Exception) {
            Log.e("CALL_NOTI", "[CALL_NOTI] FSI attach failed: ${e.message}")
        }

        if (Build.VERSION.SDK_INT >= 31) {
            // Android 12+ : 공식 CallStyle — OS 가 통화 헤드업을 30초 우선 유지 (카톡 방식)
            val caller = Person.Builder()
                .setName(callerName)
                .setImportant(true)
                .build()
            builder.setStyle(
                NotificationCompat.CallStyle.forIncomingCall(caller, rejectPi, answerPi)
            )
            Log.e("CALL_NOTI", "[CALL_NOTI] CallStyle.forIncomingCall + FSI applied (sdk=${Build.VERSION.SDK_INT})")
        } else {
            // Fallback (Android 11 이하)
            builder.setContentTitle(callerName)
                .setContentText("$typeText incoming...")
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Reject", rejectPi)
                .addAction(android.R.drawable.sym_call_incoming, "Answer", answerPi)
            Log.e("CALL_NOTI", "[CALL_NOTI] legacy heads-up + FSI (sdk=${Build.VERSION.SDK_INT})")
        }

        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(INCOMING_NOTIFICATION_ID, builder.build())
            Log.e("CALL_NOTI", "[CALL_NOTI] heads-up shown session=$sessionId (30s guaranteed)")
        } catch (e: Exception) {
            Log.e("CALL_NOTI", "[CALL_NOTI] heads-up FAILED: ${e.message}")
        }
    }

    // ================================================================
    //  Route 3: 잠금/화면꺼짐 — FSI direct send (full-screen ONLY, NO heads-up)
    //
    //  카톡 정확한 방식:
    //    - 잠금 상태에서는 nm.notify() 자체를 호출하지 않음
    //    - FSI PendingIntent.send() 만 직접 호출 → NativeIncomingCallActivity 풀스크린 1개만 표시
    //    - 헤드업/CallStyle/일반 알림 모두 발사 0 (이중 노출 방지)
    //    - Route 2(잠금 해제 시) CallStyle 헤드업 30초 유지는 그대로 유지
    // ================================================================

    fun showHeadsUpWithFullScreenFallback(
        context: Context,
        sessionId: String,
        callerId: String,
        callerName: String,
        callType: String,
        callerPhoto: String?,
        agoraFlag: Boolean = true,  // Eggplant default true
        channelName: String = "",   // Eggplant: Agora 채널명 (FCM payload)
        walletAddress: String = "", // Eggplant: 본인 지갑주소
    ) {
        Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] lock-state route — full-screen ONLY (no heads-up) sessionId=$sessionId")

        ensureChannels(context)

        val fullScreenPi = makeFullScreenPendingIntent(
            context, sessionId, callerId, callerName, callType, callerPhoto, agoraFlag, channelName, walletAddress
        )

        // Android 14+ 전체 화면 알림 권한 런타임 체크 (Google Play 정책 준수)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val canUseFsi = if (Build.VERSION.SDK_INT >= 34) {
            try { nm.canUseFullScreenIntent() } catch (_: Throwable) { true }
        } else true
        Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] canUseFullScreenIntent=$canUseFsi sdk=${Build.VERSION.SDK_INT}")

        // 권한 거부 상태이면 시스템 설정 이동 알림 발사
        if (!canUseFsi && Build.VERSION.SDK_INT >= 34) {
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] ⚠️ FSI permission DENIED — sending settings deep-link notification")
            try {
                val settingsIntent = Intent(android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                    data = android.net.Uri.parse("package:${context.packageName}")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                val settingsPi = PendingIntent.getActivity(
                    context, 99, settingsIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val permissionRequestBuilder = NotificationCompat.Builder(context, INCOMING_CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.sym_call_incoming)
                    .setContentTitle("⚠️ 통화 수신 권한이 필요합니다")
                    .setContentText("$callerName 님으로부터 통화 수신 — 시스템 설정에서 '전체 화면 알림' 권한을 켜주세요")
                    .setStyle(NotificationCompat.BigTextStyle()
                        .bigText("Eggplant 가 잠금화면 통화 수신을 표시하려면 '전체 화면 알림' 권한이 필요합니다.\n\n탭하여 시스템 설정에서 권한을 켜주세요. (한 번만 설정하면 다시 묻지 않습니다)"))
                    .setPriority(NotificationCompat.PRIORITY_MAX)
                    .setCategory(NotificationCompat.CATEGORY_CALL)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setContentIntent(settingsPi)
                    .setAutoCancel(true)
                    .setOngoing(false)
                nm.notify(INCOMING_NOTIFICATION_ID, permissionRequestBuilder.build())
                Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] permission-request notification sent (deep-link to ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)")
            } catch (e: Exception) {
                Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] permission-request notification FAILED: ${e.message}")
            }
            return // FSI 권한 없으면 send() 시도하지 않음 (의미 없음)
        }

        // 핵심: FSI 직접 send. 헤드업/알림 발사 절대 없음.
        try {
            fullScreenPi.send()
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] ★ FSI direct send OK (full-screen only, NO heads-up) sessionId=$sessionId")
        } catch (e: Exception) {
            // FSI direct send 가 실패한 극히 드문 경우 (PendingIntent.CanceledException 등)
            // 이 경우만 fallback 으로 일반 알림 발사. CallStyle/헤드업 사용 안 함 (이중 노출 방지)
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] FSI direct send FAILED — fallback to plain notification: ${e.message}")
            try {
                val typeText = if (callType == "video") "Video Call" else "Voice Call"
                val fallbackBuilder = NotificationCompat.Builder(context, INCOMING_CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.sym_call_incoming)
                    .setContentTitle(callerName)
                    .setContentText("$typeText incoming...")
                    .setPriority(NotificationCompat.PRIORITY_HIGH) // PRIORITY_MAX 아님 — 헤드업 회피
                    .setCategory(NotificationCompat.CATEGORY_CALL)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setOngoing(true)
                    .setAutoCancel(false)
                    .setTimeoutAfter(30_000)
                    .setFullScreenIntent(fullScreenPi, true)
                    // CallStyle / addAction 모두 추가 안 함 — 이중 노출 방지
                nm.notify(INCOMING_NOTIFICATION_ID, fallbackBuilder.build())
                Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] fallback nm.notify() done (NO CallStyle, NO actions)")
            } catch (e2: Exception) {
                Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] fallback FAILED too: ${e2.message}")
            }
        }

        // 진단용 상태 로깅
        try {
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] state: locked=${km.isKeyguardLocked} screenOn=${pm.isInteractive} canUseFsi=$canUseFsi")
        } catch (_: Exception) {}
    }

    /**
     * FSI 타겟 = NativeIncomingCallActivity (순수 Kotlin Activity, Flutter 깨우지 않음)
     *
     * Eggplant Q3=생략 적용:
     *   수락 시: NativeIncomingCallActivity.onAnswerClicked → AgoraCallActivity 직행
     *   (NativeAcceptCallActivity 게이트 제거 — 채팅목록 flash 방지는 NativeIncomingCallActivity 자체가 담당)
     */
    private fun makeFullScreenPendingIntent(
        context: Context, sessionId: String, callerId: String,
        callerName: String, callType: String, callerPhoto: String?,
        agoraFlag: Boolean = true,
        channelName: String = "",
        walletAddress: String = "",
    ): PendingIntent {
        Log.e("CALL_ROUTE", "[CALL_ROUTE] makeFullScreenPendingIntent target=NativeIncomingCallActivity sessionId=$sessionId")
        val intent = Intent(context, NativeIncomingCallActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION
            putExtra("from_fullscreen_incoming", true)
            putExtra("sessionId", sessionId)
            putExtra("callerId", callerId)
            putExtra("callerNickname", callerName)
            putExtra("callType", callType)
            putExtra("callerProfilePhoto", callerPhoto ?: "")
            // Eggplant: 채널명 + 지갑주소 전파 (NativeIncomingCallActivity → AgoraCallActivity)
            if (channelName.isNotEmpty()) putExtra("channelName", channelName)
            if (walletAddress.isNotEmpty()) putExtra("walletAddress", walletAddress)
            // agora flag 전파 → NativeIncomingCallActivity.onAnswerClicked() 에서 AgoraCallActivity 직행
            if (agoraFlag) {
                putExtra("agora", "1")
                putExtra("agora_call", true)
            }
        }
        return PendingIntent.getActivity(
            context, 3, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /**
     * Eggplant Q3=생략: Answer PendingIntent 도 NativeIncomingCallActivity 로 직행
     * (NativeAcceptCallActivity 게이트 제거)
     *
     * NativeIncomingCallActivity.onCreate() 에서 from_headsup_answer=true 면 즉시 AgoraCallActivity 로 전환.
     */
    private fun makeAnswerPendingIntent(
        context: Context, sessionId: String, callerId: String,
        callerName: String, callType: String, callerPhoto: String?,
        agoraFlag: Boolean = true,
        channelName: String = "",
        walletAddress: String = "",
    ): PendingIntent {
        Log.e("CALL_ROUTE", "[CALL_ROUTE] makeAnswerPendingIntent target=NativeIncomingCallActivity (Q3=생략) sessionId=$sessionId")
        val intent = Intent(context, NativeIncomingCallActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("from_native_answer", true)
            putExtra("skip_flutter_ringing", true)
            putExtra("from_headsup_answer", true)
            putExtra("sessionId", sessionId)
            putExtra("callerId", callerId)
            putExtra("callerNickname", callerName)
            putExtra("callType", callType)
            putExtra("callerProfilePhoto", callerPhoto ?: "")
            // Eggplant: 채널명 + 지갑주소 전파
            if (channelName.isNotEmpty()) putExtra("channelName", channelName)
            if (walletAddress.isNotEmpty()) putExtra("walletAddress", walletAddress)
            if (agoraFlag) {
                putExtra("agora", "1")
                putExtra("agora_call", true)
            }
        }
        return PendingIntent.getActivity(
            context, 1, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun makeRejectPendingIntent(
        context: Context, sessionId: String, callerId: String, callerName: String
    ): PendingIntent {
        val intent = Intent(context, CallActionReceiver::class.java).apply {
            action = CallActionReceiver.ACTION_REJECT
            putExtra("sessionId", sessionId)
            putExtra("callerId", callerId)
            putExtra("callerNickname", callerName)
        }
        return PendingIntent.getBroadcast(
            context, 2, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    // ==================================================
    //  Cancel notifications
    // ==================================================

    fun cancelIncomingCallNotification(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(INCOMING_NOTIFICATION_ID)
        Log.e("CALL_ACTION", "[CALL_ACTION] incoming notification cancelled")
    }

    fun cancelOngoingCallNotification(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(ONGOING_NOTIFICATION_ID)
    }

    fun cleanupIncomingState(context: Context, sessionId: String = "") {
        stopRingtone()
        cancelIncomingCallNotification(context)
        clearNativeIncomingActive(context)
        Log.e("CALL_ACTION", "[CALL_ACTION] cleanupIncomingState session=$sessionId")
    }

    // ==================================================
    //  Ringtone
    // ==================================================

    fun startRingtoneImmediately(context: Context, sessionId: String = "") {
        if (isRingtoneActive) {
            Log.e("CALL_RING", "[CALL_RING] already playing -- skip session=$sessionId")
            return
        }
        isRingtoneActive = true
        Log.e("CALL_RING", "[CALL_RING] start session=$sessionId")
        mainHandler.post { startRingtoneOnMainThread(context.applicationContext, sessionId) }
        startVibration(context.applicationContext)
    }

    private fun startRingtoneOnMainThread(context: Context, sessionId: String) {
        stopMediaPlayerOnly()
        try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManagerRef = am
            var focusGranted = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                    .setAudioAttributes(attrs)
                    .setOnAudioFocusChangeListener {}.build()
                audioFocusRequest = req
                focusGranted = am.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } else {
                @Suppress("DEPRECATION")
                focusGranted = am.requestAudioFocus(null, AudioManager.STREAM_RING,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
            if (focusGranted) startWithMediaPlayer(context, sessionId)
            else startWithRingtoneManager(context, sessionId)
        } catch (e: Exception) {
            Log.e("CALL_RING", "[CALL_RING] FAILED: ${e.message}")
            try { startWithRingtoneManager(context, sessionId) } catch (_: Exception) { isRingtoneActive = false }
        }
    }

    private fun startWithMediaPlayer(context: Context, sessionId: String) {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        mediaPlayer = MediaPlayer().apply {
            setDataSource(context, uri)
            setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setLegacyStreamType(AudioManager.STREAM_RING).build())
            isLooping = true; prepare(); start()
        }
        Log.e("CALL_RING", "[CALL_RING] MediaPlayer started session=$sessionId")
    }

    private fun startWithRingtoneManager(context: Context, sessionId: String) {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val rt = RingtoneManager.getRingtone(context, uri)
        if (rt != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) rt.isLooping = true
            rt.play(); fallbackRingtone = rt
            Log.e("CALL_RING", "[CALL_RING] RingtoneManager started session=$sessionId")
        } else { isRingtoneActive = false }
    }

    fun stopRingtone() {
        if (!isRingtoneActive) return
        isRingtoneActive = false
        // 이중 벨소리 제거 — 동기로 즉시 정지 (main thread에서 호출 가능)
        if (Looper.myLooper() == Looper.getMainLooper()) {
            stopMediaPlayerOnly()
            stopFallbackRingtone()
            abandonAudioFocus()
        } else {
            mainHandler.post { stopMediaPlayerOnly(); stopFallbackRingtone(); abandonAudioFocus() }
        }
        stopVibration()
        Log.e("CALL_RING", "[CALL_RING] stopped (sync on main thread)")
    }

    private fun stopMediaPlayerOnly() {
        try { mediaPlayer?.let { if (it.isPlaying) it.stop(); it.reset(); it.release() } } catch (_: Exception) {}
        mediaPlayer = null
    }
    private fun stopFallbackRingtone() {
        try { fallbackRingtone?.let { if (it.isPlaying) it.stop() } } catch (_: Exception) {}
        fallbackRingtone = null
    }
    private fun abandonAudioFocus() {
        try {
            val am = audioManagerRef
            if (am != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
        } catch (_: Exception) {}
        audioFocusRequest = null; audioManagerRef = null
    }

    // ==================================================
    //  Vibration
    // ==================================================

    private fun startVibration(context: Context) {
        try {
            val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            vibrator = vib
            val pattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
            else @Suppress("DEPRECATION") vib.vibrate(pattern, 0)
        } catch (_: Exception) {}
    }

    private fun stopVibration() {
        try { vibrator?.cancel(); vibrator = null } catch (_: Exception) {}
    }
}
