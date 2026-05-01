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
      case 'withdrawal':
        return '출금 신청';
      case 'withdrawal_refund':
        return '출금 취소·환불';
      default:
        return reason;
    }
  }
}

/// 출금 신청 1건. 서버 응답 형식:
///   {id, amount, status, wallet_address, requested_at, processed_at, tx_hash, reject_reason}
class QtaWithdrawal {
  final String id;
  final int amount;
  final String status; // requested | processing | completed | rejected
  final String walletAddress;
  final DateTime requestedAt;
  final DateTime? processedAt;
  final String? txHash;
  final String? rejectReason;

  QtaWithdrawal({
    required this.id,
    required this.amount,
    required this.status,
    required this.walletAddress,
    required this.requestedAt,
    this.processedAt,
    this.txHash,
    this.rejectReason,
  });

  factory QtaWithdrawal.fromJson(Map<String, dynamic> j) {
    return QtaWithdrawal(
      id: j['id']?.toString() ?? '',
      amount: (j['amount'] as num?)?.toInt() ?? 0,
      status: j['status']?.toString() ?? 'requested',
      walletAddress: j['wallet_address']?.toString() ?? '',
      requestedAt: DateTime.tryParse(j['requested_at']?.toString() ?? '') ??
          DateTime.now(),
      processedAt: j['processed_at'] != null
          ? DateTime.tryParse(j['processed_at'].toString())
          : null,
      txHash: j['tx_hash']?.toString(),
      rejectReason: j['reject_reason']?.toString(),
    );
  }

  /// 한국어 상태 라벨.
  String get statusLabel {
    switch (status) {
      case 'requested':
        return '대기 중';
      case 'processing':
        return '송금 중';
      case 'completed':
        return '완료';
      case 'rejected':
        return '거절·환불';
      default:
        return status;
    }
  }

  bool get isPending => status == 'requested' || status == 'processing';
  bool get canCancel => status == 'requested';
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
      final res = await auth.api.get(
        '/api/users/me/qta/ledger',
        query: {'limit': limit},
      );
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
    _withdrawals.clear();
    _withdrawalsLoaded = false;
    _withdrawalMin = 5000;
    _withdrawalUnit = 5000;
    _browseCount = 0;
    _browseThreshold = 10;
    _browseCredited = false;
    _browseLoaded = false;
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────
  // 둘러보기 채굴 현황 (오늘 KST 기준)
  //   - 상품 상세 응답의 mining 필드로도 갱신됨 (즉시 반영용).
  //   - my_tab 진입 시 GET /api/products/mining/browse 로 1회 동기화.
  // ────────────────────────────────────────────────────────────────────
  int _browseCount = 0;
  int _browseThreshold = 10;
  bool _browseCredited = false;
  bool _browseLoaded = false;
  bool _browseLoading = false;

  int get browseCount => _browseCount;
  int get browseThreshold => _browseThreshold;
  bool get browseCredited => _browseCredited;
  bool get browseLoaded => _browseLoaded;
  bool get browseLoading => _browseLoading;

  /// 채굴 진행도 (0.0 ~ 1.0).
  double get browseProgress {
    if (_browseThreshold <= 0) return 0;
    final p = _browseCount / _browseThreshold;
    return p > 1.0 ? 1.0 : p;
  }

  /// 서버에서 오늘 둘러보기 채굴 현황 가져오기.
  Future<void> loadBrowseMining({bool force = false}) async {
    if (_browseLoading) return;
    if (_browseLoaded && !force) return;
    _browseLoading = true;
    try {
      final res = await auth.api.get('/api/products/mining/browse');
      final data = res.data as Map<String, dynamic>;
      _browseCount = (data['count'] as num?)?.toInt() ?? 0;
      _browseThreshold = (data['threshold'] as num?)?.toInt() ?? 10;
      _browseCredited = data['credited'] == true;
      _browseLoaded = true;
      _browseLoading = false;
      notifyListeners();
    } catch (e) {
      _browseLoading = false;
      debugPrint('[qta] loadBrowseMining failed: $e');
    }
  }

