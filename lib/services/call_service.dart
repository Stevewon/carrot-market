// ============================================================
// call_service.dart — 1:1 음성통화 (Agora RTC SDK 전면 전환)
// ============================================================
// v1.0.125 (2026-05-07) — 사장님 결정: flutter_webrtc 폐기, Agora 사용.
//
// 정책:
//   1) 시그널링: ChatService WebSocket (call_invite/response/end/cancel)
//   2) 미디어: Agora RTC Engine (joinChannel/leaveChannel)
//      → STUN/TURN 자체 운영 불필요. Agora SD-RTN 가 NAT/방화벽 통과.
//   3) 채널명: AgoraService.callChannel(myWallet, peerWallet) — 양쪽 동일.
//   4) 토큰: AgoraService.fetchRtcToken(channel) — 서버 HMAC-SHA256 v006.
//   5) UID: AgoraUid.fromWalletAddress (양쪽 결정론적, 32bit unsigned).
//
// 기능 보강 (12개 항목 모두):
//   1) 30초 발신 타임아웃 자동 취소 + 부재중 처리
//   2) 받은 즉시 ringback 정지 (call_response accepted=true)
//   3) CallKit accept → 앱 부팅 후 acceptCall 라우팅 (PushService 가 처리)
//   4) Foreground Service 로 백그라운드 음성 보장 (main.dart 에서 init)
//   5) Agora connectionStateChanged 콜백 → failed/disconnected 5초 retry
//   6) 마이크 권한 거부 시 reject + 사용자 안내
//   7) 동시 발신 race: userId 작은 쪽 우선
//   8) 부재중 D1 기록 (서버측 처리)
//   9) 통화 중 다른 앱 알림 — OS 가 처리 (변경 X)
//  10) 스피커폰/뮤트 — Agora API 사용
//  11) 통화 끝난 후 즉시 재발신 가능 (clearEnded 3초 지연 제거)
//  12) NAT/방화벽 — Agora SD-RTN 자동 라우팅
// ============================================================

import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

// ★ v1.0.128 (2026-05-08): flutter_foreground_task 직접 import 제거.
//   8.10.4 API 시그니처 불일치로 빌드 실패. AndroidManifest 의 service 선언 +
//   FOREGROUND_SERVICE_MICROPHONE 권한 + Agora SDK 자체 audio focus 처리만으로
//   백그라운드 마이크 유지 가능 (Android 14+ 검증됨).
//   필요 시 별도 native MethodChannel 로 ContextCompat.startForegroundService
//   호출하는 안 검토.

import '../utils/agora_uid.dart';
import 'agora_service.dart';
import 'auth_service.dart';
import 'chat_service.dart';

enum CallState {
  idle,       // No call
  outgoing,   // I'm calling someone, waiting for answer
  incoming,   // Someone is calling me, I haven't answered yet
  connecting, // Accepted, Agora joinChannel in progress
  connected,  // Call is active (audio flowing)
  ended,      // Just ended - show brief "ended" state
}

/// Manages anonymous 1:1 voice calls via Agora RTC.
/// - Signaling: ChatService WebSocket (call_invite/response/end/cancel).
/// - Media: Agora SD-RTN (no self-hosted STUN/TURN).
/// - No call history is stored anywhere (server logs missed calls only).
class CallService extends ChangeNotifier {
  final AuthService auth;
  final ChatService chat;
  final AgoraService agora;

  final List<StreamSubscription> _subs = [];

  CallService({
    required this.auth,
    required this.chat,
    required this.agora,
  }) {
    _attachListeners();
  }

  // --- State ---
  CallState _state = CallState.idle;
  CallState get state => _state;

  String? _activeCallId;
  String? get activeCallId => _activeCallId;

  String? _peerUserId;
  String? get peerUserId => _peerUserId;

  String? _peerNickname;
  String? get peerNickname => _peerNickname;

  String? _peerWalletAddress;
  String? get peerWalletAddress => _peerWalletAddress;

  bool _isCaller = false;
  bool get isCaller => _isCaller;

  DateTime? _connectedAt;
  DateTime? get connectedAt => _connectedAt;

  bool _muted = false;
  bool get muted => _muted;

  bool _speakerOn = true;
  bool get speakerOn => _speakerOn;

  String? _lastError;
  String? get lastError => _lastError;

  /// 30초 발신 타임아웃 / 5초 ICE 재연결 타이머 등을 관리.
  Timer? _outgoingTimeoutTimer;
  Timer? _reconnectTimer;

  // --- Ringtones ---
  AudioPlayer? _ringbackPlayer;
  bool _ringbackPlaying = false;
  bool _osRingtonePlaying = false;

  // --- Agora Engine ---
  RtcEngine? _engine;
  bool _engineInitialized = false;
  String? _activeChannel;

  /// ★ v1.0.144 (2026-05-09): _joinAgoraChannel 실패 분기별 진단 사유.
  ///   acceptCall 의 토스트가 이 값을 함께 노출 → 사장님 보고 시 원인 즉시 식별.
  String? _lastJoinFailReason;

  /// 발신 타임아웃 (초). 응답 없으면 자동 취소 + 부재중.
  static const int _outgoingTimeoutSec = 30;

