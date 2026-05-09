package com.eggplant.market

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * v1.0.142: CallForegroundService — Eggplant 어댑트.
 *
 * 큐알쳇 v4.0.270 CallForegroundService 를 에그플랜트로 포팅:
 *   - package: io.qrchat.app → com.eggplant.market
 *   - CHANNEL_ID: qrchat_ongoing_calls_silent → eggplant_ongoing_calls_silent
 *   - ACTION 문자열: io.qrchat.app.* → com.eggplant.market.*
 *   - SharedPreferences: qrchat_call_audio → eggplant_call_audio
 *   - WakeLock 태그: qrchat:* → eggplant:*
 *   - HandlerThread 이름: QRChatAudioWatchdog → EggplantAudioWatchdog
 *
 * Keeps the call alive when the app moves to background or the screen turns off.
 *
 * 핵심 책임:
 *   1. ForegroundService(microphone) — Android 12+ 백그라운드 마이크 캡처 권한 유지
 *   2. PARTIAL_WAKE_LOCK + WifiLock — CPU/네트워크 sleep 방지
 *   3. AudioFocus + MODE_IN_COMMUNICATION — 통화 오디오 라우팅
 *   4. setCommunicationDevice (Android 12+) — 명시적 earpiece/speaker 라우팅
 *   5. Audio watchdog (전용 HandlerThread) — main looper throttle 무관 동작
 *   6. 근접센서 WakeLock — 음성통화 시 얼굴 닿으면 화면 OFF
 *   7. STREAM_VOICE_CALL 볼륨 0 복원 (일부 OEM 안전망)
 *
 * Lifecycle:
 *   - Started by AgoraCallActivity.onCreate() (양방향 — 발신/수신 모두)
 *   - Stopped by:
 *       a) AgoraCallActivity.onDestroy() → CallForegroundService.stop()
 *       b) User taps "End call" action on the notification
 */
class CallForegroundService : Service() {

    // CPU wake lock + Wi-Fi lock
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    // Audio focus + mode watchdog
    private var audioFocusRequest: AudioFocusRequest? = null
    private var audioWatchdogThread: HandlerThread? = null
    private var audioWatchdogHandler: Handler? = null
    private var audioWatchdogRunnable: Runnable? = null
    private var isSpeakerphoneOn: Boolean = false
    private var savedVoiceCallVolume: Int = -1

    // 화면 OFF 진단용 BroadcastReceiver
    private var screenOffReceiver: BroadcastReceiver? = null

    // 근접센서 WakeLock (음성통화 시 얼굴 닿으면 화면 OFF)
    private var proximityWakeLock: PowerManager.WakeLock? = null
    private var currentCallType: String = "audio"

    companion object {
        private const val TAG = "CALL_KEEP"
        private const val CHANNEL_ID = "eggplant_ongoing_calls_silent"
        private const val NOTIFICATION_ID = 9002
        private const val AUDIO_WATCHDOG_INTERVAL_MS = 1000L
        private const val AUDIO_WATCHDOG_FIRST_RUN_MS = 500L
        const val ACTION_RETURN_TO_CALL = "com.eggplant.market.ACTION_RETURN_TO_CALL"
        const val ACTION_END_CALL = "com.eggplant.market.ACTION_END_CALL_FROM_NOTIFICATION"

        @Volatile
        var isRunning = false
            private set

        fun start(context: Context, callerName: String, callType: String) {
            val intent = Intent(context, CallForegroundService::class.java).apply {
                putExtra("callerName", callerName)
                putExtra("callType", callType)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.e(TAG, "[$TAG] start requested callerName=$callerName callType=$callType")
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallForegroundService::class.java))
            Log.e(TAG, "[$TAG] stop requested")
        }

        // 동적 근접센서 토글용 static helper
        @Volatile
        private var instanceRef: CallForegroundService? = null

        fun setProximityEnabled(enabled: Boolean) {
            try {
                instanceRef?.setProximityEnabledInternal(enabled)
            } catch (e: Exception) {
                Log.e(TAG, "[$TAG] setProximityEnabled failed: ${e.message}")
            }
        }

