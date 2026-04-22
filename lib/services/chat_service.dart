import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../app/constants.dart';
import '../models/chat_message.dart';
import 'auth_service.dart';

/// Ephemeral chat service over raw WebSocket (Cloudflare Workers + Durable Object).
///
/// - Messages are NOT persisted locally or on the server.
/// - Server acts as a pure relay.
/// - Messages live only in memory while the screen is open.
/// - Leaving the chat screen = messages gone forever.
///
/// Protocol: JSON text frames. See workers-server/src/chat-hub.ts.
class ChatService extends ChangeNotifier {
  final AuthService auth;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _connected = false;
  bool _connecting = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  /// Event bus for other services (e.g., CallService) to subscribe to.
  /// Events are decoded JSON maps with a `type` field.
  final StreamController<Map<String, dynamic>> _eventBus =
      StreamController<Map<String, dynamic>>.broadcast();

  final Map<String, List<ChatMessage>> _roomMessages = {};
  String? _activeRoomId;

  ChatService(this.auth);

  bool get connected => _connected;
  List<ChatMessage> messagesFor(String roomId) => _roomMessages[roomId] ?? [];

  /// Stream of all server events. Consumers filter by event `type`.
  Stream<Map<String, dynamic>> get events => _eventBus.stream;

  /// Subscribe to a specific event type. Returns a subscription that must be
  /// cancelled by the caller.
  StreamSubscription<Map<String, dynamic>> on(
    String type,
    void Function(Map<String, dynamic>) handler,
  ) {
    return _eventBus.stream.where((e) => e['type'] == type).listen(handler);
  }

  /// Send a raw JSON message to the server. No-op if not connected.
  void emit(String type, [Map<String, dynamic>? data]) {
    if (_channel == null || !_connected) return;
    final payload = <String, dynamic>{'type': type, ...?data};
    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[chat] emit failed: $e');
    }
  }

  /// Generates a deterministic room ID for two users (+ optional product).
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

  /// Open the WebSocket if not already open.
  void connect() {
    if (_connected || _connecting) return;
    final token = auth.token;
    if (token == null) return;
    _connecting = true;

    // Ensure the URL is a ws:// or wss:// scheme. If users configured an http
    // URL from an older build, upgrade it transparently.
    var url = AppConfig.socketUrl;
    if (url.startsWith('http://')) {
      url = 'ws://${url.substring(7)}';
    } else if (url.startsWith('https://')) {
      url = 'wss://${url.substring(8)}';
    }

    // Append /socket if the user supplied a bare host (legacy convenience).
    final parsed = Uri.tryParse(url);
    if (parsed != null && (parsed.path.isEmpty || parsed.path == '/')) {
      url = '${url.replaceAll(RegExp(r'/+$'), '')}/socket';
    }
    // Attach token as query param (WS upgrade headers can't be set on mobile).
    final sep = url.contains('?') ? '&' : '?';
    final full = '$url${sep}token=${Uri.encodeComponent(token)}';

    try {
      debugPrint('[chat] connecting $url');
      _channel = WebSocketChannel.connect(Uri.parse(full));
    } catch (e) {
      debugPrint('[chat] connect error: $e');
      _connecting = false;
      _scheduleReconnect();
      return;
    }

    _sub = _channel!.stream.listen(
      _onData,
      onError: (Object err) {
        debugPrint('[chat] ws error: $err');
      },
      onDone: () {
        debugPrint('[chat] ws closed (code=${_channel?.closeCode})');
        _connected = false;
        _connecting = false;
        _stopPing();
        notifyListeners();
        _scheduleReconnect();
      },
      cancelOnError: false,
    );

    // Optimistically mark connected; the server's "connected" event will
    // confirm. This lets the UI update without a round-trip.
    _connected = true;
    _connecting = false;
    _reconnectAttempts = 0;
    _startPing();
    notifyListeners();

    // Re-join active room after reconnect.
    if (_activeRoomId != null) {
      emit('join_room', {'room_id': _activeRoomId});
    }
  }

  void _onData(dynamic raw) {
    Map<String, dynamic>? msg;
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) msg = decoded;
    } catch (e) {
      debugPrint('[chat] decode error: $e');
      return;
    }
    if (msg == null) return;

    final type = msg['type']?.toString() ?? '';
    // Forward EVERY message to the event bus first so CallService sees it.
    _eventBus.add(msg);

    switch (type) {
      case 'connected':
        // Server greeting - nothing else to do.
        break;
      case 'pong':
        // Keep-alive reply.
        break;
      case 'message':
        final chatMsg = ChatMessage.fromJson(msg, currentUserId: auth.user?.id);
        _roomMessages.putIfAbsent(chatMsg.roomId, () => []);
        _roomMessages[chatMsg.roomId]!.add(chatMsg);
        notifyListeners();
        break;
      case 'system':
        if (_activeRoomId != null) {
          final sys = ChatMessage(
            id: const Uuid().v4(),
            roomId: _activeRoomId!,
            senderId: 'system',
            senderNickname: 'system',
            text: msg['text']?.toString() ?? '',
            type: 'system',
            sentAt: DateTime.now(),
          );
          _roomMessages.putIfAbsent(sys.roomId, () => []);
          _roomMessages[sys.roomId]!.add(sys);
          notifyListeners();
        }
        break;
    }
  }

  void _startPing() {
    _stopPing();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      emit('ping');
    });
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _scheduleReconnect() {
    if (auth.token == null) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts = (_reconnectAttempts + 1).clamp(1, 6);
    final delay = Duration(seconds: 1 << (_reconnectAttempts - 1)); // 1,2,4,8,16,32
    debugPrint('[chat] reconnect in ${delay.inSeconds}s');
    _reconnectTimer = Timer(delay, () {
      if (!_connected) connect();
    });
  }

  void joinRoom(String roomId, {String? peerNickname, String? productId}) {
    _activeRoomId = roomId;
    // Ephemeral: clear in-memory log every time a room is (re)entered.
    _roomMessages[roomId] = [];

    if (!_connected) {
      connect();
    }
    emit('join_room', {
      'room_id': roomId,
      if (peerNickname != null) 'peer_nickname': peerNickname,
      if (productId != null) 'product_id': productId,
    });
    notifyListeners();
  }

  void leaveRoom(String roomId) {
    emit('leave_room', {'room_id': roomId});
    _roomMessages.remove(roomId);
    if (_activeRoomId == roomId) _activeRoomId = null;
    notifyListeners();
  }

  void sendMessage(String roomId, String text) {
    if (text.trim().isEmpty) return;
    if (auth.user == null) return;
    if (!_connected) {
      connect();
      return;
    }
    emit('message', {
      'room_id': roomId,
      'text': text,
      'sender_nickname': auth.user!.nickname,
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopPing();
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close(ws_status.goingAway);
    } catch (_) {}
    _channel = null;
    _connected = false;
    _connecting = false;
    _reconnectAttempts = 0;
    _roomMessages.clear();
    _activeRoomId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _eventBus.close();
    super.dispose();
  }
}
