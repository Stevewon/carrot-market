package com.eggplant.market

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Eggplant v1.0.142 — FCM service: incoming call routing (3 routes).
 *
 * Q3=생략 + Agora flow 단순화:
 *   - Telecom ConnectionService (PhoneAccountManager) 분기 제거 — Agora 가 미디어 처리
 *   - DeviceTypeUtil TV 분기 제거 — Eggplant 는 모바일 전용
 *   - QRChatConnection 의존성 제거
 *
 * Route 1: Eggplant foreground -> Flutter handles (do not touch)
 *   단, agora=1 푸시는 항상 heads-up 으로 통일 처리 (Flutter 가 Firestore 미경유라 처리 못 함)
 * Route 2: Screen ON + unlocked + other app -> heads-up + ringtone
 * Route 3: Screen OFF / locked / app killed -> WakeLock + FSI direct send + ringtone
 *
 * FCM payload (data-only) — Phase 4 에서 chat-hub.ts 가 송신:
 *   - type: "incoming_call" | "call_cancelled" | "call_ended"
 *   - sessionId: 세션 ID
 *   - callerId: 발신자 wallet
 *   - callerNickname: 발신자 닉네임
 *   - callType: "audio" | "video"
 *   - callerProfilePhoto: 프로필 URL (optional)
 *   - channel: "eggplant_call_<sortedLowerWalletPair>" (Eggplant 신규)
 *   - agora: "1" (Eggplant default — 항상 Agora)
 *
 * NO call records on server (CRITICAL INVARIANT) — D1 INSERT 0건.
 *
 * 절대 금지:
 *   - startActivity() 직접 호출 (홈화면 노출 원인)
 *   - Handler.post { startActivity } (같은 원인)
 */
