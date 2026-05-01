/// 본인인증 사업자 추상화 인터페이스.
///
/// 정책:
///   1) 휴대폰 번호 평문은 절대 다루지 않는다. 사업자 SDK 가 내부에서 받고,
///      앱은 SDK 가 돌려준 CI 토큰만 서버로 올린다.
///   2) 어댑터별 구현은 [PassIdentityProvider] / [SmsIdentityProvider] /
///      [KisaIdentityProvider] / [DummyIdentityProvider] 처럼 분리한다.
///   3) 서버 `/api/users/me/verify/identity` 는 [IdentityVerifyResult] 의
///      provider/ciToken/nonce/txId/phoneHash 필드를 그대로 받는다.
///
/// 신규 사업자 추가 시:
///   - 이 파일에 새 [IdentityProvider] 구현 클래스를 만들고
///   - [IdentityProviderRegistry.resolve] 에 등록하면 끝.
library;

/// 본인인증 시도 결과 — 서버로 그대로 올리는 페이로드 형태.
class IdentityVerifyResult {
  /// 'pass' / 'sms' / 'kisa' / 'dummy'
  final String provider;

  /// 사업자가 발급한 CI(Connecting Information) 토큰. 서버에서 SHA-256 해시.
  final String ciToken;

  /// (옵션) 재전송/리플레이 방지용 nonce. PASS/KISA 는 필수.
  final String? nonce;

  /// (옵션) 사업자 트랜잭션 ID. 감사 로그용.
  final String? txId;

  /// (옵션) 클라이언트가 미리 SHA-256 해시한 전화번호.
  /// 평문은 절대 담지 말 것 (반드시 64자 hex).
  final String? phoneHash;

  /// (옵션) 사업자가 알려준 사용자 표시명. 로컬 분석용.
  final String? displayName;

  const IdentityVerifyResult({
    required this.provider,
    required this.ciToken,
    this.nonce,
    this.txId,
    this.phoneHash,
    this.displayName,
  });

  /// 서버 `/api/users/me/verify/identity` 가 그대로 받는 형태.
  Map<String, dynamic> toServerPayload() {
    return {
      'provider': provider,
      'ci_token': ciToken,
      if (nonce != null && nonce!.isNotEmpty) 'nonce': nonce,
      if (txId != null && txId!.isNotEmpty) 'tx_id': txId,
      if (phoneHash != null && phoneHash!.isNotEmpty) 'phone_hash': phoneHash,
    };
  }
}

/// 본인인증 도중 사용자가 취소했을 때 던지는 예외.
class IdentityVerifyCancelled implements Exception {
  final String? message;
  IdentityVerifyCancelled([this.message]);
  @override
  String toString() => 'IdentityVerifyCancelled(${message ?? "user cancelled"})';
}

/// 본인인증 사업자 어댑터 인터페이스.
///
/// 실제 SDK 패키지가 도입되면 [verify] 안에서 SDK 의 native 메서드를 호출하고
/// 결과를 [IdentityVerifyResult] 로 감싸서 돌려주면 된다.
abstract class IdentityProvider {
  /// 사업자 코드. 'pass' / 'sms' / 'kisa' / 'dummy'.
  String get code;

  /// 사용자가 사업자 SDK 화면을 통해 본인인증을 진행한다.
  ///
  /// 성공 시 서버로 보낼 [IdentityVerifyResult] 를 반환한다.
  /// 사용자가 취소하면 [IdentityVerifyCancelled] 를 throw 한다.
  Future<IdentityVerifyResult> verify();
}

/// 더미(데모/시연) 사업자. SDK 패키지가 아직 연결되지 않은 상태에서
/// UI 흐름을 검증할 때 사용. 운영 환경에서는 서버가 ALLOW_DUMMY_VERIFY!=1
/// 으로 거부한다.
class DummyIdentityProvider implements IdentityProvider {
  @override
  String get code => 'dummy';

  @override
  Future<IdentityVerifyResult> verify() async {
    // 약간의 딜레이로 SDK 화면 흉내.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return IdentityVerifyResult(
      provider: code,
      ciToken: 'dummy_ci_${DateTime.now().millisecondsSinceEpoch}',
      txId: 'dummy_tx_${DateTime.now().microsecondsSinceEpoch}',
    );
  }
}

