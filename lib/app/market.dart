import 'package:intl/intl.dart';

import '../models/user.dart';
import 'l10n.dart';

/// 한국/일본 시장.
///   kr — 한국어 · 원 · 한국 동네 · 1 QTA = 10원
///   jp — 일본어 · 엔 · 일본 지역 · 1 QTA = 1엔
/// 회원 시장은 가입 때 기기 언어로 정해져 서버(users.market)에 남는다.
class AppMarket {
  static String get device => L10n.isJapanese ? 'jp' : 'kr';

  static String of(User? u) => u?.market ?? device;

  static bool isJp(String market) => market == 'jp';

  /// 현지 화폐 몇 단위가 1 QTA 인가.
  static int moneyPerQta(String market) => isJp(market) ? 1 : 10;

  static final NumberFormat _thousands = NumberFormat('#,###');

  static String thousands(int n) => n == 0 ? '0' : _thousands.format(n);

  /// 10,000원 / ¥10,000. 0 이면 나눔(無料).
  static String formatPrice(int price, String market) {
    final t = L10n.current;
    if (price == 0) return t.commonFree;
    return isJp(market) ? t.priceJpy(thousands(price)) : t.priceKrw(thousands(price));
  }
}
