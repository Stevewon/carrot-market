import '../app/l10n.dart';

/// 인증 단계.
///
/// - [none] (0): 가입 직후, 둘러보기·채팅·통화·상품등록 가능. 결제·출금 불가.
/// - [identity] (1): 본인인증 완료, KRW/QTA 결제 가능. 출금 불가.
/// - [bankAccount] (2): 계좌 등록 완료, QTA 출금 가능.
///
/// 채팅·통화는 단계와 무관하게 항상 익명성 유지 (닉네임만 사용).
enum VerificationLevel {
  none(0),
  identity(1),
  bankAccount(2);

  final int value;
  const VerificationLevel(this.value);

  static VerificationLevel fromInt(int v) {
    switch (v) {
      case 2:
        return VerificationLevel.bankAccount;
      case 1:
        return VerificationLevel.identity;
      default:
        return VerificationLevel.none;
    }
  }

  /// 거래(결제) 가능 여부.
  bool get canTrade => value >= 1;

  /// QTA 출금 가능 여부.
  bool get canWithdraw => value >= 2;

  String get label {
    switch (this) {
      case VerificationLevel.none:
        return L10n.current.myVerifyLabelNone;
      case VerificationLevel.identity:
        return L10n.current.myVerifyLabelIdentity;
      case VerificationLevel.bankAccount:
        return L10n.current.myVerifyLabelBank;
    }
  }
}

class User {
  final String id;
  final String nickname;
  final String deviceUuid;
  final String? walletAddress;
  final String? region;

  /// 내 동네 목록 (최대 10곳). [region] 은 그중 지금 보고 있는 동네.
  final List<String> regions;

  /// 'kr' | 'jp' — 언어·화폐·지역 목록.
  final String market;

  /// 동네 인증 통과 시각. null 이면 미인증.
  final DateTime? regionVerifiedAt;

  /// Manner score stored as ×10 integer (e.g. 365 = 36.5°).
  /// Default is 365 (= 36.5°), matching 당근의 시작값.
  /// Old API rows that still return 36 are auto-upgraded to 365 (see [fromJson]).
  final int mannerScore;

  /// QTA 토큰 잔액 (정수, 본인 응답에만 포함).
  final int qtaBalance;

  /// 본인인증 / 계좌 인증 단계 (0/1/2).
  final VerificationLevel verificationLevel;

  /// 본인인증 통과 시각. 미인증 시 null.
  final DateTime? verifiedAt;

  /// 계좌 등록 시각. 미등록 시 null.
  final DateTime? bankRegisteredAt;

  /// 지갑 소유 증명(소액 송금) 완료 시각 — 출금 조건. 미인증 시 null.
  final DateTime? walletVerifiedAt;

  final DateTime createdAt;

  User({
    required this.id,
    required this.nickname,
    required this.deviceUuid,
    this.walletAddress,
    this.region,
    this.regions = const [],
    this.market = 'kr',
    this.regionVerifiedAt,
    this.mannerScore = 365,
    this.qtaBalance = 0,
    this.verificationLevel = VerificationLevel.none,
    this.verifiedAt,
    this.bankRegisteredAt,
    this.walletVerifiedAt,
    required this.createdAt,
  });

  /// 동네 인증 여부.
  bool get isRegionVerified => regionVerifiedAt != null;

  /// 본인인증 여부 (Lv1 이상).
  bool get isIdentityVerified => verificationLevel.canTrade;

  /// 계좌 등록 여부 (Lv2).
  bool get isBankRegistered => verificationLevel.canWithdraw;

  /// 지갑 소유 증명 여부.
  bool get isWalletVerified => walletVerifiedAt != null;

  /// 지갑이 등록돼 있는지 (지갑 없이 가입 → 나중에 지갑 인증으로 등록).
  bool get hasWallet => (walletAddress ?? '').trim().isNotEmpty;

  /// 통화 식별 키 — 지갑이 있으면 지갑주소, 없으면 'u_<회원 id>'.
  /// 서버 utils/agoraToken.ts callIdentity() 와 같은 규칙이어야 양쪽 채널이 맞는다.
  String get callIdentity =>
      hasWallet ? walletAddress!.trim().toLowerCase() : 'u_$id';

