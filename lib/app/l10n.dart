import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/gen/app_localizations.dart';
import 'constants.dart';

export '../l10n/gen/app_localizations.dart';

/// 화면에서: `context.l10n.commonCancel`
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// 앱 언어·시장 — 접속 IP 의 나라로 정한다.
///   일본 IP → 일본어 · 일본 지역 · 엔화, 그 외 → 한국어 · 한국 동네 · 원화.
/// 처음 실행할 때 서버 GET /api/geo (Cloudflare 가 IP 로 판별) 로 정해 기억하고,
/// 로그인하면 계정의 시장(users.market)을 따른다.
/// 시험용: `--dart-define=FORCE_LOCALE=ja` 로 강제.
class L10n {
  static const String _force = String.fromEnvironment('FORCE_LOCALE');
  static const String _kMarket = 'app_market';

  static String? _market;

  /// runApp 전에 한 번. 저장된 값이 없으면 IP 로 판별 (최대 3초, 실패하면 기기 언어).
  static Future<void> init(SharedPreferences prefs) async {
    _market = prefs.getString(_kMarket);
    if (_market != null) return;
    try {
      final res = await Dio(BaseOptions(
        baseUrl: AppConfig.apiBase,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
      )).get('/api/geo');
      final m = (res.data is Map) ? res.data['market']?.toString() : null;
      if (m == 'jp' || m == 'kr') {
        _market = m;
        await prefs.setString(_kMarket, m!);
        return;
      }
    } catch (e) {
      debugPrint('[L10n] geo 판별 실패 → 기기 언어로: $e');
    }
    // 판별 실패는 저장하지 않는다 → 다음 실행에 다시 IP 로 시도.
    _market = PlatformDispatcher.instance.locale.languageCode == 'ja' ? 'jp' : 'kr';
  }

  /// 로그인한 계정의 시장으로 맞춘다 (가입 때 정해진 값이 기준).
  static Future<void> adopt(String market, SharedPreferences prefs) async {
    if (market != 'jp' && market != 'kr') return;
    _market = market;
    await prefs.setString(_kMarket, market);
  }

  static String get market {
    if (_force.isNotEmpty) return _force == 'ja' ? 'jp' : 'kr';
    return _market ??
        (PlatformDispatcher.instance.locale.languageCode == 'ja' ? 'jp' : 'kr');
  }

  static bool get isJapanese => market == 'jp';

  static Locale get locale => isJapanese ? const Locale('ja') : const Locale('ko');

  static const List<Locale> supported = [Locale('ko'), Locale('ja')];

  /// 위젯 밖(서비스·모델)에서 쓰는 문구.
  static AppLocalizations get current => lookupAppLocalizations(locale);
}
