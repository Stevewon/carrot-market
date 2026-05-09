package com.eggplant.market

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Eggplant v1.0.142 — Handles "End call" action from the ongoing-call foreground notification.
 *
 * When the user taps "End call" on the ongoing notification (CallForegroundService 발행),
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

        // Stop the foreground service
        CallForegroundService.stop(context)

        // Launch MainActivity so Flutter can handle endCall()
        // The MethodChannel will handle the actual call termination + WebSocket call_end signal.
        try {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("end_call_from_notification", true)
            }
            context.startActivity(launchIntent)
            Log.e(TAG, "[$TAG] MainActivity launched for end call")
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] Failed to launch MainActivity for end call: ${e.message}")
        }
    }
}
