package com.eggplant.market

import android.content.Context
import java.util.Locale

/**
 * 네이티브 UI 문자열 언어 선택 (한국어 / 日本語).
 *
 * 앱 언어는 시스템 로케일이 아니라 Flutter 쪽(L10n)이 IP 국가로 정해
 * shared_preferences 키 `app_market` ('jp' | 'kr') 에 저장한다.
 * Flutter legacy SharedPreferences API 는 "FlutterSharedPreferences" 파일에
 * "flutter." 접두사를 붙여 저장하므로 여기서 같은 값을 읽는다.
 * 값이 없으면 시스템 로케일(ja → 일본어, 그 외 → 한국어)로 폴백.
 */
object AppLang {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_MARKET = "flutter.app_market"

    fun isJa(ctx: Context): Boolean {
        val market = try {
            ctx.applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_MARKET, null)
        } catch (_: Exception) {
            null
        }
        return when (market) {
            "jp" -> true
            "kr" -> false
            else -> Locale.getDefault().language == "ja"
        }
    }

    fun t(ctx: Context, ko: String, ja: String): String = if (isJa(ctx)) ja else ko
}
