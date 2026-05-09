package com.eggplant.market

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * v1.0.142: Agora RTC 토큰 발급 클라이언트 (큐알쳇 v4.0.114 이식)
 *
 * Cloudflare Workers `/api/users/agora/token` 을 호출해 Agora 채널 입장용 토큰을 받아옴.
 *
 * 큐알쳇 (Firebase Functions) → 에그플랜트 (HTTPS GET + JWT) 변환:
 *   - Firebase Auth/Functions 의존성 제거
 *   - JWT 인증 (SharedPreferences 의 미러링된 토큰 사용)
 *   - Dart AgoraService._requestToken() 과 동일한 엔드포인트/파라미터/응답 형식
 *
 * 보안 모델:
 *   - App Certificate 는 Workers Secret 에만 존재
 *   - 클라이언트는 짧은 수명(1시간) 토큰만 받음
 *   - JWT 가 walletAddress 로 검증됨 → 임의 채널 발급 불가 (서버에서 검증)
 *
 * 사용 예 (Kotlin coroutine):
 *   val result = AgoraTokenService.fetchToken(context, channelName, uid, "rtc")
 *   val token = result.token
 *   val appId = result.appId
 *
 * 토큰 데이터 zero 정책:
 *   - 토큰은 메모리에만 보관, 통화 종료 시 즉시 폐기
 *   - 디스크/SharedPreferences 미저장
 */
object AgoraTokenService {
    private const val TAG = "AGORA_TOKEN"

    /**
     * SharedPreferences 키 — auth_service.dart 가 로그인 직후 미러링.
     * (Phase 5 에서 Dart 측에 채워 넣음)
     */
    private const val PREFS_NAME = "eggplant_native_call"
    private const val KEY_JWT = "jwt_token"
    private const val KEY_WALLET = "wallet_address"

    /**
     * 토큰 응답 데이터 클래스 (큐알쳇과 동일 인터페이스)
     */
    data class TokenResult(
        val token: String,
        val appId: String,
        val expireAt: Long,  // Unix epoch seconds
    )

    /**
     * Cloudflare Workers `/api/users/agora/token` 호출.
     *
     * @param channelName Agora 채널명 (sortedWalletPair 기반, 양쪽 동일)
     * @param uid 발급받을 Agora UID (지갑주소 기반 결정론적)
     * @param kind "rtc" (통화) 또는 "rtm" (시그널링) — Eggplant 통화는 항상 "rtc"
     * @return TokenResult { token, appId, expireAt }
     * @throws Exception 인증 실패 / 네트워크 오류 / 서버 미설정
     */
    suspend fun fetchToken(
        context: Context,
        channelName: String,
        uid: Int,
        kind: String = "rtc",
    ): TokenResult = withContext(Dispatchers.IO) {
        val jwt = readJwt(context)
        if (jwt.isNullOrBlank()) {
            throw IllegalStateException("Not logged in (jwt missing in eggplant_native_call prefs)")
        }

        val urlStr = buildString {
            append(AgoraConfig.API_BASE_URL)
            append(AgoraConfig.TOKEN_PATH)
            append("?kind=").append(URLEncoder.encode(kind, "UTF-8"))
            append("&uid=").append(uid)
            append("&channel=").append(URLEncoder.encode(channelName, "UTF-8"))
        }

        Log.d(TAG, "[AGORA_TOKEN] requesting kind=$kind uid=$uid chLen=${channelName.length}")

        val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 8_000
            readTimeout = 8_000
            setRequestProperty("Authorization", "Bearer $jwt")
            setRequestProperty("Accept", "application/json")
            doInput = true
        }

        try {
            val code = conn.responseCode
            if (code != 200) {
                val errText = try {
                    (conn.errorStream ?: conn.inputStream)?.bufferedReader()?.use { it.readText() }
                        ?: ""
                } catch (_: Exception) { "" }
                Log.e(TAG, "[AGORA_TOKEN] HTTP $code body=${errText.take(200)}")
                throw IllegalStateException("Token endpoint HTTP $code")
            }

            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            val token = json.optString("token", "")
            if (token.isBlank()) {
                throw IllegalStateException("token field missing in response")
            }
            // 서버는 expire_at(snake_case) 또는 expireAt(camelCase) 양쪽 가능 — 둘 다 시도
            val expireAt = when {
                json.has("expire_at") -> json.optLong("expire_at")
                json.has("expireAt") -> json.optLong("expireAt")
                else -> System.currentTimeMillis() / 1000 + AgoraConfig.TOKEN_TTL_SECONDS
            }
            val appId = json.optString("app_id").ifBlank {
                json.optString("appId").ifBlank { AgoraConfig.APP_ID }
            }
            Log.d(TAG, "[AGORA_TOKEN] received tokenLen=${token.length} expireAt=$expireAt")
            TokenResult(token, appId, expireAt)
        } finally {
            try { conn.disconnect() } catch (_: Exception) {}
        }
    }

    /**
     * 로그인된 walletAddress 조회 (네이티브 통화 채널명 생성용).
     *
     * Eggplant: non-null String 반환 — 미로그인/미저장 시 빈 문자열.
     * 호출처가 `walletAddress.isEmpty()` 로 판단하도록 통일.
     *
     * @return walletAddress 소문자 정규화 또는 빈 문자열
     */
    fun readWalletAddress(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_WALLET, "")?.trim()?.lowercase() ?: ""
    }

    /**
     * Dart 측에서 미러링한 JWT 조회.
     */
    private fun readJwt(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_JWT, null)?.takeIf { it.isNotBlank() }
    }

    /**
     * 통화 종료/로그아웃 시 토큰 캐시 비움.
     * (현재는 캐시 안 쓰지만, 추후 추가 시 안전망)
     */
    fun clearCache() {
        // No-op for now — future-proof
    }
}
