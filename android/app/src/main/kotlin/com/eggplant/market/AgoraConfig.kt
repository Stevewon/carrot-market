package com.eggplant.market

/**
 * v1.0.142: Agora RTC 설정 상수 (큐알쳇 v4.0.113 이식)
 *
 * 통화 시스템 아키텍처:
 *   1. 발신자/수신자 모두 동일한 channelName(=sortedWalletPair) 으로 Agora 채널 입장
 *   2. 미디어는 Agora P2P/Cloud Relay (서버 미저장, DTLS-SRTP 암호화)
 *   3. 시그널링은 WebSocket(api.eggplant.life) — Firestore 미사용
 *   4. 토큰은 Cloudflare Workers `/api/users/agora/token` 에서 발급 (1시간 유효)
 *
 * 보안 모델:
 *   - APP_ID: 공개 가능 (앱 식별자)
 *   - APP_CERTIFICATE: Cloudflare Workers Secret 에만 존재 (절대 클라이언트 노출 금지)
 *   - 토큰: 채널 + UID + 만료시간으로 제한된 짧은 입장권
 *
 * 통화 데이터 zero 정책:
 *   - 통화 시간/상대방 정보 서버 저장 안 함 (사장님 명시)
 *   - FCM 푸시는 forwarding only — D1 미저장
 *   - 채널명은 매번 동일한 walletPair 로 결정론적 — 별도 sessionId 불필요
 */
object AgoraConfig {
    /**
     * Agora App ID (공개 가능)
     * - 앱 식별자일 뿐, 이 값만으로는 토큰 발급 불가
     * - APK 디컴파일로 추출 가능하지만 보안 위협 없음
     * - lib/services/agora_service.dart 의 fallback 과 동일
     */
    const val APP_ID: String = "66ee6650c8b244b1941fac87eae3fc9a"

    /**
     * Cloudflare Workers API base URL
     */
    const val API_BASE_URL: String = "https://api.eggplant.life"

    /**
     * Agora 토큰 발급 엔드포인트 (Cloudflare Workers)
     */
    const val TOKEN_PATH: String = "/api/users/agora/token"

    /**
     * 토큰 유효 시간 (초) — 서버와 동기화
     */
    const val TOKEN_TTL_SECONDS: Int = 3600

    /**
     * 채널명 prefix — Eggplant 트래픽을 큐알쳇과 분리
     * (lib/utils/agora_uid.dart 의 channelName('call', pair) 와 동일 결과)
     */
    const val CHANNEL_PREFIX: String = "eggplant_call_"

    /**
     * 1:1 통화 채널명 생성 (sorted wallet pair 기반).
     *
     * 양쪽이 같은 채널에 들어가야 통화 성립.
     * Dart 측 AgoraService.callChannel() 과 100% 동일 알고리즘.
     *
     * @param walletA 한쪽 지갑주소 (대소문자 무관)
     * @param walletB 다른쪽 지갑주소 (대소문자 무관)
     * @return "eggplant_call_<lowerA>_<lowerB>" (사전순 정렬)
     */
    fun callChannel(walletA: String, walletB: String): String {
        val a = walletA.lowercase()
        val b = walletB.lowercase()
        val pair = if (a < b) "${a}_$b" else "${b}_$a"
        return CHANNEL_PREFIX + pair
    }

    /**
     * Agora UID 계산 (지갑주소에서 결정론적으로 파생)
     *
     * 서버 utils/agoraToken.ts 의 walletToAgoraUid() 와
     * Dart utils/agora_uid.dart 의 fromWalletAddress() 와 100% 동일 알고리즘:
     *   SHA-256(lowercase(walletAddress without 0x prefix)) 의 앞 4바이트를 big-endian u32.
     *   결과가 0 이면 1 로 보정.
     */
    fun walletToUid(walletAddress: String): Int {
        var s = walletAddress.trim().lowercase()
        if (s.startsWith("0x")) s = s.substring(2)
        val hash = java.security.MessageDigest.getInstance("SHA-256")
            .digest(s.toByteArray(Charsets.UTF_8))
        val uid = (
            ((hash[0].toInt() and 0xff) shl 24) or
            ((hash[1].toInt() and 0xff) shl 16) or
            ((hash[2].toInt() and 0xff) shl 8) or
            (hash[3].toInt() and 0xff)
        )
        // Java Int 는 signed 라 음수 가능 — 양의 32-bit unsigned 로 보정 (Agora UID 제약).
        // Long 으로 변환 후 0xFFFFFFFFL & 로 unsigned 처리, 0 이면 1 로 보정.
        val unsigned = uid.toLong() and 0xFFFFFFFFL
        val finalUid = if (unsigned == 0L) 1 else unsigned.toInt()
        // toInt() 는 32-bit 그대로 보존 (Agora SDK 가 signed Int 받음, 음수도 유효)
        return finalUid
    }
}
