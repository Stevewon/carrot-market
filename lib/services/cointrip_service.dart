import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../app/l10n.dart';
import 'auth_service.dart';

/// 코인 종류 (블랙코인은 주워야 알 수 있어 null).
class CtCoin {
  final String id;
  final String symbol;
  final String name;
  final String color; // '#RRGGBB'
  const CtCoin({required this.id, required this.symbol, required this.name, required this.color});

  factory CtCoin.fromJson(Map<String, dynamic> j) => CtCoin(
        id: j['id'].toString(),
        symbol: (j['symbol'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        color: (j['color'] ?? '#7C3AED').toString(),
      );

  int get argb {
    final h = color.replaceFirst('#', '');
    return int.tryParse('FF$h', radix: 16) ?? 0xFF7C3AED;
  }
}

/// 지도 위 코인 하나. 멀리 있으면 [precise] = false 이고 위치는 대략 (약 550m 칸의 가운데).
class CtDrop {
  final String id;
  final double lat;
  final double lng;
  final bool precise;
  final int distanceM;
  final bool isBlack;
  final CtCoin? coin;
  final String? amount;
  const CtDrop({
    required this.id,
    required this.lat,
    required this.lng,
    required this.precise,
    required this.distanceM,
    required this.isBlack,
    this.coin,
    this.amount,
  });

  factory CtDrop.fromJson(Map<String, dynamic> j) => CtDrop(
        id: j['id'].toString(),
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        precise: j['precise'] == true,
        distanceM: (j['distance_m'] as num?)?.toInt() ?? 0,
        isBlack: j['is_black'] == true,
        coin: j['coin'] is Map ? CtCoin.fromJson(Map<String, dynamic>.from(j['coin'] as Map)) : null,
        amount: j['amount']?.toString(),
      );
}

class CtUnionMember {
  final String userId;
  final String nickname;
  const CtUnionMember(this.userId, this.nickname);
}

class CtUnion {
  final String id;
  final String name;
  final String code;
  final String ownerId;
  final List<CtUnionMember> members;
  const CtUnion({required this.id, required this.name, required this.code, required this.ownerId, required this.members});

  static CtUnion? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return CtUnion(
      id: j['id'].toString(),
      name: (j['name'] ?? '').toString(),
      code: (j['code'] ?? '').toString(),
      ownerId: (j['owner_id'] ?? '').toString(),
      members: [
        for (final m in (j['members'] as List? ?? const []))
          if (m is Map) CtUnionMember(m['user_id'].toString(), (m['nickname'] ?? '').toString()),
      ],
    );
  }
}

/// 앱 지갑의 코인 하나.
class CtBalance {
  final CtCoin coin;
  final String walletKind; // quantarium | evm (이더리움·BNB·폴리곤) | solana
  final String network;
  final String amount;
  final String withdrawMin;
  final String? address;
  const CtBalance({
    required this.coin,
    required this.walletKind,
    required this.network,
    required this.amount,
    required this.withdrawMin,
    this.address,
  });

  factory CtBalance.fromJson(Map<String, dynamic> j) => CtBalance(
        coin: CtCoin.fromJson(Map<String, dynamic>.from(j['coin'] as Map)),
        walletKind: (j['wallet_kind'] ?? '').toString(),
        network: (j['network'] ?? '').toString(),
        amount: (j['amount'] ?? '0').toString(),
        withdrawMin: (j['withdraw_min'] ?? '0').toString(),
        address: j['address']?.toString(),
      );
}

class CtWithdrawal {
  final String id;
  final String symbol;
  final String amount;
  final String walletAddress;
  final String status; // requested | processing | completed | rejected
  final DateTime requestedAt;
  final String? txHash;
  final String? rejectReason;
  const CtWithdrawal({
    required this.id,
    required this.symbol,
    required this.amount,
    required this.walletAddress,
    required this.status,
    required this.requestedAt,
    this.txHash,
    this.rejectReason,
  });

