package com.eggplant.market

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Eggplant v1.0.142 — Notification button action handler (REJECT only).
 *
 * Q3=생략 환경:
 *   Answer 버튼은 BroadcastReceiver 를 거치지 않음.
 *   CallNotificationHelper.makeAnswerPendingIntent() 는 PendingIntent.getActivity() 로
 *   NativeIncomingCallActivity 를 직접 실행 (Q3=생략으로 NativeAccept 게이트도 제거).
 *   → 따라서 ACTION_ANSWER 분기는 Eggplant 에서 제거.
 *
 * ACTION_REJECT:
 *   1. Stop ringtone
 *   2. Cancel incoming notification
 *   3. Cleanup state (including nativeIncomingActive)
 *   4. 서버에 거절 신호 직접 전송 (CallSignalClient, POST /api/calls/signal)
 *
 * 절대 금지:
 *   - 통화내역을 서버 D1 에 INSERT (CRITICAL INVARIANT)
 *   - WebRTC/peerConnection 직접 조작 (Flutter call_service 가 담당)
 */
class CallActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_REJECT = "com.eggplant.market.ACTION_REJECT_CALL"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val sessionId = intent.getStringExtra("sessionId") ?: ""

        when (action) {
            ACTION_REJECT -> {
                Log.e("CALL_ACTION", "[CALL_ACTION] notification reject tapped sessionId=$sessionId")

                // 1. Stop ringtone immediately
                CallNotificationHelper.stopRingtone()
                Log.e("CALL_ACTION", "[CALL_ACTION] ringtone stopped sessionId=$sessionId")

                // 2. Cancel incoming notification immediately
                CallNotificationHelper.cancelIncomingCallNotification(context)
                Log.e("CALL_ACTION", "[CALL_ACTION] incoming notification cancelled sessionId=$sessionId")

                // 3. Clear session state (including nativeIncomingActive)
                CallNotificationHelper.cleanupIncomingState(context, sessionId)
                Log.e("CALL_ACTION", "[CALL_ACTION] session cleared sessionId=$sessionId")

                // 4. 발신자에게 거절 신호를 서버로 직접 전송.
                //    예전엔 MainActivity 를 띄워 Flutter 가 WebSocket 으로 보냈지만,
                //    Android 12+ 는 알림 버튼 → BroadcastReceiver → Activity 실행(트램펄린)을
                //    막아서 거절이 발신자에게 도달하지 않았다.
                val callerId = intent.getStringExtra("callerId") ?: ""
                CallSignalClient.sendResponse(context, sessionId, callerId, accepted = false)
                Log.e("CALL_ACTION", "[CALL_ACTION] reject signal sent sessionId=$sessionId")
            }

            else -> {
                Log.w("CALL_ACTION", "[CALL_ACTION] unknown action=$action sessionId=$sessionId")
            }
        }
    }
}
