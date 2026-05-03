/// 가격 제안(price_offer) 메시지에 첨부되는 흥정 정보.
///
/// 서버는 chat_messages 와 price_offers 를 LEFT JOIN 해서 내려보내고,
/// 메시지 type 이 'price_offer' 인 경우 이 객체가 채워진다. 일반 텍스트
/// 메시지에서는 null.
class PriceOfferInfo {
  final String id;
  final int price;
  /// pending | accepted | rejected | cancelled
  final String status;
  final String buyerId;
  final String sellerId;
  final DateTime? respondedAt;

  const PriceOfferInfo({
    required this.id,
    required this.price,
    required this.status,
    required this.buyerId,
    required this.sellerId,
    this.respondedAt,
  });

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  /// "12,300원" 같이 한국식 통화 표기.
  String get priceLabel {
    final s = price.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return '${buf.toString()}원';
  }

  String get statusLabel {
    switch (status) {
      case 'accepted':
        return '수락됨';
      case 'rejected':
        return '거절됨';
      case 'cancelled':
        return '취소됨';
      case 'pending':
      default:
        return '응답 대기';
    }
  }

  static PriceOfferInfo? tryParse(Map<String, dynamic> json) {
    // Server may send either a nested `offer: {...}` object (WS push) or
    // the flat `offer_id / offer_price / ...` columns (REST history).
    final nested = json['offer'];
    if (nested is Map) {
      final id = nested['id']?.toString();
      final priceRaw = nested['price'];
      if (id == null || id.isEmpty || priceRaw == null) return null;
      return PriceOfferInfo(
        id: id,
        price: (priceRaw is num) ? priceRaw.toInt() : int.tryParse('$priceRaw') ?? 0,
        status: nested['status']?.toString() ?? 'pending',
        buyerId: nested['buyer_id']?.toString() ?? '',
        sellerId: nested['seller_id']?.toString() ?? '',
        respondedAt: DateTime.tryParse(nested['responded_at']?.toString() ?? ''),
      );
    }
    final flatId = json['offer_id']?.toString();
    if (flatId == null || flatId.isEmpty) return null;
    final priceRaw = json['offer_price'];
    return PriceOfferInfo(
      id: flatId,
      price: (priceRaw is num) ? priceRaw.toInt() : int.tryParse('$priceRaw') ?? 0,
      status: json['offer_status']?.toString() ?? 'pending',
      buyerId: json['offer_buyer_id']?.toString() ?? '',
      sellerId: json['offer_seller_id']?.toString() ?? '',
      respondedAt: null,
    );
  }

  PriceOfferInfo copyWith({String? status, DateTime? respondedAt}) {
    return PriceOfferInfo(
      id: id,
      price: price,
      buyerId: buyerId,
      sellerId: sellerId,
      status: status ?? this.status,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }
}

class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String senderNickname;
  final String text;
  final String type; // 'text', 'image', 'system', 'price_offer'
  final DateTime sentAt;
  final bool isMine;
  final PriceOfferInfo? offer;

  /// 상대방이 이 메시지를 읽었는지 (당근식 '1' 표시용).
  ///
  /// 정책 (D1 저장 0건, 0022 휘발성 정책 준수):
  ///   - 내가 보낸 메시지(isMine=true)에만 의미 있음.
  ///   - 처음에는 false (= '1' 회색 표시).
  ///   - peer 가 채팅방을 보면 WebSocket 으로 read_receipt 가 와서
  ///     ChatService 가 sent_at <= read_at 인 모든 내 메시지를
  ///     `isRead=true` 로 copyWith 한다.
  ///   - 휘발성: 앱을 재시작하면 메시지 자체가 사라지므로 isRead 도 함께 휘발.
  final bool isRead;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderNickname,
    required this.text,
    this.type = 'text',
    required this.sentAt,
    this.isMine = false,
    this.offer,
    this.isRead = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, {String? currentUserId}) {
    final senderId = json['sender_id']?.toString() ?? '';
    // 서버는 메시지 타입을 'msg_type' (REST) 혹은 'type' (WS) 둘 다 쓸 수 있음.
    final type = json['type']?.toString() ??
        json['msg_type']?.toString() ??
        'text';
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      roomId: json['room_id']?.toString() ?? '',
      senderId: senderId,
      senderNickname: json['sender_nickname'] ?? '익명',
      text: json['text'] ?? '',
      type: type,
      sentAt: DateTime.tryParse(json['sent_at'] ?? '') ?? DateTime.now(),
      isMine: currentUserId != null && senderId == currentUserId,
      offer: type == 'price_offer' ? PriceOfferInfo.tryParse(json) : null,
      isRead: false,
    );
  }

  ChatMessage copyWith({
    PriceOfferInfo? offer,
    String? text,
    String? type,
    bool? isRead,
  }) {
    return ChatMessage(
      id: id,
      roomId: roomId,
      senderId: senderId,
      senderNickname: senderNickname,
      text: text ?? this.text,
      type: type ?? this.type,
      sentAt: sentAt,
      isMine: isMine,
      offer: offer ?? this.offer,
      isRead: isRead ?? this.isRead,
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
        if (offer != null)
          'offer': {
            'id': offer!.id,
            'price': offer!.price,
            'status': offer!.status,
            'buyer_id': offer!.buyerId,
            'seller_id': offer!.sellerId,
          },
      };
}