/// PASS(이통3사 본인확인) 어댑터 스켈레톤.
///
/// 실제 SDK(예: pass_dsop_sdk, kt_pass_flutter, pass_certi 등)가 결정되면
/// [verify] 안에서 SDK 의 startVerification(...) 같은 native 메서드를
/// 호출해 (ciToken, nonce, txId) 를 받아오면 된다.
///
/// 현재는 SDK 미연결 상태이므로 [UnsupportedError] 를 던지며,
/// [IdentityProviderRegistry] 가 dummy 로 자동 폴백한다.
class PassIdentityProvider implements IdentityProvider {
  @override
  String get code => 'pass';

  @override
  Future<IdentityVerifyResult> verify() async {
    // TODO(pass-sdk): pass_dsop_sdk 등 실제 패키지 연결.
    //   final sdk = PassSdk();
    //   final r = await sdk.startVerification(
    //     siteCode: 'XXXX',
    //     popupTitle: '가지마켓 본인인증',
    //   );
    //   return IdentityVerifyResult(
    //     provider: 'pass',
    //     ciToken: r.ci,
    //     nonce: r.nonce,
    //     txId: r.txId,
    //   );
    throw UnsupportedError(
      'PASS SDK 가 아직 연결되지 않았어요. dummy 로 폴백합니다.',
    );
  }
}

/// SMS 인증 어댑터 스켈레톤.
class SmsIdentityProvider implements IdentityProvider {
  @override
  String get code => 'sms';

  @override
  Future<IdentityVerifyResult> verify() async {
    throw UnsupportedError('SMS 인증 SDK 가 아직 연결되지 않았어요.');
  }
}

/// KISA(NICE/KCB) 본인확인 어댑터 스켈레톤.
class KisaIdentityProvider implements IdentityProvider {
  @override
  String get code => 'kisa';

  @override
  Future<IdentityVerifyResult> verify() async {
    throw UnsupportedError('KISA 본인확인 SDK 가 아직 연결되지 않았어요.');
  }
}

/// 사업자 코드 → 어댑터 인스턴스 매핑.
///
/// 운영 배포 시 [defaultProvider] 를 'pass' 로 두고, 그 코드의 SDK 가
/// 연결되지 않은 빌드(개발/시연)에서는 dummy 로 자동 폴백한다.
class IdentityProviderRegistry {
  /// 기본 사업자. dart-define 으로 빌드 시 오버라이드 가능.
  ///   flutter build apk --dart-define=IDENTITY_PROVIDER=pass
  static const String defaultProvider = String.fromEnvironment(
    'IDENTITY_PROVIDER',
    defaultValue: 'dummy',
  );

  /// SDK 가 안 붙어 있으면 자동으로 dummy 로 폴백할지.
  /// (개발 빌드 편의 — 운영에서는 false 로 두는 게 안전)
  static const bool fallbackToDummy = bool.fromEnvironment(
    'IDENTITY_FALLBACK_DUMMY',
    defaultValue: true,
  );

  /// [code] 에 해당하는 [IdentityProvider] 를 돌려준다.
  /// 코드를 모르거나 SDK 미연결이면 [fallbackToDummy] 에 따라 dummy 폴백.
  static IdentityProvider resolve([String? code]) {
    final c = (code ?? defaultProvider).toLowerCase();
    switch (c) {
      case 'pass':
        return PassIdentityProvider();
      case 'sms':
        return SmsIdentityProvider();
      case 'kisa':
        return KisaIdentityProvider();
      case 'dummy':
        return DummyIdentityProvider();
      default:
        if (fallbackToDummy) return DummyIdentityProvider();
        throw ArgumentError('Unknown identity provider: $code');
    }
  }

  /// SDK 미연결 사업자도 자동으로 dummy 로 폴백해서 무조건 결과를 돌려준다.
  /// profile_verify_screen 에서 호출하기 좋은 헬퍼.
  static Future<IdentityVerifyResult> verifyOrFallback([String? code]) async {
    final primary = resolve(code);
    try {
      return await primary.verify();
    } on UnsupportedError {
      if (!fallbackToDummy) rethrow;
      // SDK 미연결 → dummy 로 폴백.
      return DummyIdentityProvider().verify();
    }
  }
}
