class User {
  final String id;
  final String nickname;
  final String deviceUuid;
  final String? walletAddress;
  final String? region;
  final int mannerScore; // starts at 36 (36.5°C)
  final DateTime createdAt;

  User({
    required this.id,
    required this.nickname,
    required this.deviceUuid,
    this.walletAddress,
    this.region,
    this.mannerScore = 36,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      nickname: json['nickname'] ?? '익명가지',
      deviceUuid: json['device_uuid'] ?? '',
      walletAddress: json['wallet_address'] as String?,
      region: json['region'] as String?,
      mannerScore: (json['manner_score'] ?? 36) is int
          ? json['manner_score'] ?? 36
          : (json['manner_score'] as num).toInt(),
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
