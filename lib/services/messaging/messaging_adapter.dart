/// QRChat SDK 통합을 위한 추상 어댑터 인터페이스.
///
/// 배경:
///   채팅·통화 SDK 는 QRChat 을 만든 회사가 추후 제공한다.
///   가지(Eggplant) 와 QRChat 은 같은 회사의 자매 앱이며,
///   **퀀타리움 지갑주소 = Universal User ID** 라는 SSO 컨셉을 공유한다.
///
///   사용자 = 퀀타리움 지갑주소 (단 하나)
///     ├── QRChat 앱에서 가입/로그인 → 자동으로 가지 가입됨
///     ├── 가지 앱에서 가입/로그인 → 자동으로 QRChat 가입됨
///     └── 채팅·통화 데이터는 양쪽 앱에서 100% 공유
///
/// 이 파일이 정의하는 추상 인터페이스를 만족시키면
/// QRChat SDK 구현체를 그대로 끼워 넣을 수 있다.
///
/// 현재는 `EggplantBuiltinMessagingAdapter` / `EggplantBuiltinCallingAdapter`
/// 가 자체 WebSocket·WebRTC 구현(ChatService/CallService)을 감싼다.
///
/// 추후 SDK 출시 시 동일 인터페이스로 `QRChatMessagingAdapter` 만 추가하면
/// main.dart 의 한 줄 교체로 전환 완료.

import 'dart:async';

import '../../models/chat_message.dart';
import '../../models/chat_room.dart';

/// SSO 세션 — 어댑터 init 시점에 전달되는 사용자 정체성.
///
/// 핵심 키는 **walletAddress** (퀀타리움 지갑주소 = Universal User ID).
/// 휴대폰/이메일 등 사적 정보는 SDK 에 노출하지 않는다.
class MessagingIdentity {
  /// 퀀타리움 지갑주소 (0x + 40 hex). Universal User ID.
  /// QRChat 과 가지가 같은 사용자를 식별하는 유일한 키.
  final String walletAddress;

  /// 표시용 닉네임 (SDK 가 채팅창에 표시).
  final String nickname;

  /// 가지 백엔드 JWT — SDK 가 가지 서버에 user 검증 콜백을 보낼 때 사용.
  /// QRChat 단독 모드에서는 null 가능.
  final String? authToken;

  const MessagingIdentity({
    required this.walletAddress,
    required this.nickname,
    this.authToken,
  });
}

/// 어댑터 연결 상태.
enum MessagingConnectionState {
  disconnected,
  connecting,
  connected,
}

/// 채팅(메시지) 어댑터.
///
/// SDK 교체 가능한 핵심 표면만 노출. 가격 제안·읽음 처리 등
/// 가지 고유 기능은 [emit] 의 generic event 로 흘려 보낸다.
abstract class MessagingAdapter {
  /// 어댑터 식별자 ('eggplant_builtin', 'qrchat_sdk' 등).
  String get adapterId;

  /// 현재 연결 상태.
  MessagingConnectionState get connectionState;

  /// 미수신 알림 총합 (탭 배지용).
  int get totalUnread;

  /// 어댑터에 보유된 채팅방 목록 (메모리 캐시).
  List<ChatRoom> get rooms;

  /// 특정 방의 메시지 목록.
  List<ChatMessage> messagesFor(String roomId);

  /// 어댑터 변경 통지를 구독 (Provider/ChangeNotifier 와 호환되도록 별도 stream 도 제공).
  Stream<void> get changes;

  /// 임의 이벤트 스트림 (가격 제안, 읽음, 통화 시그널링 등).
  /// QRChat SDK 도 동일한 이벤트 이름 규약을 따른다.
  Stream<Map<String, dynamic>> get events;

  /// 특정 type 이벤트만 필터링해 구독.
  StreamSubscription<Map<String, dynamic>> on(
    String type,
    void Function(Map<String, dynamic>) handler,
  );

  /// SSO 정체성으로 어댑터 초기화. 로그인 직후 1회 호출.
  Future<void> init(MessagingIdentity identity);

  /// 실시간 채널 연결 시도 (자동 재시도 내장).
  void connect();

  /// 채널 닫고 정리.
  Future<void> disconnect();

  /// 채팅방 열기 (peer 의 walletAddress 또는 user_id 기반).
  Future<ChatRoom?> openRoomWithPeer({
    required String peerUserId,
    String? peerNickname,
    String? productId,
    String? productTitle,
    String? productThumb,
  });

  /// 텍스트 메시지 전송 (SDK 별 채널 raw API 사용).
  Future<String?> sendText(String roomId, String text);

  /// 가지 고유 이벤트 송신 (가격 제안 등). 일반화된 emit.
  void emit(String type, [Map<String, dynamic>? data]);

  /// 채팅방 나가기 (양쪽 즉시 사라짐).
  Future<bool> deleteRoom(String roomId);

  /// 채팅 내역만 비우기.
  Future<bool> clearMessages(String roomId);

  /// 읽음 처리.
  Future<void> markRoomAsRead(String roomId);

  /// 로그아웃 등으로 메모리 캐시 비우기.
  void clearAll();
}

/// 음성통화 어댑터.
///
/// 시그널링은 [MessagingAdapter.events] 채널을 그대로 재사용한다.
/// (QRChat SDK 도 같은 채널에 'webrtc_offer/answer/ice' 이벤트를 흘려준다.)
abstract class CallingAdapter {
  String get adapterId;

  CallSessionState get state;
  String? get peerUserId;
  String? get peerNickname;
  DateTime? get connectedAt;

  Stream<void> get changes;

  /// SSO 정체성으로 통화 어댑터 초기화 (마이크 권한 등 사전 점검 X).
  Future<void> init(MessagingIdentity identity);

  /// 발신 — peer 의 Universal User ID(=지갑주소 매핑된 user_id).
  Future<void> startCall({
    required String peerUserId,
    required String peerNickname,
  });

  /// 수신 수락.
  Future<void> acceptIncoming();

  /// 수신 거절 / 발신 취소 / 통화 종료.
  Future<void> hangUp();

  /// 마이크 음소거 토글.
  Future<void> toggleMute();
  bool get isMuted;

  /// 스피커 토글.
  Future<void> toggleSpeaker();
  bool get isSpeaker;
}

/// 통화 상태 — CallService.CallState 와 1:1 매핑.
enum CallSessionState {
  idle,
  outgoing,
  incoming,
  connecting,
  connected,
  ended,
}
