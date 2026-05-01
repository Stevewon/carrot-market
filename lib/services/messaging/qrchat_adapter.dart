/// QRChat SDK 어댑터 — 스켈레톤(미구현 stub).
///
/// 배경:
///   채팅·통화 SDK 는 QRChat 을 만든 회사가 제공한다.
///   가지(Eggplant) 와 QRChat 은 같은 회사의 자매 앱이며
///   **퀀타리움 지갑주소 = Universal User ID** 라는 SSO 컨셉을 공유한다.
///
/// 이 파일은 SDK 인터페이스가 확정되면 즉시 채워 넣을 수 있도록
/// [MessagingAdapter] / [CallingAdapter] 의 모든 메서드를 stub 으로 미리
/// 정의해 둔 상태다. 실제 구현 시 TODO 로 표시된 부분을 SDK 호출로 바꾸면 된다.
///
/// 채팅 내역 정책:
///   가지 백엔드는 채팅 메시지를 절대 저장하지 않으며,
///   저장·암호화·삭제·내보내기 정책은 100% QRChat SDK 정책을 따른다.
library;

import 'dart:async';

import '../../models/chat_message.dart';
import '../../models/chat_room.dart';
import 'messaging_adapter.dart';

/// QRChat SDK 메시징 어댑터 (스켈레톤).
///
/// SDK 가 결정되면 다음 단계로 채워진다:
///   1) pubspec.yaml 에 SDK Flutter 패키지 추가 (예: `qrchat_sdk: ^1.0.0`)
///   2) [_sdk] 필드 타입을 `QRChatSdk` (혹은 패키지가 제공하는 클래스) 로 교체
///   3) 각 메서드의 TODO 부분을 SDK 호출로 바꾸기
///   4) main.dart 에서 `EggplantBuiltinMessagingAdapter` 대신 이 클래스를 주입
class QRChatMessagingAdapter implements MessagingAdapter {
  QRChatMessagingAdapter();

  // TODO(qrchat-sdk): 실제 SDK 객체 주입.
  //   final QRChatSdk _sdk;
  //   QRChatMessagingAdapter(this._sdk);

  // ── 식별자 / 상태 ──────────────────────────────────────────────
  @override
  String get adapterId => 'qrchat_sdk';

  MessagingConnectionState _state = MessagingConnectionState.disconnected;

  @override
  MessagingConnectionState get connectionState => _state;

  // ── 캐시 ───────────────────────────────────────────────────────
  // SDK 가 자체 캐시를 제공하면 이 필드들은 SDK getter 로 위임 가능.
  final List<ChatRoom> _rooms = [];
  final Map<String, List<ChatMessage>> _roomMessages = {};

  @override
  int get totalUnread => _rooms.fold(0, (a, r) => a + r.unreadCount);

  @override
  List<ChatRoom> get rooms => List.unmodifiable(_rooms);

  @override
  List<ChatMessage> messagesFor(String roomId) =>
      List.unmodifiable(_roomMessages[roomId] ?? const []);

  // ── 스트림 ─────────────────────────────────────────────────────
  final _changes = StreamController<void>.broadcast();
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  StreamSubscription<Map<String, dynamic>> on(
    String type,
    void Function(Map<String, dynamic>) handler,
  ) {
    return _events.stream.where((e) => e['type'] == type).listen(handler);
  }

  // ── 라이프사이클 ───────────────────────────────────────────────
  MessagingIdentity? _identity;

  @override
  Future<void> init(MessagingIdentity identity) async {
    _identity = identity;
    // TODO(qrchat-sdk): SDK 초기화. 핵심은 wallet_address(Universal User ID).
    //   await _sdk.init(
    //     walletAddress: identity.walletAddress,
    //     displayName: identity.nickname,
    //     authToken: identity.authToken,           // 가지 서버 user 검증 콜백용
    //     environment: kReleaseMode ? 'prod' : 'dev',
    //   );
    //   _sdk.onConnectionStateChanged.listen(_handleConnState);
    //   _sdk.onMessage.listen(_handleIncoming);
    //   _sdk.onEvent.listen(_handleSdkEvent);
    throw UnsupportedError(
      'QRChat SDK 가 아직 연결되지 않았어요. '
      '현재는 EggplantBuiltinMessagingAdapter 를 사용하세요.',
    );
  }

  @override
  void connect() {
    // TODO(qrchat-sdk): _sdk.connect();
    _state = MessagingConnectionState.connecting;
    _changes.add(null);
  }

  @override
  Future<void> disconnect() async {
    // TODO(qrchat-sdk): await _sdk.disconnect();
    _state = MessagingConnectionState.disconnected;
    _changes.add(null);
  }

  // ── 룸/메시지 ──────────────────────────────────────────────────

