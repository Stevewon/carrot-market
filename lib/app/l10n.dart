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

/// 앱 언어 — 큐알챗처럼 사용자가 고른다 (첫 실행 언어 선택 화면 · 마이페이지 "언어").
///   한국어 → 새로 가입하면 한국 회원(한국 동네 · 원화)
///   日本語 → 새로 가입하면 일본 회원(일본 지역 · 엔화)
///   English → 새로 가입하면 필리핀 회원(필리핀 지역 · 페소)
/// 이미 가입한 회원의 지역·화폐는 계정 시장(users.market)을 따르고, 언어만 바뀐다.
/// 첫 화면의 기본 선택은 접속 IP 의 나라 (GET /api/geo — 일본 IP 면 日本語, 필리핀 IP 면 English).
class L10n {
  static const String _force = String.fromEnvironment('FORCE_LOCALE');
  static const String _kLang = 'app_lang';
  static const String _kMarket = 'app_market'; // IP 판별 결과 (기본 선택용)

  static String? _lang;
  static String? _ipMarket;

  /// 언어를 고르거나 바꾸면 값이 올라가고 MaterialApp 이 다시 그린다.
  static final ValueNotifier<int> notifier = ValueNotifier(0);

  /// runApp 전에 한 번. 고른 언어를 읽고, 아직 안 골랐으면 IP 로 기본 선택을 정한다.
  static Future<void> init(SharedPreferences prefs) async {
    final saved = prefs.getString(_kLang);
    _lang = _codes.contains(saved) ? saved : null;
    _ipMarket = prefs.getString(_kMarket);
    notifier.value++;
    if (_lang != null || _ipMarket != null) return;
    try {
      final res = await Dio(BaseOptions(
        baseUrl: AppConfig.apiBase,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
      )).get('/api/geo');
      final m = (res.data is Map) ? res.data['market']?.toString() : null;
      if (m == 'jp' || m == 'kr' || m == 'ph') {
        _ipMarket = m;
        await prefs.setString(_kMarket, m!);
      }
    } catch (e) {
      debugPrint('[L10n] geo 판별 실패 → 기기 언어로: $e');
    }
    notifier.value++;
  }

  /// 사용자가 언어를 골랐는지 (안 골랐으면 첫 실행 언어 선택 화면).
  static bool get hasChosen => _force.isNotEmpty || _lang != null;

  static const List<String> _codes = ['ko', 'ja', 'en'];

  /// 'ko' | 'ja' | 'en' 저장 후 앱 전체 언어를 바꾼다.
  static Future<void> setLanguage(String lang, SharedPreferences prefs) async {
    if (!_codes.contains(lang)) return;
    _lang = lang;
    await prefs.setString(_kLang, lang);
    notifier.value++;
  }

  /// 아직 고르기 전의 기본 언어 — IP(일본 → ja, 필리핀 → en), 판별 실패면 기기 언어.
  static String get suggested {
    if (_ipMarket != null) return langOfMarket(_ipMarket!);
    final d = PlatformDispatcher.instance.locale.languageCode;
    return _codes.contains(d) ? d : 'ko';
  }

  static String get lang {
    if (_force.isNotEmpty) return _codes.contains(_force) ? _force : 'ko';
    return _lang ?? suggested;
  }

  static bool get isJapanese => lang == 'ja';
  static bool get isEnglish => lang == 'en';

  /// 시장 → 언어 (jp → ja, ph → en, 그 외 ko).
  static String langOfMarket(String market) => market == 'jp' ? 'ja' : market == 'ph' ? 'en' : 'ko';

  /// 언어에 따른 시장 — 서버 X-Market 헤더(응답 언어)와 새 가입 시장에 쓴다.
  static String get market => isJapanese ? 'jp' : isEnglish ? 'ph' : 'kr';

  static Locale get locale => Locale(lang);

  static const List<Locale> supported = [Locale('ko'), Locale('ja'), Locale('en')];

  /// 언어 이름 (그 언어로) — 언어 선택 · 마이페이지 표시용.
  static const Map<String, String> names = {'ko': '한국어', 'ja': '日本語', 'en': 'English'};

  /// 위젯 밖(서비스·모델)에서 쓰는 문구.
  static AppLocalizations get current => lookupAppLocalizations(locale);
}
