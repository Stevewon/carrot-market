import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// QTA 토큰 잔액 + 적립 내역 ledger.
///
/// 서버 응답:
///   GET /api/users/me/qta/ledger?limit=30
///     -> { balance: int, items: [{amount, reason, meta, created_at}] }
///
/// reason 값 매핑(UI 라벨):
///   signup        : 가입 보너스
///   login_daily   : 출석 보너스
///   trade_seller  : 판매 완료 보상
///   trade_buyer   : 구매 완료 보상
class QtaLedgerItem {
  final int amount;
  final String reason;
  final Map<String, dynamic>? meta;
  final DateTime createdAt;

  QtaLedgerItem({
    required this.amount,
    required this.reason,
    required this.meta,
    required this.createdAt,
  });

  factory QtaLedgerItem.fromJson(Map<String, dynamic> j) {
    return QtaLedgerItem(
      amount: (j['amount'] as num?)?.toInt() ?? 0,
      reason: j['reason']?.toString() ?? '',
      meta: j['meta'] is Map ? Map<String, dynamic>.from(j['meta'] as Map) : null,
      createdAt:
          DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  /// 사용자에게 보여줄 한국어 라벨.
  String get label {
    switch (reason) {
      case 'signup':
        return '가입 보너스';
      case 'login_daily':
        return '출석 보너스';
      case 'trade_seller':
        return '판매 완료 보상';
      case 'trade_buyer':
        return '구매 완료 보상';
      default:
        return reason;
    }
  }
}

class QtaService extends ChangeNotifier {
  final AuthService auth;
  QtaService(this.auth);

  int _balance = 0;
  final List<QtaLedgerItem> _items = [];
  bool _loading = false;
  bool _loaded = false;

  int get balance => _balance;
  List<QtaLedgerItem> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get loaded => _loaded;

  /// 서버에서 잔액 + 최근 30개 ledger 가져오기.
  Future<String?> load({int limit = 30, bool force = false}) async {
    if (_loading) return null;
    if (_loaded && !force) return null;
    _loading = true;
    notifyListeners();
    try {
      final res =
          await auth.api.get('/api/users/me/qta/ledger', queryParameters: {
        'limit': limit,
      });
      final data = res.data as Map<String, dynamic>;
      _balance = (data['balance'] as num?)?.toInt() ?? 0;
      _items
        ..clear()
        ..addAll(((data['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => QtaLedgerItem.fromJson(Map<String, dynamic>.from(m))));

      // AuthService 의 user.qtaBalance 도 동기화.
      // ignore: discarded_futures
      auth.updateQtaBalance(_balance);

      _loaded = true;
      _loading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _loading = false;
      notifyListeners();
      debugPrint('[qta] load failed: $e');
      return 'QTA 잔액을 불러오지 못했어요';
    }
  }

  void clear() {
    _items.clear();
    _balance = 0;
    _loaded = false;
    notifyListeners();
  }
}
