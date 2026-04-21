import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:uuid/uuid.dart';

import '../app/constants.dart';
import '../models/chat_message.dart';
import 'auth_service.dart';

/// Ephemeral chat service.
/// - Messages are NOT persisted locally or on the server.
/// - Server acts as a pure relay.
/// - Messages live only in memory while the screen is open.
/// - Leaving the chat screen = messages gone forever.
class ChatService extends ChangeNotifier {
  final AuthService auth;
  IO.Socket? _socket;
  final Map<String, List<ChatMessage>> _roomMessages = {};
  String? _activeRoomId;

  ChatService(this.auth);

  bool get connected => _socket?.connected ?? false;
  List<ChatMessage> messagesFor(String roomId) => _roomMessages[roomId] ?? [];

  /// Expose the underlying socket so CallService can share the same
  /// signaling channel (no second connection needed).
  IO.Socket? get socketForCalls => _socket;

  /// Start QR-based chat room.
  /// Generates a room ID from two user IDs (deterministic).
  static String roomIdFor(String userA, String userB, {String? productId}) {
    final sorted = [userA, userB]..sort();
    final base = '${sorted[0]}_${sorted[1]}';
    return productId != null ? '${base}_$productId' : base;
  }

  Future<String> startRoomFromQR(String qrPayload, {String? productId}) async {
    // QR payload format: "eggplant://user/<userId>/<nickname>"
    final uri = Uri.tryParse(qrPayload);
    if (uri == null || uri.scheme != 'eggplant') {
      throw '유효하지 않은 QR 코드예요';
    }
    final parts = uri.pathSegments;
    if (parts.length < 2) throw '잘못된 QR 형식이에요';
    final peerUserId = parts[0];

    if (auth.user == null) throw '로그인이 필요해요';
    return roomIdFor(auth.user!.id, peerUserId, productId: productId);
  }

  void connect() {
    if (_socket != null && _socket!.connected) return;
    final token = auth.token;
    if (token == null) return;

    _socket = IO.io(
      AppConfig.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[chat] socket connected');
      if (_activeRoomId != null) {
        _socket!.emit('join_room', {'room_id': _activeRoomId});
      }
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      debugPrint('[chat] socket disconnected');
      notifyListeners();
    });

    _socket!.on('message', (data) {
      if (data is Map<String, dynamic>) {
        final msg = ChatMessage.fromJson(data, currentUserId: auth.user?.id);
        _roomMessages.putIfAbsent(msg.roomId, () => []);
        _roomMessages[msg.roomId]!.add(msg);
        notifyListeners();
      }
    });

    _socket!.on('system', (data) {
      if (data is Map<String, dynamic> && _activeRoomId != null) {
        final msg = ChatMessage(
          id: const Uuid().v4(),
          roomId: _activeRoomId!,
          senderId: 'system',
          senderNickname: 'system',
          text: data['text'] ?? '',
          type: 'system',
          sentAt: DateTime.now(),
        );
        _roomMessages.putIfAbsent(msg.roomId, () => []);
        _roomMessages[msg.roomId]!.add(msg);
        notifyListeners();
      }
    });
  }

  void joinRoom(String roomId, {String? peerNickname, String? productId}) {
    _activeRoomId = roomId;
    // Clear previous in-memory messages for this room (ephemeral)
    _roomMessages[roomId] = [];

    if (_socket == null || !_socket!.connected) {
      connect();
      return;
    }
    _socket!.emit('join_room', {
      'room_id': roomId,
      'peer_nickname': peerNickname,
      'product_id': productId,
    });
    notifyListeners();
  }

  void leaveRoom(String roomId) {
    if (_socket?.connected == true) {
      _socket!.emit('leave_room', {'room_id': roomId});
    }
    // Purge messages - ephemeral design
    _roomMessages.remove(roomId);
    if (_activeRoomId == roomId) _activeRoomId = null;
    notifyListeners();
  }

  void sendMessage(String roomId, String text) {
    if (text.trim().isEmpty) return;
    if (auth.user == null) return;
    if (_socket == null || !_socket!.connected) {
      connect();
      return;
    }
    _socket!.emit('message', {
      'room_id': roomId,
      'text': text,
      'sender_nickname': auth.user!.nickname,
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _roomMessages.clear();
    _activeRoomId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