  factory CtWithdrawal.fromJson(Map<String, dynamic> j) => CtWithdrawal(
        id: j['id'].toString(),
        symbol: (j['symbol'] ?? '').toString(),
        amount: (j['amount'] ?? '0').toString(),
        walletAddress: (j['wallet_address'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        requestedAt: parseServerTime(j['requested_at']),
        txHash: j['tx_hash']?.toString(),
        rejectReason: j['reject_reason']?.toString(),
      );
}

/// 줍기 결과.
/// 블랙코인 꽝 — 광고를 끝까지 보면 그냥 넘어가고, 안 보면 [qta] 를 내놓는다 (10분 안에 안 정하면 내는 것으로).
class CtPenalty {
  final String id;
  final int qta;
  final String adUnit;
  final bool serverVerify; // true = AdMob 서버 확인(SSV)이 와야 인정
  final DateTime expiresAt;
  const CtPenalty({required this.id, required this.qta, required this.adUnit, required this.serverVerify, required this.expiresAt});

  static CtPenalty? fromJson(Object? v) {
    if (v is! Map) return null;
    return CtPenalty(
      id: v['id'].toString(),
      qta: (v['qta'] as num?)?.toInt() ?? 0,
      adUnit: (v['ad_unit'] ?? '').toString(),
      serverVerify: v['ad_verify'] == 'ssv',
      expiresAt: parseServerTime(v['expires_at']),
    );
  }
}

/// 블랙코인 "광고 보고 열기" — 광고를 끝까지 봐야 어떤 코인이 몇 개인지 보이고 받는다.
/// 안 보면(그만두기 · 10분 지남) 못 받고 그 코인은 지도에 다시 놓인다. [penaltyId] 자리에 [id] 를 그대로 쓴다.
class CtReveal {
  final String id;
  final String adUnit;
  final bool serverVerify;
  const CtReveal({required this.id, required this.adUnit, required this.serverVerify});

  static CtReveal? fromJson(Object? v) {
    if (v is! Map) return null;
    return CtReveal(id: v['id'].toString(), adUnit: (v['ad_unit'] ?? '').toString(), serverVerify: v['ad_verify'] == 'ssv');
  }
}

/// 줍기 결과 — 코인을 주웠거나, 블랙코인 꽝 ([empty], 아무것도 없음), 블랙코인 벌칙 ([dud] != null),
/// 블랙코인 광고 보고 열기 ([reveal] != null).
class CtPickResult {
  final CtPenalty? dud;
  final CtReveal? reveal;
  final bool empty;
  final bool wasBlack;
  final CtCoin coin;
  final String total;
  final String mine;
  final List<(String nickname, String amount)> shared;
  const CtPickResult({this.dud, this.reveal, this.empty = false, required this.wasBlack, required this.coin, required this.total, required this.mine, required this.shared});
}

/// 서버 datetime('now') 는 'YYYY-MM-DD HH:MM:SS' (UTC, 시간대 표시 없음).
DateTime parseServerTime(Object? v) {
  final raw = (v ?? '').toString();
  final at = DateTime.tryParse(raw.contains('T') ? raw : '${raw.replaceFirst(' ', 'T')}Z');
  return (at ?? DateTime.now()).toLocal();
}

/// 서버 오류 → 사용자 문구 + 코드.
class CtError implements Exception {
  final String message;
  final String? code;
  final int? distanceM;

  /// code == 'dud_pending' 이면 먼저 정리해야 할 벌칙.
  final CtPenalty? penalty;

  /// code == 'reveal_pending' 이면 먼저 열어야 할 블랙코인.
  final CtReveal? reveal;
  const CtError(this.message, {this.code, this.distanceM, this.penalty, this.reveal});
  @override
  String toString() => message;

  static CtError from(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['error'] != null) {
        return CtError(d['error'].toString(),
            code: d['code']?.toString(), distanceM: (d['distance_m'] as num?)?.toInt(), penalty: CtPenalty.fromJson(d['penalty']), reveal: CtReveal.fromJson(d['reveal']));
      }
    }
    return CtError(L10n.current.ctNetworkError);
  }
}

/// 코인트립 (지도 코인 찾기). 서버가 열어 둔 회원에게만 [open] = true — 탭도 그때만 보인다.
/// 받을 지갑이 없는 코인은 서버가 아예 보내지 않는다.
class CointripService extends ChangeNotifier {
  CointripService(this.auth);

  final AuthService auth;

  bool _open = false;
  bool _statusLoaded = false;
  int pickRadiusM = 30;
  int preciseRadiusM = 300;
  double finderMultiplier = 2;
  int unionMax = 50;
  List<String> walletKinds = const [];
  String? quantariumWallet;
  String? extWallet;
  String? solWallet;
  bool phoneVerified = false;
  bool introAcked = false;
  int dudPenaltyQta = 10;

  /// 아직 정리 안 한 벌칙 (있으면 다른 코인을 못 줍는다).
  CtPenalty? penalty;

  /// 아직 안 연 "광고 보고 열기" 블랙코인 (있으면 다른 코인을 못 줍는다).
  CtReveal? reveal;
  CtUnion? union;

  bool get open => _open;
  bool get statusLoaded => _statusLoaded;
  bool get hasAnyWallet => walletKinds.isNotEmpty;

