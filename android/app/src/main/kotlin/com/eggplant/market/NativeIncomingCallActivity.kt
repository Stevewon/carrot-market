package com.eggplant.market

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.app.Activity

/**
 * Eggplant v1.0.142 — Native full-screen incoming call UI.
 *
 * Q3=생략 적용 (NativeAcceptCallActivity 게이트 제거):
 *   - heads-up Answer / FSI Answer 모두 → 이 Activity → 즉시 AgoraCallActivity.start() 직행
 *   - agoraFlag default = true (Eggplant 는 항상 Agora 통화)
 *   - Legacy MainActivity 경유 분기 제거 (Flutter 채팅목록 flash 방지)
 *
 * 잠금화면 동작 (카톡 방식):
 *   - setShowWhenLocked(true) — 잠금 위에 이 Activity 만 그림
 *   - setTurnScreenOn(true) — 화면 꺼짐 시 켬
 *   - FLAG_DISMISS_KEYGUARD 미사용 — 잠금은 건드리지 않음 (HomeScreen flash 방지)
 *
 * 수락 1번 = 최종 수락. 두 번째 수신화면 없음.
 *
 * FORBIDDEN:
 *   - 수락 후 또 다른 수신화면 열기
 *   - 수락 후 Flutter IncomingCallScreen 재진입
 *   - 수락 후 알림만 닫고 끝내기
 *   - extras 부족하다고 finish() (기본값으로 UI 표시)
 */
class NativeIncomingCallActivity : Activity() {

    companion object {
        private const val TAG = "CALL_FULLSCREEN"
        // 발신자가 통화를 끊으면 이 broadcast 로 수신화면을 종료.
        // EggplantFirebaseMessagingService 가 call_cancel/call_end FCM 을 받으면 송신.
        const val ACTION_CANCEL_INCOMING = "com.eggplant.market.CANCEL_INCOMING"
        const val EXTRA_SESSION_ID = "sessionId"
    }

    private var sessionId = ""
    private var callerId = ""
    private var callerName = ""
    private var callType = "audio"
    private var callerPhoto = ""
    // Eggplant: agoraFlag default true (항상 Agora 통화)
    private var agoraFlag = true

    // Eggplant: Agora 채널명 + 본인 지갑주소 (FCM payload 또는 SharedPreferences fallback)
    private var channelName = ""
    private var walletAddress = ""

    // 35초 WakeLock — 수신 타임아웃(30초)보다 약간 길게
    private var wakeLock: PowerManager.WakeLock? = null

    // 발신자가 끊었을 때 수신화면 자동 종료용 BroadcastReceiver
    private var cancelReceiver: BroadcastReceiver? = null

