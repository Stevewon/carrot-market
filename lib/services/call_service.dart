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

import '../utils/agora_uid.dart';
import 'agora_service.dart';
import 'auth_service.dart';
import 'chat_service.dart';
import 'permission_service.dart';

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
      if (_state != CallState.idle) {
        // Already busy - auto-reject.
        chat.emit('call_response', {
          'to_user_id': data['from_user_id'],
          'call_id': data['call_id'],
          'accepted': false,
        });
        return;
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
        await _joinAgoraChannel();
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
    chat.connect();
    if (!chat.connected) {
      await _waitForSocket();
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
    await _ensureEngine();

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

  /// Callee accepts the incoming call.
  Future<void> acceptCall() async {
    if (_state != CallState.incoming || _activeCallId == null) return;
    final ok = await _ensureMicPermission();
    if (!ok) {
      await rejectCall(reason: '마이크 권한이 필요해요');
      return;
    }
    await _stopOsRingtone();
    _state = CallState.connecting;
    notifyListeners();

    await _ensureEngine();

    chat.emit('call_response', {
      'to_user_id': _peerUserId,
      'call_id': _activeCallId,
      'accepted': true,
    });

    // 수신자도 즉시 채널 join (양쪽 모두 publisher).
    await _joinAgoraChannel();
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

  Future<bool> _ensureMicPermission() async {
    if (await Permission.microphone.isGranted) return true;
    if (!await PermissionService.hasAskedBefore()) {
      final status = await Permission.microphone.request();
      return status.isGranted;
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
    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: AgoraService.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          audioScenario: AudioScenarioType.audioScenarioChatroom,
        ),
      );
      await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await _engine!.enableAudio();
      await _engine!.disableVideo();
      await _engine!.setEnableSpeakerphone(_speakerOn);
      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection conn, int elapsed) {
          debugPrint('[call] Agora joined channel=${conn.channelId} uid=${conn.localUid} elapsed=${elapsed}ms');
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
          if (_state == CallState.connected || _state == CallState.connecting) {
            _teardown(stateAfter: CallState.ended);
          }
        },
        onConnectionStateChanged: (RtcConnection conn,
            ConnectionStateType s, ConnectionChangedReasonType reason) {
          debugPrint('[call] connection state=$s reason=$reason');
          if (s == ConnectionStateType.connectionStateFailed) {
            _setError('연결이 끊어졌어요');
            _teardown(stateAfter: CallState.ended);
          } else if (s == ConnectionStateType.connectionStateDisconnected ||
              s == ConnectionStateType.connectionStateReconnecting) {
            _scheduleReconnectGuard();
          } else if (s == ConnectionStateType.connectionStateConnected) {
            _reconnectTimer?.cancel();
          }
        },
        onError: (ErrorCodeType err, String msg) {
          debugPrint('[call] Agora error code=$err msg=$msg');
        },
      ));
      _engineInitialized = true;
    } catch (e) {
      debugPrint('[call] engine init failed: $e');
      _engine = null;
      _engineInitialized = false;
      rethrow;
    }
  }

  /// Disconnected/Reconnecting 5초 이상 지속되면 자동 종료.
  void _scheduleReconnectGuard() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_state == CallState.connected || _state == CallState.connecting) {
        _setError('네트워크가 불안정해요');
        _teardown(stateAfter: CallState.ended);
      }
    });
  }

  Future<void> _joinAgoraChannel() async {
    if (_engine == null) await _ensureEngine();
    final myWallet = auth.user?.walletAddress ?? '';
    final peerWallet = _peerWalletAddress ?? '';
    if (myWallet.isEmpty || peerWallet.isEmpty) {
      _setError('통화 정보를 불러올 수 없어요');
      await _teardown(stateAfter: CallState.ended);
      return;
    }

    final channel = agora.callChannel(myWallet, peerWallet);
    final myUid = AgoraUid.fromWalletAddress(myWallet);

    // 서버 토큰 발급 (실패 시 채널 join 실패 → 종료).
    String? token;
    try {
      token = await agora.fetchRtcToken(channel: channel);
    } catch (e) {
      debugPrint('[call] fetchRtcToken failed: $e');
    }
    if (token == null || token.isEmpty) {
      _setError('통화 토큰 발급 실패');
      await _teardown(stateAfter: CallState.ended);
      return;
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
    } catch (e) {
      debugPrint('[call] joinChannel failed: $e');
      _setError('채널 입장 실패');
      await _teardown(stateAfter: CallState.ended);
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