  /// Attach WebSocket signaling listeners.
  void _attachListeners() {
    _subs.add(chat.on('call_incoming', (data) {
      // Race condition (양쪽이 동시에 발신): userId 작은 쪽이 우선권.
      // 내가 outgoing 중인데 같은 상대에게서 incoming 이 오면, peer userId 비교.
      if (_state == CallState.outgoing && _peerUserId == data['from_user_id']) {
        final myId = auth.user?.id ?? '';
        final peerId = data['from_user_id']?.toString() ?? '';
        if (myId.compareTo(peerId) > 0) {
          // 내가 큰 쪽 → 내 발신 취소하고 상대 incoming 받기.
          chat.emit('call_end', {
            'to_user_id': _peerUserId,
            'call_id': _activeCallId,
          });
          _stopRingback();
          _outgoingTimeoutTimer?.cancel();
          _activeCallId = data['call_id']?.toString();
          _peerNickname = data['caller_nickname']?.toString() ?? '익명';
          _isCaller = false;
          _state = CallState.incoming;
          notifyListeners();
          // ignore: discarded_futures
          _startOsRingtone();
          return;
        }
        // 내가 작은 쪽 → 상대 invite 무시 (상대가 내 invite 를 받아야 함).
        return;
      }
      // ★ P0-#1 (v1.0.127): ended 상태도 idle 로 취급.
      //   직전 통화 종료 후 800ms 동안 ended 상태로 머무는 동안 새 incoming 이
      //   오면 자동 거절되던 버그 수정. ended 상태 자동 정리 후 incoming 진행.
      if (_state != CallState.idle && _state != CallState.ended) {
        // ★ v1.0.139 (2026-05-08): 동일 call_id 재전송 silent skip.
        //   v1.0.137 에서 도입한 bootstrapIncomingFromPush 가 main isolate
        //   에서 _state=CallState.incoming 으로 미리 진입시킨 뒤,
        //   ChatService.connect() 가 끝나면 서버가 backlog 로 같은 call_id 의
        //   call_incoming 이벤트를 재전송함. 이전 코드는 "이미 incoming 이니
        //   busy" 라고 오판해서 자기 자신의 통화에 auto-reject 를 발사 →
        //   발신자에게 'accepted=false' 도달 → 사장님이 보신 "수락 누르면
        //   상대방이 통화를 거절했어요" 증상.
        //   해결: 동일 call_id (또는 동일 from_user_id) 재전송이면 무시.
        final incomingCallId = data['call_id']?.toString() ?? '';
        final incomingFromUserId = data['from_user_id']?.toString() ?? '';
        if (incomingCallId.isNotEmpty && incomingCallId == _activeCallId) {
          debugPrint('[call] call_incoming duplicate (call_id=$incomingCallId) — skip');
          // 부트스트랩 시점에 데이터가 비어있을 수 있으니 보강.
          if (_peerWalletAddress == null || _peerWalletAddress!.isEmpty) {
            _peerWalletAddress = data['caller_wallet']?.toString();
          }
          if (_peerNickname == null || _peerNickname == '익명') {
            final n = data['caller_nickname']?.toString();
            if (n != null && n.isNotEmpty) _peerNickname = n;
          }
          return;
        }
        // 같은 발신자가 다시 invite 한 케이스도 부트스트랩 race 일 수 있음.
        if (_state == CallState.incoming &&
            incomingFromUserId.isNotEmpty &&
            incomingFromUserId == _peerUserId) {
          debugPrint('[call] call_incoming same peer (from=$incomingFromUserId) — refresh data, skip reject');
          _activeCallId = incomingCallId.isNotEmpty ? incomingCallId : _activeCallId;
          _peerWalletAddress = data['caller_wallet']?.toString() ?? _peerWalletAddress;
          final n = data['caller_nickname']?.toString();
          if (n != null && n.isNotEmpty) _peerNickname = n;
          notifyListeners();
          return;
        }
        // 진짜 다른 통화가 들어왔을 때만 busy auto-reject 발사.
        chat.emit('call_response', {
          'to_user_id': data['from_user_id'],
          'call_id': data['call_id'],
          'accepted': false,
        });
        return;
      }
      // ended → 즉시 정리하고 새 incoming 받기.
      if (_state == CallState.ended) {
        _state = CallState.idle;
        _activeCallId = null;
        _peerUserId = null;
        _peerNickname = null;
        _peerWalletAddress = null;
        _isCaller = false;
        _connectedAt = null;
      }
      _activeCallId = data['call_id']?.toString();
      _peerUserId = data['from_user_id']?.toString();
      _peerNickname = data['caller_nickname']?.toString() ?? '익명';
      _peerWalletAddress = data['caller_wallet']?.toString();
      _isCaller = false;
      _state = CallState.incoming;
      notifyListeners();
      // ignore: discarded_futures
      _startOsRingtone();
    }));

    _subs.add(chat.on('call_response', (data) async {
      if (data['call_id'] != _activeCallId) return;
      final accepted = data['accepted'] == true;
      if (!accepted) {
        _setError('상대방이 통화를 거절했어요');
        await _teardown(stateAfter: CallState.ended);
        return;
      }
      if (_isCaller) {
        // 상대 수락 → 발신음 정지 + Agora 채널 join.
        await _stopRingback();
        _outgoingTimeoutTimer?.cancel();
        _state = CallState.connecting;
        notifyListeners();
        final joined = await _joinAgoraChannel();
        if (joined) {
          // ★ P0-#3: 백그라운드 음성 보장.
          await _startCallForegroundService();
        }
      }
    }));

    // ★ v1.0.124 핫픽스: 발신자가 끊었을 때 수신자 단말 UI 강제 종료.
    _subs.add(chat.on('call_cancel', (data) async {
      final cid = data['call_id']?.toString();
      if (cid == null) return;
      try {
        await FlutterCallkitIncoming.endCall(cid);
      } catch (_) {}
      if (cid == _activeCallId) {
        await _teardown(stateAfter: CallState.ended);
      }
    }));

    _subs.add(chat.on('call_end', (data) async {
      if (data['call_id'] != _activeCallId) return;
      await _teardown(stateAfter: CallState.ended);
    }));

    _subs.add(chat.on('call_failed', (data) async {
      if (data['call_id'] != _activeCallId) return;
      final reason = data['message']?.toString() ?? '통화 실패';
      _setError(reason);
      await _teardown(stateAfter: CallState.ended);
    }));
  }

  // --- Public API -------------------------------------------------------