class EggplantFirebaseMessagingService : FlutterFirebaseMessagingService() {
    companion object {
        private const val TAG = "Eggplant.FCM"

        // MainActivity / Flutter 측이 foreground 진입/이탈 시 toggle
        @Volatile
        var isAppForeground = false
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val type = data["type"] ?: ""

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val screenOn = pm.isInteractive
        val locked = km.isKeyguardLocked

        Log.e("CALL_PATH", "[CALL_PATH] FCM type=$type fg=$isAppForeground screenOn=$screenOn locked=$locked")

        // ================================================================
        // 발신자가 통화를 끊었을 때 수신자 벨/UI 정지 처리
        //   서버 chat-hub.ts (call_cancel/call_end) 가 발송.
        //   문제 사례 방지: Flutter 미동작 시에도 NativeIncomingCallActivity 종료 보장.
        // ================================================================
        if (type == "call_cancelled" || type == "call_ended" || type == "call_cancel" || type == "call_end") {
            val cancelSessionId = data["sessionId"] ?: ""
            val reason = data["reason"] ?: "unknown"
            Log.e("CALL_PATH", "[CALL_PATH] $type session=$cancelSessionId reason=$reason")
            try {
                // cleanupIncomingState: stopRingtone + cancelIncomingCallNotification + clearNativeIncomingActive
                CallNotificationHelper.cleanupIncomingState(this, cancelSessionId)
                // NativeIncomingCallActivity 가 떠있으면 finish() 시키도록 broadcast 발송
                val cancelIntent = Intent(NativeIncomingCallActivity.ACTION_CANCEL_INCOMING).apply {
                    setPackage(packageName)
                    putExtra(NativeIncomingCallActivity.EXTRA_SESSION_ID, cancelSessionId)
                }
                sendBroadcast(cancelIntent)
                Log.e("CALL_PATH", "[CALL_PATH] cancel broadcast sent session=$cancelSessionId")
            } catch (e: Exception) {
                Log.e("CALL_PATH", "[CALL_PATH] $type handling failed: ${e.message}")
            }
            return
        }

        if (type != "incoming_call") {
            // 일반 채팅/시스템 푸시는 FlutterFirebaseMessagingService 기본 처리에 위임
            super.onMessageReceived(message)
            return
        }

        // ================================================================
        // incoming_call 처리 시작
        // ================================================================
        val sessionId   = data["sessionId"] ?: ""
        val callerId    = data["callerId"] ?: ""
        val callerName  = data["callerNickname"] ?: data["callerName"] ?: "Unknown"
        val callType    = data["callType"] ?: "audio"
        val callerPhoto = data["callerProfilePhoto"] ?: ""
        // Eggplant: agora default true — 명시적 "0" 일 때만 false
        val agoraFlag   = data["agora"] != "0"
        // Eggplant 신규: 채널명 (FCM payload 에서 직접 전달, 폴백은 caller+receiver wallet 으로 재구성)
        val channelName = data["channel"] ?: ""
        // ★ v1.0.159 (2026-05-11): callerWallet — 발신자의 지갑주소.
        //   server chat-hub.ts 가 callerWallet (camelCase) + caller_wallet (snake_case) 둘 다 보냄.
        //   v1.0.158 까지 native 가 이 필드를 읽지 않아서 Flutter 측 _peerWalletAddress
        //   가 user_id 로 잘못 들어가 'wallet missing (my=ok, peer=empty)' 발생.
        val callerWallet = data["callerWallet"] ?: data["caller_wallet"] ?: ""
        // Eggplant: 본인 지갑주소 (수신자) — SharedPreferences 에서 fallback
        val walletAddress = AgoraTokenService.readWalletAddress(this)

        Log.e("CALL_PATH", "[CALL_PATH] incoming session=$sessionId caller=$callerName type=$callType agora=$agoraFlag channel=$channelName walletEmpty=${walletAddress.isEmpty()} callerWalletEmpty=${callerWallet.isEmpty()}")

        // ================================================================
        // Route 1: Eggplant foreground -> Flutter handles (do not touch)
        //   단, agora=1 푸시는 Flutter 가 처리 못 함 (Firestore 미경유 — Eggplant 는 WebSocket).
        //   → 포그라운드여도 heads-up 알림으로 통일 처리.
        //   → Eggplant 는 항상 agoraFlag=true 이므로 사실상 항상 heads-up.
        // ================================================================
        if (isAppForeground) {
            if (agoraFlag) {
                Log.e("CALL_PATH", "[CALL_PATH] fg+agora=1 → heads-up (callee chooses to accept)")
                CallNotificationHelper.setNativeIncomingActive(this, sessionId)
                CallNotificationHelper.showHeadsUpNotification(
                    context = this,
                    sessionId = sessionId,
                    callerId = callerId,
                    callerName = callerName,
                    callType = callType,
                    callerPhoto = callerPhoto,
                    agoraFlag = true,
                    channelName = channelName,
                    walletAddress = walletAddress,
                    callerWallet = callerWallet,
                )
                CallNotificationHelper.startRingtoneImmediately(this, sessionId)
                return
            }
            Log.e("CALL_PATH", "[CALL_PATH] route1 foreground -> skip (Flutter handles)")
            return
        }

        // ================================================================
        // Route 2: Other app + screen ON + unlocked -> heads-up
        //   - CallStyle.forIncomingCall + FSI for heads-up retention (30s)
        //   - 2 buttons: Reject / Answer
        //   - ringtone
        //   nativeIncomingActive flag 설정 → Flutter 이중 표시 차단
        // ================================================================
        if (screenOn && !locked) {
            Log.e("CALL_HUD", "[CALL_HUD] route2 headsUp sessionId=$sessionId")
            CallNotificationHelper.setNativeIncomingActive(this, sessionId)
            CallNotificationHelper.showHeadsUpNotification(
                context = this,
                sessionId = sessionId,
                callerId = callerId,
                callerName = callerName,
                callType = callType,
                callerPhoto = callerPhoto,
                agoraFlag = agoraFlag,
                channelName = channelName,
                walletAddress = walletAddress,
                callerWallet = callerWallet,
            )
            CallNotificationHelper.startRingtoneImmediately(this, sessionId)
            return
        }

        // ================================================================
        // Route 3: Screen OFF / locked / app killed
        //   - WakeLock 으로 화면 켜기 (ACQUIRE_CAUSES_WAKEUP)
        //   - showHeadsUpWithFullScreenFallback: FSI direct send (full-screen ONLY, NO heads-up)
        //   - 벨소리 시작
        //
        //   Q3=생략 + Agora flow: Telecom ConnectionService 분기 완전 제거.
        //   Agora 가 미디어 처리하므로 OS Telecom UI 불필요. FSI 만으로 충분.
        //
        //   절대 금지: startActivity() 직접 호출
        // ================================================================
        Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] locked/off sessionId=$sessionId screenOn=$screenOn locked=$locked")

        // Flutter IncomingCallScreen 이중 표시 차단
        CallNotificationHelper.setNativeIncomingActive(this, sessionId)

        // Step 1: WakeLock 으로 화면 켜기 — FSI 가 보이려면 화면이 켜져야 함
        try {
            val wakeLock = pm.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "eggplant:IncomingCall"
            )
            wakeLock.acquire(10_000L)  // 10초 후 자동 해제
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] WakeLock acquired for FSI sessionId=$sessionId")
        } catch (e: Exception) {
            Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] WakeLock acquire failed: ${e.message}")
        }

        // Step 2: FSI direct send (잠금화면 풀스크린 단독, NO heads-up — 이중 노출 방지)
        CallNotificationHelper.showHeadsUpWithFullScreenFallback(
            context = this,
            sessionId = sessionId,
            callerId = callerId,
            callerName = callerName,
            callType = callType,
            callerPhoto = callerPhoto,
            agoraFlag = agoraFlag,
            channelName = channelName,
            walletAddress = walletAddress,
            callerWallet = callerWallet,
        )

        // Step 3: 벨소리 시작
        CallNotificationHelper.startRingtoneImmediately(this, sessionId)

        Log.e("CALL_LOCK_REAL", "[CALL_LOCK_REAL] route3 fired sessionId=$sessionId")
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "[FCM] new token len=${token.length}")
    }
}