    // 안전망 타임아웃 — Cloud Function 미배포/실패 시에도 35초 후 자동 종료
    private val timeoutHandler = Handler(Looper.getMainLooper())
    private val timeoutRunnable = Runnable {
        Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] safety timeout (35s) — auto-finish session=$sessionId")
        try {
            CallNotificationHelper.cleanupIncomingState(this, sessionId)
        } catch (_: Exception) {}
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ======= 1. Lock-screen / wake flags (카톡 방식) =======
        // setShowWhenLocked(true) — 잠금 위에 이 Activity만 그림
        // setTurnScreenOn(true) — 화면 꺼짐 시 켬
        // FLAG_DISMISS_KEYGUARD 제거 — 잠금은 안 건드림 (수락 시 자연스럽게 해제)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        // 공통 레거시 플래그: 화면 유지만, 잠금 해제는 안 함
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )

        // ======= 2. Keyguard 는 건드리지 않음 (카톡 방식) =======
        try {
            val km = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] keyguard NOT dismissed (locked=${km.isKeyguardLocked})")
        } catch (e: Exception) {
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] keyguard query failed: ${e.message}")
        }

        // ======= 3. WakeLock 획득 =======
        // 35초 WakeLock — 수신 타임아웃(30초)보다 약간 길게
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            wakeLock = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "eggplant:IncomingCallWakeLock"
            ).also { it.acquire(35_000L) }
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] WakeLock acquired (35s)")
        } catch (e: Exception) {
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] WakeLock acquire failed: ${e.message}")
        }

        // ======= Extract extras =======
        // extras 부족해도 finish() 금지 — 기본값으로 UI 표시
        sessionId = intent.getStringExtra("sessionId") ?: ""
        callerId = intent.getStringExtra("callerId") ?: ""
        callerName = intent.getStringExtra("callerNickname")
            ?: intent.getStringExtra("callerName") ?: "Unknown"
        callType = intent.getStringExtra("callType") ?: "audio"
        callerPhoto = intent.getStringExtra("callerProfilePhoto")
            ?: intent.getStringExtra("callerPhoto") ?: ""
        // Eggplant: agora=1 또는 agora_call=true 면 native AgoraCallActivity 로 진입 (default=true)
        // Q3=생략으로 모든 경로가 Agora 직행 — agora extra 가 명시적으로 false 인 경우만 비활성화
        val agoraExplicit = intent.getStringExtra("agora") == "1" ||
                            intent.getBooleanExtra("agora_call", false)
        // Eggplant: agora extra 가 없어도 default true (항상 Agora)
        agoraFlag = agoraExplicit || (
            !intent.hasExtra("agora") && !intent.hasExtra("agora_call")
        )

        // Eggplant: 채널명 + 지갑주소 (FCM payload 에서 채널 직접 전달)
        channelName = intent.getStringExtra("channelName")
            ?: intent.getStringExtra("channel") ?: ""
        walletAddress = intent.getStringExtra("walletAddress") ?: ""
        // walletAddress 누락 시 SharedPreferences fallback (수신자 본인 지갑)
        if (walletAddress.isEmpty()) {
            walletAddress = AgoraTokenService.readWalletAddress(this)
        }

        Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] IncomingCallActivity onCreate sessionId=$sessionId caller=$callerName type=$callType channel=$channelName walletEmpty=${walletAddress.isEmpty()}")
        Log.e(TAG, "[CALL_FULLSCREEN] onCreate sessionId=$sessionId caller=$callerName type=$callType")

        // 발신자가 끊었을 때 수신화면 자동 종료를 위한 receiver
        cancelReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                val targetSession = intent?.getStringExtra(EXTRA_SESSION_ID) ?: ""
                Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] cancel broadcast received targetSession=$targetSession current=$sessionId")
                // 같은 세션이거나 빈 sessionId 면 (안전하게) 종료
                if (targetSession.isEmpty() || targetSession == sessionId) {
                    try {
                        CallNotificationHelper.stopRingtone()
                        CallNotificationHelper.cancelIncomingCallNotification(this@NativeIncomingCallActivity)
                        CallNotificationHelper.cleanupIncomingState(this@NativeIncomingCallActivity, sessionId)
                    } catch (e: Exception) {
                        Log.e(TAG, "[CALL_FULLSCREEN] cancel cleanup failed: ${e.message}")
                    }
                    finish()
                }
            }
        }
        try {
            val filter = IntentFilter(ACTION_CANCEL_INCOMING)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(cancelReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(cancelReceiver, filter)
            }
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] cancelReceiver registered for $ACTION_CANCEL_INCOMING")
        } catch (e: Exception) {
            Log.e(TAG, "[CALL_FULLSCREEN] cancelReceiver register failed: ${e.message}")
        }

        // 35초 안전 타임아웃 등록 — 서버 cancel push 실패해도 화면이 영원히 떠있지 않도록
        timeoutHandler.postDelayed(timeoutRunnable, 35_000L)

        // 진단용: 어떤 경로로 실행됐는지
        val launchedFromNotification = intent.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0
        Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] launched from system fullScreenIntent or direct startActivity (newTask=$launchedFromNotification)")

        // ★★★ Q3=생략: heads-up Answer 경로(from_headsup_answer=true)인 경우
        //   기존 QRChat 은 NativeAcceptCallActivity 게이트로 가서 cleanup + flag + pending 저장 후
        //   MainActivity 로 갔지만, Eggplant 는 그 게이트를 제거했음.
        //   이 Activity 자체가 cleanup + flag + pending 을 모두 담당하고 즉시 onAnswerClicked() 실행.
        val fromHeadsupAnswer = intent.getBooleanExtra("from_headsup_answer", false) ||
                                intent.getBooleanExtra("from_native_answer", false)
        if (fromHeadsupAnswer) {
            Log.e(TAG, "[CALL_FULLSCREEN] Q3=생략: from_headsup_answer=true → onAnswerClicked() 즉시 실행 (UI skip)")
            // UI 빌드를 건너뛰고 즉시 수락 처리
            onAnswerClicked()
            return
        }

        // ======= Build UI programmatically (FSI 경로 — heads-up 아닌 풀스크린 진입) =======
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            // 진한 퍼플 → 다크 네이비 그라데이션 느낌의 단색 배경
            setBackgroundColor(Color.parseColor("#1A1A2E"))
            setPadding(48, 160, 48, 160)
        }

        val typeText = if (callType == "video") "📹 영상통화" else "📞 음성통화"

        val typeLabel = TextView(this).apply {
            text = typeText
            textSize = 20f
            setTextColor(Color.parseColor("#AAB8FF"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 16)
        }
        layout.addView(typeLabel)

        val statusLabel = TextView(this).apply {
            text = "걸려오는 전화"
            textSize = 16f
            setTextColor(Color.parseColor("#8892B0"))
            gravity = Gravity.CENTER
        }
        layout.addView(statusLabel)

        val nameLabel = TextView(this).apply {
            text = callerName
            textSize = 36f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 64, 0, 32)
            setTypeface(null, android.graphics.Typeface.BOLD)
        }
        layout.addView(nameLabel)

        val appLabel = TextView(this).apply {
            text = "Eggplant"
            textSize = 14f
            setTextColor(Color.parseColor("#6A5AE0"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 96)
        }
        layout.addView(appLabel)

        val buttonRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, 48, 0, 0)
        }

        val rejectBtn = Button(this).apply {
            text = "거절"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#E53935"))
            setPadding(64, 40, 64, 40)
            textSize = 18f
            setTypeface(null, android.graphics.Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(24, 0, 24, 0) }
            setOnClickListener { onRejectClicked() }
        }
        buttonRow.addView(rejectBtn)

        val answerBtn = Button(this).apply {
            text = "수락"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#43A047"))
            setPadding(64, 40, 64, 40)
            textSize = 18f
            setTypeface(null, android.graphics.Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(24, 0, 24, 0) }
            setOnClickListener { onAnswerClicked() }
        }
        buttonRow.addView(answerBtn)

        layout.addView(buttonRow)
        setContentView(layout)
    }

    /**
     * heads-up Answer 를 통한 수락이 이미 진행 중이면 이 Activity 는 즉시 종료.
     *
     * Q3=생략 환경에서도 일부 OEM 이 heads-up + FSI 동시 트리거할 가능성이 있어 이중 안전장치 유지.
     * MainActivity.nativeAnswerInProgress=true 이면 다른 경로에서 이미 수락 처리 중이므로 finish.
     */
    override fun onStart() {
        super.onStart()
        if (MainActivity.nativeAnswerInProgress) {
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] NativeIncomingCallActivity.onStart: " +
                    "nativeAnswerInProgress=true (answer already in flight) → auto-finish")
            finish()
        }
    }

    /**
     * Eggplant Q3=생략: 수락 1번 = 즉시 AgoraCallActivity.start() 직행.
     *
     * 동작 순서:
     *   1. stopRingtone -> 즉시 벨소리 중지
     *   2. cancelIncomingCallNotification -> FSI 알림 제거
     *   3. cleanupIncomingState -> ringing 상태 정리
     *   4. savePendingNativeAnswer -> SharedPreferences (cold-start 방어, MainActivity 가 깨어나면 소비)
     *   5. nativeAnswerInProgress = true -> Flutter IncomingCallScreen 차단
     *   6. AgoraCallActivity.start() -> 즉시 통화 화면 (Flutter 안 깨움)
     *   7. finish() -> 이 Activity 종료
     *
     * 절대 금지:
     *   - 수락 후 또 다른 수신화면 열기
     *   - 수락 후 Flutter IncomingCallScreen 재진입
     */
    private fun onAnswerClicked() {
        Log.e(TAG, "[CALL_FULLSCREEN] answer tapped sessionId=$sessionId")
        Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] answer tapped sessionId=$sessionId")

        // 1. Stop ringtone
        CallNotificationHelper.stopRingtone()

        // 2. Cancel incoming notification (if any)
        CallNotificationHelper.cancelIncomingCallNotification(this)

        // 3. Clear ringing state
        CallNotificationHelper.cleanupIncomingState(this, sessionId)

        // 4. Save pending native answer -> SharedPreferences (cold-start 방어)
        //    MainActivity 가 다른 시점에 깨어나면 이 데이터를 소비해 Flutter 측 상태 동기화
        CallNotificationHelper.savePendingNativeAnswer(
            context = this,
            sessionId = sessionId,
            callerId = callerId,
            callerNickname = callerName,
            callType = callType,
            callerProfilePhoto = callerPhoto
        )

        // 5. Block Flutter ringing UI re-entry + set pending data
        //    flag와 pendingData를 BEFORE AgoraCallActivity 실행 시점에 설정.
        MainActivity.nativeAnswerInProgress = true
        MainActivity.pendingNativeAnswerData = mapOf(
            "sessionId" to sessionId,
            "callerId" to callerId,
            "callerNickname" to callerName,
            "callType" to callType,
            "callerProfilePhoto" to callerPhoto
        )

        // 6. Q3=생략: 항상 AgoraCallActivity 직행 (Flutter 미경유)
        //   Eggplant 는 채널명 + 본인 지갑주소를 추가로 전달
        Log.e(TAG, "[CALL_FULLSCREEN] AgoraCallActivity direct launch sessionId=$sessionId channel=$channelName walletEmpty=${walletAddress.isEmpty()}")
        AgoraCallActivity.start(
            context = this,
            sessionId = sessionId,
            channelName = channelName,
            walletAddress = walletAddress,
            callerId = callerId,
            callerNickname = callerName,
            callType = callType,
            callerPhoto = callerPhoto,
            isIncoming = true,
        )

        // 7. Finish this activity (no second UI)
        finish()
    }

    private fun onRejectClicked() {
        Log.e(TAG, "[CALL_FULLSCREEN] reject tapped sessionId=$sessionId")
        Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] reject tapped sessionId=$sessionId")

        CallNotificationHelper.stopRingtone()
        CallNotificationHelper.cancelIncomingCallNotification(this)
        CallNotificationHelper.cleanupIncomingState(this, sessionId)

        // MainActivity 로 reject 신호 전달 — Flutter MethodChannel 이 WebSocket call_response(rejected) 송신
        try {
            val rejectIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("reject_call_from_native", true)
                putExtra("sessionId", sessionId)
            }
            startActivity(rejectIntent)
            Log.e(TAG, "[CALL_FULLSCREEN] MainActivity launched for reject sessionId=$sessionId")
        } catch (e: Exception) {
            Log.e(TAG, "[CALL_FULLSCREEN] reject launch failed: ${e.message}")
            // Fallback: broadcast (Eggplant package)
            val rejectBroadcast = Intent("com.eggplant.market.CALL_ACTION").apply {
                setPackage(packageName)
                putExtra("action", "reject")
                putExtra("sessionId", sessionId)
            }
            sendBroadcast(rejectBroadcast)
        }

        finish()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // Block back press -- user must answer or reject
    }

    // WakeLock 정리 — 수신 UI 가 사라질 때 확실히 풀어 배터리 누수 방지
    override fun onDestroy() {
        super.onDestroy()
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] WakeLock released (onDestroy)")
                }
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] WakeLock release failed: ${e.message}")
        }

        // cancelReceiver 정리
        try {
            cancelReceiver?.let { unregisterReceiver(it) }
            cancelReceiver = null
        } catch (e: Exception) {
            Log.e(TAG, "[CALL_FULLSCREEN] cancelReceiver unregister failed: ${e.message}")
        }
        // 안전망 타임아웃 취소
        try {
            timeoutHandler.removeCallbacks(timeoutRunnable)
        } catch (_: Exception) {}
    }
}