  /// Start a call to the given peer user.
  Future<void> startCall({
    required String peerUserId,
    required String peerNickname,
    required String peerWalletAddress,
  }) async {
    // ★ v1.0.126: stuck 상태 자가 회복.
    //   _state 가 outgoing/connecting/connected 로 stuck 된 경우, 신뢰할 수
    //   있는 진행 신호(_connectedAt 또는 최근 ringback) 가 없으면 강제 리셋.
    //   사장님 케이스: 직전 통화가 비정상 종료되어 _state == ended/connecting
    //   이 남아있고, 사용자가 다시 통화 버튼 누르면 "이미 통화 중이에요" 토스트.
    if (_state != CallState.idle && _state != CallState.ended) {
      // connected 상태에서 진짜 음성이 흐르고 있다면 _connectedAt 이 있을 것.
      final isReallyConnected = _state == CallState.connected &&
          _connectedAt != null &&
          DateTime.now().difference(_connectedAt!).inSeconds < 3600;
      // outgoing/connecting 인데 ringback 도 안 울리고 timer 도 없으면 stuck.
      final isStuckOutgoing = (_state == CallState.outgoing ||
              _state == CallState.connecting) &&
          !_ringbackPlaying &&
          _outgoingTimeoutTimer == null;
      if (isReallyConnected) {
        // 진짜로 통화 중 — 사용자 안내 후 차단.
        switch (_state) {
          case CallState.connected:
            throw '이미 통화 중이에요';
          case CallState.connecting:
            throw '연결 중이에요';
          case CallState.outgoing:
            throw '응답을 기다리고 있어요';
          case CallState.incoming:
            throw '걸려온 통화가 있어요';
          default:
            throw '이미 통화 중이에요';
        }
      }
      // stuck 의심 — 강제 정리 후 새 통화 진행.
      debugPrint('[call] stuck state detected (state=$_state, '
          'ringback=$_ringbackPlaying, timer=${_outgoingTimeoutTimer != null}). '
          'force-resetting before new call.');
      await _forceReset();
      // ignore: unused_local_variable
      final _ = isStuckOutgoing; // silence linter
    }
    // ended 상태 리셋 (즉시 재발신 허용)
    if (_state == CallState.ended) {
      _state = CallState.idle;
      _activeCallId = null;
    }
    final ok = await _ensureMicPermission();
    if (!ok) {
      throw '마이크 권한이 필요해요';
    }
    // ★ P1-#9 (v1.0.127): WebSocket 1회 재시도.
    //   첫 연결 실패 시 즉시 throw 하던 동작 → 4G 약전계에서 통화 시도 자체가
    //   불가능. 1초 대기 후 한 번 더 connect + 대기.
    chat.connect();
    if (!chat.connected) {
      await _waitForSocket();
    }
    if (!chat.connected) {
      debugPrint('[call] WebSocket first attempt failed, retrying...');
      await Future.delayed(const Duration(seconds: 1));
      chat.connect();
      await _waitForSocket(timeoutMs: 4000);
    }
    if (!chat.connected) {
      throw '서버에 연결되지 않았어요';
    }

    _activeCallId = const Uuid().v4();
    _peerUserId = peerUserId;
    _peerNickname = peerNickname;
    _peerWalletAddress = peerWalletAddress;
    _isCaller = true;
    _state = CallState.outgoing;
    _lastError = null;
    notifyListeners();

    // Agora 엔진은 미리 초기화 (joinChannel 은 상대 수락 시).
    // ★ v1.0.131: 엔진 초기화 실패 시에도 통화 invite 는 발사.
    //   상대가 받으면 _joinAgoraChannel 시점에 다시 한 번 _ensureEngine() 시도됨.
    //   첫 시도 실패 = 일시적 OEM/하드웨어 이슈일 수 있으니 토스트 띄우지 않고
    //   진행. 진짜로 채널 join 까지 실패하면 그때 사용자에게 알림.
    try {
      await _ensureEngine();
    } catch (e) {
      debugPrint('[call] startCall: engine pre-init failed (will retry on join): $e');
      // throw 하지 않음 — invite 진행, 채널 join 시점에 재시도.
    }

    chat.emit('call_invite', {
      'to_user_id': peerUserId,
      'call_id': _activeCallId,
      'caller_nickname': auth.user?.nickname ?? '익명',
      'caller_wallet': auth.user?.walletAddress ?? '',
    });
    await _startRingback();

    // 30초 안에 응답 없으면 자동 취소.
    _outgoingTimeoutTimer?.cancel();
    _outgoingTimeoutTimer = Timer(const Duration(seconds: _outgoingTimeoutSec), () async {
      if (_state == CallState.outgoing) {
        _setError('상대방이 받지 않았어요');
        // 서버에 call_end 보내서 수신측 CallKit UI 도 닫음.
        chat.emit('call_end', {
          'to_user_id': _peerUserId,
          'call_id': _activeCallId,
        });
        await _teardown(stateAfter: CallState.ended);
      }
    });
  }

  /// ★ v1.0.137 (2026-05-08): CallKit "받기" 푸시 경로 부트스트랩.
  ///
  /// 백그라운드/앱 종료 상태에서 푸시로 깨워진 경우, ChatService(WebSocket)
  /// 가 아직 연결 안 돼 chat.on('call_incoming') 이벤트를 못 받았으므로
  /// _activeCallId/_peerUserId/_peerWalletAddress 가 비어 있다.
  /// 이 상태에서 acceptCall() 을 호출하면 line 358 가드에 막혀 silent return →
  /// 사장님이 보신 "수락 누르면 메인 화면으로 가버림" 증상.
  ///
  /// 푸시 data (call_id/from_user_id/caller_nickname/caller_wallet) 만으로
  /// CallService 의 incoming 상태를 직접 부트스트랩한다. WS 가 아직 끊겨 있어도
  /// state 를 CallState.incoming 으로 강제 진입시키고, 이후 acceptCall 이
  /// 호출되면 _waitForSocket 으로 재연결 후 join 진행.
  void bootstrapIncomingFromPush({
    required String callId,
    required String peerUserId,
    required String peerNickname,
    required String peerWalletAddress,
  }) {
    if (callId.isEmpty || peerUserId.isEmpty) {
      debugPrint('[call] bootstrapIncomingFromPush: missing callId/peerUserId — skip');
      return;
    }
    // 이미 동일 call_id 로 incoming 상태면 중복 진입 방지.
    if (_state == CallState.incoming && _activeCallId == callId) {
      debugPrint('[call] bootstrapIncomingFromPush: already incoming for $callId — skip');
      return;
    }
    // 이미 connecting/connected 면 별도 진입 금지 (race 보호).
    if (_state == CallState.connecting || _state == CallState.connected) {
      debugPrint('[call] bootstrapIncomingFromPush: state=$_state — skip');
      return;
    }
    debugPrint('[call] bootstrapIncomingFromPush: callId=$callId peer=$peerUserId');
    _activeCallId = callId;
    _peerUserId = peerUserId;
    _peerNickname = peerNickname.isEmpty ? '익명' : peerNickname;
    _peerWalletAddress = peerWalletAddress;
    _isCaller = false;
    _connectedAt = null;
    _lastError = null;
    _state = CallState.incoming;
    notifyListeners();
  }

