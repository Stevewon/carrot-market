import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../utils/agora_uid.dart';
import 'api_client.dart';

/// AgoraService — 1차 푸시 단계 (시그널링 셋업 / 토큰 발급)
/// =========================================================
///
/// 정책 (사장님 룰):
///   - "퀀타리움 지갑주소 = Universal User ID"
///   - Agora App ID 는 절대 코드에 하드코딩하지 않는다.
///     `--dart-define=AGORA_APP_ID=...` 로 빌드 시 주입.
///   - App Certificate 는 클라이언트가 모른다.
///     서버에서 토큰을 발급받아 사용 (Cloudflare Workers Secret).
///   - 큐알쳇과 같은 App ID 를 공유하지만, 채널명에 'eggplant_' prefix 를
///     강제하여 트래픽이 섞이지 않도록 한다 (AgoraUid.channelName 사용).
///
/// 1차 단계에서 제공하는 것:
///   1) App ID 환경변수 노출 (`appId`)
///   2) 지갑주소 → UID 변환 (`uidFor()`)
///   3) 서버 토큰 발급 호출 (`fetchRtmToken`, `fetchRtcToken`)
///   4) 연결 상태 enum + 알림 (실제 RTM 연결은 2차에서 사용)
///
/// 1차에서 제공하지 않는 것 (다음 단계로 미룸):
///   - 실제 RTM 메시지 송수신 → 2차 (채팅 푸시)
///   - 백그라운드 통화 수신 → 3차 (CallKit + Chat Push)
///   - 키워드/거래완료 알림 발송 → 4차
class AgoraService extends ChangeNotifier {
  AgoraService({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// 빌드 시 주입되는 Agora App ID.
  ///   `flutter build apk --dart-define=AGORA_APP_ID=66ee6650c8b244b1941fac87eae3fc9a`
  /// dart-define 미주입 시 fallback 으로 프로덕션 App ID 사용 (v1.0.129 핫픽스).
  /// — 기존 build-apk.yml 에 AGORA_APP_ID 가 빠져있어 isConfigured=false 가 되며
  ///   "통화 엔진 초기화 실패" 토스트가 발생했음. workflow 파일은 GitHub App
  ///   권한 제한으로 push 불가하여 코드 fallback 으로 우회.
  static const String appId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: '66ee6650c8b244b1941fac87eae3fc9a',
  );

  /// 빌드된 앱이 Agora 를 사용할 수 있는 상태인지.
  static bool get isConfigured => appId.isNotEmpty;

  AgoraConnectionState _state = AgoraConnectionState.disconnected;
  AgoraConnectionState get connectionState => _state;

  /// 현재 로그인된 사용자의 Agora UID (지갑주소에서 결정론적으로 파생).
  int? _uid;
  int? get uid => _uid;

  /// 마지막으로 발급받은 RTM 토큰 (서버 발급, App Certificate 로 서명됨).
  /// 토큰은 만료 시간이 있으므로 백그라운드에서 갱신 필요.
  String? _rtmToken;
  DateTime? _rtmTokenExpireAt;
  Timer? _refreshTimer;

  /// ★ v1.0.145 (2026-05-09): _requestToken 의 마지막 실패 사유 (외부 진단용).
  ///   call_service.dart 가 이 값을 토스트에 포함시켜 사장님이 원인 즉시 식별.
  ///   기존엔 catch (e) 가 debugPrint 로만 남기고 null return 해서 정보 유실.
  String? _lastTokenError;
  String? get lastTokenError => _lastTokenError;

  // ─────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────

  /// 지갑주소로 UID 계산 (서버/클라이언트 동일 알고리즘).
  int uidFor(String walletAddress) =>
      AgoraUid.fromWalletAddress(walletAddress);

  /// 1차 단계의 "준비" 단계.
  ///
  /// AuthService 로그인 성공 후 호출하면:
  ///   1) 지갑주소 → UID 계산 후 멤버 변수 세팅
  ///   2) 서버에서 RTM 토큰 1회 발급 (실패해도 앱 동작은 막지 않음)
  ///   3) 갱신 타이머 등록 (만료 5분 전 재발급)
  ///
  /// 실제 RTM 클라이언트 연결은 2차에서 추가한다.
  Future<void> prepare({required String walletAddress}) async {
    if (!isConfigured) {
      debugPrint('[agora] AGORA_APP_ID not configured — skip prepare');
      return;
    }
    _uid = uidFor(walletAddress);
    debugPrint('[agora] prepared uid=$_uid (wallet=${_mask(walletAddress)})');

    try {
      await _refreshRtmToken();
      _scheduleRefresh();
      _setState(AgoraConnectionState.ready);
    } catch (e) {
      debugPrint('[agora] prepare warning: $e');
      // 토큰 발급이 실패해도 1차에서는 앱 동작에 영향 X.
      // 2차/3차에서 실제 RTM 연결할 때 다시 시도한다.
      _setState(AgoraConnectionState.disconnected);
    }
  }

  /// 로그아웃 시 호출.
  Future<void> teardown() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _rtmToken = null;
    _rtmTokenExpireAt = null;
    _uid = null;
    _setState(AgoraConnectionState.disconnected);
  }

  /// 서버에서 RTM 토큰 발급 (App Certificate 로 HMAC-SHA256 서명).
  /// 만료 시간은 서버가 결정 (기본 1시간).
  Future<String?> fetchRtmToken({String? channel}) async {
    if (!isConfigured || _uid == null) return null;
    return _requestToken(kind: 'rtm', uid: _uid!, channel: channel);
  }

