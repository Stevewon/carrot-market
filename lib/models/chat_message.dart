import 'dart:convert';

import '../app/l10n.dart';
import '../app/market.dart';

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

  /// "12,300원" / "¥12,300" — 기기 시장 기준.
  String get priceLabel => priceLabelFor(AppMarket.device);

  /// 시장(kr/jp)에 맞는 통화 표기. 0원도 '나눔' 이 아니라 금액으로 표시.
  String priceLabelFor(String market) {
    return AppMarket.money(price, market);
  }

  String get statusLabel {
    switch (status) {
      case 'accepted':
        return L10n.current.chatOfferStatusAccepted;
      case 'rejected':
        return L10n.current.chatOfferStatusRejected;
      case 'cancelled':
        return L10n.current.chatOfferStatusCancelled;
      case 'pending':
      default:
        return L10n.current.chatOfferStatusPending;
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
        respondedAt:
            DateTime.tryParse(nested['responded_at']?.toString() ?? '')
                ?.toLocal(),
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

/// 채팅 사진 — 서버에 잠시 있는 암호문(mediaId)과 그것을 여는 열쇠(key, base64).
class ChatImageInfo {
  final String mediaId;
  final String key;
  final int width;
  final int height;
  const ChatImageInfo({required this.mediaId, required this.key, this.width = 0, this.height = 0});

  static ChatImageInfo? tryParse(Object? raw) {
    Object? v = raw;
    if (v is String && v.isNotEmpty) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return null;
      }
    }
    if (v is! Map) return null;
    final id = v['media_id']?.toString() ?? '';
    final key = v['key']?.toString() ?? '';
    if (id.isEmpty || key.isEmpty) return null;
    int n(Object? x) => x is num ? x.toInt() : int.tryParse('${x ?? ''}') ?? 0;
    return ChatImageInfo(mediaId: id, key: key, width: n(v['w']), height: n(v['h']));
  }

  Map<String, dynamic> toJson() => {'media_id': mediaId, 'key': key, 'w': width, 'h': height};
}

/// 거래 약속 — 날짜·시간 + 장소. action 'cancel' 이면 약속 취소 알림.
class AppointmentInfo {
  final DateTime at;
  final String place;
  final bool cancelled;
  const AppointmentInfo({required this.at, this.place = '', this.cancelled = false});

  static AppointmentInfo? tryParse(Object? raw) {
    Object? v = raw;
    if (v is String && v.isNotEmpty) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return null;
      }
    }
    if (v is! Map) return null;
    final at = DateTime.tryParse(v['at']?.toString() ?? '')?.toLocal();
    if (at == null) return null;
    return AppointmentInfo(
      at: at,
      place: v['place']?.toString() ?? '',
      cancelled: v['action']?.toString() == 'cancel',
    );
  }

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'place': place,
        'action': cancelled ? 'cancel' : 'set',
      };
}

class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String senderNickname;
  final String text;
  final String type; // 'text', 'image', 'system', 'price_offer', 'appointment'
  final DateTime sentAt;
  final bool isMine;
  final PriceOfferInfo? offer;
  final ChatImageInfo? image;
  final AppointmentInfo? appointment;

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
    this.image,
    this.appointment,
    this.isRead = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, {String? currentUserId}) {
    final senderId = json['sender_id']?.toString() ?? '';
    // WS 이벤트는 type 이 'message'(이벤트 이름)이고 메시지 종류는 msg_type 에 온다.
    // 예전엔 type 을 먼저 읽어서 가격 제안이 'message' 로 바뀌어 제안 칸이 안 보였다.
    final rawType = json['type']?.toString();
    final type = json['msg_type']?.toString() ??
        (rawType == null || rawType == 'message' ? null : rawType) ??
        'text';
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      roomId: json['room_id']?.toString() ?? '',
      senderId: senderId,
      senderNickname: json['sender_nickname'] ?? L10n.current.chatAnonymous,
      text: json['text'] ?? '',
      type: type,
      // 서버는 UTC ISO8601 로 보냄. 반드시 .toLocal() 로 KST(한국시간) 변환.
      sentAt: (DateTime.tryParse(json['sent_at'] ?? '')?.toLocal()) ??
          DateTime.now(),
      isMine: currentUserId != null && senderId == currentUserId,
      offer: type == 'price_offer' ? PriceOfferInfo.tryParse(json) : null,
      image: type == 'image' ? ChatImageInfo.tryParse(json['image']) : null,
      appointment: type == 'appointment' ? AppointmentInfo.tryParse(json['appointment']) : null,
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
      image: image,
      appointment: appointment,
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
        if (image != null) 'image': image!.toJson(),
        if (appointment != null) 'appointment': appointment!.toJson(),
      };
}
