package com.eggplant.market

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * 네이티브 통화 화면 → 서버 통화 신호 (POST /api/calls/signal).
 *
 * 앱이 백그라운드·종료·잠금 상태에서 받은 통화는 네이티브 화면이 처리한다.
 * 예전에는 수락/거절 때 MainActivity(Flutter)를 깨워 WebSocket 으로 응답을 보냈는데,
 * 콜드 스타트에서는 Dart 핸들러가 붙기 전에 신호가 사라져 발신자가 영영 응답을
 * 받지 못했다. 이제 Dart 가 미러링해 둔 JWT 로 서버에 직접 보낸다.
 *
 * 네트워크 호출은 전용 단일 스레드에서 하고, 실패 시 1회 재시도한다.
 */
object CallSignalClient {
    private const val TAG = "CALL_SIGNAL"
    private const val PATH = "/api/calls/signal"
    private val executor = Executors.newSingleThreadExecutor()

    /** 수락/거절 응답. */
    fun sendResponse(context: Context, callId: String, toUserId: String, accepted: Boolean) {
        send(context, JSONObject().apply {
            put("type", "response")
            put("call_id", callId)
            put("to_user_id", toUserId)
            put("accepted", accepted)
        })
    }

    /** 통화 종료 (수락 후 끊기, 연결 실패 등). */
    fun sendEnd(context: Context, callId: String, toUserId: String) {
        send(context, JSONObject().apply {
            put("type", "end")
            put("call_id", callId)
            put("to_user_id", toUserId)
        })
    }

    private fun send(context: Context, body: JSONObject) {
        val appCtx = context.applicationContext
        val callId = body.optString("call_id")
        val to = body.optString("to_user_id")
        if (callId.isEmpty() || to.isEmpty()) {
            Log.e(TAG, "[$TAG] skip — callId/toUserId empty type=${body.optString("type")}")
            return
        }
        executor.execute {
            val jwt = appCtx.getSharedPreferences(MainActivity.NATIVE_CALL_PREFS, Context.MODE_PRIVATE)
                .getString(MainActivity.KEY_JWT, null)
            if (jwt.isNullOrBlank()) {
                Log.e(TAG, "[$TAG] skip — not logged in (jwt missing)")
                return@execute
            }
            for (attempt in 0 until 2) {
                if (post(AgoraConfig.apiBaseUrl(appCtx), jwt, body)) return@execute
                try { Thread.sleep(700) } catch (_: InterruptedException) {}
            }
            Log.e(TAG, "[$TAG] failed after retry type=${body.optString("type")}")
        }
    }

    private fun post(baseUrl: String, jwt: String, body: JSONObject): Boolean {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(baseUrl + PATH).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8_000
                readTimeout = 8_000
                doOutput = true
                setRequestProperty("Authorization", "Bearer $jwt")
                setRequestProperty("Content-Type", "application/json")
            }
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            Log.d(TAG, "[$TAG] type=${body.optString("type")} HTTP $code")
            code in 200..299
        } catch (e: Exception) {
            Log.e(TAG, "[$TAG] request error: ${e.message}")
            false
        } finally {
            try { conn?.disconnect() } catch (_: Exception) {}
        }
    }
}