  /// 출금 가능 — 본인인증(Lv1) + 지갑 소유 증명.
  bool get canWithdraw => isIdentityVerified && isWalletVerified;

  /// Display-friendly temperature, e.g. `36.5`.
  double get mannerTemperature => mannerScore / 10.0;

  /// "36.5°" — ready to render in UI.
  String get mannerLabel => '${mannerTemperature.toStringAsFixed(1)}°';

  factory User.fromJson(Map<String, dynamic> json) {
    final raw = json['manner_score'];
    int score;
    if (raw == null) {
      score = 365;
    } else if (raw is int) {
      score = raw;
    } else if (raw is num) {
      score = raw.toInt();
    } else {
      score = 365;
    }
    // Backwards-compat: if the server still serves the old 0–99 scale
    // (anything < 100), upgrade to ×10.
    if (score > 0 && score < 100) score = score * 10 + 5; // 36 → 36.5°

    final lvRaw = json['verification_level'];
    int lvInt;
    if (lvRaw is int) {
      lvInt = lvRaw;
    } else if (lvRaw is num) {
      lvInt = lvRaw.toInt();
    } else {
      lvInt = 0;
    }

    return User(
      id: json['id'].toString(),
      nickname: json['nickname'] ?? '익명가지',
      deviceUuid: json['device_uuid'] ?? '',
      walletAddress: json['wallet_address'] as String?,
      region: json['region'] as String?,
      regions: () {
        final r = json['regions'];
        final list = r is List ? r.map((e) => e.toString()).toList() : <String>[];
        final cur = json['region'] as String?;
        if (cur != null && cur.isNotEmpty && !list.contains(cur)) list.insert(0, cur);
        return list;
      }(),
      market: const ['jp', 'ph'].contains(json['market']?.toString()) ? json['market'].toString() : 'kr',
      regionVerifiedAt: json['region_verified_at'] is String
          ? DateTime.tryParse(json['region_verified_at'] as String)
          : null,
      mannerScore: score,
      qtaBalance: () {
        final r = json['qta_balance'];
        if (r is int) return r;
        if (r is num) return r.toInt();
        return 0;
      }(),
      verificationLevel: VerificationLevel.fromInt(lvInt),
      verifiedAt: json['verified_at'] is String
          ? DateTime.tryParse(json['verified_at'] as String)
          : null,
      bankRegisteredAt: json['bank_registered_at'] is String
          ? DateTime.tryParse(json['bank_registered_at'] as String)
          : null,
      walletVerifiedAt: json['wallet_verified_at'] is String
          ? DateTime.tryParse(json['wallet_verified_at'] as String)
          : null,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'device_uuid': deviceUuid,
        'wallet_address': walletAddress,
        'region': region,
        'regions': regions,
        'market': market,
        'region_verified_at': regionVerifiedAt?.toIso8601String(),
        'manner_score': mannerScore,
        'qta_balance': qtaBalance,
        'verification_level': verificationLevel.value,
        'verified_at': verifiedAt?.toIso8601String(),
        'bank_registered_at': bankRegisteredAt?.toIso8601String(),
        'wallet_verified_at': walletVerifiedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  User copyWith({
    String? nickname,
    String? deviceUuid,
    String? walletAddress,
    String? region,
    List<String>? regions,
    DateTime? regionVerifiedAt,
    int? mannerScore,
    int? qtaBalance,
    VerificationLevel? verificationLevel,
    DateTime? verifiedAt,
    DateTime? bankRegisteredAt,
    DateTime? walletVerifiedAt,
  }) {
    return User(
      id: id,
      nickname: nickname ?? this.nickname,
      deviceUuid: deviceUuid ?? this.deviceUuid,
      walletAddress: walletAddress ?? this.walletAddress,
      region: region ?? this.region,
      regions: regions ?? this.regions,
      market: market,
      regionVerifiedAt: regionVerifiedAt ?? this.regionVerifiedAt,
      mannerScore: mannerScore ?? this.mannerScore,
      qtaBalance: qtaBalance ?? this.qtaBalance,
      verificationLevel: verificationLevel ?? this.verificationLevel,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      bankRegisteredAt: bankRegisteredAt ?? this.bankRegisteredAt,
      walletVerifiedAt: walletVerifiedAt ?? this.walletVerifiedAt,
      createdAt: createdAt,
    );
  }
}
