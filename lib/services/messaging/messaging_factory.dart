/// 메시징/통화 어댑터 팩토리.
///
/// dart-define 으로 빌드 시 어댑터를 한 줄로 교체할 수 있다.
///
///   flutter build apk --dart-define=MESSAGING_ADAPTER=qrchat
///
/// 기본값은 `eggplant_builtin` (가지 자체 WebSocket 구현).
/// 'qrchat' 으로 지정해도 SDK 가 미연결이면 빌트인으로 자동 폴백.
library;

import '../auth_service.dart';
import '../call_service.dart';
import '../chat_service.dart';
import 'eggplant_builtin_adapter.dart';
import 'messaging_adapter.dart';
import 'qrchat_adapter.dart';

class MessagingFactory {
  /// dart-define 으로 받은 기본 어댑터 코드.
  ///   --dart-define=MESSAGING_ADAPTER=qrchat
  ///   --dart-define=MESSAGING_ADAPTER=eggplant_builtin
  static const String defaultAdapterCode = String.fromEnvironment(
    'MESSAGING_ADAPTER',
    defaultValue: 'eggplant_builtin',
  );

  /// QRChat SDK 가 미연결 상태일 때 빌트인으로 자동 폴백할지.
  /// 운영 빌드에서는 false 로 두는 게 SDK 미사용 회귀를 방지.
  static const bool fallbackToBuiltin = bool.fromEnvironment(
    'MESSAGING_FALLBACK_BUILTIN',
    defaultValue: true,
  );

  /// 메시징 어댑터를 생성한다.
  ///
  /// QRChat 어댑터를 요청했지만 미연결이면 [fallbackToBuiltin] 에 따라
  /// 자동으로 [EggplantBuiltinMessagingAdapter] 를 돌려준다.
  ///
  /// [auth] 는 SSO Identity 구성에 사용되며 (현재 빌트인은 ChatService 만 받지만,
  /// QRChat SDK 가 들어오면 init() 에서 auth.user.walletAddress 를 사용한다.)
  static MessagingAdapter createMessaging(
    AuthService auth,
    ChatService chat, {
    MessagingAdapterKind? kind,
  }) {
    final k = kind ?? MessagingAdapterKindCode.fromCode(defaultAdapterCode);
    switch (k) {
      case MessagingAdapterKind.qrchatSdk:
        try {
          return QRChatMessagingAdapter();
        } catch (_) {
          if (!fallbackToBuiltin) rethrow;
          return EggplantBuiltinMessagingAdapter(chat);
        }
      case MessagingAdapterKind.eggplantBuiltin:
        return EggplantBuiltinMessagingAdapter(chat);
    }
  }

  /// 통화 어댑터를 생성한다 (메시징 어댑터와 짝을 맞춰서).
  static CallingAdapter createCalling(
    AuthService auth,
    ChatService chat,
    CallService call, {
    MessagingAdapterKind? kind,
  }) {
    final k = kind ?? MessagingAdapterKindCode.fromCode(defaultAdapterCode);
    switch (k) {
      case MessagingAdapterKind.qrchatSdk:
        try {
          return QRChatCallingAdapter();
        } catch (_) {
          if (!fallbackToBuiltin) rethrow;
          return EggplantBuiltinCallingAdapter(call);
        }
      case MessagingAdapterKind.eggplantBuiltin:
        return EggplantBuiltinCallingAdapter(call);
    }
  }

  /// 로그인 직후 호출 — 어댑터에 SSO 정체성을 주입.
  /// QRChat 어댑터일 때만 의미 있고, 빌트인은 init 이 no-op 라 안전하다.
  static Future<void> initWithUser(
    MessagingAdapter messaging,
    CallingAdapter calling,
    AuthService auth,
  ) async {
    final u = auth.user;
    if (u == null) return;
    final wallet = u.walletAddress;
    if (wallet == null || wallet.isEmpty) return;
    final identity = MessagingIdentity(
      walletAddress: wallet,
      nickname: u.nickname,
      authToken: auth.token,
    );
    try {
      await messaging.init(identity);
    } catch (_) {
      // 빌트인은 init 이 stub 일 수 있음. 무시.
    }
    try {
      await calling.init(identity);
    } catch (_) {}
  }
}
