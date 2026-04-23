class ChatRoom {
  final String id;
  final String peerId;
  final String peerNickname;
  final int peerMannerScore;
  final String? productId;
  final String? productTitle;
  final String? productThumb;
  final String lastMessage;
  final String? lastSenderId;
  final DateTime lastMessageAt;
  final DateTime createdAt;

  ChatRoom({
    required this.id,
    required this.peerId,
    required this.peerNickname,
    this.peerMannerScore = 36,
    this.productId,
    this.productTitle,
    this.productThumb,
    this.lastMessage = '',
    this.lastSenderId,
    required this.lastMessageAt,
    required this.createdAt,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id']?.toString() ?? '',
      peerId: json['peer_id']?.toString() ?? '',
      peerNickname: json['peer_nickname']?.toString() ?? '익명',
      peerMannerScore:
          (json['peer_manner_score'] is num) ? (json['peer_manner_score'] as num).toInt() : 36,
      productId: json['product_id']?.toString(),
      productTitle: json['product_title']?.toString(),
      productThumb: json['product_thumb']?.toString(),
      lastMessage: json['last_message']?.toString() ?? '',
      lastSenderId: json['last_sender_id']?.toString(),
      lastMessageAt:
          DateTime.tryParse(json['last_message_at']?.toString() ?? '') ?? DateTime.now(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  ChatRoom copyWith({
    String? lastMessage,
    String? lastSenderId,
    DateTime? lastMessageAt,
  }) {
    return ChatRoom(
      id: id,
      peerId: peerId,
      peerNickname: peerNickname,
      peerMannerScore: peerMannerScore,
      productId: productId,
      productTitle: productTitle,
      productThumb: productThumb,
      lastMessage: lastMessage ?? this.lastMessage,
      lastSenderId: lastSenderId ?? this.lastSenderId,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      createdAt: createdAt,
    );
  }

  String get timeAgo {
    final diff = DateTime.now().difference(lastMessageAt);
    if (diff.inSeconds < 60) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}주 전';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}개월 전';
    return '${(diff.inDays / 365).floor()}년 전';
  }
}
