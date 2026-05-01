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

/// PASS(이통3사 본인확인) 어댑터.
///
/// SDK 연결 옵션 두 가지:
///
/// [A] Pub.dev 패키지 (예: pass_dsop_sdk, kg_inicis_pass) 가 있는 경우
///     → 아래 TODO(pass-sdk:flutter) 블록을 그대로 채우면 끝.
///
/// [B] 통신사·사업자가 native(android/ios) SDK 만 제공하는 경우
///     → [PassNativeBridge] 의 MethodChannel 로 호출.
///       Android: MainActivity.kt 에 PassPlugin 을 등록하고
///                "eggplant.pass/verify" 채널에서 startVerification 처리.
///       iOS: AppDelegate.swift 에서 같은 채널 등록.
///
/// 어떤 경로든 결과는 [IdentityVerifyResult] 한 형태로 통일되어
/// [AuthService.verifyIdentity] 가 그대로 서버로 올린다.
///
/// SDK 미연결 빌드(개발/시연)에서는 [UnsupportedError] 를 던지고
/// [IdentityProviderRegistry] 가 dummy 로 자동 폴백한다.
class PassIdentityProvider implements IdentityProvider {
  /// (옵션) PASS 사업자가 발급한 사이트 코드. dart-define 으로 주입.
  ///   flutter build apk --dart-define=PASS_SITE_CODE=XXXX
  static const String siteCode = String.fromEnvironment(
    'PASS_SITE_CODE',
    defaultValue: '',
  );

  /// (옵션) 사업자가 발급한 사이트 패스워드(서버키). 가급적 백엔드에 두고
  /// 클라이언트에는 두지 말 것 — placeholder 일 뿐.
  static const String sitePw = String.fromEnvironment(
    'PASS_SITE_PW',
    defaultValue: '',
  );

  /// 네이티브 브리지(MethodChannel) 사용 여부. 기본값은 false (pub 패키지 우선).
  ///   --dart-define=PASS_USE_NATIVE_BRIDGE=true
  static const bool useNativeBridge = bool.fromEnvironment(
    'PASS_USE_NATIVE_BRIDGE',
    defaultValue: false,
  );

  @override
  String get code => 'pass';

  @override
  Future<IdentityVerifyResult> verify() async {
    if (useNativeBridge) {
      // ── [B] Native MethodChannel 경로 ───────────────────────────
      try {
        return await PassNativeBridge.verify(
          siteCode: siteCode,
          popupTitle: '가지마켓 본인인증',
        );
      } catch (e) {
        // MissingPluginException → 네이티브 등록 안 됨 → 미연결로 처리.
        throw UnsupportedError(
          'PASS native bridge 가 등록되지 않았어요. '
          'Android/iOS 의 PassPlugin 을 먼저 연결해주세요. ($e)',
        );
      }
    }

    // ── [A] Pub.dev 패키지 경로 ──────────────────────────────────
    // TODO(pass-sdk:flutter):
    //   pubspec.yaml 의 PASS SDK 후보 중 한 줄 주석 해제 후 import 하고
    //   아래 의사코드를 실제 SDK 메서드 호출로 교체.
    //
    //   import 'package:pass_dsop_sdk/pass_dsop_sdk.dart';
    //
    //   if (siteCode.isEmpty) {
    //     throw UnsupportedError('PASS_SITE_CODE 가 설정되지 않았어요');
    //   }
    //   final sdk = PassDsopSdk();
    //   final r = await sdk.startVerification(
    //     siteCode: siteCode,
    //     popupTitle: '가지마켓 본인인증',
    //     // 사업자가 요구하면 returnUrl, schemeUrl 등 추가
    //   );
    //   if (r.cancelled) throw IdentityVerifyCancelled();
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

/// PASS 네이티브 SDK 브리지 — Android/iOS 의 PassPlugin 과 통신.
///
/// 사용 채널: `eggplant.pass/verify`
/// 메서드:    `startVerification`
/// 파라미터:  { siteCode: string, popupTitle: string }
/// 반환:      { ci: string, nonce: string?, txId: string?, phoneHash: string?,
///             cancelled: bool? }
///
/// 네이티브 측에서 [cancelled]=true 를 돌려주면 [IdentityVerifyCancelled].
class PassNativeBridge {
  // 채널 이름은 네이티브 측 Plugin 등록 시 동일하게 써야 함.
  static const _channelName = 'eggplant.pass/verify';

  /// MethodChannel 로 PASS 네이티브 SDK 를 호출.
  /// Flutter 만 있고 네이티브 미등록이면 MissingPluginException 이 throw 되어
  /// [PassIdentityProvider.verify] 가 UnsupportedError 로 변환한다.
  static Future<IdentityVerifyResult> verify({
    required String siteCode,
    required String popupTitle,
  }) async {
    // 동적 import 회피 — 외부 라이브러리 없이 dart:ui 의 PlatformDispatcher
    // 만으로는 채널 호출이 어려우므로, 실제 통합 시점에 아래 한 줄을 살림.
    //
    //   import 'package:flutter/services.dart';
    //   const ch = MethodChannel(_channelName);
    //   final dynamic res = await ch.invokeMethod('startVerification', {
    //     'siteCode': siteCode,
    //     'popupTitle': popupTitle,
    //   });
    //
    // 현재는 네이티브 미등록 상태이므로 명시적으로 unsupported.
    throw UnsupportedError(
      'PASS native bridge 호출부($_channelName)가 활성화되지 않았어요. '
      'pubspec.yaml 가이드를 따라 SDK 를 먼저 연결하세요.',
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
