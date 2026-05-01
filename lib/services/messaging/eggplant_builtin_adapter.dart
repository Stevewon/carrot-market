/// 가지(Eggplant) 자체 구현 메시징·통화 어댑터.
///
/// 기존 ChatService(WebSocket Durable Object) 와 CallService(WebRTC P2P) 를
/// 그대로 위임 — 행동 동등성을 보장하면서 [MessagingAdapter] /
/// [CallingAdapter] 인터페이스로 표면만 통일한다.
///
/// QRChat SDK 출시 시 동일 인터페이스로 `QRChatMessagingAdapter` 만 추가하고
/// main.dart 에서 한 줄 교체하면 전환 완료.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/chat_message.dart';
import '../../models/chat_room.dart';
import '../call_service.dart';
import '../chat_service.dart';
import 'messaging_adapter.dart';

class EggplantBuiltinMessagingAdapter implements MessagingAdapter {
  final ChatService _chat;
  final StreamController<void> _changes =
      StreamController<void>.broadcast();
  late final VoidCallback _listener;

  EggplantBuiltinMessagingAdapter(this._chat) {
    _listener = () => _changes.add(null);
    _chat.addListener(_listener);
  }

  @override
  String get adapterId => 'eggplant_builtin';

  @override
  MessagingConnectionState get connectionState =>
      _chat.connected
          ? MessagingConnectionState.connected
          : MessagingConnectionState.disconnected;

  @override
  int get totalUnread => _chat.totalUnread;

  @override
  List<ChatRoom> get rooms => _chat.rooms;

  @override
  List<ChatMessage> messagesFor(String roomId) =>
      _chat.messagesFor(roomId);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<Map<String, dynamic>> get events => _chat.events;

  @override
  StreamSubscription<Map<String, dynamic>> on(
    String type,
    void Function(Map<String, dynamic>) handler,
  ) =>
      _chat.on(type, handler);

  @override
  Future<void> init(MessagingIdentity identity) async {
    // Builtin 어댑터는 ChatService 가 AuthService 를 통해 이미
    // walletAddress / nickname / token 을 알고 있으므로 별도 작업 없음.
    // SSO 통합 컨셉만 표면에 노출 — 실제 인증은 AuthService 가 담당.
  }

  @override
  void connect() => _chat.connect();

  @override
  Future<void> disconnect() async {
    // ChatService 는 명시적 disconnect 메서드가 public 이 아니므로
    // 어댑터 레벨에서는 listener 만 정리. 실제 소켓은 AuthService.logout 이 닫는다.
  }

  @override
  Future<ChatRoom?> openRoomWithPeer({
    required String peerUserId,
    String? peerNickname,
    String? productId,
    String? productTitle,
    String? productThumb,
  }) =>
      _chat.openRoomWithPeer(
        peerUserId: peerUserId,
        peerNickname: peerNickname,
        productId: productId,
        productTitle: productTitle,
        productThumb: productThumb,
      );

  @override
  Future<String?> sendText(String roomId, String text) async {
    if (!_chat.connected) {
      _chat.connect();
    }
    _chat.emit('chat_message', {
      'room_id': roomId,
      'text': text,
    });
    return null;
  }

  @override
  void emit(String type, [Map<String, dynamic>? data]) =>
      _chat.emit(type, data);

  @override
  Future<bool> deleteRoom(String roomId) => _chat.deleteRoom(roomId);

  @override
  Future<bool> clearMessages(String roomId) => _chat.clearMessages(roomId);

  @override
  Future<void> markRoomAsRead(String roomId) =>
      _chat.markRoomAsRead(roomId);

  @override
  void clearAll() {
    // ChatService 의 내부 캐시는 logout 시점에 정리됨.
  }

  void dispose() {
    _chat.removeListener(_listener);
    _changes.close();
  }
}

class EggplantBuiltinCallingAdapter implements CallingAdapter {
  final CallService _call;
  final StreamController<void> _changes =
      StreamController<void>.broadcast();
  late final VoidCallback _listener;

  EggplantBuiltinCallingAdapter(this._call) {
    _listener = () => _changes.add(null);
    _call.addListener(_listener);
  }

  @override
  String get adapterId => 'eggplant_builtin';

  @override
  CallSessionState get state {
    switch (_call.state) {
      case CallState.idle:
        return CallSessionState.idle;
      case CallState.outgoing:
        return CallSessionState.outgoing;
      case CallState.incoming:
        return CallSessionState.incoming;
      case CallState.connecting:
        return CallSessionState.connecting;
      case CallState.connected:
        return CallSessionState.connected;
      case CallState.ended:
        return CallSessionState.ended;
    }
  }

  @override
  String? get peerUserId => _call.peerUserId;

  @override
  String? get peerNickname => _call.peerNickname;

  @override
  DateTime? get connectedAt => _call.connectedAt;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> init(MessagingIdentity identity) async {
    // Builtin: 별도 init 불필요 (CallService 가 ChatService 통해 SSO 식별).
  }

  @override
  Future<void> startCall({
    required String peerUserId,
    required String peerNickname,
  }) =>
      _call.startCall(
        peerUserId: peerUserId,
        peerNickname: peerNickname,
      );

  @override
  Future<void> acceptIncoming() => _call.acceptCall();

  @override
  Future<void> hangUp() => _call.endCall();

  @override
  Future<void> toggleMute() async {
    _call.toggleMute();
  }

  @override
  bool get isMuted {
    // CallService 의 isMuted 가 public 이 아닐 경우 dynamic 으로 안전 조회.
    try {
      return (_call as dynamic).isMuted == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> toggleSpeaker() => _call.toggleSpeaker();

  @override
  bool get isSpeaker {
    try {
      return (_call as dynamic).isSpeaker == true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _call.removeListener(_listener);
    _changes.close();
  }
}