  @override
  Future<ChatRoom?> openRoomWithPeer({
    required String peerUserId,
    String? peerNickname,
    String? productId,
    String? productTitle,
    String? productThumb,
  }) async {
    // TODO(qrchat-sdk): SDK 가 wallet/userId 기반으로 1:1 룸을 보장.
    //   final r = await _sdk.openOrCreateRoom(
    //     peerWalletOrUserId: peerUserId,
    //     metadata: {
    //       'product_id': productId,
    //       'product_title': productTitle,
    //       'product_thumb': productThumb,
    //     },
    //   );
    //   return _toChatRoom(r, peerNickname: peerNickname);
    throw UnsupportedError('QRChat SDK 미연결');
  }

  @override
  Future<String?> sendText(String roomId, String text) async {
    if (_identity == null) return '로그인이 필요해요';
    if (text.trim().isEmpty) return '내용을 입력해주세요';
    // TODO(qrchat-sdk): await _sdk.sendText(roomId, text);
    return 'QRChat SDK 미연결';
  }

  @override
  void emit(String type, [Map<String, dynamic>? data]) {
    // TODO(qrchat-sdk): _sdk.emit(type, data ?? {});
    // 가격 제안·읽음 처리 같은 가지 고유 이벤트도 generic event 로 흘려보낸다.
    if (_state != MessagingConnectionState.connected) return;
    _events.add({
      'type': type,
      ...?data,
    });
  }

  @override
  Future<bool> deleteRoom(String roomId) async {
    // TODO(qrchat-sdk): await _sdk.leaveRoom(roomId, broadcast: true);
    _rooms.removeWhere((r) => r.id == roomId);
    _roomMessages.remove(roomId);
    _changes.add(null);
    return true;
  }

  @override
  Future<bool> clearMessages(String roomId) async {
    // TODO(qrchat-sdk): SDK 정책에 따름. 일부 SDK 는 양쪽 동기 삭제,
    // 일부는 본인 디바이스만 삭제. QRChat 정책 100% 준수.
    //   await _sdk.clearLocalMessages(roomId);
    _roomMessages[roomId] = [];
    _changes.add(null);
    return true;
  }

  @override
  Future<void> markRoomAsRead(String roomId) async {
    // TODO(qrchat-sdk): await _sdk.markAsRead(roomId);
    final i = _rooms.indexWhere((r) => r.id == roomId);
    if (i >= 0 && _rooms[i].unreadCount > 0) {
      _rooms[i] = _rooms[i].copyWith(unreadCount: 0);
      _changes.add(null);
    }
  }

  @override
  void clearAll() {
    _rooms.clear();
    _roomMessages.clear();
    _identity = null;
    _state = MessagingConnectionState.disconnected;
    _changes.add(null);
  }
}

/// QRChat SDK 통화 어댑터 (스켈레톤).
///
/// 시그널링은 [QRChatMessagingAdapter.events] 채널을 재사용하고,
/// 미디어는 SDK 의 자체 WebRTC 스택을 사용한다.
class QRChatCallingAdapter implements CallingAdapter {
  QRChatCallingAdapter();

  // TODO(qrchat-sdk): SDK 의 voice call 객체 주입.
  //   final QRChatVoiceSession _voice;

  @override
  String get adapterId => 'qrchat_sdk_call';

  CallSessionState _state = CallSessionState.idle;
  String? _peerUserId;
  String? _peerNickname;
  DateTime? _connectedAt;
  bool _muted = false;
  bool _speaker = false;

  final _changes = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => _changes.stream;

  @override
  CallSessionState get state => _state;
  @override
  String? get peerUserId => _peerUserId;
  @override
  String? get peerNickname => _peerNickname;
  @override
  DateTime? get connectedAt => _connectedAt;

  @override
  Future<void> init(MessagingIdentity identity) async {
    // TODO(qrchat-sdk): _voice = _sdk.voice;
    //   _voice.onIncoming.listen(_handleIncoming);
    //   _voice.onStateChanged.listen(_handleState);
    throw UnsupportedError('QRChat SDK 미연결');
  }

  @override
  Future<void> startCall({
    required String peerUserId,
    required String peerNickname,
  }) async {
    _peerUserId = peerUserId;
    _peerNickname = peerNickname;
    _state = CallSessionState.outgoing;
    _changes.add(null);
    // TODO(qrchat-sdk): await _voice.invite(peerUserId);
    throw UnsupportedError('QRChat SDK 미연결');
  }

  @override
  Future<void> acceptIncoming() async {
    // TODO(qrchat-sdk): await _voice.accept();
    _state = CallSessionState.connecting;
    _changes.add(null);
  }

  @override
  Future<void> hangUp() async {
    // TODO(qrchat-sdk): await _voice.hangUp();
    _state = CallSessionState.ended;
    _peerUserId = null;
    _peerNickname = null;
    _connectedAt = null;
    _changes.add(null);
  }

  @override
  Future<void> toggleMute() async {
    // TODO(qrchat-sdk): await _voice.setMuted(!_muted);
    _muted = !_muted;
    _changes.add(null);
  }

  @override
  bool get isMuted => _muted;

  @override
  Future<void> toggleSpeaker() async {
    // TODO(qrchat-sdk): await _voice.setSpeaker(!_speaker);
    _speaker = !_speaker;
    _changes.add(null);
  }

  @override
  bool get isSpeaker => _speaker;
}