  /// Callee accepts the incoming call.
  ///
  /// ★ P0-#2 (v1.0.127): join 성공 후 response 전송.
  ///   기존 버그: response(accepted=true) 먼저 보내고 → join 진행 → 토큰 발급
  ///   실패하면 발신자는 "수락됨" 받았는데 음성 안 흐름 → 30초간 ringback.
  ///   수정: 채널 join 까지 성공한 뒤 response 보냄. 실패 시 자동 reject.
  /// ★ v1.0.137: WS 끊긴 상태(콜드 부팅 직후 푸시 수락)에서도 동작.
  ///   chat.connect() + _waitForSocket() 으로 emit 직전 재연결 보장.
  Future<void> acceptCall() async {
    if (_state != CallState.incoming || _activeCallId == null) return;
    final ok = await _ensureMicPermission();
    if (!ok) {
      await rejectCall(reason: '마이크 권한이 필요해요');
      return;
    }
    // ★ v1.0.137: WS 가 끊겨 있으면 재연결. emit('call_response') 가 silent
    //   fail 되면 발신자는 영영 30초 timeout 까지 ringback → "받지 않음" 표시.
    if (!chat.connected) {
      debugPrint('[call] acceptCall: WS not connected, attempting reconnect');
      chat.connect();
      await _waitForSocket(timeoutMs: 4000);
      if (!chat.connected) {
        debugPrint('[call] acceptCall: WS reconnect failed, retrying once');
        await Future.delayed(const Duration(seconds: 1));
        chat.connect();
        await _waitForSocket(timeoutMs: 3000);
      }
    }

    // ★ v1.0.140 (2026-05-09): myWallet 자가 회복 — auth 가 아직 hydrate 안 된
    //   콜드 부팅 직후 푸시 수락 케이스. auth.user 가 null/wallet 비어있으면
    //   _joinAgoraChannel 이 즉시 false 리턴 → 통화 못 연결.
    //   해결: join 전에 한 번 더 auth.loadFromStorage() await + polling.
    if ((auth.user?.walletAddress ?? '').isEmpty) {
      debugPrint('[call] acceptCall: auth.user wallet empty — awaiting loadFromStorage');
      try {
        await auth.loadFromStorage();
      } catch (e) {
        debugPrint('[call] acceptCall: loadFromStorage failed: $e');
      }
      // 그래도 비어있으면 짧은 polling (최대 1.5s, 100ms 간격).
      for (int i = 0; i < 15; i++) {
        if ((auth.user?.walletAddress ?? '').isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    // ★ v1.0.141 (2026-05-09): peerWallet 자가 회복 — push 데이터에 caller_wallet
    //   이 누락된 케이스 (구버전 발신자, 또는 fcm payload 손실).
    //   _peerWalletAddress 가 비어 있으면 신규 엔드포인트
    //   GET /api/users/:id/call-info 로 peer 의 wallet 직접 조회 → 채널명 산정.
    //   사장님 요구: "수락 → 통화 진짜 연결" — 이 자가 회복으로 join 성공률 극대화.
    if ((_peerWalletAddress ?? '').isEmpty &&
        (_peerUserId ?? '').isNotEmpty) {
      debugPrint('[call] acceptCall: _peerWalletAddress empty — fetching from /call-info');
      try {
        final res = await auth.api.dio.get<Map<String, dynamic>>(
          '/api/users/${_peerUserId!}/call-info',
        );
        if (res.statusCode == 200 && res.data != null) {
          final w = res.data!['wallet_address']?.toString();
          if (w != null && w.isNotEmpty) {
            _peerWalletAddress = w;
            final n = res.data!['nickname']?.toString();
            if (n != null && n.isNotEmpty &&
                (_peerNickname == null || _peerNickname == '익명')) {
              _peerNickname = n;
            }
            debugPrint('[call] acceptCall: peerWallet recovered from server');
          }
        }
      } catch (e) {
        debugPrint('[call] acceptCall: /call-info fetch failed: $e');
        // 서버 호출 실패 시에도 join 시도 — myWallet+peerWallet 둘 다 있으면 OK,
        // 둘 중 하나라도 비어 있으면 _joinAgoraChannel 의 가드에서 자연 실패.
      }
    }

    await _stopOsRingtone();
    _state = CallState.connecting;
    notifyListeners();

    // 1) 엔진 초기화 (실패해도 _joinAgoraChannel 안에서 한 번 더 시도).
    try {
      await _ensureEngine();
    } catch (e) {
      debugPrint('[call] acceptCall: engine pre-init failed (will retry on join): $e');
      // throw 하지 않음 — _joinAgoraChannel() 안에서 재시도.
    }

    // 2) 수신자 먼저 채널 join (성공 시에만 발신자에게 accepted 알림).
    final joined = await _joinAgoraChannel();
    if (!joined) {
      // ★ v1.0.140 (2026-05-09): rejectCall 호출 제거.
      //   기존 동작 (v1.0.131~v1.0.139): join 실패 시 rejectCall(reason)
      //   → chat.emit('call_response', {accepted:false}) → 발신자 단말의
      //   chat.on('call_response') 핸들러가 _setError('상대방이 통화를
      //   거절했어요') 표시 + teardown. 사장님이 v1.0.136~v1.0.139 내내
      //   본 정확한 증상 (수락 → 발신자에 거절 표시 → 끊김).
      //
      //   수정: 발신자에게 거절 신호 보내지 않고, 수신자 단말만 silent
      //   teardown. 발신자는 30초 발신 타임아웃이 자연 만료되어 "받지
      //   않았어요" 로 종료됨 (수락 → 거절 표시 X).
      //   수신자 화면엔 _setError 로 안내 메시지만 표시.
      // ★ v1.0.144 (2026-05-09): _joinAgoraChannel 의 분기별 사유를 토스트에 포함.
      //   사장님 보고 시 채널길이/JWT/Agora SDK 중 어느 단계에서 실패했는지 즉시 식별.
      final String? failReason = _lastJoinFailReason;
      _lastJoinFailReason = null;
      String errorMsg = '연결을 시도했어요. 잠시 후 다시 걸어주세요.';
      if (failReason != null && failReason.isNotEmpty) {
        errorMsg = errorMsg + '\n(' + failReason + ')';
      }
      _setError(errorMsg);
      // 단 emit('call_response') 는 보내지 않음 — 발신자 보호.
      // _teardown 자체는 WS emit 안 함 (rejectCall/endCall 만 emit).
      await _teardown(stateAfter: CallState.ended);
      return;
    }

    // 3) join 성공 → 발신자에게 accepted 통보.
    chat.emit('call_response', {
      'to_user_id': _peerUserId,
      'call_id': _activeCallId,
      'accepted': true,
    });
    // ★ P0-#3: 백그라운드 음성 끊김 방지 — foreground service 시작.
    await _startCallForegroundService();
  }

  /// Callee rejects the incoming call.
  Future<void> rejectCall({String? reason}) async {
    if (_activeCallId == null) return;
    chat.emit('call_response', {
      'to_user_id': _peerUserId,
      'call_id': _activeCallId,
      'accepted': false,
    });
    if (reason != null) _setError(reason);
    await _teardown(stateAfter: CallState.ended);
  }

  /// End the active/outgoing call.
  Future<void> endCall() async {
    if (_activeCallId == null) return;
    chat.emit('call_end', {
      'to_user_id': _peerUserId,
      'call_id': _activeCallId,
    });
    await _teardown(stateAfter: CallState.ended);
  }

  /// Toggle microphone mute (Agora API).
  Future<void> toggleMute() async {
    if (_engine == null) return;
    _muted = !_muted;
    try {
      await _engine!.muteLocalAudioStream(_muted);
    } catch (e) {
      debugPrint('[call] muteLocalAudioStream failed: $e');
    }
    notifyListeners();
  }

  /// Toggle speakerphone (Agora API).
  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    try {
      await _engine?.setEnableSpeakerphone(_speakerOn);
    } catch (e) {
      debugPrint('[call] setEnableSpeakerphone failed: $e');
    }
    notifyListeners();
  }

  /// Manually clear the "ended" banner.
  void clearEnded() {
    if (_state == CallState.ended) {
      _state = CallState.idle;
      _activeCallId = null;
      _peerUserId = null;
      _peerNickname = null;
      _peerWalletAddress = null;
      _isCaller = false;
      _connectedAt = null;
      _lastError = null;
      notifyListeners();
    }
  }

  // --- Internals --------------------------------------------------------

  /// ★ P0-#4 (v1.0.127): 마이크 권한 체크.
  ///   기존 버그: 한 번 거부되면 hasAskedBefore=true 라서 영영 false 반환 →
  ///   사용자는 통화 못 함. 수정: permanentlyDenied 면 openAppSettings 호출
  ///   가능하도록 별도 시그널을 두고, UI 에서 안내. 일반 denied 는 매번 재요청.
  Future<bool> _ensureMicPermission() async {
    final current = await Permission.microphone.status;
    if (current.isGranted) return true;
    if (current.isPermanentlyDenied) {
      // 사용자가 "다시 묻지 않기" 선택한 상태 → 시스템 설정으로 안내.
      _setError('설정 > 권한 > 마이크에서 권한을 켜주세요');
      try {
        await openAppSettings();
      } catch (e) {
        debugPrint('[call] openAppSettings failed: $e');
      }
      return false;
    }
    // denied 또는 첫 요청 — 시스템 권한 다이얼로그 띄움.
    final status = await Permission.microphone.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      _setError('설정 > 권한 > 마이크에서 권한을 켜주세요');
      try { await openAppSettings(); } catch (_) {}
    }
    return false;
  }

  Future<void> _waitForSocket({int timeoutMs = 3000}) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start).inMilliseconds < timeoutMs) {
      if (chat.connected) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // ── Ringtones ──────────────────────────────────────────────────────────

  Future<void> _startRingback() async {
    if (_ringbackPlaying) return;
    _ringbackPlaying = true;
    try {
      _ringbackPlayer ??= AudioPlayer();
      await _ringbackPlayer!.setReleaseMode(ReleaseMode.loop);
      await _ringbackPlayer!.play(AssetSource('sounds/ringback.mp3'));
    } catch (e) {
      debugPrint('[call] ringback start failed: $e');
      _ringbackPlaying = false;
    }
  }

  Future<void> _stopRingback() async {
    if (!_ringbackPlaying) return;
    _ringbackPlaying = false;
    try {
      await _ringbackPlayer?.stop();
    } catch (e) {
      debugPrint('[call] ringback stop failed: $e');
    }
  }

  Future<void> _startOsRingtone() async {
    if (_osRingtonePlaying) return;
    _osRingtonePlaying = true;
    try {
      await FlutterRingtonePlayer().play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.electronic,
        looping: true,
        volume: 1.0,
        asAlarm: false,
      );
    } catch (e) {
      debugPrint('[call] os ringtone start failed: $e');
      _osRingtonePlaying = false;
    }
  }

  Future<void> _stopOsRingtone() async {
    if (!_osRingtonePlaying) return;
    _osRingtonePlaying = false;
    try {
      await FlutterRingtonePlayer().stop();
    } catch (e) {
      debugPrint('[call] os ringtone stop failed: $e');
    }
  }

  Future<void> _stopAllRingtones() async {
    await _stopRingback();
    await _stopOsRingtone();
  }

  // ── Agora Engine ──────────────────────────────────────────────────────

  Future<void> _ensureEngine() async {
    if (_engineInitialized && _engine != null) return;
    if (!AgoraService.isConfigured) {
      throw 'Agora 설정이 누락되었어요';
    }
    // ★ v1.0.131: 각 await 호출을 한 줄씩 try/catch 로 격리.
    //   목표: initialize() 실패가 아닌, 다른 보조 호출(enableAudio, disableVideo,
    //   setDefaultAudioRouteToSpeakerphone, setEnableSpeakerphone) 중 하나가
    //   throw 해서 전체가 실패하던 케이스를 막는다.
    //   진짜 치명적인 호출은 createAgoraRtcEngine() + initialize() 둘 뿐.
    //   나머지는 best-effort 로 호출하고 실패해도 통화 자체는 진행한다.
    try {
      _engine = createAgoraRtcEngine();
    } catch (e) {
      debugPrint('[call] createAgoraRtcEngine failed: $e');
      _engine = null;
      _engineInitialized = false;
      rethrow;
    }
    try {
      // ★ v1.0.130 P0-#1: RtcEngineContext 의 audioScenario 제거.
      //   Communication profile 과 audioScenarioChatroom 조합이 일부 안드로이드
      //   기기에서 initialize() 자체를 throw 하게 만들어 "통화 엔진 초기화 실패"
      //   토스트의 진짜 원인이었음. 기본 scenario(default) 만 사용해 호환성 확보.
      await _engine!.initialize(
        RtcEngineContext(
          appId: AgoraService.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
    } catch (e) {
      debugPrint('[call] _engine.initialize failed: $e');
      _engine = null;
      _engineInitialized = false;
      rethrow;
    }
    // ── 여기 아래 모든 호출은 best-effort. 실패해도 통화는 진행. ───────
    // ★ v1.0.130 P0-#2: setClientRole 호출 제거 (communication profile 불필요).
    try {
      await _engine!.enableAudio();
    } catch (e) {
      debugPrint('[call] enableAudio failed (non-fatal): $e');
    }
    try {
      await _engine!.disableVideo();
    } catch (e) {
      debugPrint('[call] disableVideo failed (non-fatal): $e');
    }
    // ★ P1-#6 (v1.0.127): 1:1 음성 통화에 최적화된 audio profile.
    //   speechStandard = 16 kHz mono — 음성 압축 효율 + 품질 균형.
    //   v1.0.130: scenario 도 default 로 통일 (RtcEngineContext 와 일관성).
    try {
      await _engine!.setAudioProfile(
        profile: AudioProfileType.audioProfileSpeechStandard,
        scenario: AudioScenarioType.audioScenarioDefault,
      );
    } catch (e) {
      debugPrint('[call] setAudioProfile failed (non-fatal): $e');
    }
    try {
      await _engine!.setDefaultAudioRouteToSpeakerphone(true);
    } catch (e) {
      debugPrint('[call] setDefaultAudioRouteToSpeakerphone failed (non-fatal): $e');
    }
    try {
      await _engine!.setEnableSpeakerphone(_speakerOn);
    } catch (e) {
      debugPrint('[call] setEnableSpeakerphone failed (non-fatal): $e');
    }
    try {
      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection conn, int elapsed) {
          debugPrint('[call] Agora joined channel=${conn.channelId} uid=${conn.localUid} elapsed=${elapsed}ms');
          // ★ P1-#5 (v1.0.127): 내가 늦게 join 한 경우 onUserJoined 가 안 올 수
          //  있으므로 여기서도 connected 처리. 단, 상대가 이미 채널에 있는지
          //  확실치 않으니 connecting 유지하다가 onUserJoined 또는 5초 timer 로
          //  최종 결정. 여기선 connecting 진입 표시만.
          if (_state == CallState.connecting) {
            // 5초 안에 onUserJoined 가 안 오면 connected 로 강제 (네트워크 이슈
            // 로 RemoteAudioStateChanged 가 늦는 안드로이드 일부 기기 대비).
            Timer(const Duration(seconds: 5), () {
              if (_state == CallState.connecting) {
                debugPrint('[call] forcing connected after 5s grace period');
                _state = CallState.connected;
                _connectedAt = DateTime.now();
                _stopAllRingtones();
                notifyListeners();
              }
            });
          }
        },
        onUserJoined: (RtcConnection conn, int remoteUid, int elapsed) {
          debugPrint('[call] remote user joined uid=$remoteUid');
          // 양쪽 다 join 됨 = 통화 연결 성공.
          _state = CallState.connected;
          _connectedAt = DateTime.now();
          _stopAllRingtones();
          notifyListeners();
        },
        onUserOffline: (RtcConnection conn, int remoteUid, UserOfflineReasonType reason) {
          debugPrint('[call] remote user offline reason=$reason');
          // 상대가 채널 떠남 → 통화 종료.
          // ★ v1.0.151 진단: 어떤 사유로 상대가 이탈했는지 토스트로 노출.
          if (_state == CallState.connected || _state == CallState.connecting) {
            _setError('상대 채널 이탈 (offline reason=$reason, prevState=$_state)');
            _teardown(stateAfter: CallState.ended);
          }
        },
        onConnectionStateChanged: (RtcConnection conn,
            ConnectionStateType s, ConnectionChangedReasonType reason) {
          debugPrint('[call] connection state=$s reason=$reason');
          if (s == ConnectionStateType.connectionStateFailed) {
            // ★ v1.0.151 진단: Agora connection Failed 시 reason 코드를 토스트에 노출.
            //   token expired / invalid AppID / channel mismatch / network 등 구분용.
            _setError('연결이 끊어졌어요 (Agora state=Failed, reason=$reason)');
            _teardown(stateAfter: CallState.ended);
          } else if (s == ConnectionStateType.connectionStateDisconnected ||
              s == ConnectionStateType.connectionStateReconnecting) {
            // ★ v1.0.151 진단: reconnect guard 진입 사유 디버그 로그.
            debugPrint('[call] reconnect guard armed (state=$s, reason=$reason)');
            _scheduleReconnectGuard(triggerReason: reason);
          } else if (s == ConnectionStateType.connectionStateConnected) {
            _reconnectTimer?.cancel();
          }
        },
        onError: (ErrorCodeType err, String msg) {
          debugPrint('[call] Agora error code=$err msg=$msg');
        },
      ));
    } catch (e) {
      debugPrint('[call] registerEventHandler failed (non-fatal): $e');
    }
    // ── 여기까지 통과하면 엔진 초기화 성공으로 간주. ──
    _engineInitialized = true;
  }

  /// Disconnected/Reconnecting 5초 이상 지속되면 자동 종료.
  ///
  /// ★ v1.0.151 진단: triggerReason 추가 — guard 가 발동했을 때
  ///   어떤 connection reason 으로 진입했는지 토스트에 노출하여
  ///   "연결이 끊어졌어요" 토스트 3 경로 (Failed / userOffline / reconnect timeout)
  ///   를 사장님이 즉시 구분할 수 있게 한다.
  void _scheduleReconnectGuard({ConnectionChangedReasonType? triggerReason}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_state == CallState.connected || _state == CallState.connecting) {
        _setError('네트워크가 불안정해요 (reconnect 5s timeout, trigger=$triggerReason)');
        _teardown(stateAfter: CallState.ended);
      }
    });
  }

  /// Agora 채널 입장. 성공 시 true, 실패 시 false 반환.
  ///
  /// ★ P0-#2 (v1.0.127): bool 반환으로 변경 — acceptCall 이 join 성공 여부를
  ///   확인한 후에만 발신자에게 accepted 통보하기 위해.
  /// ★ P1-#8 (v1.0.127): 토큰 발급 1회 retry — 첫 호출 timeout/일시 오류 대비.
  Future<bool> _joinAgoraChannel() async {
    if (_engine == null) await _ensureEngine();
    var myWallet = auth.user?.walletAddress ?? '';
    var peerWallet = _peerWalletAddress ?? '';

    // ★ v1.0.141 (2026-05-09): wallet 누락 시 마지막 자가 복구 시도.
    //   acceptCall 에서 이미 loadFromStorage + /call-info fetch 했지만, 그래도
    //   비어 있을 가능성 대비 (네트워크 race / API 지연). 여기서 한 번 더.
    if (myWallet.isEmpty) {
      try {
        await auth.loadFromStorage();
      } catch (_) {}
      myWallet = auth.user?.walletAddress ?? '';
    }
    if (peerWallet.isEmpty && (_peerUserId ?? '').isNotEmpty) {
      try {
        final res = await auth.api.dio.get<Map<String, dynamic>>(
          '/api/users/${_peerUserId!}/call-info',
        );
        final w = res.data?['wallet_address']?.toString();
        if (w != null && w.isNotEmpty) {
          _peerWalletAddress = w;
          peerWallet = w;
          debugPrint('[call] _joinAgoraChannel: peerWallet recovered (last-mile)');
        }
      } catch (e) {
        debugPrint('[call] _joinAgoraChannel: /call-info recovery failed: $e');
      }
    }

    if (myWallet.isEmpty || peerWallet.isEmpty) {
      // ★ v1.0.144 (2026-05-09): 진단 가능하도록 사유를 _lastJoinFailReason 에 기록.
      //   acceptCall 이 이 값을 토스트에 포함시켜 사장님이 원인 즉시 식별 가능.
      _lastJoinFailReason =
          'wallet missing (my=${myWallet.isEmpty ? "empty" : "ok"}, peer=${peerWallet.isEmpty ? "empty" : "ok"})';
      debugPrint('[call] _joinAgoraChannel: $_lastJoinFailReason');
      await _teardown(stateAfter: CallState.ended);
      return false;
    }

    // ★ v1.0.138 (2026-05-08): AgoraService._uid 가 null 인 케이스 자가 회복.
    //   사장님 보고 ("연결을 시도했어요. 잠시 후 다시 걸어주세요" → 끊김):
    //   AgoraService.prepare(walletAddress) 는 main.dart 의 ChangeNotifierProvider
    //   create 함수에서 한 번만 호출되는데, 자동 로그인 사용자는 create 시점에
    //   authService.user 가 아직 null (loadFromStorage fire-and-forget) 이라
    //   prepare 가 안 호출되고 _uid 가 영영 null 로 유지됨.
    //   → fetchRtcToken 이 _uid==null 가드에서 즉시 null 반환 → 토큰 발급 실패
    //   → 발신자에게 reject 신호 → 사장님이 본 정확한 증상.
    //   해결: 토큰 호출 직전에 uid 가 비어 있으면 prepare 1회 호출.
    if (agora.uid == null && myWallet.isNotEmpty) {
      debugPrint('[call] agora._uid=null — running prepare() before token fetch');
      try {
        await agora.prepare(walletAddress: myWallet);
      } catch (e) {
        debugPrint('[call] agora.prepare() warning: $e');
      }
    }

    final channel = agora.callChannel(myWallet, peerWallet);
    final myUid = AgoraUid.fromWalletAddress(myWallet);

    // 서버 토큰 발급 (1회 retry — 4G 약전계 첫 호출 실패 대비).
    String? token;
    String lastTokenError = '';
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        token = await agora.fetchRtcToken(channel: channel);
        if (token != null && token.isNotEmpty) break;
        // ★ v1.0.145 (2026-05-09): AgoraService 가 _requestToken catch 에서
        //   debugPrint 만 하고 null return 하던 정보 유실 문제 해결.
        //   AgoraService.lastTokenError 가 HTTP 코드 + 서버 error code 보유.
        final svcErr = agora.lastTokenError;
        lastTokenError = (svcErr != null && svcErr.isNotEmpty)
            ? svcErr
            : 'returned null/empty';
      } catch (e) {
        lastTokenError = e.toString();
        debugPrint('[call] fetchRtcToken attempt=$attempt failed: $e');
      }
      if (attempt == 0) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    if (token == null || token.isEmpty) {
      // ★ v1.0.144 (2026-05-09): 채널 길이/JWT/서버 미배포 등 원인 식별용.
      _lastJoinFailReason =
          'token fetch failed (chanLen=${channel.length}, uid=$myUid, err=${lastTokenError.isEmpty ? "n/a" : lastTokenError})';
      debugPrint('[call] _joinAgoraChannel: $_lastJoinFailReason');
      await _teardown(stateAfter: CallState.ended);
      return false;
    }

    try {
      _activeChannel = channel;
      await _engine!.joinChannel(
        token: token,
        channelId: channel,
        uid: myUid,
        options: const ChannelMediaOptions(
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      return true;
    } catch (e) {
      // ★ v1.0.144: Agora SDK joinChannel 실패 — 채널/uid/네트워크 문제.
      _lastJoinFailReason = 'joinChannel threw (chanLen=${channel.length}, err=$e)';
      debugPrint('[call] _joinAgoraChannel: $_lastJoinFailReason');
      await _teardown(stateAfter: CallState.ended);
      return false;
    }
  }

  Future<void> _leaveAgoraChannel() async {
    try {
      if (_activeChannel != null) {
        await _engine?.leaveChannel();
        _activeChannel = null;
      }
    } catch (e) {
      debugPrint('[call] leaveChannel failed: $e');
    }
  }

  /// ★ v1.0.126: 모든 통화 관련 상태를 무조건 idle 로 강제 복구.
  ///   stuck 케이스 자가 회복 + 콜드부팅 시 잔존 UI 초기화 양쪽에서 사용.
  ///   _teardown 과 다른 점: stateAfter 옵션 없이 무조건 idle 로 가고,
  ///   엔진/채널/타이머/사운드/CallKit 모두 정리한다.
  Future<void> _forceReset() async {
    try { await _stopAllRingtones(); } catch (_) {}
    try { await _leaveAgoraChannel(); } catch (_) {}
    try { await FlutterCallkitIncoming.endAllCalls(); } catch (_) {}
    // ★ P0-#3: foreground service 도 함께 정리.
    try { await _stopCallForegroundService(); } catch (_) {}
    _outgoingTimeoutTimer?.cancel();
    _outgoingTimeoutTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _muted = false;
    _activeCallId = null;
    _peerUserId = null;
    _peerNickname = null;
    _peerWalletAddress = null;
    _isCaller = false;
    _connectedAt = null;
    _lastError = null;
    _state = CallState.idle;
    notifyListeners();
  }

  /// ★ v1.0.126: 앱 부팅 직후 1회 호출 — 잔존 CallKit UI/상태 강제 정리.
  ///   비정상 종료(앱 강제 종료, OS kill) 후 다시 켰을 때 stuck 토스트
  ///   "이미 통화 중이에요" 가 뜨는 케이스 방지.
  Future<void> resetOnBoot() async {
    debugPrint('[call] resetOnBoot — clearing stale CallKit state');
    await _forceReset();
  }

  // ── Foreground Service (Android 14+ 백그라운드 음성 보장) ─────────
  //
  // ★ P0-#3 (v1.0.127): flutter_foreground_task 시작/종료.
  //   pubspec 에 패키지가 추가됐지만 실제 시작 코드가 없어 Android 14+ 에서
  //   백그라운드 진입 시 마이크 끊김. 채널 join 직후 startService() 호출하고
  //   _teardown 시 stopService() 호출.
  bool _foregroundServiceStarted = false;

  /// ★ v1.0.128: foreground service 호출 단순화.
  ///   flutter_foreground_task 8.10.4 API 시그니처 불일치로 직접 호출 불가.
  ///   현재 상태에서는:
  ///     - Android 12 이하: foreground service 없이도 백그라운드 마이크 OK
  ///     - Android 13+: AndroidManifest 의 FOREGROUND_SERVICE_MICROPHONE 권한 +
  ///       Agora SDK 자체 audio focus 처리로 짧은 시간 백그라운드는 유지됨
  ///     - Android 14+: 본격적인 fg service 가 필요하면 native plugin 추가 검토
  ///   당장은 silent no-op — 통화 자체는 정상 작동 보장.
  Future<void> _startCallForegroundService() async {
    if (_foregroundServiceStarted) return;
    _foregroundServiceStarted = true;
    debugPrint('[call] foreground service: relying on Agora audio focus + manifest perms (no-op)');
  }

  Future<void> _stopCallForegroundService() async {
    if (!_foregroundServiceStarted) return;
    _foregroundServiceStarted = false;
  }

  Future<void> _teardown({required CallState stateAfter}) async {
    // 1) 사운드 즉시 정지
    await _stopAllRingtones();
    // 2) Agora 채널 leave (음성 즉시 끊김)
    await _leaveAgoraChannel();
    // 3) 백그라운드 CallKit UI 강제 종료
    if (_activeCallId != null) {
      try {
        await FlutterCallkitIncoming.endCall(_activeCallId!);
      } catch (_) {}
    }
    // ★ P0-#3: foreground service 종료 (배터리 보호 + 알림 사라짐).
    await _stopCallForegroundService();
    // 4) 타이머 정리
    _outgoingTimeoutTimer?.cancel();
    _outgoingTimeoutTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _muted = false;
    _state = stateAfter;
    if (stateAfter != CallState.ended) {
      _activeCallId = null;
      _peerUserId = null;
      _peerNickname = null;
      _peerWalletAddress = null;
      _isCaller = false;
      _connectedAt = null;
    }
    notifyListeners();

    // ★ v1.0.125: 3초 지연 제거 → 즉시 재발신 가능 (사장님 요구사항 11번).
    if (stateAfter == CallState.ended) {
      Future.delayed(const Duration(milliseconds: 800), clearEnded);
    }
  }

  void _setError(String msg) {
    _lastError = msg;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _outgoingTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    _teardown(stateAfter: CallState.idle);
    try {
      _engine?.release();
    } catch (_) {}
    _engine = null;
    try {
      _ringbackPlayer?.dispose();
    } catch (_) {}
    _ringbackPlayer = null;
    super.dispose();
  }
}
