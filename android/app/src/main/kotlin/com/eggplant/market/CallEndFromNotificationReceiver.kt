package com.eggplant.market

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Eggplant v1.0.142 — Handles "End call" action from the ongoing-call foreground notification.
 *
 * 진행 중 통화 알림(CallForegroundService)의 "통화 종료" 버튼 처리.
 * this receiver tells Flutter (via MethodChannel) to end the call,
 * and stops the foreground service.
 *
 * The actual session cleanup (Agora leave, signaling, audio mode) is done
 * by Flutter call_service._cleanupCall() / Native AgoraCallManager.cleanupState().
 *
 * Triggered by: CallForegroundService.ACTION_END_CALL = "com.eggplant.market.ACTION_END_CALL_FROM_NOTIFICATION"
 */
class CallEndFromNotificationReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CALL_KEEP"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != CallForegroundService.ACTION_END_CALL) return

        Log.e(TAG, "[$TAG] End call from notification tapped")

        // Android 12+ 는 알림 버튼 → BroadcastReceiver → Activity 실행(트램펄린)을
        // 막는다. 그래서 MainActivity 를 띄우지 않고 직접 처리한다.
        if (AgoraCallActivity.isActive) {
            // 네이티브 통화 화면 통화 — 그 화면의 종료 처리(서버 종료 신호 포함)를 그대로 호출.
            AgoraCallActivity.endFromNotification()
        } else {
            // Flutter 통화 — 살아 있는 Flutter 엔진에 종료를 알린다 (WebSocket call_end).
            val delivered = MainActivity.notifyFlutterEndFromNotification()
            if (!delivered) Log.e(TAG, "[$TAG] Flutter engine not available — stopping service only")
        }
        CallForegroundService.stop(context)
    }
}
