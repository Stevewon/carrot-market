package com.eggplant.market

import android.Manifest
import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import io.agora.rtc2.video.VideoCanvas

/**
 * ★★★ v1.0.142: Native (Kotlin-only) Agora 통화 Activity — Eggplant 어댑트.
 *
 * 큐알쳇 v4.0.270 AgoraCallActivity 를 에그플랜트로 포팅:
 *   - package: io.qrchat.app → com.eggplant.market
 *   - EXTRA_CHANNEL_NAME, EXTRA_WALLET_ADDRESS 추가 (Agora joinCall 에 전달)
 *   - SharedPreferences "qrchat_call_audio" → "eggplant_call_audio"
 *   - WakeLock 태그/HandlerThread 이름: qrchat → eggplant
 *
 * 핵심 원칙:
 *   1. Flutter 엔진 절대 깨우지 않음 (MainActivity 미경유)
 *   2. 잠금화면 위에 직접 표시 (setShowWhenLocked + setTurnScreenOn)
 *   3. AgoraCallManager 를 통해 Agora 채널 입장 → 미디어 P2P/Cloud Relay
 *   4. 통화 데이터 zero 정책: 통화 종료 시 모든 메모리 데이터 폐기
 *
 * 진입 방법 (Eggplant v1.0.142):
 *   - NativeIncomingCallActivity.onAnswerClicked() → AgoraCallActivity (수신측)
 *   - 발신측은 Flutter CallScreen 그대로 (A1 정책 — 사장님 결정)
 *
 * 화면 구성:
 *   - 상태 텍스트 (연결 중 / 통화 중 / 종료됨)
 *   - 발신자 이름
 *   - 통화 시간 타이머
 *   - 영상 통화일 때 원격/로컬 비디오 표시 영역
 *   - 컨트롤 버튼: 음소거, 스피커, (영상 시) 카메라 on/off, 카메라 전환, 끊기
 */
class AgoraCallActivity : Activity(), AgoraCallManager.CallListener {

