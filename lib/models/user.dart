class User {
  final String id;
  final String nickname;
  final String deviceUuid;
  final String? walletAddress;
  final String? region;

  /// Manner score stored as ×10 integer (e.g. 365 = 36.5°).
  /// Default is 365 (= 36.5°), matching 당근의 시작값.
  /// Old API rows that still return 36 are auto-upgraded to 365 (see [fromJson]).
  final int mannerScore;
  final DateTime createdAt;

  User({
    required this.id,
    required this.nickname,
    required this.deviceUuid,
    this.walletAddress,
    this.region,
    this.mannerScore = 365,
    required this.createdAt,
  });

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
    if (score > 0 && score < 100) score *= 10;
    return User(
      id: json['id'].toString(),
      nickname: json['nickname'] ?? '익명가지',
      deviceUuid: json['device_uuid'] ?? '',
      walletAddress: json['wallet_address'] as String?,
      region: json['region'] as String?,
      mannerScore: score,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'device_uuid': deviceUuid,
        'wallet_address': walletAddress,
        'region': region,
        'manner_score': mannerScore,
        'created_at': createdAt.toIso8601String(),
      };

  User copyWith({
    String? nickname,
    String? deviceUuid,
    String? walletAddress,
    String? region,
    int? mannerScore,
  }) {
    return User(
      id: id,
      nickname: nickname ?? this.nickname,
      deviceUuid: deviceUuid ?? this.deviceUuid,
      walletAddress: walletAddress ?? this.walletAddress,
      region: region ?? this.region,
      mannerScore: mannerScore ?? this.mannerScore,
      createdAt: createdAt,
    );
  }
}