  Future<void> loadStatus() async {
    if (!auth.isLoggedIn) return;
    try {
      final res = await auth.api.get('/api/cointrip/status');
      final j = Map<String, dynamic>.from(res.data as Map);
      _open = j['open'] == true;
      if (_open) {
        pickRadiusM = (j['pick_radius_m'] as num?)?.toInt() ?? 30;
        preciseRadiusM = (j['precise_radius_m'] as num?)?.toInt() ?? 300;
        finderMultiplier = (j['finder_multiplier'] as num?)?.toDouble() ?? 2;
        unionMax = (j['union_max'] as num?)?.toInt() ?? 50;
        walletKinds = [for (final k in (j['wallet_kinds'] as List? ?? const [])) k.toString()];
        quantariumWallet = j['quantarium_wallet']?.toString();
        extWallet = j['ext_wallet_address']?.toString();
        solWallet = j['sol_wallet_address']?.toString();
        phoneVerified = j['phone_verified'] == true;
        introAcked = j['intro_acked'] == true;
        dudPenaltyQta = (j['dud_penalty_qta'] as num?)?.toInt() ?? 10;
        penalty = CtPenalty.fromJson(j['penalty']);
        reveal = CtReveal.fromJson(j['reveal']);
        union = CtUnion.fromJson(j['union']);
      }
      _statusLoaded = true;
    } catch (e) {
      // 서버가 아직 코인트립을 모르면(예전 서버) 그냥 닫힌 상태로 둔다.
      debugPrint('[cointrip] status failed: $e');
    }
    notifyListeners();
  }

  Future<void> ack(String context) async {
    try {
      await auth.api.post('/api/cointrip/ack', data: {'context': context});
      if (context == 'cointrip_intro') {
        introAcked = true;
        notifyListeners();
      }
    } catch (e) {
      throw CtError.from(e);
    }
  }

  Future<({bool needWallet, List<CtDrop> drops})> drops(double lat, double lng, {int radiusM = 5000}) async {
    try {
      final res = await auth.api.get('/api/cointrip/drops', query: {'lat': lat, 'lng': lng, 'radius_m': radiusM});
      final j = Map<String, dynamic>.from(res.data as Map);
      return (
        needWallet: j['need_wallet'] == true,
        drops: [for (final d in (j['drops'] as List? ?? const [])) CtDrop.fromJson(Map<String, dynamic>.from(d as Map))],
      );
    } catch (e) {
      throw CtError.from(e);
    }
  }

  Future<CtPickResult> pick(CtDrop d, {required double lat, required double lng, required double accuracy, required bool mocked}) async {
    try {
      final res = await auth.api.post('/api/cointrip/drops/${d.id}/pick',
          data: {'lat': lat, 'lng': lng, 'accuracy': accuracy, 'mocked': mocked});
      final j = Map<String, dynamic>.from(res.data as Map);
      if (j['ad_reveal'] == true) {
        reveal = CtReveal.fromJson(j['reveal']);
        notifyListeners();
        return CtPickResult(reveal: reveal, wasBlack: true, coin: const CtCoin(id: '', symbol: '', name: '', color: '#111111'), total: '', mine: '', shared: const []);
      }
      if (j['empty'] == true) {
        return const CtPickResult(empty: true, wasBlack: true, coin: CtCoin(id: '', symbol: '', name: '', color: '#111111'), total: '', mine: '', shared: []);
      }
      if (j['dud'] == true) {
        penalty = CtPenalty.fromJson(j['penalty']);
        notifyListeners();
        return CtPickResult(dud: penalty, wasBlack: true, coin: const CtCoin(id: '', symbol: '', name: '', color: '#111111'), total: '', mine: '', shared: const []);
      }
      return _coinResult(j);
    } catch (e) {
      throw CtError.from(e);
    }
  }

  static CtPickResult _coinResult(Map<String, dynamic> j) => CtPickResult(
        wasBlack: j['was_black'] == true,
        coin: CtCoin.fromJson(Map<String, dynamic>.from(j['coin'] as Map)),
        total: (j['total'] ?? '').toString(),
        mine: (j['mine'] ?? '').toString(),
        shared: [
          for (final s in (j['shared'] as List? ?? const []))
            if (s is Map) ((s['nickname'] ?? '').toString(), (s['amount'] ?? '').toString()),
        ],
      );

