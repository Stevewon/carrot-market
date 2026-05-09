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
 *   4. Launch MainActivity for MethodChannel reject (WebSocket call_response=rejected)
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

                // 4. Launch MainActivity for MethodChannel reject
                //    BroadcastReceiver cannot hold MethodChannel, so launch MainActivity
                //    with reject intent. MainActivity will forward via MethodChannel
                //    → Flutter call_service sends WebSocket call_response(rejected) to caller.
                try {
                    val rejectIntent = Intent(context, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP
                        putExtra("reject_call_from_native", true)
                        putExtra("sessionId", sessionId)
                    }
                    context.startActivity(rejectIntent)
                    Log.e("CALL_ACTION", "[CALL_ACTION] MainActivity launched for reject sessionId=$sessionId")
                } catch (e: Exception) {
                    Log.e("CALL_ACTION", "[CALL_ACTION] reject launch failed: ${e.message}")
                    // Fallback: broadcast (may not reach Flutter if engine not ready)
                    val rejectBroadcast = Intent("com.eggplant.market.CALL_ACTION").apply {
                        setPackage(context.packageName)
                        putExtra("action", "reject")
                        putExtra("sessionId", sessionId)
                    }
                    context.sendBroadcast(rejectBroadcast)
                }
            }

            else -> {
                Log.w("CALL_ACTION", "[CALL_ACTION] unknown action=$action sessionId=$sessionId")
            }
        }
    }
}