        /**
         * Activity 가 백그라운드 진입 시 즉시 audio mode 잠금.
         */
        fun notifyAppGoingToBackground(context: Context) {
            if (!isRunning) return
            try {
                val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val currentMode = am.mode

                val prefs = context.getSharedPreferences("eggplant_call_audio", Context.MODE_PRIVATE)
                val speakerOn = prefs.getBoolean("speaker_on", am.isSpeakerphoneOn)

                if (currentMode != AudioManager.MODE_IN_COMMUNICATION) {
                    am.mode = AudioManager.MODE_IN_COMMUNICATION
                    Log.e(TAG, "[$TAG] BG_LOCK: mode was ${getModeStringStatic(currentMode)} → MODE_IN_COMMUNICATION")
                }
                applyCommunicationDeviceStatic(am, speakerOn)
                am.isSpeakerphoneOn = speakerOn
                am.isMicrophoneMute = false

                val vol = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
                val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
                if (vol == 0 && maxVol > 0) {
                    am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVol / 2, 0)
                    Log.e(TAG, "[$TAG] BG_LOCK: volume was 0 → restored to ${maxVol / 2}")
                }

                Log.e(TAG, "[$TAG] BG_LOCK: audio locked for background (speaker=$speakerOn, vol=$vol/$maxVol)")
            } catch (e: Exception) {
                Log.e(TAG, "[$TAG] BG_LOCK error: ${e.message}")
            }
        }

        private fun getModeStringStatic(mode: Int): String = when (mode) {
            AudioManager.MODE_NORMAL -> "MODE_NORMAL"
            AudioManager.MODE_IN_COMMUNICATION -> "MODE_IN_COMMUNICATION"
            AudioManager.MODE_IN_CALL -> "MODE_IN_CALL"
            AudioManager.MODE_RINGTONE -> "MODE_RINGTONE"
            else -> "MODE_UNKNOWN($mode)"
        }

        /**
         * Android 12+ setCommunicationDevice 정적 헬퍼.
         */
        fun applyCommunicationDeviceStatic(am: AudioManager, speakerOn: Boolean): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
            try {
                val available = am.availableCommunicationDevices
                if (available.isEmpty()) return false
                val candidate: AudioDeviceInfo? = if (speakerOn) {
                    available.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                } else {
                    available.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
                        ?: available.firstOrNull {
                            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                                    it.type == AudioDeviceInfo.TYPE_USB_HEADSET
                        }
                        ?: available.firstOrNull { it.type != AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                }
                val target: AudioDeviceInfo = candidate ?: return false
                val ok = am.setCommunicationDevice(target)
                Log.e(TAG, "[$TAG] setCommunicationDevice(static) speakerOn=$speakerOn type=${target.type} ok=$ok")
                return ok
            } catch (e: Exception) {
                Log.e(TAG, "[$TAG] setCommunicationDevice(static) FAILED: ${e.message}")
                return false
            }
        }
    }

    /** 인스턴스 헬퍼 (watchdog용). */
    private fun applyCommunicationDevice(am: AudioManager, speakerOn: Boolean): Boolean {
        return applyCommunicationDeviceStatic(am, speakerOn)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        instanceRef = this
        Log.e(TAG, "[$TAG] service onCreate")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callerName = intent?.getStringExtra("callerName") ?: "Call"
        val callType = intent?.getStringExtra("callType") ?: "audio"

        val notification = buildOngoingNotification(callerName, callType)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or
                            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }

            // CPU + Wi-Fi wake locks
            acquireWakeLocks()

            // 음성통화일 때만 근접센서 WakeLock 획득
            currentCallType = callType
            if (callType == "audio") {
                acquireProximityLock()
            }

            // Audio focus + MODE_IN_COMMUNICATION
            acquireAudioFocus()

            // 초기 STREAM_VOICE_CALL 볼륨 저장 (복원용)
            try {
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                savedVoiceCallVolume = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
                if (savedVoiceCallVolume == 0) {
                    savedVoiceCallVolume = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL) / 2
                }
                Log.e(TAG, "[$TAG] saved voice call volume=$savedVoiceCallVolume")
            } catch (e: Exception) {
                Log.e(TAG, "[$TAG] save volume error: ${e.message}")
            }

            // 전용 HandlerThread 에서 audio watchdog 시작 (main looper throttle 무관)
            startAudioWatchdog()

            // SCREEN_OFF 진단 receiver 등록
            registerScreenOffReceiver()

            isRunning = true
            Log.e(TAG, "[$TAG] service started callerName=$callerName callType=$callType")
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] startForeground FAILED: ${e.message}")
            stopSelf()
        }

        return START_STICKY
    }

    override fun onDestroy() {
        stopAudioWatchdog()
        unregisterScreenOffReceiver()
        releaseAudioFocus()
        releaseWakeLocks()
        releaseProximityLock()
        instanceRef = null
        isRunning = false
        Log.e(TAG, "[$TAG] service stopped (call ended)")
        super.onDestroy()
    }

    // ==================================================
    //  근접센서 WakeLock — 얼굴 닿으면 화면 OFF
    // ==================================================

    @Suppress("WakelockTimeout")
    private fun acquireProximityLock() {
        try {
            if (proximityWakeLock?.isHeld == true) {
                Log.e(TAG, "[$TAG] proximity already held — skip acquire")
                return
            }
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                Log.e(TAG, "[$TAG] PROXIMITY_SCREEN_OFF_WAKE_LOCK not supported on this device")
                return
            }
            proximityWakeLock = pm.newWakeLock(
                PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                "eggplant:call_proximity_lock"
            )
            proximityWakeLock?.acquire()
            Log.e(TAG, "[$TAG] PROXIMITY_SCREEN_OFF_WAKE_LOCK acquired (callType=$currentCallType)")
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] proximity acquire failed: ${e.message}")
        }
    }

    private fun releaseProximityLock() {
        try {
            proximityWakeLock?.let {
                if (it.isHeld) {
                    @Suppress("DEPRECATION")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                        try {
                            it.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY)
                        } catch (_: Exception) {
                            it.release()
                        }
                    } else {
                        it.release()
                    }
                    Log.e(TAG, "[$TAG] PROXIMITY_SCREEN_OFF_WAKE_LOCK released")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] proximity release failed: ${e.message}")
        } finally {
            proximityWakeLock = null
        }
    }

    /**
     * 외부(MethodChannel)에서 동적 ON/OFF — 영상통화 중 스피커 OFF 시 등.
     */
    fun setProximityEnabledInternal(enabled: Boolean) {
        if (enabled) acquireProximityLock() else releaseProximityLock()
    }

    // ==================================================
    //  Screen-off receiver — 진단 모니터링만 (audio 안 건드림)
    // ==================================================

    private fun registerScreenOffReceiver() {
        if (screenOffReceiver != null) return
        screenOffReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action ?: return
                if (action == Intent.ACTION_SCREEN_OFF || action == Intent.ACTION_SCREEN_ON) {
                    Log.e(TAG, "[$TAG] SCREEN event=$action (모니터링만, audio 안 건드림)")
                }
            }
        }
        try {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
            }
            registerReceiver(screenOffReceiver, filter)
            Log.e(TAG, "[$TAG] SCREEN_OFF receiver registered (diagnostic only)")
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] SCREEN_OFF register failed: ${e.message}")
        }
    }

    private fun unregisterScreenOffReceiver() {
        try {
            screenOffReceiver?.let { unregisterReceiver(it) }
        } catch (_: Exception) {}
        screenOffReceiver = null
    }

    // ==================================================
    //  Audio focus management
    // ==================================================

    @Suppress("DEPRECATION")
    private fun acquireAudioFocus() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager

            // 1. Set audio mode to MODE_IN_COMMUNICATION
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            Log.e(TAG, "[$TAG] AudioManager.mode set to MODE_IN_COMMUNICATION")

            // 2. Request audio focus
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()

                // Watchdog handler 사용 (main looper throttle 무관)
                val focusHandler = audioWatchdogHandler ?: Handler(Looper.getMainLooper())

                audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attrs)
                    .setWillPauseWhenDucked(false)
                    .setAcceptsDelayedFocusGain(true)
                    .setOnAudioFocusChangeListener({ focusChange ->
                        Log.e(TAG, "[$TAG] audio focus changed: $focusChange")
                        when (focusChange) {
                            AudioManager.AUDIOFOCUS_LOSS,
                            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                                Log.e(TAG, "[$TAG] audio focus LOST — will re-acquire in 500ms")
                                focusHandler.postDelayed({
                                    if (isRunning) {
                                        reacquireAudioFocus()
                                    }
                                }, 500)
                            }
                            AudioManager.AUDIOFOCUS_GAIN -> {
                                Log.e(TAG, "[$TAG] audio focus REGAINED")
                                ensureAudioMode()
                            }
                        }
                    }, focusHandler)
                    .build()

                val result = am.requestAudioFocus(audioFocusRequest!!)
                Log.e(TAG, "[$TAG] requestAudioFocus result=$result (1=GRANTED)")
            } else {
                val result = am.requestAudioFocus(
                    { focusChange ->
                        Log.e(TAG, "[$TAG] audio focus changed (legacy): $focusChange")
                    },
                    AudioManager.STREAM_VOICE_CALL,
                    AudioManager.AUDIOFOCUS_GAIN
                )
                Log.e(TAG, "[$TAG] requestAudioFocus (legacy) result=$result")
            }

            // 3. Ensure microphone is not muted
            am.isMicrophoneMute = false

            // 4. Read speaker state from SharedPreferences
            readSpeakerStateFromPrefs()
            // Android 12+ setCommunicationDevice 로 초기 라우팅 확정
            applyCommunicationDevice(am, isSpeakerphoneOn)
            am.isSpeakerphoneOn = isSpeakerphoneOn

            Log.e(
                TAG, "[$TAG] audio focus acquired: mode=${getModeString(am.mode)}, " +
                        "speaker=$isSpeakerphoneOn, micMute=${am.isMicrophoneMute}"
            )
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] acquireAudioFocus error: ${e.message}")
        }
    }

    /**
     * Re-acquire audio focus after losing it to another app.
     */
    @Suppress("DEPRECATION")
    private fun reacquireAudioFocus() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.mode = AudioManager.MODE_IN_COMMUNICATION

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
                val result = am.requestAudioFocus(audioFocusRequest!!)
                Log.e(TAG, "[$TAG] re-requestAudioFocus result=$result")
            } else {
                am.requestAudioFocus(null, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN)
                Log.e(TAG, "[$TAG] re-requestAudioFocus (legacy)")
            }

            applyCommunicationDevice(am, isSpeakerphoneOn)
            am.isSpeakerphoneOn = isSpeakerphoneOn
            am.isMicrophoneMute = false
            Log.e(TAG, "[$TAG] audio re-acquired: mode=${getModeString(am.mode)}, speaker=$isSpeakerphoneOn")
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] reacquireAudioFocus error: ${e.message}")
        }
    }

    @Suppress("DEPRECATION")
    private fun releaseAudioFocus() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
                am.abandonAudioFocusRequest(audioFocusRequest!!)
                audioFocusRequest = null
            } else {
                am.abandonAudioFocus(null)
            }
            am.mode = AudioManager.MODE_NORMAL
            am.isSpeakerphoneOn = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try { am.clearCommunicationDevice() } catch (e: Exception) {
                    Log.e(TAG, "[$TAG] clearCommunicationDevice error: ${e.message}")
                }
            }
            Log.e(TAG, "[$TAG] audio focus released, mode=MODE_NORMAL")
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] releaseAudioFocus error: ${e.message}")
        }
    }

    // ==================================================
    //  Audio mode watchdog (전용 HandlerThread)
    // ==================================================

    private fun startAudioWatchdog() {
        stopAudioWatchdog()

        // 전용 HandlerThread — main looper throttle 무관
        audioWatchdogThread = HandlerThread("EggplantAudioWatchdog").apply { start() }
        audioWatchdogHandler = Handler(audioWatchdogThread!!.looper)

        audioWatchdogRunnable = object : Runnable {
            override fun run() {
                if (!isRunning) return
                ensureAudioMode()
                audioWatchdogHandler?.postDelayed(this, AUDIO_WATCHDOG_INTERVAL_MS)
            }
        }
        audioWatchdogHandler?.postDelayed(audioWatchdogRunnable!!, AUDIO_WATCHDOG_FIRST_RUN_MS)
        Log.e(
            TAG, "[$TAG] audio watchdog started on DEDICATED THREAD " +
                    "(first=${AUDIO_WATCHDOG_FIRST_RUN_MS}ms, interval=${AUDIO_WATCHDOG_INTERVAL_MS}ms)"
        )
    }

    private fun stopAudioWatchdog() {
        audioWatchdogRunnable?.let { audioWatchdogHandler?.removeCallbacks(it) }
        audioWatchdogHandler = null
        audioWatchdogRunnable = null
        try {
            audioWatchdogThread?.quitSafely()
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] watchdog thread quit error: ${e.message}")
        }
        audioWatchdogThread = null
    }

    /**
     * 워치독 — Agora SDK 가 audio session 을 관리하도록 위임.
     *
     * 주의: mode/speaker/setCommunicationDevice 는 절대 만지지 않음.
     *   Agora SDK 가 자체 관리. 1초마다 덮어쓰면 Agora audio session 이 충돌해서
     *   마이크 캡처가 죽음 (큐알쳇 v4.0.131 회고 참조).
     *
     * 유지:
     *   - STREAM_VOICE_CALL 볼륨 0 일 때만 복원 (Agora 와 충돌 없음, 사용자 보호)
     *   - audio focus 재요청 (포커스 잃었을 때만, mode 안 건드림)
     */
    @Suppress("DEPRECATION")
    private fun ensureAudioMode() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager

            val currentMode = am.mode
            val modeStr = getModeString(currentMode)

            // 볼륨 0 일 때만 복원
            val currentVol = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
            val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            if (currentVol == 0 && maxVol > 0) {
                val restoreVol = if (savedVoiceCallVolume > 0) savedVoiceCallVolume else maxVol / 2
                am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, restoreVol, 0)
                Log.e(TAG, "[$TAG] WATCHDOG: volume restored to $restoreVol/$maxVol (mode=$modeStr)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] ensureAudioMode error: ${e.message}")
        }
    }

    /**
     * SharedPreferences 에서 speaker 상태 읽기 (AgoraCallActivity 가 onCreate 에서 미리 동기화).
     */
    private fun readSpeakerStateFromPrefs() {
        try {
            val prefs = applicationContext.getSharedPreferences("eggplant_call_audio", Context.MODE_PRIVATE)
            isSpeakerphoneOn = prefs.getBoolean("speaker_on", isSpeakerphoneOn)
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] readSpeakerState error: ${e.message}")
        }
    }

    private fun getModeString(mode: Int): String = when (mode) {
        AudioManager.MODE_NORMAL -> "MODE_NORMAL"
        AudioManager.MODE_IN_COMMUNICATION -> "MODE_IN_COMMUNICATION"
        AudioManager.MODE_IN_CALL -> "MODE_IN_CALL"
        AudioManager.MODE_RINGTONE -> "MODE_RINGTONE"
        else -> "MODE_UNKNOWN($mode)"
    }

    // ==================================================
    //  Wake locks
    // ==================================================

    private fun acquireWakeLocks() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "eggplant:call_cpu_lock"
                )
                wakeLock?.acquire(60 * 60 * 1000L)
                Log.e(TAG, "[$TAG] PARTIAL_WAKE_LOCK acquired")
            }

            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                if (wm != null) {
                    @Suppress("DEPRECATION")
                    wifiLock = wm.createWifiLock(
                        WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                        "eggplant:call_wifi_lock"
                    )
                    wifiLock?.acquire()
                    Log.e(TAG, "[$TAG] WifiLock acquired")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] acquireWakeLocks error: ${e.message}")
        }
    }

    private fun releaseWakeLocks() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = null
            Log.e(TAG, "[$TAG] PARTIAL_WAKE_LOCK released")
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] wakeLock release error: ${e.message}")
        }

        try {
            wifiLock?.let { if (it.isHeld) it.release() }
            wifiLock = null
            Log.e(TAG, "[$TAG] WifiLock released")
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] wifiLock release error: ${e.message}")
        }
    }

    // ==================================================
    //  Notification
    // ==================================================

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            // IMPORTANCE_MIN: 상태바 아이콘/알림그림자 안보임 → 알림 드로어 펼쳐야 보임.
            //   Foreground Service 유지를 위해 알림 자체는 필요 — 최소화만.
            nm.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, "Ongoing Calls", NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Shows while a call is in progress"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            })
            Log.e(TAG, "[$TAG] channel created: $CHANNEL_ID (IMPORTANCE_MIN — 하단 바 제거)")
        }
    }

    private fun buildOngoingNotification(callerName: String, callType: String): Notification {
        val typeText = if (callType == "video") "Video call" else "Voice call"

        val returnIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("from_ongoing_call_notification", true)
        }
        val returnPi = PendingIntent.getActivity(
            this, 100, returnIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val endIntent = Intent(this, CallEndFromNotificationReceiver::class.java).apply {
            action = ACTION_END_CALL
        }
        val endPi = PendingIntent.getBroadcast(
            this, 101, endIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // CATEGORY_SERVICE + VISIBILITY_SECRET + PRIORITY_MIN → 숨김 수준.
        //   Foreground Service 요건은 충족(알림 자체는 있음).
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setContentTitle("$typeText with $callerName")
            .setContentText("Tap to return to call")
            .setContentIntent(returnPi)
            .setOngoing(true)
            .setAutoCancel(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSilent(true)
            .addAction(android.R.drawable.ic_menu_call, "Return", returnPi)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "End call", endPi)
            .build()
    }
}