    companion object {
        private const val TAG = "AGORA_CALL_UI"

        // Intent extras
        const val EXTRA_SESSION_ID = "sessionId"
        const val EXTRA_CALLER_ID = "callerId"
        const val EXTRA_CALLER_NICKNAME = "callerNickname"
        const val EXTRA_CALL_TYPE = "callType"
        const val EXTRA_CALLER_PHOTO = "callerProfilePhoto"
        const val EXTRA_IS_INCOMING = "isIncoming"
        // ★★★ Eggplant: FCM 페이로드에서 받은 channel 명 (sortedWalletPair 기반)
        const val EXTRA_CHANNEL_NAME = "channelName"
        // ★★★ Eggplant: 본인 지갑 주소 (uid 결정론적 생성용)
        const val EXTRA_WALLET_ADDRESS = "walletAddress"

        /**
         * AgoraCallActivity 시작 헬퍼 — Eggplant 버전.
         *
         * @param context 호출 컨텍스트
         * @param sessionId 통화 세션 UUID (양쪽 동일, 추적용)
         * @param channelName Agora 채널명 (eggplant_call_<sortedLowerWalletPair>)
         * @param walletAddress 본인 지갑 주소 (uid 생성용)
         * @param callerId 발신자 ID (UI 표시용, 메모리만)
         * @param callerNickname 발신자 닉네임 (UI 표시용, 메모리만)
         * @param callType "audio" or "video"
         * @param callerPhoto 발신자 프로필 사진 URL (선택)
         * @param isIncoming 발신/수신 구분 (기본 true=수신)
         */
        @JvmStatic
        @JvmOverloads
        fun start(
            context: Context,
            sessionId: String,
            channelName: String,
            walletAddress: String,
            callerId: String,
            callerNickname: String,
            callType: String,
            callerPhoto: String = "",
            isIncoming: Boolean = true,
        ) {
            val intent = Intent(context, AgoraCallActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_SESSION_ID, sessionId)
                putExtra(EXTRA_CHANNEL_NAME, channelName)
                putExtra(EXTRA_WALLET_ADDRESS, walletAddress)
                putExtra(EXTRA_CALLER_ID, callerId)
                putExtra(EXTRA_CALLER_NICKNAME, callerNickname)
                putExtra(EXTRA_CALL_TYPE, callType)
                putExtra(EXTRA_CALLER_PHOTO, callerPhoto)
                putExtra(EXTRA_IS_INCOMING, isIncoming)
            }
            context.startActivity(intent)
        }
    }

    // ======= Call session data (메모리 only) =======
    private var sessionId = ""
    private var channelName = ""
    private var walletAddress = ""
    private var callerId = ""
    private var callerNickname = ""
    private var callType = "audio"
    private var callerPhoto = ""
    private var isIncoming = true

    // 통화 시작 시점에 Eggplant MainActivity 가 이미 살아있었는지 기록
    //   true  : 사용자가 에그플랜트 안에 있다가 통화 → 종료 후 기존 화면 복귀
    //   false : 외부 앱 또는 콜드 스타트에서 받음 → 종료 후 task 만 백그라운드,
    //           OS 가 사용자가 통화 직전 보던 화면으로 자연스럽게 복귀
    private var eggplantWasAlive = false

    // ======= UI =======
    private lateinit var rootView: FrameLayout
    private lateinit var remoteVideoContainer: FrameLayout
    private lateinit var localVideoContainer: FrameLayout
    private lateinit var statusText: TextView
    private lateinit var nameText: TextView
    private lateinit var timerText: TextView
    private lateinit var muteButton: LinearLayout
    private lateinit var speakerButton: LinearLayout
    private lateinit var cameraButton: LinearLayout
    private lateinit var switchCameraButton: LinearLayout
    private lateinit var endButton: LinearLayout
    // 음성통화 중 → 영상통화 전환 버튼 (callType=audio 일 때만 추가)
    private var upgradeToVideoButton: LinearLayout? = null
    private lateinit var muteIcon: TextView
    private lateinit var speakerIcon: TextView
    private lateinit var cameraIcon: TextView

    // 카메라 OFF 시 영상 컨테이너 위에 덮어 마지막 프레임을 가리는 검정 오버레이
    private var localBlackOverlay: View? = null
    private var remoteBlackOverlay: View? = null

    // ======= State =======
    private var isMuted = false
    private var isSpeakerOn = false
    private var isCameraOn = true
    private var isRemoteCameraOn = true
    private var callStartedAtMs: Long = 0L
    private var remoteJoined = false
    // 영상통화 스왑 — false=remote 풀스크린/local PIP (기본),
    //   true=local 풀스크린/remote PIP. 메인 화면 탭으로 토글.
    private var isVideoSwapped = false
    private var lastRemoteUid: Int = 0

    // 발신음(ringback tone) — 발신측에서만 재생, 상대방 join 시 자동 정지
    private var ringbackTone: ToneGenerator? = null

    // ======= WakeLock + timer =======
    private var wakeLock: PowerManager.WakeLock? = null
    /** 화면 OFF 후에도 CPU 깨워두는 통화용 PARTIAL WakeLock */
    private var cpuWakeLock: PowerManager.WakeLock? = null
    private val timerHandler = Handler(Looper.getMainLooper())
    private val timerRunnable = object : Runnable {
        override fun run() {
            updateTimer()
            timerHandler.postDelayed(this, 1000)
        }
    }

    // 외부 시작 케이스 전용 마이크 보강 워치독 (큐알쳇 v4.0.180 패턴)
    private var micGuardThread: android.os.HandlerThread? = null
    private var micGuardHandler: Handler? = null
    private val micGuardRunnable = object : Runnable {
        override fun run() {
            try {
                AgoraCallManager.ensureMicAlive()
                Log.e(TAG, "[AGORA_CALL_UI] ext-mic-guard tick (ensureMicAlive)")
            } catch (e: Exception) {
                Log.e(TAG, "[AGORA_CALL_UI] ext-mic-guard error: ${e.message}")
            }
            micGuardHandler?.postDelayed(this, 5_000L)
        }
    }

    // Connection timeout (15s)
    private val connectTimeoutHandler = Handler(Looper.getMainLooper())
    private val connectTimeoutRunnable = Runnable {
        if (!remoteJoined) {
            Log.w(TAG, "[AGORA_CALL_UI] connect timeout — remote did not join in 15s")
            statusText.text = "연결 실패 — 상대방 응답 없음"
            timerHandler.postDelayed({ finishCall() }, 5000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. Lock-screen / wake flags (NativeIncomingCallActivity 와 동일 패턴)
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
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )

        // 2. 카톡 방식 — Keyguard 는 절대 건드리지 않음 (잠금 위에 통화 UI 만 표시)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            try {
                val km = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
                Log.e(TAG, "[AGORA_CALL_UI] keyguard NOT dismissed (locked=${km.isKeyguardLocked})")
            } catch (e: Exception) {
                Log.e(TAG, "[AGORA_CALL_UI] keyguard query failed: ${e.message}")
            }
        }

        // 3. WakeLock — 통화 중 화면 유지
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            wakeLock = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                "eggplant:agora_call_screen"
            )
            wakeLock?.acquire(60 * 60 * 1000L)  // 1시간 안전망

            // 추가 PARTIAL WakeLock — 화면 꺼져도 CPU 는 깨어 있어야 마이크 캡처 안 끊김
            cpuWakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "eggplant:agora_call_cpu"
            )
            cpuWakeLock?.setReferenceCounted(false)
            cpuWakeLock?.acquire(60 * 60 * 1000L)
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] WakeLock acquire failed: ${e.message}")
        }

        // 4. Read intent extras
        sessionId = intent.getStringExtra(EXTRA_SESSION_ID) ?: ""
        channelName = intent.getStringExtra(EXTRA_CHANNEL_NAME) ?: ""
        walletAddress = intent.getStringExtra(EXTRA_WALLET_ADDRESS) ?: ""
        callerId = intent.getStringExtra(EXTRA_CALLER_ID) ?: ""
        callerNickname = intent.getStringExtra(EXTRA_CALLER_NICKNAME) ?: "통화 중"
        callType = intent.getStringExtra(EXTRA_CALL_TYPE) ?: "audio"
        callerPhoto = intent.getStringExtra(EXTRA_CALLER_PHOTO) ?: ""
        isIncoming = intent.getBooleanExtra(EXTRA_IS_INCOMING, true)

        // ★★★ Eggplant: 본인 지갑 주소가 비었으면 SharedPreferences 에서 자동 보충
        // ★ v1.0.142: AgoraTokenService.readWalletAddress 가 non-null String 반환으로
        //   변경됨 (이전 String? → String, 비어있으면 ""). Elvis 연산자 제거.
        if (walletAddress.isEmpty()) {
            walletAddress = AgoraTokenService.readWalletAddress(this)
            Log.d(TAG, "[AGORA_CALL_UI] walletAddress auto-loaded from prefs (empty=${walletAddress.isEmpty()})")
        }

        // Eggplant MainActivity 가 통화 시작 시점에 이미 살아있었는지 기록
        eggplantWasAlive = try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val tasks = am.appTasks
            var found = false
            for (t in tasks) {
                val info = t.taskInfo
                val baseName = info.baseActivity?.className ?: ""
                val topName = info.topActivity?.className ?: ""
                if ((baseName.endsWith("MainActivity") || topName.endsWith("MainActivity")) &&
                    info.numActivities >= 1
                ) {
                    found = true
                    break
                }
            }
            Log.e(TAG, "[AGORA_CALL_UI] eggplantWasAlive=$found (tasks=${tasks.size})")
            found
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] eggplantWasAlive detect failed: ${e.message}")
            true
        }

        Log.d(
            TAG,
            "[AGORA_CALL_UI] onCreate sessionLen=${sessionId.length} chLen=${channelName.length} type=$callType isIncoming=$isIncoming eggplantWasAlive=$eggplantWasAlive",
        )

        // CallForegroundService 직접 시작 — Android 15 환경에서 ForegroundService(microphone) 없이는
        //   화면 OFF + 책상 시나리오에서 OS 가 마이크 캡처를 끊음.
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            // 스피커 상태를 SharedPreferences 에 미리 동기화 (서비스가 acquireAudioFocus 에서 읽음)
            getSharedPreferences("eggplant_call_audio", MODE_PRIVATE)
                .edit()
                .putBoolean("speaker_on", audioManager.isSpeakerphoneOn || callType == "video")
                .apply()
            CallForegroundService.start(this, callerNickname, callType)
            Log.e(TAG, "[AGORA_CALL_UI] CallForegroundService.start() 호출")
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] CallForegroundService.start FAILED: ${e.message}")
        }

        // 5. Build UI
        buildUi()

        // 6. Validate sessionId / channelName — 비었으면 즉시 종료
        if (sessionId.isEmpty()) {
            Log.e(TAG, "[AGORA_CALL_UI] sessionId is empty — finishing")
            statusText.text = "잘못된 통화 요청"
            timerHandler.postDelayed({ finishCall() }, 2000)
            return
        }
        if (channelName.isEmpty()) {
            Log.e(TAG, "[AGORA_CALL_UI] channelName is empty — finishing")
            statusText.text = "통화 채널 정보 없음"
            timerHandler.postDelayed({ finishCall() }, 2000)
            return
        }
        if (walletAddress.isEmpty()) {
            Log.e(TAG, "[AGORA_CALL_UI] walletAddress is empty — finishing (인증 필요)")
            statusText.text = "로그인 필요"
            timerHandler.postDelayed({ finishCall() }, 2000)
            return
        }

        // 권한 체크 — 다이얼로그 안 띄우고 토스트+종료 (로그인 시점에 받아둔 권한에만 의존)
        val micGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        if (!micGranted) {
            Log.e(TAG, "[AGORA_CALL_UI] RECORD_AUDIO 권한 없음 — 통화 종료")
            Toast.makeText(
                this,
                "마이크 권한이 없어 통화할 수 없습니다.\n설정 > 앱 > Eggplant > 권한 에서 허용해 주세요.",
                Toast.LENGTH_LONG,
            ).show()
            timerHandler.postDelayed({ finishCall() }, 2000)
            return
        }
        if (callType == "video") {
            val camGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                    PackageManager.PERMISSION_GRANTED
            if (!camGranted) {
                Log.e(TAG, "[AGORA_CALL_UI] CAMERA 권한 없음 — 음성통화로 강등")
                Toast.makeText(
                    this,
                    "카메라 권한이 없어 음성통화로 진행합니다.",
                    Toast.LENGTH_SHORT,
                ).show()
                callType = "audio"
            }
        }

        startCallFlow()
    }

    /**
     * 권한 확보 후 실제 Agora 채널 입장.
     */
    private fun startCallFlow() {
        statusText.text = "연결 중..."
        AgoraCallManager.init(applicationContext)

        // ★★★ Eggplant: channelName + walletAddress 를 직접 전달
        AgoraCallManager.joinCall(
            context = applicationContext,
            sessionId = sessionId,
            channelName = channelName,
            walletAddress = walletAddress,
            callType = callType,
            listener = this,
        )

        // 통화 시작 직후 기본 라우팅을 명시적으로 적용
        //   - 음성통화 → earpiece (speaker OFF)
        //   - 영상통화 → speaker ON
        isSpeakerOn = (callType == "video")
        timerHandler.postDelayed({ applySpeakerRouting(isSpeakerOn) }, 500)
        setIconBgColor(
            speakerIcon,
            if (isSpeakerOn) Color.parseColor("#1976D2") else Color.parseColor("#444444"),
        )

        // 15초 안에 상대가 들어오지 않으면 실패 처리
        connectTimeoutHandler.postDelayed(connectTimeoutRunnable, 15000)

        // 발신측이면 발신음(ringback "뚜루루") 재생
        //   Eggplant v1.0.142: A1 정책으로 발신측은 Flutter CallScreen 사용 → isIncoming 항상 true
        //   향후 발신측까지 네이티브 전환할 때를 위해 로직 보존.
        if (!isIncoming) {
            startRingback()
        }
    }

    private fun startRingback() {
        try {
            if (ringbackTone != null) {
                Log.d(TAG, "[AGORA_CALL_UI] ringback already playing — skip")
                return
            }
            ringbackTone = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80)
            ringbackTone?.startTone(ToneGenerator.TONE_SUP_RINGTONE, 30000)
            Log.d(TAG, "[AGORA_CALL_UI] ringback STARTED")
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] ringback start failed: ${e.message}")
            ringbackTone = null
        }
    }

    private fun stopRingback() {
        try {
            ringbackTone?.stopTone()
            ringbackTone?.release()
            if (ringbackTone != null) {
                Log.d(TAG, "[AGORA_CALL_UI] ringback STOPPED")
            }
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] ringback stop failed: ${e.message}")
        } finally {
            ringbackTone = null
        }
    }

    // ===================================================================
    // 음성통화 → 영상통화 전환
    // ===================================================================
    private fun upgradeAudioToVideo() {
        Log.d(TAG, "[AGORA_CALL_UI] upgradeAudioToVideo requested")
        if (callType == "video") {
            Log.d(TAG, "[AGORA_CALL_UI] already video — ignore")
            return
        }
        // 1) CAMERA 권한 체크
        val camGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        if (!camGranted) {
            Toast.makeText(
                this,
                "카메라 권한이 없습니다.\n설정 > 앱 > Eggplant > 권한 에서 카메라를 허용해 주세요.",
                Toast.LENGTH_LONG,
            ).show()
            return
        }

        // 2) callType 변경
        callType = "video"

        // 3) Agora 엔진에서 비디오 활성화 + 미리보기 시작 + 상대에게 시그널 전송
        try {
            AgoraCallManager.upgradeToVideo(notifyPeer = true)
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] upgradeToVideo engine call failed: ${e.message}")
            Toast.makeText(this, "영상통화 전환에 실패했습니다.", Toast.LENGTH_SHORT).show()
            callType = "audio" // 롤백
            return
        }

        // 4) UI 변경 (양쪽이 동일하게 수행)
        applyVideoUpgradeUi(showToast = true)
        Log.d(TAG, "[AGORA_CALL_UI] upgradeAudioToVideo done")
    }

    /**
     * 본인 카메라 토글 — 검정 오버레이 + Agora 송신 + 상대 시그널.
     */
    private fun applyLocalCameraState(on: Boolean) {
        isCameraOn = on
        try { AgoraCallManager.setCameraOn(on) } catch (_: Exception) {}
        runOnUiThread {
            setIconBgColor(
                cameraIcon,
                if (!on) Color.parseColor("#E53935") else Color.parseColor("#444444"),
            )
            cameraIcon.text = if (!on) "🚫" else "📹"
            if (!on) {
                localBlackOverlay?.visibility = View.VISIBLE
                localVideoContainer.visibility = View.GONE
            } else {
                localBlackOverlay?.visibility = View.GONE
                localVideoContainer.visibility = View.VISIBLE
            }
            updateRemoteVideoVisibility()
        }
    }

    private fun updateRemoteVideoVisibility() {
        remoteBlackOverlay?.visibility = if (isRemoteCameraOn) View.GONE else View.VISIBLE
        remoteBlackOverlay?.let { remoteVideoContainer.bringChildToFront(it) }
        localBlackOverlay?.let { localVideoContainer.bringChildToFront(it) }
    }

    /**
     * 영상통화 전환 시 UI 변경 — 발신/수신 측 공통.
     */
    private fun applyVideoUpgradeUi(showToast: Boolean) {
        runOnUiThread {
            localVideoContainer.visibility = View.VISIBLE
            remoteVideoContainer.visibility = View.VISIBLE
            localVideoContainer.post { setupLocalVideoView() }
            if (remoteJoined && lastRemoteUid != 0) {
                remoteVideoContainer.post { setupRemoteVideoView(lastRemoteUid) }
            }

            // 하단 컨트롤 바 재구성 — "영상전환" 버튼 제거 + 카메라/스위치 버튼 추가
            try {
                upgradeToVideoButton?.let { btn ->
                    val parent = btn.parent as? LinearLayout
                    parent?.let { bar ->
                        val idx = bar.indexOfChild(btn)
                        bar.removeView(btn)
                        upgradeToVideoButton = null

                        val camResult = makeControlButton(
                            emoji = "📹",
                            labelText = "카메라",
                            bgColor = Color.parseColor("#444444"),
                        ) {
                            applyLocalCameraState(!isCameraOn)
                        }
                        cameraButton = camResult.first
                        cameraIcon = camResult.second
                        bar.addView(cameraButton, idx)

                        val switchResult = makeControlButton(
                            emoji = "🔄",
                            labelText = "전환",
                            bgColor = Color.parseColor("#444444"),
                        ) {
                            AgoraCallManager.switchCamera()
                        }
                        switchCameraButton = switchResult.first
                        bar.addView(switchCameraButton, idx + 1)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "[AGORA_CALL_UI] bottom bar rebuild failed: ${e.message}")
            }

            isSpeakerOn = true
            applySpeakerRouting(true)
            setIconBgColor(speakerIcon, Color.parseColor("#1976D2"))

            statusText.text = if (remoteJoined) "영상 통화 중" else "영상 연결 중..."
            if (showToast) {
                Toast.makeText(this, "영상통화로 전환되었습니다.", Toast.LENGTH_SHORT).show()
            }
        }
    }

    // ===================================================================
    // UI Construction (programmatic — 의존성 최소화)
    // ===================================================================
    private fun buildUi() {
        rootView = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#1A1A1A"))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        // 1. Remote video container (배경 전체)
        remoteVideoContainer = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        rootView.addView(remoteVideoContainer)

        remoteBlackOverlay = View(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            visibility = View.GONE
            isClickable = false
            isFocusable = false
        }
        remoteVideoContainer.addView(remoteBlackOverlay)

        // 2. 상단 정보 영역 (이름 + 상태 + 타이머)
        val topInfo = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, dp(72), 0, 0)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.CENTER_HORIZONTAL,
            )
        }

        nameText = TextView(this).apply {
            text = callerNickname
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
        }
        topInfo.addView(nameText)

        statusText = TextView(this).apply {
            text = "연결 중..."
            setTextColor(Color.parseColor("#CCCCCC"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
        }
        topInfo.addView(statusText)

        timerText = TextView(this).apply {
            text = ""
            setTextColor(Color.parseColor("#CCCCCC"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, 0)
        }
        topInfo.addView(timerText)

        rootView.addView(topInfo)

        // 3. Local video preview (영상 통화 시 우측 상단 작은 박스)
        localVideoContainer = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#222222"))
            visibility = if (callType == "video") View.VISIBLE else View.GONE
            layoutParams = FrameLayout.LayoutParams(
                dp(110),
                dp(160),
                Gravity.TOP or Gravity.END,
            ).apply {
                setMargins(0, dp(48), dp(16), 0)
            }
        }
        rootView.addView(localVideoContainer)

        localBlackOverlay = View(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            visibility = View.GONE
            isClickable = false
            isFocusable = false
        }
        localVideoContainer.addView(localBlackOverlay)

        // 영상통화에서 메인 화면 또는 PIP 를 탭하면 본인↔상대 위치 스왑
        if (callType == "video") {
            val swapClick = View.OnClickListener {
                if (remoteJoined) toggleVideoSwap()
            }
            remoteVideoContainer.setOnClickListener(swapClick)
            localVideoContainer.setOnClickListener(swapClick)
        }

        // 하단 컨트롤 영역 — weight 기반 균등 분배
        val bottomBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), dp(16), dp(4), dp(12))
            setBackgroundColor(Color.parseColor("#CC000000"))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
            )
        }
        // 시스템 네비게이션 바 / 제스처 inset 만큼 하단 padding 추가
        ViewCompat.setOnApplyWindowInsetsListener(bottomBar) { v, insets ->
            val sysBars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            v.setPadding(
                v.paddingLeft,
                v.paddingTop,
                v.paddingRight,
                dp(12) + sysBars.bottom,
            )
            insets
        }

        // ── 음소거 ──
        val muteResult = makeControlButton(
            emoji = "🎤",
            labelText = "음소거",
            bgColor = Color.parseColor("#444444"),
        ) {
            isMuted = !isMuted
            AgoraCallManager.setMicMuted(isMuted)
            setIconBgColor(
                muteIcon,
                if (isMuted) Color.parseColor("#E53935") else Color.parseColor("#444444"),
            )
            muteIcon.text = if (isMuted) "🔇" else "🎤"
        }
        muteButton = muteResult.first
        muteIcon = muteResult.second
        bottomBar.addView(muteButton)

        // ── 스피커 ──
        val spkResult = makeControlButton(
            emoji = "🔊",
            labelText = "스피커",
            bgColor = Color.parseColor("#444444"),
        ) {
            isSpeakerOn = !isSpeakerOn
            applySpeakerRouting(isSpeakerOn)
            setIconBgColor(
                speakerIcon,
                if (isSpeakerOn) Color.parseColor("#1976D2") else Color.parseColor("#444444"),
            )
            Log.e(TAG, "[AGORA_CALL_UI] speaker toggled = $isSpeakerOn")
        }
        speakerButton = spkResult.first
        speakerIcon = spkResult.second
        bottomBar.addView(speakerButton)

        // ── 카메라 / 전환 (영상통화만 추가) ──
        if (callType == "video") {
            val camResult = makeControlButton(
                emoji = "📹",
                labelText = "카메라",
                bgColor = Color.parseColor("#444444"),
            ) {
                applyLocalCameraState(!isCameraOn)
            }
            cameraButton = camResult.first
            cameraIcon = camResult.second
            bottomBar.addView(cameraButton)

            val switchResult = makeControlButton(
                emoji = "🔄",
                labelText = "전환",
                bgColor = Color.parseColor("#444444"),
            ) {
                AgoraCallManager.switchCamera()
            }
            switchCameraButton = switchResult.first
            bottomBar.addView(switchCameraButton)
        }

        // ── 음성통화 중 → 영상통화 전환 버튼 (음성통화일 때만 추가) ──
        if (callType == "audio") {
            val upgradeResult = makeControlButton(
                emoji = "📹",
                labelText = "영상전환",
                bgColor = Color.parseColor("#444444"),
            ) {
                upgradeAudioToVideo()
            }
            upgradeToVideoButton = upgradeResult.first
            bottomBar.addView(upgradeToVideoButton)
        }

        // ── 통화 종료 ──
        val endResult = makeControlButton(
            emoji = "📞",
            labelText = "끊기",
            bgColor = Color.parseColor("#E53935"),
        ) {
            finishCall()
        }
        endButton = endResult.first
        bottomBar.addView(endButton)

        rootView.addView(bottomBar)

        setContentView(rootView)
    }

    /**
     * 통화 컨트롤 버튼 생성 (둥근 아이콘 + 한글 라벨 세로 정렬).
     */
    private fun makeControlButton(
        emoji: String,
        labelText: String,
        bgColor: Int,
        onClick: () -> Unit,
    ): Pair<LinearLayout, TextView> {
        val iconView = TextView(this).apply {
            text = emoji
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            gravity = Gravity.CENTER
            includeFontPadding = false
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(bgColor)
            }
            layoutParams = LinearLayout.LayoutParams(dp(56), dp(56))
        }

        val labelView = TextView(this).apply {
            text = labelText
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            gravity = Gravity.CENTER
            setPadding(0, dp(4), 0, 0)
            maxLines = 1
            setSingleLine(true)
            includeFontPadding = false
        }

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f,
            )
            isClickable = true
            isFocusable = true
            addView(iconView)
            addView(labelView)
            setOnClickListener { onClick() }
        }

        return Pair(container, iconView)
    }

    /**
     * 아이콘 TextView의 원형 배경 색을 갱신 (GradientDrawable 유지).
     */
    private fun setIconBgColor(view: TextView, color: Int) {
        val bg = view.background
        if (bg is android.graphics.drawable.GradientDrawable) {
            bg.setColor(color)
        } else {
            view.setBackgroundColor(color)
        }
    }

    // ===================================================================
    // Local / Remote video setup
    // ===================================================================
    private fun setupLocalVideoView() {
        try {
            val engine = AgoraCallManager.getRtcEngine() ?: return
            val surfaceView = android.view.SurfaceView(applicationContext)
            // PIP 측 SurfaceView 만 상위 레이어에 그리도록 z-order 지정
            surfaceView.setZOrderMediaOverlay(!isVideoSwapped)
            localVideoContainer.removeAllViews()
            localVideoContainer.addView(
                surfaceView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
            )
            // removeAllViews 로 검정 오버레이도 제거됐으므로 재첨부
            localBlackOverlay?.let { ov ->
                (ov.parent as? ViewGroup)?.removeView(ov)
                localVideoContainer.addView(ov)
                ov.visibility = if (!isCameraOn) View.VISIBLE else View.GONE
                localVideoContainer.bringChildToFront(ov)
            }
            engine.setupLocalVideo(VideoCanvas(surfaceView, VideoCanvas.RENDER_MODE_HIDDEN, 0))
            engine.startPreview()
            Log.d(TAG, "[AGORA_CALL_UI] local preview bound (zOrderOverlay=${!isVideoSwapped})")
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] setupLocalVideo failed: ${e.message}")
        }
    }

    private fun setupRemoteVideoView(uid: Int) {
        try {
            val engine = AgoraCallManager.getRtcEngine() ?: return
            val surfaceView = android.view.SurfaceView(applicationContext)
            surfaceView.setZOrderMediaOverlay(isVideoSwapped)
            remoteVideoContainer.removeAllViews()
            remoteVideoContainer.addView(
                surfaceView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
            )
            remoteBlackOverlay?.let { ov ->
                (ov.parent as? ViewGroup)?.removeView(ov)
                remoteVideoContainer.addView(ov)
                ov.visibility = if (!isRemoteCameraOn) View.VISIBLE else View.GONE
                remoteVideoContainer.bringChildToFront(ov)
            }
            engine.setupRemoteVideo(VideoCanvas(surfaceView, VideoCanvas.RENDER_MODE_HIDDEN, uid))
            Log.d(TAG, "[AGORA_CALL_UI] remote bound uid=$uid (zOrderOverlay=$isVideoSwapped)")
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] setupRemoteVideo failed: ${e.message}")
        }
    }

    /**
     * 본인↔상대 위치 스왑.
     */
    private fun toggleVideoSwap() {
        isVideoSwapped = !isVideoSwapped
        Log.d(TAG, "[AGORA_CALL_UI] swap toggled → swapped=$isVideoSwapped")

        val fullParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        val pipParams = FrameLayout.LayoutParams(
            dp(110),
            dp(160),
            Gravity.TOP or Gravity.END,
        ).apply {
            setMargins(0, dp(48), dp(16), 0)
        }

        if (isVideoSwapped) {
            localVideoContainer.layoutParams = fullParams
            remoteVideoContainer.layoutParams = pipParams
        } else {
            remoteVideoContainer.layoutParams = fullParams
            localVideoContainer.layoutParams = pipParams
        }

        rootView.bringChildToFront(if (isVideoSwapped) remoteVideoContainer else localVideoContainer)

        // 스왑 후 하단 컨트롤 바와 상단 정보 바가 PIP 뒤로 숨는 문제 방지
        try {
            val linearChildren = mutableListOf<View>()
            for (i in 0 until rootView.childCount) {
                val child = rootView.getChildAt(i)
                if (child is LinearLayout) linearChildren.add(child)
            }
            for (v in linearChildren) {
                rootView.bringChildToFront(v)
            }
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] swap z-order fix failed: ${e.message}")
        }

        try {
            setupLocalVideoView()
            if (remoteJoined && lastRemoteUid != 0) {
                setupRemoteVideoView(lastRemoteUid)
            }
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] swap rebind failed: ${e.message}")
        }
    }

    // ===================================================================
    // AgoraCallManager.CallListener
    // ===================================================================
    override fun onJoinedChannel(channel: String, uid: Int) {
        Log.d(TAG, "[AGORA_CALL_UI] joined channel uid=$uid")
        runOnUiThread {
            statusText.text = "상대방 응답 대기 중..."
            if (callType == "video") {
                localVideoContainer.post { setupLocalVideoView() }
            }
        }
    }

    override fun onRemoteUserJoined(uid: Int) {
        Log.d(TAG, "[AGORA_CALL_UI] remote joined uid=$uid")
        remoteJoined = true
        lastRemoteUid = uid
        connectTimeoutHandler.removeCallbacks(connectTimeoutRunnable)
        // 상대방이 통화에 들어오면 발신음 즉시 정지 (실제 통화 시작)
        stopRingback()

        // 외부 시작 케이스(eggplantWasAlive=false)면 마이크 보강 워치독 시작
        if (!eggplantWasAlive) {
            startExternalMicGuard()
        }

        runOnUiThread {
            statusText.text = if (callType == "video") "영상 통화 중" else "통화 중"
            callStartedAtMs = System.currentTimeMillis()
            timerHandler.post(timerRunnable)
            if (callType == "video") {
                setupRemoteVideoView(uid)
            }
        }
    }

    // 외부 시작 케이스 전용 마이크 보강 워치독 시작/정지 헬퍼
    private fun startExternalMicGuard() {
        if (micGuardHandler != null) return
        try {
            micGuardThread = android.os.HandlerThread("EggplantExtCallMicGuard").apply { start() }
            micGuardHandler = Handler(micGuardThread!!.looper)
            micGuardHandler?.postDelayed(micGuardRunnable, 5_000L)
            Log.e(TAG, "[AGORA_CALL_UI] ext-mic-guard STARTED (5s interval, dedicated thread)")
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] ext-mic-guard start failed: ${e.message}")
        }
    }

    private fun stopExternalMicGuard() {
        try {
            micGuardHandler?.removeCallbacks(micGuardRunnable)
            micGuardThread?.quitSafely()
        } catch (_: Exception) {}
        micGuardHandler = null
        micGuardThread = null
        Log.e(TAG, "[AGORA_CALL_UI] ext-mic-guard STOPPED")
    }

    override fun onRemoteUserLeft(uid: Int, reason: Int) {
        Log.d(TAG, "[AGORA_CALL_UI] remote left uid=$uid reason=$reason")
        runOnUiThread {
            statusText.text = "통화 종료됨"
            timerHandler.postDelayed({ finishCall() }, 1500)
        }
    }

    override fun onCallError(code: Int, msg: String) {
        Log.e(TAG, "[AGORA_CALL_UI] error code=$code msg=$msg")
        runOnUiThread {
            statusText.text = "오류: $msg"
            timerHandler.postDelayed({ finishCall() }, 2500)
        }
    }

    override fun onConnectionLost() {
        Log.w(TAG, "[AGORA_CALL_UI] connection lost")
        runOnUiThread {
            statusText.text = "연결 끊김 — 재연결 중..."
        }
    }

    override fun onConnectionStateChanged(state: Int, reason: Int) {
        Log.d(TAG, "[AGORA_CALL_UI] connectionState state=$state reason=$reason")
    }

    /**
     * 상대방이 카메라 ON/OFF 했음 (Data Stream 시그널 수신).
     */
    override fun onRemoteCameraToggle(on: Boolean) {
        Log.d(TAG, "[AGORA_CALL_UI] onRemoteCameraToggle on=$on")
        isRemoteCameraOn = on
        runOnUiThread { updateRemoteVideoVisibility() }
    }

    /**
     * 상대방이 음성→영상 전환 시그널을 보낸 경우 콜백.
     */
    override fun onRemoteUpgradeToVideo() {
        Log.d(TAG, "[AGORA_CALL_UI] onRemoteUpgradeToVideo")
        if (callType == "video") {
            Log.d(TAG, "[AGORA_CALL_UI] already video — skip remote upgrade UI")
            return
        }
        callType = "video"

        val camGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        if (!camGranted) {
            try { AgoraCallManager.setCameraOn(false) } catch (_: Exception) {}
            isCameraOn = false
            runOnUiThread {
                Toast.makeText(
                    this,
                    "상대방이 영상통화로 전환했습니다.\n카메라 권한이 없어 본인 영상은 송출되지 않습니다.",
                    Toast.LENGTH_LONG,
                ).show()
            }
        }

        applyVideoUpgradeUi(showToast = camGranted)
    }

    // ===================================================================
    // Timer
    // ===================================================================
    private fun updateTimer() {
        if (callStartedAtMs == 0L) return
        val elapsed = (System.currentTimeMillis() - callStartedAtMs) / 1000
        val mm = elapsed / 60
        val ss = elapsed % 60
        timerText.text = String.format("%02d:%02d", mm, ss)
    }

    // ===================================================================
    // End call
    // ===================================================================
    private fun finishCall() {
        Log.d(TAG, "[AGORA_CALL_UI] finishCall")
        stopRingback()
        try {
            AgoraCallManager.endCall()
        } catch (_: Exception) {}
        timerHandler.removeCallbacks(timerRunnable)
        connectTimeoutHandler.removeCallbacks(connectTimeoutRunnable)

        stopExternalMicGuard()

        // 통화 시작 시점 Eggplant 생존 여부에 따라 분기
        //
        //   [Case A] eggplantWasAlive == true → 에그플랜트 안에 있다가 통화한 케이스
        //     MainActivity 다시 띄워서 채팅방/이전 화면 복귀
        //
        //   [Case B] eggplantWasAlive == false → 외부 앱 또는 콜드 스타트에서 받음
        //     moveTaskToBack(true) → OS 가 직전 task 를 자연스럽게 전면에 가져옴
        //     (카톡 정확한 방식 — 외부에서 받은 통화 종료 시 메인 안 띄움)
        if (eggplantWasAlive) {
            try {
                val backToChat = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                }
                startActivity(backToChat)
                Log.e(TAG, "[AGORA_CALL_UI] finishCall: eggplant alive → return to MainActivity")
            } catch (e: Exception) {
                Log.e(TAG, "[AGORA_CALL_UI] return-to-main launch failed: ${e.message}")
            }
            finish()
        } else {
            Log.e(TAG, "[AGORA_CALL_UI] finishCall: eggplant NOT alive → moveTaskToBack + finish")
            try {
                moveTaskToBack(true)
            } catch (e: Exception) {
                Log.e(TAG, "[AGORA_CALL_UI] moveTaskToBack failed: ${e.message}")
            }
            finish()
        }
    }

    override fun onPause() {
        super.onPause()
        Log.d(TAG, "[AGORA_CALL_UI] onPause (audio 안 건드림 — Agora 자체 관리)")
    }

    override fun onStop() {
        super.onStop()
        Log.d(TAG, "[AGORA_CALL_UI] onStop (audio 안 건드림 — Agora 자체 관리)")
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRingback()
        try {
            wakeLock?.release()
        } catch (_: Exception) {}
        wakeLock = null
        try {
            cpuWakeLock?.release()
        } catch (_: Exception) {}
        cpuWakeLock = null
        timerHandler.removeCallbacks(timerRunnable)
        connectTimeoutHandler.removeCallbacks(connectTimeoutRunnable)

        stopExternalMicGuard()

        // ForegroundService 종료 (통화 끝났으므로 microphone 권한 점유 해제)
        try {
            CallForegroundService.stop(this)
            Log.e(TAG, "[AGORA_CALL_UI] CallForegroundService.stop() 호출")
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] CallForegroundService.stop FAILED: ${e.message}")
        }

        // 메모리 zero-fill (통화 데이터 zero 정책)
        sessionId = ""
        channelName = ""
        walletAddress = ""
        callerId = ""
        callerNickname = ""
        callType = "audio"
        callerPhoto = ""
        callStartedAtMs = 0L
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        // 통화 중에는 뒤로가기로 종료하지 않음 (홈으로 돌리기만 함)
        moveTaskToBack(true)
    }

    // ===================================================================
    // Helpers
    // ===================================================================
    private fun dp(value: Int): Int {
        val density = resources.displayMetrics.density
        return (value * density + 0.5f).toInt()
    }

    /**
     * 스피커폰 라우팅.
     *
     *   1. Agora SDK setEnableSpeakerphone() 만 호출 (Agora 가 audio session 관리)
     *   2. SharedPreferences "speaker_on" 갱신 (CallForegroundService 워치독 동기화)
     *
     * AudioManager 직접 조작은 모두 제거. Agora SDK 가 알아서 mode 와 routing 처리.
     */
    private fun applySpeakerRouting(speakerOn: Boolean) {
        try {
            // 1. Agora SDK (이게 핵심 — audio session 은 Agora 가 관리)
            AgoraCallManager.setSpeakerOn(speakerOn)

            // 2. SharedPreferences 동기화 (워치독 일치)
            try {
                val prefs = getSharedPreferences("eggplant_call_audio", Context.MODE_PRIVATE)
                prefs.edit().putBoolean("speaker_on", speakerOn).apply()
            } catch (e: Exception) {
                Log.e(TAG, "[AGORA_CALL_UI] prefs write failed: ${e.message}")
            }

            Log.e(TAG, "[AGORA_CALL_UI] applySpeakerRouting speakerOn=$speakerOn (Agora SDK only)")
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL_UI] applySpeakerRouting error: ${e.message}")
        }
    }
}
