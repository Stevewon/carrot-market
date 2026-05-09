package com.eggplant.market

import android.content.Context
import android.util.Log
import io.agora.rtc2.ChannelMediaOptions
import io.agora.rtc2.Constants
import io.agora.rtc2.DataStreamConfig
import io.agora.rtc2.IRtcEngineEventHandler
import io.agora.rtc2.RtcEngine
import io.agora.rtc2.RtcEngineConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * ★★★ v1.0.142: Agora RTC 통화 엔진 매니저 (싱글톤) — Eggplant 어댑트 버전
 *
 * 큐알쳇 v4.0.270 AgoraCallManager 를 에그플랜트로 포팅:
 *   - package: io.qrchat.app → com.eggplant.market
 *   - channel name: 파라미터로 직접 수신 (sortedWalletPair, FCM 페이로드에서 추출)
 *   - uid: AgoraConfig.walletToUid(walletAddress) — 양 피어 결정론적 (SHA-256 4 bytes)
 *   - token: AgoraTokenService.fetchToken(context, channel, uid, "rtc")
 *     → Cloudflare Workers /api/users/agora/token?kind=rtc&uid=N&channel=C (JWT 인증)
 *   - UserIdentityProvider/CallSecretManager 의존성 없음 (HMAC 미사용)
 *
 * 책임:
 *   1. RtcEngine 초기화/해제
 *   2. 토큰 발급 → 채널 입장 → 통화 시작
 *   3. 음성/영상/스피커/마이크 토글
 *   4. 통화 종료 + 리소스 정리
 *
 * 통화 데이터 zero 원칙 (사장님 명시):
 *   - 통화 정보 메모리에만 보관
 *   - 통화 종료 즉시 token/uid/channelName 모두 zero-fill
 *   - D1/SharedPreferences 일절 사용 안 함 (eggplant_native_call SP 는 jwt/wallet 만)
 *   - Agora SDK 로깅 최소화 (개인정보 미노출)
 *
 * 사용 흐름:
 *   AgoraCallManager.init(context)
 *   AgoraCallManager.joinCall(context, sessionId, channel, walletAddress, callType, listener)
 *   ... 통화 진행 ...
 *   AgoraCallManager.endCall()
 */
object AgoraCallManager {
    private const val TAG = "AGORA_CALL"

    /**
     * 통화 상태 콜백 (Activity 가 구현)
     */
    interface CallListener {
        fun onJoinedChannel(channel: String, uid: Int)
        fun onRemoteUserJoined(uid: Int)
        fun onRemoteUserLeft(uid: Int, reason: Int)
        fun onCallError(code: Int, msg: String)
        fun onConnectionLost()
        fun onConnectionStateChanged(state: Int, reason: Int)

        // 상대방이 음성→영상 전환 시그널 보냄 (Data Stream 수신)
        fun onRemoteUpgradeToVideo() {}

        // 상대방이 카메라 ON/OFF 토글 시그널 보냄
        //   on=false 일 때 본인 화면도 즉시 검정으로 (마지막 프레임 잔상 제거)
        fun onRemoteCameraToggle(on: Boolean) {}
    }

    @Volatile
    private var rtcEngine: RtcEngine? = null

    @Volatile
    private var currentSessionId: String? = null

    @Volatile
    private var currentChannelName: String? = null

    @Volatile
    private var currentUid: Int = 0

    @Volatile
    private var currentToken: String? = null

    @Volatile
    private var currentListener: CallListener? = null

    @Volatile
    private var currentCallType: String = "audio"

    // 음성→영상 전환 시그널용 Data Stream ID
    @Volatile
    private var dataStreamId: Int = -1

    private val managerScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var activeJob: Job? = null

