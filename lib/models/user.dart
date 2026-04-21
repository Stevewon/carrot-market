class User {
  final String id;
  final String nickname;
  final String deviceUuid;
  final String? region;
  final int mannerScore; // starts at 36 (36.5°C)
  final DateTime createdAt;

  User({
    required this.id,
    required this.nickname,
    required this.deviceUuid,
    this.region,
    this.mannerScore = 36,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      nickname: json['nickname'] ?? '익명가지',
      deviceUuid: json['device_uuid'] ?? '',
      region: json['region'],
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
        'region': region,
        'manner_score': mannerScore,
        'created_at': createdAt.toIso8601String(),
      };
}