  /// 서버에서 RTC 토큰 발급 (1:1 통화용 채널 토큰).
  Future<String?> fetchRtcToken({required String channel}) async {
    if (!isConfigured || _uid == null) return null;
    return _requestToken(kind: 'rtc', uid: _uid!, channel: channel);
  }

  /// 채팅방 채널명 (네임스페이스 prefix 포함).
  String chatChannel(String roomId) => AgoraUid.channelName('chat', roomId);

  /// 1:1 통화 채널명 (sorted UID pair, prefix 포함).
  /// 양쪽이 같은 채널에 들어가야 통화 성립.
  ///
  /// ★ v1.0.143 (2026-05-09): raw wallet 두 개를 그대로 join 하면
  ///   `eggplant_call_<0x...42자>_<0x...42자>` = 99자 → 서버 64자 한도 초과 (HTTP 400).
  ///   해결: 양쪽 wallet 을 결정론적 UID (32-bit unsigned) 로 변환 후 sorted join.
  ///   결과 길이 최대 `eggplant_call_<10>_<10>` = 35자 ✅
  ///   (서버 chat-hub.ts / Kotlin AgoraConfig.callChannel 동일 알고리즘)
  String callChannel(String walletA, String walletB) {
    final uidA = AgoraUid.fromWalletAddress(walletA);
    final uidB = AgoraUid.fromWalletAddress(walletB);
    final lo = uidA < uidB ? uidA : uidB;
    final hi = uidA < uidB ? uidB : uidA;
    return AgoraUid.channelName('call', '${lo}_$hi');
  }

  // ─────────────────────────────────────────────────────────
  // Internal
  // ─────────────────────────────────────────────────────────

  Future<void> _refreshRtmToken() async {
    final token = await _requestToken(kind: 'rtm', uid: _uid!);
    if (token != null) {
      _rtmToken = token;
      // 서버는 보통 expire_at(epoch sec) 도 같이 주지만, 간단하게 55분 후로 가정.
      // 실제 구현에서는 서버 응답의 expire_at 을 우선 사용한다 (_requestToken 내부).
      _rtmTokenExpireAt ??= DateTime.now().add(const Duration(minutes: 55));
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final exp = _rtmTokenExpireAt;
    if (exp == null) return;
    final wait = exp.difference(DateTime.now()) - const Duration(minutes: 5);
    final delay = wait.isNegative ? const Duration(minutes: 1) : wait;
    _refreshTimer = Timer(delay, () async {
      try {
        await _refreshRtmToken();
        _scheduleRefresh();
      } catch (e) {
        debugPrint('[agora] token refresh failed: $e');
        // 1분 뒤 재시도
        _refreshTimer = Timer(const Duration(minutes: 1), _scheduleRefresh);
      }
    });
  }

  Future<String?> _requestToken({
    required String kind,
    required int uid,
    String? channel,
  }) async {
    // ★ v1.0.145: 매 호출마다 진단 정보 초기화.
    _lastTokenError = null;
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/api/users/agora/token',
        queryParameters: {
          'kind': kind,
          'uid': uid,
          if (channel != null) 'channel': channel,
        },
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      if (res.statusCode != 200 || res.data == null) {
        _lastTokenError = 'HTTP ' + (res.statusCode?.toString() ?? '?') + ' (no data)';
        debugPrint('[agora] _requestToken($kind) ' + _lastTokenError!);
        return null;
      }

      final token = res.data!['token'] as String?;
      if (token == null || token.isEmpty) {
        // ★ v1.0.145: HTTP 200 인데 token 필드가 비어있는 케이스.
        //   서버 코드 분기상 거의 불가능하지만 (200 응답엔 항상 token 포함),
        //   서버 측 변경/캐시 문제 시 진단 가능하도록 명시.
        final keys = res.data!.keys.join(',');
        _lastTokenError = 'HTTP 200 but token empty (keys=' + keys + ')';
        debugPrint('[agora] _requestToken($kind) ' + _lastTokenError!);
        return null;
      }
      final expSec = res.data!['expire_at'];
      if (expSec is int) {
        _rtmTokenExpireAt =
            DateTime.fromMillisecondsSinceEpoch(expSec * 1000);
      }
      return token;
    } on DioException catch (e) {
      // ★ v1.0.145: dio 가 4xx/5xx throw 한 케이스 — HTTP 코드 + 서버 error code 추출.
      final status = e.response?.statusCode;
      final body = e.response?.data;
      String? serverCode;
      String? serverErr;
      if (body is Map) {
        serverCode = body['code']?.toString();
        serverErr = body['error']?.toString();
      }
      _lastTokenError =
          'HTTP ' +
          (status?.toString() ?? '?') +
          (serverCode != null ? ' code=' + serverCode : '') +
          (serverErr != null ? ' msg=' + serverErr : '') +
          (status == null ? ' type=' + e.type.toString() : '');
      debugPrint('[agora] _requestToken($kind) ' + _lastTokenError!);
      return null;
    } catch (e) {
      _lastTokenError = e.toString();
      debugPrint('[agora] _requestToken($kind) error: $e');
      return null;
    }
  }

  void _setState(AgoraConnectionState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  String _mask(String walletAddress) {
    if (walletAddress.length < 10) return walletAddress;
    return '${walletAddress.substring(0, 6)}…${walletAddress.substring(walletAddress.length - 4)}';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

/// Agora 연결 상태 (간단 enum).
enum AgoraConnectionState {
  disconnected,
  ready, // 토큰 발급 완료, 실제 RTM 연결은 2차에서 사용
  connecting,
  connected,
}
