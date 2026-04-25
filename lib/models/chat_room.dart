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
  /// Number of messages from the peer I haven't read yet.
  /// Renders as the red badge on the chat list and the bottom-tab.
  final int unreadCount;
  /// When the PEER last read MY messages. Used for the "읽음" indicator
  /// next to my outgoing bubbles. null = peer hasn't opened the room yet.
  final DateTime? peerLastReadAt;

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
    this.unreadCount = 0,
    this.peerLastReadAt,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    // Server sends peer_last_read_at = the OTHER user's last_read_at_*.
    // (Endpoint computes which side I am and returns the peer's value.)
    // For backward-compat, also check both raw columns.
    String? peerLastReadStr;
    if (json['peer_last_read_at'] != null) {
      peerLastReadStr = json['peer_last_read_at'].toString();
    } else {
      // Pre-0006 payloads won't have these — that's fine.
      peerLastReadStr = null;
    }

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
      unreadCount: (json['unread_count'] is num)
          ? (json['unread_count'] as num).toInt()
          : 0,
      peerLastReadAt: peerLastReadStr != null
          ? DateTime.tryParse(peerLastReadStr)
          : null,
    );
  }

  ChatRoom copyWith({
    String? lastMessage,
    String? lastSenderId,
    DateTime? lastMessageAt,
    int? unreadCount,
    DateTime? peerLastReadAt,
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
      unreadCount: unreadCount ?? this.unreadCount,
      peerLastReadAt: peerLastReadAt ?? this.peerLastReadAt,
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