  /// 상품 상세 응답에 포함된 mining 필드로 즉시 갱신.
  /// 채굴 보너스가 방금 적립된 경우 잔액·ledger 도 다시 가져온다.
  void applyBrowseMiningFromDetail(Map<String, dynamic>? mining) {
    if (mining == null) return;
    final newCount = (mining['count'] as num?)?.toInt();
    final newThreshold = (mining['threshold'] as num?)?.toInt();
    final justCredited = mining['credited'] == true;
    final alreadyCredited = mining['alreadyCredited'] == true;
    if (newCount != null) _browseCount = newCount;
    if (newThreshold != null) _browseThreshold = newThreshold;
    if (alreadyCredited) _browseCredited = true;
    _browseLoaded = true;
    if (justCredited) {
      // 보너스가 방금 적립됐으니 잔액/내역 다시 로드.
      _loaded = false;
      // ignore: discarded_futures
      load(force: true);
    }
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────
  // 출금 (퀀타리움 지갑으로 송금 신청)
  // ────────────────────────────────────────────────────────────────────
  // 서버 정책: 최소 5,000 QTA, 5,000 단위로만.
  // 사용자가 신청하면 잔액이 즉시 차감되고 운영자가 실제 송금을 처리한다.
  // 'requested' 상태에서는 사용자가 직접 취소(=환불)할 수 있다.

  final List<QtaWithdrawal> _withdrawals = [];
  bool _withdrawalsLoading = false;
  bool _withdrawalsLoaded = false;
  int _withdrawalMin = 5000;
  int _withdrawalUnit = 5000;

  List<QtaWithdrawal> get withdrawals => List.unmodifiable(_withdrawals);
  bool get withdrawalsLoading => _withdrawalsLoading;
  bool get withdrawalsLoaded => _withdrawalsLoaded;
  int get withdrawalMin => _withdrawalMin;
  int get withdrawalUnit => _withdrawalUnit;

  /// 진행 중인 신청이 있나 (requested/processing).
  QtaWithdrawal? get pendingWithdrawal {
    for (final w in _withdrawals) {
      if (w.isPending) return w;
    }
    return null;
  }

  /// 출금 가능한 최대 금액 (잔액 이하의 5,000 배수).
  int get maxRequestableAmount {
    if (_balance < _withdrawalMin) return 0;
    final units = _balance ~/ _withdrawalUnit;
    return units * _withdrawalUnit;
  }

  Future<String?> loadWithdrawals({bool force = false}) async {
    if (_withdrawalsLoading) return null;
    if (_withdrawalsLoaded && !force) return null;
    _withdrawalsLoading = true;
    notifyListeners();
    try {
      final res = await auth.api.get('/api/withdrawals');
      final data = res.data as Map<String, dynamic>;
      _withdrawals
        ..clear()
        ..addAll(((data['withdrawals'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => QtaWithdrawal.fromJson(Map<String, dynamic>.from(m))));
      final policy = data['policy'];
      if (policy is Map) {
        _withdrawalMin = (policy['min'] as num?)?.toInt() ?? _withdrawalMin;
        _withdrawalUnit = (policy['unit'] as num?)?.toInt() ?? _withdrawalUnit;
      }
      _withdrawalsLoaded = true;
      _withdrawalsLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _withdrawalsLoading = false;
      notifyListeners();
      debugPrint('[qta] loadWithdrawals failed: $e');
      return '출금 내역을 불러오지 못했어요';
    }
  }

  /// 새 출금 신청. 성공 시 null 반환, 실패 시 에러 메시지.
  Future<String?> requestWithdrawal(int amount) async {
    if (amount < _withdrawalMin) {
      return '최소 $_withdrawalMin QTA 부터 신청할 수 있어요';
    }
    if (amount % _withdrawalUnit != 0) {
      return '$_withdrawalUnit QTA 단위로만 신청할 수 있어요';
    }
    if (amount > _balance) {
      return 'QTA 잔액이 부족해요';
    }
    if (pendingWithdrawal != null) {
      return '진행 중인 신청이 있어요. 처리되면 다시 시도해주세요.';
    }
    try {
      final res = await auth.api.post(
        '/api/withdrawals',
        data: {'amount': amount},
      );
      final data = res.data as Map<String, dynamic>;
      final w = data['withdrawal'];
      if (w is Map) {
        _withdrawals.insert(
            0, QtaWithdrawal.fromJson(Map<String, dynamic>.from(w)));
      }
      final newBal = (data['qta_balance'] as num?)?.toInt();
      if (newBal != null) {
        _balance = newBal;
        // ignore: discarded_futures
        auth.updateQtaBalance(newBal);
      }
      // ledger 도 새 행이 생겼으니 다음 진입 때 재로딩.
      _loaded = false;
      notifyListeners();
      return null;
    } catch (e) {
      final msg = _extractError(e);
      debugPrint('[qta] requestWithdrawal failed: $e');
      return msg ?? '출금 신청에 실패했어요';
    }
  }

  /// 신청 취소 (requested 상태만 가능). 성공 시 null.
  Future<String?> cancelWithdrawal(String withdrawalId) async {
    try {
      final res = await auth.api.post('/api/withdrawals/$withdrawalId/cancel');
      final data = res.data as Map<String, dynamic>;
      final newBal = (data['qta_balance'] as num?)?.toInt();
      if (newBal != null) {
        _balance = newBal;
        // ignore: discarded_futures
        auth.updateQtaBalance(newBal);
      }
      // 로컬 캐시에서 해당 항목 상태를 'rejected' 로 갱신.
      final i = _withdrawals.indexWhere((w) => w.id == withdrawalId);
      if (i >= 0) {
        final old = _withdrawals[i];
        _withdrawals[i] = QtaWithdrawal(
          id: old.id,
          amount: old.amount,
          status: 'rejected',
          walletAddress: old.walletAddress,
          requestedAt: old.requestedAt,
          processedAt: DateTime.now(),
          txHash: old.txHash,
          rejectReason: '사용자 취소',
        );
      }
      _loaded = false;
      notifyListeners();
      return null;
    } catch (e) {
      final msg = _extractError(e);
      debugPrint('[qta] cancelWithdrawal failed: $e');
      return msg ?? '취소에 실패했어요';
    }
  }

  String? _extractError(Object e) {
    try {
      // dynamic 사용 — DioException 의 response.data?.error 추출.
      final dyn = e as dynamic;
      final data = dyn.response?.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
    } catch (_) {}
    return null;
  }
}
