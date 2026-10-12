import 'package:intl/intl.dart';

import '../models/user.dart';
import 'l10n.dart';

/// 한국/일본/필리핀 시장.
///   kr — 한국어 · 원 · 한국 동네 · 1 QTA = 10원
///   jp — 일본어 · 엔 · 일본 지역 · 1 QTA = 1엔
///   ph — 영어 · 페소 · 필리핀 지역 · 1 QTA = 1페소
/// 회원 시장은 가입 때 기기 언어로 정해져 서버(users.market)에 남는다.
class AppMarket {
  static String get device => L10n.market;

  static String of(User? u) => u?.market ?? device;

  static bool isJp(String market) => market == 'jp';
  static bool isPh(String market) => market == 'ph';

  /// 현지 화폐 몇 단위가 1 QTA 인가.
  static int moneyPerQta(String market) => isJp(market) || isPh(market) ? 1 : 10;

  /// 가격 입력칸 앞 기호.
  static String currencyPrefix(String market) => isJp(market) ? '¥ ' : isPh(market) ? '₱ ' : '₩ ';

  static final NumberFormat _thousands = NumberFormat('#,###');

  static String thousands(int n) => n == 0 ? '0' : _thousands.format(n);

  /// 10,000원 / ¥10,000 / ₱10,000. 0 이면 나눔(無料).
  static String formatPrice(int price, String market) {
    if (price == 0) return L10n.current.commonFree;
    return money(price, market);
  }

  /// 금액 표기 — 0 도 금액으로 (formatPrice 는 0 을 '나눔' 으로 바꿈).
  static String money(int amount, String market) {
    final t = L10n.current;
    final n = thousands(amount);
    return isJp(market) ? t.priceJpy(n) : isPh(market) ? t.pricePhp(n) : t.priceKrw(n);
  }
}
