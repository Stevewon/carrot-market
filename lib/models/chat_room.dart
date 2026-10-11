import '../app/l10n.dart';

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
      peerNickname: json['peer_nickname']?.toString() ?? L10n.current.chatAnonymous,
      peerMannerScore:
          (json['peer_manner_score'] is num) ? (json['peer_manner_score'] as num).toInt() : 36,
      productId: json['product_id']?.toString(),
      productTitle: json['product_title']?.toString(),
      productThumb: json['product_thumb']?.toString(),
      lastMessage: json['last_message']?.toString() ?? '',
      lastSenderId: json['last_sender_id']?.toString(),
      // 서버는 UTC ISO8601 로 보냄. 반드시 .toLocal() 로 KST(한국시간) 변환.
      lastMessageAt:
          (DateTime.tryParse(json['last_message_at']?.toString() ?? '')
                  ?.toLocal()) ??
              DateTime.now(),
      createdAt:
          (DateTime.tryParse(json['created_at']?.toString() ?? '')
                  ?.toLocal()) ??
              DateTime.now(),
      unreadCount: (json['unread_count'] is num)
          ? (json['unread_count'] as num).toInt()
          : 0,
      peerLastReadAt: peerLastReadStr != null
          ? DateTime.tryParse(peerLastReadStr)?.toLocal()
          : null,
    );
  }

  ChatRoom copyWith({
    String? peerNickname,
    int? peerMannerScore,
    String? productId,
    String? productTitle,
    String? productThumb,
    String? lastMessage,
    String? lastSenderId,
    DateTime? lastMessageAt,
    int? unreadCount,
    DateTime? peerLastReadAt,
  }) {
    return ChatRoom(
      id: id,
      peerId: peerId,
      peerNickname: peerNickname ?? this.peerNickname,
      peerMannerScore: peerMannerScore ?? this.peerMannerScore,
      productId: productId ?? this.productId,
      productTitle: productTitle ?? this.productTitle,
      productThumb: productThumb ?? this.productThumb,
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
    final t = L10n.current;
    if (diff.inSeconds < 60) return t.chatTimeJustNow;
    if (diff.inMinutes < 60) return t.chatTimeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return t.chatTimeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return t.chatTimeDaysAgo(diff.inDays);
    if (diff.inDays < 30) return t.chatTimeWeeksAgo((diff.inDays / 7).floor());
    if (diff.inDays < 365) return t.chatTimeMonthsAgo((diff.inDays / 30).floor());
    return t.chatTimeYearsAgo((diff.inDays / 365).floor());
  }
}
