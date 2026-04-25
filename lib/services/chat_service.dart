import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../app/constants.dart';
import '../models/chat_message.dart';
import '../models/chat_room.dart';
import 'auth_service.dart';
import 'notification_service.dart';

/// Persistent chat service (당근 style).
///
/// - Messages are stored server-side in D1 and loaded on demand.
/// - Leaving a room (DELETE /rooms/:id) wipes the room AND all messages for
///   both users via CASCADE. The server then broadcasts `room_deleted` so the
///   peer's UI drops the room immediately.
/// - Clearing messages (DELETE /rooms/:id/messages) keeps the room but erases
///   all history, broadcasting `messages_cleared`.
///
/// Transport:
///   REST : AuthService.api (Bearer token) for CRUD.
///   WS   : raw WebSocket against /socket?token=... for realtime push.
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
  final StreamController<Map<String, dynamic>> _eventBus =
      StreamController<Map<String, dynamic>>.broadcast();

  /// In-memory rooms + messages caches.
  List<ChatRoom> _rooms = [];
  bool _roomsLoading = false;
  final Map<String, List<ChatMessage>> _roomMessages = {};
  String? _activeRoomId;

  ChatService(this.auth);

  bool get connected => _connected;
  List<ChatRoom> get rooms => _rooms;
  bool get roomsLoading => _roomsLoading;
  List<ChatMessage> messagesFor(String roomId) => _roomMessages[roomId] ?? const [];

  /// Total unread across every room — used by the bottom-tab badge.
  int get totalUnread =>
      _rooms.fold<int>(0, (sum, r) => sum + r.unreadCount);

  Stream<Map<String, dynamic>> get events => _eventBus.stream;

  StreamSubscription<Map<String, dynamic>> on(
    String type,
    void Function(Map<String, dynamic>) handler,
  ) {
    return _eventBus.stream.where((e) => e['type'] == type).listen(handler);
  }

  void emit(String type, [Map<String, dynamic>? data]) {
    if (_channel == null || !_connected) return;
    final payload = <String, dynamic>{'type': type, ...?data};
    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[chat] emit failed: $e');
    }
  }

  // ------------------------------------------------------------------
  // REST: rooms list / create / messages / delete
  // ------------------------------------------------------------------

  Future<void> fetchRooms({bool silent = false}) async {
    if (!silent) {
      _roomsLoading = true;
      notifyListeners();
    }
    try {
      final res = await auth.api.get('/api/chat/rooms');
      final data = res.data as Map<String, dynamic>;
      final list = (data['rooms'] as List? ?? [])
          .map((e) => ChatRoom.fromJson(e as Map<String, dynamic>))
          .toList();
      _rooms = list;
    } catch (e) {
      debugPrint('[chat] fetchRooms failed: $e');
    } finally {
      _roomsLoading = false;
      notifyListeners();
    }
  }

  /// Create or retrieve a room with a peer.
  /// Returns the room id, or null on failure.
  Future<ChatRoom?> openRoomWithPeer({
    required String peerUserId,
    String? productId,
    String? productTitle,
    String? productThumb,
  }) async {
    try {
      final res = await auth.api.post('/api/chat/rooms', data: {
        'peer_user_id': peerUserId,
        if (productId != null) 'product_id': productId,
        if (productTitle != null) 'product_title': productTitle,
        if (productThumb != null) 'product_thumb': productThumb,
      });
      final data = res.data as Map<String, dynamic>;
      final room = ChatRoom.fromJson({
        ...data['room'] as Map<String, dynamic>,
        'last_message_at': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
      // Merge into local cache.
      final existing = _rooms.indexWhere((r) => r.id == room.id);
      if (existing >= 0) {
        _rooms[existing] = room;
      } else {
        _rooms.insert(0, room);
      }
      notifyListeners();
      return room;
    } on DioException catch (e) {
      debugPrint('[chat] openRoomWithPeer failed: ${e.response?.data ?? e.message}');
      return null;
    } catch (e) {
      debugPrint('[chat] openRoomWithPeer failed: $e');
      return null;
    }
  }

  /// Load persisted history for a room.
  Future<void> loadHistory(String roomId) async {
    try {
      final res = await auth.api.get('/api/chat/rooms/$roomId/messages');
      final data = res.data as Map<String, dynamic>;
      final msgs = (data['messages'] as List? ?? []).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        // Pass through every server field so PriceOfferInfo.tryParse can pick
        // up the joined offer_* columns. We only stuff in a placeholder
        // sender_nickname since per-message nicknames aren't persisted.
        m['sender_nickname'] = '';
        return ChatMessage.fromJson(m, currentUserId: auth.user?.id);
      }).toList();
      _roomMessages[roomId] = msgs;
      notifyListeners();
    } catch (e) {
      debugPrint('[chat] loadHistory failed: $e');
    }
  }

  // ── Price offer (가격 제안 / 네고) ──────────────────────────────────

  /// Send a price offer in the given room. Server requires the room to have
  /// a product attached and the sender to NOT be the seller. Any prior
  /// pending offer in this room is auto-cancelled by the server.
  /// Returns null on success, error string on failure.
  Future<String?> sendPriceOffer(String roomId, int price) async {
    if (price <= 0) return '금액을 입력해주세요';
    try {
      await auth.api.post(
        '/api/chat/rooms/$roomId/offer',
        data: {'price': price},
      );
      // The server broadcasts via WS so the message appears via _onData.
      // We don't optimistically insert here to keep the source of truth
      // consistent (avoids duplicate bubbles).
      return null;
    } on DioException catch (e) {
      debugPrint('[chat] sendPriceOffer failed: ${e.response?.data ?? e.message}');
      final data = e.response?.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
      return '제안 전송 실패';
    } catch (e) {
      debugPrint('[chat] sendPriceOffer failed: $e');
      return '제안 전송 실패';
    }
  }

  /// Accept / reject (seller) or cancel (buyer) a pending offer.
  /// [action] must be one of: 'accept', 'reject', 'cancel'.
  Future<String?> respondToOffer(String offerId, String action) async {
    if (!['accept', 'reject', 'cancel'].contains(action)) {
      return 'invalid action';
    }
    try {
      await auth.api.patch(
        '/api/chat/offers/$offerId',
        data: {'action': action},
      );
      // Server broadcasts 'offer_updated' which we handle in _onData.
      return null;
    } on DioException catch (e) {
      debugPrint('[chat] respondToOffer failed: ${e.response?.data ?? e.message}');
      final data = e.response?.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
      return '처리 실패';
    } catch (e) {
      debugPrint('[chat] respondToOffer failed: $e');
      return '처리 실패';
    }
  }

  /// Permanently delete a room (and all messages) for BOTH users.
  Future<bool> deleteRoom(String roomId) async {
    try {
      await auth.api.delete('/api/chat/rooms/$roomId');
      _rooms.removeWhere((r) => r.id == roomId);
      _roomMessages.remove(roomId);
      if (_activeRoomId == roomId) _activeRoomId = null;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[chat] deleteRoom failed: $e');
      return false;
    }
  }

  /// Mark the room as read up to now. Called when the user opens the chat
  /// screen, and also whenever a new incoming message arrives while the user
  /// is already in that room. Optimistically zeroes the local badge so the UI
  /// snaps immediately, then tells the server (which broadcasts a read_receipt
  /// to the peer for the "읽음" indicator).
  Future<void> markRoomAsRead(String roomId) async {
    final idx = _rooms.indexWhere((r) => r.id == roomId);
    if (idx >= 0 && _rooms[idx].unreadCount > 0) {
      _rooms[idx] = _rooms[idx].copyWith(unreadCount: 0);
      notifyListeners();
    }
    // Dismiss any system notification for this room — user is here now.
    // ignore: discarded_futures
    NotificationService.instance.cancelForRoom(roomId);
    try {
      await auth.api.post('/api/chat/rooms/$roomId/read');
    } catch (e) {
      debugPrint('[chat] markRoomAsRead failed: $e');
    }
  }

  /// Clear all messages in a room (room itself stays).
  Future<bool> clearMessages(String roomId) async {
    try {
      await auth.api.delete('/api/chat/rooms/$roomId/messages');
      _roomMessages[roomId] = [];
      final idx = _rooms.indexWhere((r) => r.id == roomId);
      if (idx >= 0) {
        _rooms[idx] = _rooms[idx].copyWith(
          lastMessage: '',
          lastSenderId: null,
          lastMessageAt: DateTime.now(),
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[chat] clearMessages failed: $e');
      return false;
    }
  }

  // ------------------------------------------------------------------
  // WebSocket
  // ------------------------------------------------------------------

  void connect() {
    if (_connected || _connecting) return;
    final token = auth.token;
    if (token == null) return;
    _connecting = true;

    var url = AppConfig.socketUrl;
    if (url.startsWith('http://')) {
      url = 'ws://${url.substring(7)}';
    } else if (url.startsWith('https://')) {
      url = 'wss://${url.substring(8)}';
    }

    final parsed = Uri.tryParse(url);
    if (parsed != null && (parsed.path.isEmpty || parsed.path == '/')) {
      url = '${url.replaceAll(RegExp(r'/+$'), '')}/socket';
    }
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

    _connected = true;
    _connecting = false;
    _reconnectAttempts = 0;
    _startPing();
    notifyListeners();

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
    _eventBus.add(msg);

    switch (type) {
      case 'connected':
      case 'pong':
        break;

      case 'message': {
        final chatMsg = ChatMessage.fromJson(msg, currentUserId: auth.user?.id);
        _roomMessages.putIfAbsent(chatMsg.roomId, () => []);
        _roomMessages[chatMsg.roomId]!.add(chatMsg);

        // Bump local room preview.
        final idx = _rooms.indexWhere((r) => r.id == chatMsg.roomId);
        if (idx >= 0) {
          // If the message is from the peer and we're NOT viewing this room,
          // bump the unread badge. If we ARE viewing it, leave unread at 0
          // and tell the server we've read up to now (fires read_receipt).
          final fromPeer = !chatMsg.isMine;
          final inRoom = _activeRoomId == chatMsg.roomId;
          int newUnread = _rooms[idx].unreadCount;
          if (fromPeer && !inRoom) {
            newUnread += 1;
            // Surface a system notification (당근 style). Tap → /chat/:roomId.
            // ignore: discarded_futures
            NotificationService.instance.showChatMessage(
              roomId: chatMsg.roomId,
              senderNickname: chatMsg.senderNickname,
              text: chatMsg.text,
            );
          }

          _rooms[idx] = _rooms[idx].copyWith(
            lastMessage: chatMsg.text,
            lastSenderId: chatMsg.senderId,
            lastMessageAt: chatMsg.sentAt,
            unreadCount: newUnread,
          );
          // Re-sort desc by last_message_at.
          _rooms.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

          // If we're inside this room, immediately mark-as-read on the server
          // so the peer sees the "읽음" indicator without delay.
          if (fromPeer && inRoom) {
            // Fire-and-forget — auth.api.post returns Future, but markRoomAsRead
            // already handles errors internally.
            // ignore: discarded_futures
            markRoomAsRead(chatMsg.roomId);
          }
        } else {
          // Room showed up via WS before we fetched rooms list — refresh.
          fetchRooms(silent: true);
        }
        notifyListeners();
        break;
      }

      case 'room_updated': {
        final roomId = msg['room_id']?.toString();
        if (roomId == null) break;
        final idx = _rooms.indexWhere((r) => r.id == roomId);
        if (idx >= 0) {
          _rooms[idx] = _rooms[idx].copyWith(
            lastMessage: msg['last_message']?.toString() ?? '',
            lastSenderId: msg['last_sender_id']?.toString(),
            lastMessageAt:
                DateTime.tryParse(msg['last_message_at']?.toString() ?? '') ?? DateTime.now(),
          );
          _rooms.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
          notifyListeners();
        } else {
          fetchRooms(silent: true);
        }
        break;
      }

      case 'room_deleted': {
        final roomId = msg['room_id']?.toString();
        if (roomId == null) break;
        _rooms.removeWhere((r) => r.id == roomId);
        _roomMessages.remove(roomId);
        if (_activeRoomId == roomId) _activeRoomId = null;
        notifyListeners();
        break;
      }

      case 'messages_cleared': {
        final roomId = msg['room_id']?.toString();
        if (roomId == null) break;
        _roomMessages[roomId] = [];
        final idx = _rooms.indexWhere((r) => r.id == roomId);
        if (idx >= 0) {
          _rooms[idx] = _rooms[idx].copyWith(
            lastMessage: '',
            lastSenderId: null,
            lastMessageAt: DateTime.now(),
          );
        }
        notifyListeners();
        break;
      }

      case 'offer_updated': {
        // Server tells us a price-offer changed status (accepted/rejected/cancelled).
        // Update the matching message's offer info in-place so the UI re-renders
        // the bubble's status chip and disables the action buttons.
        final roomId = msg['room_id']?.toString();
        final offerData = msg['offer'];
        if (roomId == null || offerData is! Map) break;
        final offerId = offerData['id']?.toString();
        final newStatus = offerData['status']?.toString();
        if (offerId == null || newStatus == null) break;
        final list = _roomMessages[roomId];
        if (list == null) break;
        for (var i = 0; i < list.length; i++) {
          final m = list[i];
          if (m.offer?.id == offerId) {
            final updated = m.copyWith(
              offer: m.offer!.copyWith(
                status: newStatus,
                respondedAt: DateTime.tryParse(
                      offerData['responded_at']?.toString() ?? '',
                    ) ??
                    DateTime.now(),
              ),
            );
            list[i] = updated;
            notifyListeners();
            break;
          }
        }
        break;
      }

      case 'offer_updated': {
        // Server tells us a price-offer's status changed (accepted/rejected/cancelled).
        // Find the corresponding message in our cache and patch its `offer` field
        // so the existing bubble re-renders with the new status (no new message
        // is inserted — the same card just changes look).
        final roomId = msg['room_id']?.toString();
        final messageId = msg['message_id']?.toString();
        final offerJson = msg['offer'];
        if (roomId == null || messageId == null || offerJson is! Map) break;
        final newOffer = PriceOfferInfo.tryParse({
          'offer': Map<String, dynamic>.from(offerJson),
        });
        if (newOffer == null) break;
        final list = _roomMessages[roomId];
        if (list == null) break;
        final idx = list.indexWhere((m) => m.id == messageId);
        if (idx >= 0) {
          list[idx] = list[idx].copyWith(offer: newOffer);
          notifyListeners();
        }
        break;
      }

      case 'read_receipt': {
        // The peer just marked the room as read up to `read_at`. Update our
        // local copy so the "읽음" indicator next to my outgoing messages
        // can flip on for messages whose sent_at <= read_at.
        final roomId = msg['room_id']?.toString();
        final readAtStr = msg['read_at']?.toString();
        if (roomId == null || readAtStr == null) break;
        final readAt = DateTime.tryParse(readAtStr);
        if (readAt == null) break;
        final idx = _rooms.indexWhere((r) => r.id == roomId);
        if (idx >= 0) {
          _rooms[idx] = _rooms[idx].copyWith(peerLastReadAt: readAt);
          notifyListeners();
        }
        break;
      }

      case 'system':
        // In-room system text (e.g., "X joined"). Render in the room log only.
        final roomId = _activeRoomId;
        if (roomId != null) {
          final sys = ChatMessage(
            id: '${DateTime.now().microsecondsSinceEpoch}',
            roomId: roomId,
            senderId: 'system',
            senderNickname: 'system',
            text: msg['text']?.toString() ?? '',
            type: 'system',
            sentAt: DateTime.now(),
          );
          _roomMessages.putIfAbsent(roomId, () => []);
          _roomMessages[roomId]!.add(sys);
          notifyListeners();
        }
        break;
    }
  }

  void _startPing() {
    _stopPing();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) => emit('ping'));
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _scheduleReconnect() {
    if (auth.token == null) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts = (_reconnectAttempts + 1).clamp(1, 6);
    final delay = Duration(seconds: 1 << (_reconnectAttempts - 1));
    debugPrint('[chat] reconnect in ${delay.inSeconds}s');
    _reconnectTimer = Timer(delay, () {
      if (!_connected) connect();
    });
  }

  void joinRoom(String roomId, {String? peerNickname, String? productId}) {
    _activeRoomId = roomId;
    if (!_connected) connect();
    emit('join_room', {
      'room_id': roomId,
      if (peerNickname != null) 'peer_nickname': peerNickname,
      if (productId != null) 'product_id': productId,
    });
    // Load persisted history in parallel.
    loadHistory(roomId);
    notifyListeners();
  }

  void leaveRoom(String roomId) {
    // NOTE: this only tells the WS we're off the room view. It does NOT delete
    // anything. To wipe the room permanently, call deleteRoom().
    emit('leave_room', {'room_id': roomId});
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
    _rooms = [];
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
