import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../app/constants.dart';
import '../models/chat_message.dart';
import '../models/chat_room.dart';
import 'auth_service.dart';
import 'launcher_badge.dart';
import 'notification_service.dart';

/// 휘발성 채팅 서비스 — 사생활 보호 모드 (telegram secret chat 스타일).
///
/// 정책:
/// - 메시지·가격제안·채팅방은 서버 DB 에 절대 저장되지 않는다.
/// - 모든 데이터는 WebSocket Durable Object 메모리에서만 broadcast 된다.
/// - 앱을 닫거나 재시작하면 채팅 목록과 내역은 모두 비어 있다 (영구 소실).
/// - "채팅방 나가기" 또는 "채팅 내역 삭제" 시 양쪽 기기에서 즉시 사라진다.
/// - 통화는 원래부터 WebRTC P2P 라 미디어가 서버를 거치지 않는다.
///
/// Transport:
///   WS   : /socket?token=... 으로 실시간 송수신.
///   REST : 거의 사용 안 함 (서버는 휘발성 모드라 빈 응답만 반환).
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

  /// 휘발성 모드: 서버는 채팅방을 보관하지 않는다.
  /// 따라서 fetchRooms 는 서버에 묻지 않고 로컬 메모리(_rooms)만 사용한다.
  /// 앱이 막 켜졌거나 disconnect 직후에는 빈 목록이 정상이다.
  Future<void> fetchRooms({bool silent = false}) async {
    if (!silent) {
      _roomsLoading = true;
      notifyListeners();
    }
    // 서버에 호출하지 않는다 — 휘발성. 단, REST 엔드포인트는 빈 배열을 돌려주므로
    // 기존 호출이 살아 있어도 데이터를 덮어쓰지 않도록 그냥 종료.
    _roomsLoading = false;
    notifyListeners();
  }

  /// Deterministic roomId from two userIds (+ optional productId).
  /// Both sides compute the same id without contacting the server.
  String _makeRoomId(String userA, String userB, [String? productId]) {
    final pair = [userA, userB]..sort();
    return productId != null && productId.isNotEmpty
        ? '${pair[0]}_${pair[1]}_$productId'
        : '${pair[0]}_${pair[1]}';
  }

  /// ★ 6차 푸시: roomId 패턴(`userA_userB[_productId]`)에서 본인이 아닌
  ///   userId 를 peerId 로 추출. 휘발성 정책상 서버 DB 에 방 정보가 없어서
  ///   클라이언트가 결정적으로 peerId 를 도출해야 한다.
  ///
  ///   roomId 형식:
  ///     - 'aaa_bbb'             (유저 둘만)
  ///     - 'aaa_bbb_productId'   (상품 첨부)
  ///   userId 자체에 '_' 가 들어갈 수 있는지 — Eggplant 의 user.id 는
  ///   wallet address 또는 uuid 라 '_' 미포함. 따라서 split('_') 안전.
  ///
  ///   me 가 토큰 둘 중 하나에 포함돼 있어야 정상. 못 찾으면 null 반환 →
  ///   호출자가 합성 방 생성 포기.
  ({String peerId, String? productId})? _extractPeerFromRoomId(
    String roomId,
    String me,
  ) {
    final parts = roomId.split('_');
    if (parts.length < 2) return null;
    final a = parts[0];
    final b = parts[1];
    final productId = parts.length >= 3 ? parts.sublist(2).join('_') : null;
    if (a == me) {
      return (peerId: b, productId: productId);
    }
    if (b == me) {
      return (peerId: a, productId: productId);
    }
    return null;
  }

  /// ★ 6차 푸시: WS 'message' 이벤트로 처음 들어오는 방을 메모리에 즉석 생성.
  ///   서버 DB 에는 채팅방 자체가 없으므로 (휘발성), 메시지 payload 만으로
  ///   ChatRoom 을 합성한다. productTitle/productThumb 은 빈 값 — 방 진입 시
  ///   ChatScreen 이 productId 로 ProductService 를 통해 별도 조회한다.
  ChatRoom? _synthesizeRoomFromMessage(
    ChatMessage chatMsg,
    Map<String, dynamic> rawMsg,
  ) {
    final me = auth.user?.id;
    if (me == null) return null;
    final extracted = _extractPeerFromRoomId(chatMsg.roomId, me);
    if (extracted == null) return null;
    // 내가 보낸 메시지의 echo 면 sender_nickname 은 내 닉네임 → peerNickname 으로
    // 쓰면 안 됨. 그 경우엔 '익명' 으로 시작 (peer 응답이 오면 갱신됨).
    final fromPeer = !chatMsg.isMine;
    final peerNickname =
        fromPeer ? chatMsg.senderNickname : '익명';
    return ChatRoom(
      id: chatMsg.roomId,
      peerId: extracted.peerId,
      peerNickname: peerNickname,
      peerMannerScore: 36,
      productId: extracted.productId,
      productTitle: null,
      productThumb: null,
      lastMessage: chatMsg.text,
      lastSenderId: chatMsg.senderId,
      lastMessageAt: chatMsg.sentAt,
      createdAt: chatMsg.sentAt,
      unreadCount: 0, // 호출자 쪽(message case)에서 +1 처리
      peerLastReadAt: null,
    );
  }

  /// ★ 6차 푸시: WS 'room_updated' 이벤트로 처음 들어오는 방을 합성.
  ///   payload 에 last_sender_id/last_sender_nickname/last_message 등이 있음.
  ChatRoom? _synthesizeRoomFromUpdate(
    String roomId,
    Map<String, dynamic> rawMsg,
  ) {
    final me = auth.user?.id;
    if (me == null) return null;
    final extracted = _extractPeerFromRoomId(roomId, me);
    if (extracted == null) return null;
    final lastSenderId = rawMsg['last_sender_id']?.toString();
    final lastSenderNickname =
        rawMsg['last_sender_nickname']?.toString() ?? '익명';
    // 마지막 sender 가 peer 면 그 닉네임으로, 본인이면 '익명' 시작.
    final peerNickname =
        (lastSenderId != null && lastSenderId != me) ? lastSenderNickname : '익명';
    final lastAt = DateTime.tryParse(
            rawMsg['last_message_at']?.toString() ?? '') ??
        DateTime.now();
    return ChatRoom(
      id: roomId,
      peerId: extracted.peerId,
      peerNickname: peerNickname,
      peerMannerScore: 36,
      productId: extracted.productId,
      productTitle: null,
      productThumb: null,
      lastMessage: rawMsg['last_message']?.toString() ?? '',
      lastSenderId: lastSenderId,
      lastMessageAt: lastAt,
      createdAt: lastAt,
      unreadCount: 0,
      peerLastReadAt: null,
    );
  }

  /// Open (or recreate locally) a chat room with a peer. Does NOT touch the DB.
  /// Returns a synthetic ChatRoom that lives only in memory.
  Future<ChatRoom?> openRoomWithPeer({
    required String peerUserId,
    String? peerNickname,
    String? productId,
    String? productTitle,
    String? productThumb,
  }) async {
    final me = auth.user?.id;
    if (me == null) return null;
    final roomId = _makeRoomId(me, peerUserId, productId);
    final now = DateTime.now();
    final room = ChatRoom(
      id: roomId,
      peerId: peerUserId,
      peerNickname: peerNickname ?? '익명',
      peerMannerScore: 36, // default neutral; server uses *10 scale but for fresh local rooms keep simple
      productId: productId,
      productTitle: productTitle,
      productThumb: productThumb,
      lastMessage: '',
      lastSenderId: null,
      lastMessageAt: now,
      createdAt: now,
      unreadCount: 0,
      peerLastReadAt: null,
    );
    final existing = _rooms.indexWhere((r) => r.id == roomId);
    if (existing >= 0) {
      // 메모리에 이미 있으면 product 정보만 보강.
      _rooms[existing] = _rooms[existing].copyWith(
        productId: productId ?? _rooms[existing].productId,
        productTitle: productTitle ?? _rooms[existing].productTitle,
        productThumb: productThumb ?? _rooms[existing].productThumb,
        peerNickname: peerNickname ?? _rooms[existing].peerNickname,
      );
    } else {
      _rooms.insert(0, room);
    }
    notifyListeners();
    return _rooms.firstWhere((r) => r.id == roomId);
  }

  /// 채팅 내역 정책: **무조건 QRChat SDK 정책 100% 준수**.
  /// 가지(Eggplant) 백엔드는 채팅 메시지를 절대 저장·중계·복제하지 않는다.
  /// 따라서 서버에서 히스토리를 가져오지 않으며, QRChat SDK 가 도입되면
  /// 이 메서드는 SDK 의 history API 를 직접 호출하도록 어댑터에서 위임된다.
  Future<void> loadHistory(String roomId) async {
    // 가지 서버에는 메시지가 없다 → no-op.
    // QRChat SDK 도입 후에는 EggplantBuiltinMessagingAdapter 가
    // QRChatMessagingAdapter 로 교체되며, 그쪽에서 SDK history 를 호출한다.
    _roomMessages.putIfAbsent(roomId, () => []);
  }

  // ── 가격 제안 (휘발성: WebSocket 으로만 전송) ──────────────────────────

  /// 가격 제안을 보낸다. 서버 DB 에 저장하지 않고 WS broadcast 만 함.
  Future<String?> sendPriceOffer(String roomId, int price) async {
    if (price <= 0) return '금액을 입력해주세요';
    if (auth.user == null) return '로그인이 필요해요';
    if (!_connected) {
      connect();
      // 재연결 직후 큐에 못 실으면 사용자에게 즉시 알림.
      return '연결 중이에요. 잠시 후 다시 시도해주세요';
    }
    emit('price_offer', {
      'room_id': roomId,
      'price': price,
      'sender_nickname': auth.user!.nickname,
    });
    return null;
  }

  /// 가격 제안에 응답 (수락/거절/취소). 휘발성이라 WS 로만.
  Future<String?> respondToOffer(String offerId, String action,
      {String? roomId}) async {
    if (!['accept', 'reject', 'cancel'].contains(action)) {
      return 'invalid action';
    }
    if (auth.user == null) return '로그인이 필요해요';
    if (!_connected) {
      connect();
      return '연결 중이에요. 잠시 후 다시 시도해주세요';
    }
    // roomId 가 안 들어오면 메모리에서 offerId 로 찾는다.
    String? rid = roomId;
    if (rid == null) {
      for (final entry in _roomMessages.entries) {
        if (entry.value.any((m) => m.offer?.id == offerId)) {
          rid = entry.key;
          break;
        }
      }
    }
    if (rid == null) return '대화방을 찾을 수 없어요';
    emit('offer_response', {
      'room_id': rid,
      'offer_id': offerId,
      'action': action,
    });
    return null;
  }

  /// 채팅방 나가기 — 양쪽에서 즉시 사라짐.
  /// 서버에 저장된 데이터가 없으므로 DB delete 호출은 형식상이고,
  /// 핵심은 peer 에게 'room_deleted' broadcast 다. 양쪽 메모리 캐시가 모두 비워진다.
  Future<bool> deleteRoom(String roomId) async {
    // 즉시 로컬 캐시에서 제거.
    _rooms.removeWhere((r) => r.id == roomId);
    _roomMessages.remove(roomId);
    if (_activeRoomId == roomId) _activeRoomId = null;
    notifyListeners();
    // peer 에게도 알리기 위해 서버 REST 호출 (서버는 broadcast 만 함, DB 삭제는 없음).
    try {
      await auth.api.delete('/api/chat/rooms/$roomId');
      return true;
    } catch (e) {
      debugPrint('[chat] deleteRoom broadcast failed: $e');
      // 로컬에서는 이미 지워졌으니 사용자 입장에선 성공으로 본다.
      return true;
    }
  }

  /// 읽음 처리. 휘발성이라 서버 DB read 가 없지만 peer 에게 read_receipt 는 보내야
  /// '읽음' 표시가 켜진다. UI 뱃지는 즉시 0으로.
  Future<void> markRoomAsRead(String roomId) async {
    final idx = _rooms.indexWhere((r) => r.id == roomId);
    if (idx >= 0 && _rooms[idx].unreadCount > 0) {
      _rooms[idx] = _rooms[idx].copyWith(unreadCount: 0);
      notifyListeners();
    }
    // 시스템 알림(푸시) 도 정리.
    // ignore: discarded_futures
    NotificationService.instance.cancelForRoom(roomId);
    // ★ 7차 푸시: 런처 아이콘 뱃지 동기화 (totalUnread 기준).
    //  채팅방 진입 시 unread=0 → 바탕화면 아이콘 뱃지도 함께 갱신.
    // ignore: discarded_futures
    _syncLauncherBadge();
    // peer 에게 직접 read_receipt 를 emit (서버는 그대로 forward 함).
    if (_connected) {
      emit('read_receipt', {
        'room_id': roomId,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  /// ★ 7차 푸시: 런처 아이콘 뱃지(바탕화면 아이콘 위 숫자) 동기화.
  ///   totalUnread 가 0 이면 뱃지 제거, 그 이상이면 해당 숫자로 표시.
  ///   Samsung/Xiaomi/LG/Huawei 등 OEM 런처가 자동으로 해석.
  ///   FCM 이 띄운 시스템 알림과 별개로 직접 제어 — 채팅방 들어가서 읽었는데
  ///   바탕화면 뱃지가 그대로 남는 문제(이슈 2) 해결용.
  ///
  ///   구현: flutter_app_badger 1.5.0 이 AGP 8.x namespace 비호환 → 가지(Eggplant)
  ///   는 MainActivity.kt 의 native MethodChannel 'eggplant.market/launcher_badge' 로
  ///   OEM intent broadcast 직접 전송. lib/services/launcher_badge.dart 가 wrapper.
  Future<void> _syncLauncherBadge() async {
    try {
      await LauncherBadge.set(totalUnread);
    } catch (e) {
      debugPrint('[chat] launcher badge sync failed: $e');
    }
  }

  /// ★ 7차 푸시: FCM 푸시 수신(foreground/background/cold-start) 시 호출.
  ///   WS 가 끊긴 상태에서도 푸시 payload 의 room_id 만으로 합성 방을 _rooms 에
  ///   넣고 unread+1 처리 → 메인탭 채팅 뱃지 + 런처 아이콘 뱃지 즉시 갱신.
  ///   사용자가 바탕화면 아이콘을 탭해서 앱을 켜도 미읽음 방이 보이고 자동
  ///   진입 로직(_maybeAutoEnterUnreadRoom)이 동작한다.
  ///
  ///   동일 메시지의 중복 처리 방지: 같은 roomId 면 unread 만 +1 하고
  ///   lastMessage 갱신 (synth 합성은 1회만).
  void applyIncomingPushMessage({
    required String roomId,
    String? senderId,
    String? senderNickname,
    String? text,
    DateTime? sentAt,
  }) {
    final me = auth.user?.id;
    if (me == null) return;
    if (roomId.isEmpty) return;

    final now = sentAt ?? DateTime.now();
    final preview = (text == null || text.isEmpty) ? '새 메시지' : text;

    var idx = _rooms.indexWhere((r) => r.id == roomId);
    if (idx < 0) {
      // 합성 방 생성 — _extractPeerFromRoomId 로 peer 추출.
      final extracted = _extractPeerFromRoomId(roomId, me);
      if (extracted == null) return; // me 가 roomId 에 없으면 무시.
      final peerNick = (senderNickname != null && senderNickname.isNotEmpty)
          ? senderNickname
          : '익명';
      _rooms.insert(
        0,
        ChatRoom(
          id: roomId,
          peerId: extracted.peerId,
          peerNickname: peerNick,
          peerMannerScore: 36,
          productId: extracted.productId,
          productTitle: null,
          productThumb: null,
          lastMessage: preview,
          lastSenderId: senderId,
          lastMessageAt: now,
          createdAt: now,
          unreadCount: 1,
          peerLastReadAt: null,
        ),
      );
    } else {
      // 기존 방 — 활성 방이면 unread 유지, 아니면 +1.
      final inRoom = _activeRoomId == roomId;
      final newUnread = inRoom ? 0 : (_rooms[idx].unreadCount + 1);
      _rooms[idx] = _rooms[idx].copyWith(
        lastMessage: preview,
        lastSenderId: senderId,
        lastMessageAt: now,
        unreadCount: newUnread,
      );
      _rooms.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    }
    notifyListeners();
    // ignore: discarded_futures
    _syncLauncherBadge();
  }

  /// 채팅 내역만 비우기. 휘발성이라 서버에 지울 게 없고, peer 에게 broadcast 만 발송.
  Future<bool> clearMessages(String roomId) async {
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
    try {
      await auth.api.delete('/api/chat/rooms/$roomId/messages');
    } catch (e) {
      debugPrint('[chat] clearMessages broadcast failed: $e');
    }
    return true;
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
        var idx = _rooms.indexWhere((r) => r.id == chatMsg.roomId);
        if (idx < 0) {
          // ★ 6차 푸시: 휘발성 정책상 서버에 채팅방 목록이 없으므로,
          //  WS 로 처음 들어온 message 이벤트가 곧 "방 생성" 신호다.
          //  payload 의 sender_id, sender_nickname, room_id 로 합성 방을
          //  즉석에서 만들어 _rooms 에 추가 → 채팅 목록 탭에 즉시 노출.
          //  fetchRooms 는 휘발성이라 빈 작업이므로 의존하면 안 됨.
          final synthesized = _synthesizeRoomFromMessage(chatMsg, msg);
          if (synthesized != null) {
            _rooms.insert(0, synthesized);
            idx = 0;
          }
        }
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

          // ★ 7차 푸시: WS 로 메시지 받았을 때도 런처 아이콘 뱃지 동기화.
          //  fromPeer && !inRoom 이면 unread+1 → 바탕화면 뱃지도 갱신.
          // ignore: discarded_futures
          _syncLauncherBadge();

          // If we're inside this room, immediately mark-as-read on the server
          // so the peer sees the "읽음" indicator without delay.
          if (fromPeer && inRoom) {
            // Fire-and-forget — auth.api.post returns Future, but markRoomAsRead
            // already handles errors internally.
            // ignore: discarded_futures
            markRoomAsRead(chatMsg.roomId);
          }
        }
        notifyListeners();
        break;
      }

      case 'room_updated': {
        final roomId = msg['room_id']?.toString();
        if (roomId == null) break;
        var idx = _rooms.indexWhere((r) => r.id == roomId);
        if (idx < 0) {
          // ★ 6차 푸시: 위 'message' 와 동일 — 휘발성 정책상 fetchRooms 빈 작업.
          //  room_updated payload 자체가 last_sender_id/last_sender_nickname 을
          //  들고 오므로 합성 방 생성에 충분.
          final synthesized = _synthesizeRoomFromUpdate(roomId, msg);
          if (synthesized != null) {
            _rooms.insert(0, synthesized);
            idx = 0;
          }
        }
        if (idx >= 0) {
          _rooms[idx] = _rooms[idx].copyWith(
            lastMessage: msg['last_message']?.toString() ?? '',
            lastSenderId: msg['last_sender_id']?.toString(),
            lastMessageAt:
                DateTime.tryParse(msg['last_message_at']?.toString() ?? '') ?? DateTime.now(),
          );
          _rooms.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
          notifyListeners();
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
        // 휘발성 모드: 서버는 { room_id, offer_id, status, responder_id, updated_at } 만 보낸다.
        // 메모리에서 해당 메시지를 찾아 offer.status 만 갱신하고 같은 버블이 다시 렌더되게 한다.
        final roomId = msg['room_id']?.toString();
        final offerId = msg['offer_id']?.toString();
        final newStatus = msg['status']?.toString();
        if (roomId == null || offerId == null || newStatus == null) break;
        final list = _roomMessages[roomId];
        if (list == null) break;
        for (var i = 0; i < list.length; i++) {
          final m = list[i];
          if (m.offer?.id == offerId) {
            list[i] = m.copyWith(
              offer: m.offer!.copyWith(
                status: newStatus,
                respondedAt: DateTime.tryParse(
                      msg['updated_at']?.toString() ?? '',
                    ) ??
                    DateTime.now(),
              ),
            );
            notifyListeners();
            break;
          }
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
        }

        // 당근식 '1' 표시: 내가 보낸 메시지 중 sent_at <= read_at 인 것을
        // isRead=true 로 갱신. 휘발성 정책 준수 (D1 저장 0건, 메모리 only).
        final list = _roomMessages[roomId];
        if (list != null && list.isNotEmpty) {
          var changed = false;
          for (var i = 0; i < list.length; i++) {
            final m = list[i];
            if (m.isMine && !m.isRead && !m.sentAt.isAfter(readAt)) {
              list[i] = m.copyWith(isRead: true);
              changed = true;
            }
          }
          if (changed) notifyListeners();
        } else {
          notifyListeners();
        }
        break;
      }

      case 'keyword_alert': {
        // 새 상품이 등록 키워드와 매칭됨. NotificationService 로 로컬 푸시.
        // 사생활 보호: 알림 이력은 어디에도 저장하지 않는다.
        final productId = msg['product_id']?.toString() ?? '';
        final title = msg['title']?.toString() ?? '';
        final region = msg['region']?.toString() ?? '';
        if (productId.isNotEmpty) {
          // ignore: discarded_futures
          NotificationService.instance.showKeywordAlert(
            productId: productId,
            title: title,
            region: region,
          );
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