    /**
     * RtcEngine 초기화 (앱 시작 시 1회 호출 또는 통화 직전 lazy 호출)
     */
    @Synchronized
    fun init(context: Context) {
        if (rtcEngine != null) return

        try {
            val config = RtcEngineConfig().apply {
                mContext = context.applicationContext
                mAppId = AgoraConfig.APP_ID
                mEventHandler = engineEventHandler
            }
            rtcEngine = RtcEngine.create(config)
            Log.d(TAG, "[AGORA_CALL] RtcEngine initialized")
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL] RtcEngine init failed: ${e.message}")
        }
    }

    /**
     * 채널 입장 (통화 시작) — Eggplant 버전
     *
     * 큐알쳇 원본과 차이점:
     *   - channelName 을 파라미터로 직접 수신 (sortedWalletPair 기반, FCM 에서 추출)
     *   - walletAddress 로부터 결정론적 uid 생성 (양 피어 동일 알고리즘)
     *   - sessionId 는 통화 추적/검증용으로만 보관 (Agora 채널명에는 사용 안 함)
     *
     * @param context Application context
     * @param sessionId 통화 세션 UUID (양쪽 동일, 추적용)
     * @param channelName Agora 채널명 (eggplant_call_<sortedLowerWalletPair>)
     * @param walletAddress 본인 지갑 주소 (uid 생성용)
     * @param callType "audio" or "video"
     * @param listener 통화 상태 콜백
     */
    fun joinCall(
        context: Context,
        sessionId: String,
        channelName: String,
        walletAddress: String,
        callType: String,
        listener: CallListener,
    ) {
        // 이전 통화 정리
        if (currentSessionId != null) {
            Log.w(TAG, "[AGORA_CALL] previous call still active, ending first")
            endCallInternal()
        }

        init(context)
        val engine = rtcEngine ?: run {
            Log.e(TAG, "[AGORA_CALL] engine is null after init")
            listener.onCallError(-1, "Engine init failed")
            return
        }

        // ★★★ Eggplant: walletAddress → 결정론적 uid (양 피어 동일 알고리즘, 서버 walletToAgoraUid 와 일치)
        val uid = AgoraConfig.walletToUid(walletAddress)

        currentSessionId = sessionId
        currentChannelName = channelName
        currentUid = uid
        currentListener = listener
        currentCallType = callType

        Log.d(
            TAG,
            "[AGORA_CALL] joinCall sessionLen=${sessionId.length} chLen=${channelName.length} uid=$uid type=$callType",
        )

        // 영상통화면 비디오 활성화, 아니면 음성만
        if (callType == "video") {
            engine.enableVideo()
            // enableVideo() 직후 startPreview() 즉시 호출
            //   발신자 카메라가 검정으로 나오는 문제 방지 — joinChannel 전에 startPreview() 가
            //   호출되어야 카메라 캡처가 시작됨.
            try {
                engine.startPreview()
                Log.d(TAG, "[AGORA_CALL] startPreview ok")
            } catch (e: Exception) {
                Log.e(TAG, "[AGORA_CALL] startPreview failed: ${e.message}")
            }
        } else {
            engine.disableVideo()
        }
        engine.enableAudio()
        engine.setDefaultAudioRoutetoSpeakerphone(callType == "video")

        // 토큰 발급 후 채널 입장
        activeJob = managerScope.launch {
            try {
                // ★★★ Eggplant: kind="rtc" (Workers /api/users/agora/token?kind=rtc&uid=N&channel=C)
                val tokenResult = AgoraTokenService.fetchToken(context, channelName, uid, "rtc")
                currentToken = tokenResult.token

                val options = ChannelMediaOptions().apply {
                    autoSubscribeAudio = true
                    autoSubscribeVideo = (callType == "video")
                    publishMicrophoneTrack = true
                    publishCameraTrack = (callType == "video")
                    clientRoleType = Constants.CLIENT_ROLE_BROADCASTER
                    channelProfile = Constants.CHANNEL_PROFILE_COMMUNICATION
                }

                val ret = engine.joinChannel(tokenResult.token, channelName, uid, options)
                if (ret < 0) {
                    Log.e(TAG, "[AGORA_CALL] joinChannel failed code=$ret")
                    listener.onCallError(ret, "joinChannel returned $ret")
                    cleanupState()
                }
            } catch (e: Exception) {
                Log.e(TAG, "[AGORA_CALL] token/join failed: ${e.message}")
                listener.onCallError(-2, e.message ?: "Token fetch failed")
                cleanupState()
            }
        }
    }

    /**
     * 채널 퇴장 (통화 종료)
     */
    fun endCall() {
        Log.d(TAG, "[AGORA_CALL] endCall requested")
        endCallInternal()
    }

    @Synchronized
    private fun endCallInternal() {
        try {
            activeJob?.cancel()
            activeJob = null
            rtcEngine?.leaveChannel()
            rtcEngine?.disableVideo()
            rtcEngine?.disableAudio()
            Log.d(TAG, "[AGORA_CALL] channel left")
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL] leaveChannel failed: ${e.message}")
        } finally {
            cleanupState()
        }
    }

    /**
     * 메모리에 남은 통화 정보 zero-fill (통화 데이터 zero 원칙)
     */
    @Synchronized
    private fun cleanupState() {
        currentSessionId = null
        currentChannelName = null
        currentUid = 0
        currentToken = null
        currentListener = null
        currentCallType = "audio"
        // DataStream id 도 채널 떠나면 무효 → 리셋
        dataStreamId = -1
    }

    /**
     * 마이크 음소거 토글
     */
    fun setMicMuted(muted: Boolean) {
        rtcEngine?.muteLocalAudioStream(muted)
        userMutedMic = muted
        Log.d(TAG, "[AGORA_CALL] mic muted=$muted")
    }

    /** 사용자가 직접 음소거 버튼 누른 상태인지 추적 — 워치독은 이 경우 건드리지 않음 */
    @Volatile
    private var userMutedMic: Boolean = false

    /**
     * 마이크 트랙 알라이브 워치독 (큐알쳇 v4.0.168 강화판).
     *
     * 증상:
     *   스피커폰 통화 + 책상에 내려놓음 → 화면 OFF 약 5초 후 상대방이 내 목소리 못 들음.
     *   화면 OFF 후 OEM 절전 정책이 마이크 캡처 트랙을 백그라운드로 분류해 끊어버림.
     *
     * 진짜 복구:
     *   updateChannelMediaOptions(publishMicrophoneTrack=false → true) 토글
     *   = Agora 공식 가이드의 "마이크 publish 재발행" 절차.
     *   끊긴 트랙이 다시 채널로 송신되기 시작함.
     *
     * 라우팅(speaker/earpiece) 건드리지 않음. 트랙 publish 만 재시작.
     */
    fun ensureMicAlive() {
        if (userMutedMic) return // 사용자가 의도적으로 음소거한 상태는 존중
        val engine = rtcEngine ?: return
        try {
            // 1단계: 가벼운 보강 (이미 살아있으면 SDK 내부에서 NO-OP)
            engine.enableLocalAudio(true)
            engine.muteLocalAudioStream(false)

            // 2단계: 트랙 재발행 — 끊긴 publish 를 강제 재시작
            //   ChannelMediaOptions 는 변경된 필드만 적용(diff 기반)이라
            //   false → true 토글이 SDK 내부에서 새 microphone source 를 붙임.
            val optOff = ChannelMediaOptions().apply {
                publishMicrophoneTrack = false
            }
            engine.updateChannelMediaOptions(optOff)
            val optOn = ChannelMediaOptions().apply {
                publishMicrophoneTrack = true
            }
            engine.updateChannelMediaOptions(optOn)
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL] ensureMicAlive failed: ${e.message}")
        }
    }

    /**
     * 스피커폰 토글
     */
    fun setSpeakerOn(on: Boolean) {
        rtcEngine?.setEnableSpeakerphone(on)
        Log.d(TAG, "[AGORA_CALL] speaker on=$on")
    }

    /**
     * 카메라 토글 (영상통화).
     *
     * notifyPeer=true 면 상대방에게 "CAMERA_ON" / "CAMERA_OFF" 시그널 전송.
     *   - 본인 카메라 OFF → 상대방 화면에서도 본인 마지막 프레임을 즉시 검정 처리하기 위함.
     *   - Agora 의 muteLocalVideoStream 만으로는 상대 SurfaceView 마지막 프레임이 잔상으로 남음.
     */
    fun setCameraOn(on: Boolean, notifyPeer: Boolean = true) {
        if (on) {
            rtcEngine?.enableLocalVideo(true)
            rtcEngine?.muteLocalVideoStream(false)
        } else {
            rtcEngine?.muteLocalVideoStream(true)
        }
        Log.d(TAG, "[AGORA_CALL] camera on=$on notifyPeer=$notifyPeer")

        if (notifyPeer) {
            sendSignalToPeer(if (on) "CAMERA_ON" else "CAMERA_OFF")
        }
    }

    /**
     * 카메라 전환 (전면/후면)
     */
    fun switchCamera() {
        rtcEngine?.switchCamera()
    }

    /**
     * 음성통화 → 영상통화 전환 (양방향).
     *   현재 채널을 끊지 않고 비디오 트랙만 활성화한다.
     *   - enableVideo(): 비디오 모듈 활성
     *   - enableLocalVideo(true): 로컬 비디오 캡처 시작
     *   - muteLocalVideoStream(false): 비디오 송신 활성
     *   - startPreview(): 카메라 미리보기 시작
     *   - updateChannelMediaOptions: publishCameraTrack=true, autoSubscribeVideo=true
     *
     * @param notifyPeer true 면 Data Stream 으로 상대에게 "UPGRADE_TO_VIDEO" 시그널을 보낸다.
     *                   상대측은 onRemoteUpgradeToVideo() 콜백에서 자동으로 동일 호출하므로
     *                   양쪽이 모두 영상 송수신 가능 상태가 된다.
     */
    fun upgradeToVideo(notifyPeer: Boolean = true) {
        try {
            val engine = rtcEngine ?: run {
                Log.e(TAG, "[AGORA_CALL] upgradeToVideo: engine null")
                return
            }
            engine.enableVideo()
            engine.enableLocalVideo(true)
            engine.muteLocalVideoStream(false)
            try {
                engine.startPreview()
            } catch (e: Exception) {
                Log.e(TAG, "[AGORA_CALL] upgradeToVideo startPreview failed (already running?): ${e.message}")
            }

            // 채널 옵션 갱신 — 송신/수신 양쪽 모두 비디오 활성
            try {
                val opt = ChannelMediaOptions().apply {
                    publishCameraTrack = true
                    autoSubscribeVideo = true
                }
                engine.updateChannelMediaOptions(opt)
                Log.d(TAG, "[AGORA_CALL] updateChannelMediaOptions video=on")
            } catch (e: Exception) {
                Log.e(TAG, "[AGORA_CALL] updateChannelMediaOptions failed: ${e.message}")
            }

            currentCallType = "video"

            // 상대방에게 "영상 전환" 시그널 전송 (Data Stream)
            if (notifyPeer) {
                sendSignalToPeer("UPGRADE_TO_VIDEO")
            }

            Log.d(TAG, "[AGORA_CALL] upgradeToVideo OK notifyPeer=$notifyPeer")
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL] upgradeToVideo failed: ${e.message}")
            throw e
        }
    }

    /**
     * Agora Data Stream 으로 상대방에게 텍스트 시그널 전송.
     *   - createDataStream 은 채널당 1번만 호출 (id 캐싱)
     *   - 페이로드는 단순 ASCII 텍스트 (개인정보 미포함) — UPGRADE_TO_VIDEO, CAMERA_ON, CAMERA_OFF 등
     */
    private fun sendSignalToPeer(message: String) {
        try {
            val engine = rtcEngine ?: return
            if (dataStreamId < 0) {
                val cfg = DataStreamConfig().apply {
                    syncWithAudio = false
                    ordered = true
                }
                dataStreamId = engine.createDataStream(cfg)
                Log.d(TAG, "[AGORA_CALL] dataStream created id=$dataStreamId")
            }
            if (dataStreamId >= 0) {
                val payload = message.toByteArray(Charsets.UTF_8)
                val ret = engine.sendStreamMessage(dataStreamId, payload)
                Log.d(TAG, "[AGORA_CALL] sendStreamMessage '$message' ret=$ret")
            }
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL] sendSignalToPeer('$message') failed: ${e.message}")
        }
    }

    /**
     * 현재 sessionId (외부 검증용)
     */
    fun getCurrentSessionId(): String? = currentSessionId

    /**
     * RtcEngine 참조 (영상 표면 설정용 — Activity 에서 setupLocalVideo/setupRemoteVideo 호출)
     */
    fun getRtcEngine(): RtcEngine? = rtcEngine

    /**
     * 엔진 완전 해제 (앱 종료 시)
     */
    @Synchronized
    fun destroy() {
        try {
            endCallInternal()
            RtcEngine.destroy()
            rtcEngine = null
            managerScope.cancel()
            Log.d(TAG, "[AGORA_CALL] engine destroyed")
        } catch (e: Exception) {
            Log.e(TAG, "[AGORA_CALL] destroy failed: ${e.message}")
        }
    }

    /**
     * Agora SDK 이벤트 핸들러
     */
    private val engineEventHandler = object : IRtcEngineEventHandler() {
        override fun onJoinChannelSuccess(channel: String?, uid: Int, elapsed: Int) {
            Log.d(TAG, "[AGORA_CALL] joined channel uid=$uid elapsed=${elapsed}ms")
            currentListener?.onJoinedChannel(channel ?: "", uid)
        }

        override fun onUserJoined(uid: Int, elapsed: Int) {
            Log.d(TAG, "[AGORA_CALL] remote user joined uid=$uid")
            currentListener?.onRemoteUserJoined(uid)
        }

        override fun onUserOffline(uid: Int, reason: Int) {
            Log.d(TAG, "[AGORA_CALL] remote user offline uid=$uid reason=$reason")
            currentListener?.onRemoteUserLeft(uid, reason)
        }

        override fun onError(err: Int) {
            Log.e(TAG, "[AGORA_CALL] error code=$err")
            currentListener?.onCallError(err, "Agora error $err")
        }

        override fun onConnectionLost() {
            Log.w(TAG, "[AGORA_CALL] connection lost")
            currentListener?.onConnectionLost()
        }

        override fun onConnectionStateChanged(state: Int, reason: Int) {
            Log.d(TAG, "[AGORA_CALL] connectionState state=$state reason=$reason")
            currentListener?.onConnectionStateChanged(state, reason)
        }

        // Data Stream 메시지 수신 — 음성↔영상 전환 / 카메라 토글 시그널 처리
        override fun onStreamMessage(uid: Int, streamId: Int, data: ByteArray?) {
            try {
                val msg = data?.toString(Charsets.UTF_8) ?: return
                Log.d(TAG, "[AGORA_CALL] onStreamMessage uid=$uid msg=$msg")
                when (msg) {
                    "UPGRADE_TO_VIDEO" -> {
                        // 상대가 음성→영상 전환 → 본인도 비디오 활성. notifyPeer=false (핑퐁 방지)
                        try {
                            upgradeToVideo(notifyPeer = false)
                        } catch (e: Exception) {
                            Log.e(TAG, "[AGORA_CALL] auto upgradeToVideo failed: ${e.message}")
                        }
                        currentListener?.onRemoteUpgradeToVideo()
                    }
                    "CAMERA_OFF" -> {
                        // 상대가 카메라 OFF → 본인 화면의 상대 비디오 영역을 즉시 검정 처리해야 함
                        currentListener?.onRemoteCameraToggle(false)
                    }
                    "CAMERA_ON" -> {
                        currentListener?.onRemoteCameraToggle(true)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "[AGORA_CALL] onStreamMessage handle failed: ${e.message}")
            }
        }
    }
}
