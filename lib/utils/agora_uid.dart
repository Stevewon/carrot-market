import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Agora UID derivation utility
/// =============================
///
/// 정책 (사장님 룰):
///   "퀀타리움 지갑주소 = Universal User ID"
///
/// Agora RTM/RTC 는 UID 가 32bit unsigned int (1 ~ 2^32-1) 이어야 한다.
/// 지갑주소(0x... 42자) 그대로는 못 쓰므로, SHA-256 해시의 앞 4바이트를
/// 32bit unsigned int 로 절단하여 결정론적 UID 를 만든다.
///
/// - 같은 지갑주소 → 항상 같은 UID (서버/클라이언트 양쪽 동일 알고리즘)
/// - UID 0 은 Agora 가 "랜덤 할당" 으로 해석하므로 충돌 시 1로 보정
/// - 충돌 확률: 4.2억분의 1 (SHA-256 분포 가정), 사실상 무시 가능
///
/// 서버측 동일 구현 위치:
///   workers-server/src/utils/agoraToken.ts → walletToAgoraUid()
class AgoraUid {
  AgoraUid._();

  /// 지갑주소 → 32bit Agora UID (deterministic)
  ///
  /// [walletAddress] 는 0x prefix 유무에 무관하게 동작한다.
  /// 대소문자도 무시한다 (lowercase 정규화).
  static int fromWalletAddress(String walletAddress) {
    final normalized = _normalize(walletAddress);
    final bytes = utf8.encode(normalized);
    final digest = sha256.convert(bytes).bytes;

    // 앞 4바이트를 big-endian 32bit unsigned int 로 변환
    final uid = (digest[0] << 24) |
        (digest[1] << 16) |
        (digest[2] << 8) |
        digest[3];

    // unsigned 영역 보장 (Dart int 는 64bit signed 라 음수 안 나오지만 안전망)
    final unsigned = uid & 0xFFFFFFFF;

    // UID 0 은 Agora 가 "서버 랜덤 할당" 으로 해석 → 1로 보정
    return unsigned == 0 ? 1 : unsigned;
  }

  /// 디버깅/로그용: UID 의 hex 표현 (8자)
  static String toHex(int uid) {
    return uid.toRadixString(16).padLeft(8, '0');
  }

  /// 채널명 네임스페이스 강제 (큐알쳇과 충돌 방지)
  ///
  /// Agora App ID 를 큐알쳇과 공유하므로, 채널명에 prefix 를 붙여
  /// Eggplant 트래픽이 큐알쳇 채널과 섞이지 않도록 한다.
  static String channelName(String purpose, String suffix) {
    // purpose: 'chat' | 'call' | ...
    // suffix : roomId / walletAddress 등
    return 'eggplant_${purpose}_$suffix';
  }

  static String _normalize(String walletAddress) {
    var s = walletAddress.trim().toLowerCase();
    if (s.startsWith('0x')) s = s.substring(2);
    return s;
  }
}