  /// 광고 보고 열기: 광고를 끝까지 봤다 → 코인을 받는다. 서버 확인(SSV) 방식이면 구글 콜백을 잠깐 기다린다.
  /// 아직 확인이 안 되면 null.
  Future<CtPickResult?> revealAdWatched(CtReveal rv) async {
    for (var i = 0; i < (rv.serverVerify ? 8 : 1); i++) {
      try {
        final res = await auth.api.post('/api/cointrip/reveals/${rv.id}/ad-watched');
        final j = Map<String, dynamic>.from(res.data as Map);
        if (j['coin'] is Map) {
          reveal = null;
          notifyListeners();
          return _coinResult(j);
        }
      } catch (e) {
        final err = CtError.from(e);
        if (err.code == 'settled' || err.code == 'gone') {
          reveal = null;
          notifyListeners();
        }
        throw err;
      }
      if (rv.serverVerify) await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  /// 광고 보고 열기를 그만둔다 — 코인은 지도에 다시 놓인다.
  Future<void> revealGiveUp(CtReveal rv) async {
    try {
      await auth.api.post('/api/cointrip/reveals/${rv.id}/give-up');
    } catch (_) {}
    reveal = null;
    notifyListeners();
  }

  /// 꽝: 광고를 끝까지 봤다. 서버 확인(SSV) 방식이면 구글 콜백이 올 때까지 잠깐 기다린다. 인정되면 true.
  Future<bool> penaltyAdWatched(CtPenalty p) async {
    for (var i = 0; i < (p.serverVerify ? 8 : 1); i++) {
      try {
        final res = await auth.api.post('/api/cointrip/penalties/${p.id}/ad-watched');
        if (res.data is Map && res.data['ok'] == true) {
          penalty = null;
          notifyListeners();
          return true;
        }
      } catch (e) {
        final err = CtError.from(e);
        if (err.code == 'settled') {
          penalty = null;
          notifyListeners();
          return true;
        }
      }
      if (p.serverVerify) await Future<void>.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  /// 꽝: 광고 대신 QTA 를 낸다. 실제로 낸 수량을 돌려준다 (잔액이 모자라면 있는 만큼).
  Future<int> penaltyPay(CtPenalty p) async {
    try {
      final res = await auth.api.post('/api/cointrip/penalties/${p.id}/pay');
      penalty = null;
      notifyListeners();
      return (res.data['deducted'] as num?)?.toInt() ?? 0;
    } catch (e) {
      final err = CtError.from(e);
      if (err.code == 'settled') {
        penalty = null;
        notifyListeners();
        return 0;
      }
      throw err;
    }
  }

  /// 기존 지갑 주소 등록 — [solana] 면 솔라나 주소, 아니면 이더리움·BNB·폴리곤 공용 0x 주소.
  Future<void> setWallet(String address, {bool solana = false}) async {
    final key = solana ? 'solana' : 'evm';
    try {
      await auth.api.put(solana ? '/api/cointrip/sol-wallet' : '/api/cointrip/ext-wallet', data: {'address': address, 'ack': true});
      if (solana) {
        solWallet = address;
      } else {
        extWallet = address;
      }
      if (!walletKinds.contains(key)) walletKinds = [...walletKinds, key];
      notifyListeners();
    } catch (e) {
      throw CtError.from(e);
    }
  }

  Future<void> removeWallet({bool solana = false}) async {
    final key = solana ? 'solana' : 'evm';
    try {
      await auth.api.delete(solana ? '/api/cointrip/sol-wallet' : '/api/cointrip/ext-wallet');
      if (solana) {
        solWallet = null;
      } else {
        extWallet = null;
      }
      walletKinds = walletKinds.where((k) => k != key).toList();
      notifyListeners();
    } catch (e) {
      throw CtError.from(e);
    }
  }

  Future<({List<CtBalance> balances, List<CtWithdrawal> withdrawals})> wallet() async {
    try {
      final res = await auth.api.get('/api/cointrip/wallet');
      final j = Map<String, dynamic>.from(res.data as Map);
      return (
        balances: [for (final b in (j['balances'] as List? ?? const [])) CtBalance.fromJson(Map<String, dynamic>.from(b as Map))],
        withdrawals: [
          for (final w in (j['withdrawals'] as List? ?? const [])) CtWithdrawal.fromJson(Map<String, dynamic>.from(w as Map))
        ],
      );
    } catch (e) {
      throw CtError.from(e);
    }
  }

  Future<void> withdraw(String coinId, String amount) async {
    try {
      await auth.api.post('/api/cointrip/withdrawals', data: {'coin_id': coinId, 'amount': amount, 'ack': true});
    } catch (e) {
      throw CtError.from(e);
    }
  }

  Future<void> _unionCall(Future<Response> Function() call) async {
    try {
      final res = await call();
      final j = res.data;
      union = j is Map ? CtUnion.fromJson(j['union']) : null;
      notifyListeners();
    } catch (e) {
      throw CtError.from(e);
    }
  }

  Future<void> createUnion(String name) => _unionCall(() => auth.api.post('/api/cointrip/union', data: {'name': name}));
  Future<void> joinUnion(String code) => _unionCall(() => auth.api.post('/api/cointrip/union/join', data: {'code': code}));
  Future<void> leaveUnion() => _unionCall(() => auth.api.post('/api/cointrip/union/leave'));
  Future<void> kick(String userId) => _unionCall(() => auth.api.post('/api/cointrip/union/kick', data: {'user_id': userId}));
  Future<void> refreshUnion() => _unionCall(() => auth.api.get('/api/cointrip/union'));
}
