class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String senderNickname;
  final String text;
  final String type; // 'text', 'image', 'system'
  final DateTime sentAt;
  final bool isMine;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderNickname,
    required this.text,
    this.type = 'text',
    required this.sentAt,
    this.isMine = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, {String? currentUserId}) {
    final senderId = json['sender_id']?.toString() ?? '';
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      roomId: json['room_id']?.toString() ?? '',
      senderId: senderId,
      senderNickname: json['sender_nickname'] ?? '익명',
      text: json['text'] ?? '',
      type: json['type'] ?? 'text',
      sentAt: DateTime.tryParse(json['sent_at'] ?? '') ?? DateTime.now(),
      isMine: currentUserId != null && senderId == currentUserId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_id': roomId,
        'sender_id': senderId,
        'sender_nickname': senderNickname,
        'text': text,
        'type': type,
        'sent_at': sentAt.toIso8601String(),
      };
}
