import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'auth_service.dart';
import 'chat_service.dart';
import 'permission_service.dart';

enum CallState {
  idle,       // No call
  outgoing,   // I'm calling someone, waiting for answer
  incoming,   // Someone is calling me, I haven't answered yet
  connecting, // Accepted, WebRTC handshake in progress
  connected,  // Call is active (audio flowing)
  ended,      // Just ended - show brief "ended" state
}

/// Manages anonymous P2P voice calls over WebRTC.
/// - Signaling rides on ChatService's WebSocket (single connection).
/// - Audio flows directly peer-to-peer. Server never hears it.
/// - No call history is stored anywhere.
class CallService extends ChangeNotifier {
  final AuthService auth;
  final ChatService chat;

  final List<StreamSubscription> _subs = [];

  CallService({required this.auth, required this.chat}) {
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

  // --- Ringtones (뚜루루루 발신음 + OS 기본 수신 벨) ---
  // 발신음(ringback): assets/sounds/ringback.mp3 (CC0, 1사이클 5초, 무한 루프)
  // 수신음(ringtone): flutter_ringtone_player.playRingtone() — 단말 OS 기본 벨
  // 둘 다 _teardown / 상태 전이 시 반드시 stop 호출.
  AudioPlayer? _ringbackPlayer;
  bool _ringbackPlaying = false;
  bool _osRingtonePlaying = false;

  // --- WebRTC ---
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? get remoteStream => _remoteStream;

  // Google public STUN servers (free).
  // For production across strict NATs, add a TURN server too.
  static const Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  static const Map<String, dynamic> _offerConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  /// Attach WebSocket event listeners via the ChatService event bus.
  void _attachListeners() {
    _subs.add(chat.on('call_incoming', (data) async {
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
      _isCaller = false;
      _state = CallState.incoming;
      notifyListeners();
      // 수신자: OS 기본 벨소리 재생 시작 (acceptCall/rejectCall 또는 _teardown 시 정지)
      await _startOsRingtone();
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
        // 상대 수락 → connecting 단계 진입. 발신음은 connected 까지 계속 재생.
        _state = CallState.connecting;
        notifyListeners();
        await _createAndSendOffer();
      }
    }));

    _subs.add(chat.on('webrtc_offer', (data) async {
      if (data['call_id'] != _activeCallId) return;
      final sdp = data['sdp'];
      if (sdp is Map) await _handleRemoteOffer(sdp);
    }));

    _subs.add(chat.on('webrtc_answer', (data) async {
      if (data['call_id'] != _activeCallId) return;
      final sdp = data['sdp'];
      if (sdp is Map) await _handleRemoteAnswer(sdp);
    }));

    _subs.add(chat.on('webrtc_ice', (data) async {
      if (data['call_id'] != _activeCallId) return;
      final cand = data['candidate'];
      if (cand is Map) {
        try {
          await _pc?.addCandidate(RTCIceCandidate(
            cand['candidate']?.toString(),
            cand['sdpMid']?.toString(),
            (cand['sdpMLineIndex'] is int)
                ? cand['sdpMLineIndex'] as int
                : int.tryParse(cand['sdpMLineIndex']?.toString() ?? ''),
          ));
        } catch (e) {
          debugPrint('[call] addCandidate failed: $e');
        }
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
  }) async {
    if (_state != CallState.idle) {
      throw '이미 통화 중이에요';
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
    _isCaller = true;
    _state = CallState.outgoing;
    _lastError = null;
    notifyListeners();

    await _setupPeerConnection();
    await _addLocalAudio();

    chat.emit('call_invite', {
      'to_user_id': peerUserId,
      'call_id': _activeCallId,
      'caller_nickname': auth.user?.nickname ?? '익명',
    });
    // 발신자: "뚜루루루" 발신음 시작 (상대 수락 → connected 진입 시 정지)
    await _startRingback();
  }

  /// Callee accepts the incoming call.
  Future<void> acceptCall() async {
    if (_state != CallState.incoming || _activeCallId == null) return;
    final ok = await _ensureMicPermission();
    if (!ok) {
      await rejectCall(reason: '마이크 권한이 필요해요');
      return;
    }
    // 수신자가 수락 → OS 벨소리 즉시 정지
    await _stopOsRingtone();
    _state = CallState.connecting;
    notifyListeners();

    await _setupPeerConnection();
    await _addLocalAudio();

    chat.emit('call_response', {
      'to_user_id': _peerUserId,
      'call_id': _activeCallId,
      'accepted': true,
    });
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

  /// Toggle microphone mute.
  void toggleMute() {
    if (_localStream == null) return;
    _muted = !_muted;
    for (final t in _localStream!.getAudioTracks()) {
      t.enabled = !_muted;
    }
    notifyListeners();
  }

  /// Toggle speakerphone (Android only).
  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
    notifyListeners();
  }

  /// Manually clear the "ended" banner.
  void clearEnded() {
    if (_state == CallState.ended) {
      _state = CallState.idle;
      _activeCallId = null;
      _peerUserId = null;
      _peerNickname = null;
      _isCaller = false;
      _connectedAt = null;
      _lastError = null;
      notifyListeners();
    }
  }

  // --- Internals --------------------------------------------------------

  Future<bool> _ensureMicPermission() async {
    // Onboarding already granted this. If already granted, don't re-prompt.
    if (await Permission.microphone.isGranted) return true;
    // Fallback: only ask if onboarding was somehow skipped.
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
  /// 발신자 측: 상대 응답 전까지 "뚜루루루" 발신음 무한 루프 재생.
  /// 같은 통화 사이클 안에서 중복 호출돼도 안전 (이미 재생 중이면 무시).
  Future<void> _startRingback() async {
    if (_ringbackPlaying) return;
    _ringbackPlaying = true;
    try {
      _ringbackPlayer ??= AudioPlayer();
      await _ringbackPlayer!.setReleaseMode(ReleaseMode.loop);
      // call: speakerphone (외부 스피커, 통화 컨텍스트)
      await _ringbackPlayer!.setAudioContext(
        const AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.voiceCommunication,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.allowBluetooth,
            },
          ),
        ),
      );
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

  /// 수신자 측: 단말 OS 기본 벨소리 재생 (사용자가 자기 폰에 설정한 벨).
  /// 사용자가 익숙한 소리이고 사일런트 모드도 OS 가 알아서 처리.
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

  /// 모든 사운드 즉시 정지 (연결 성공/통화 종료/dispose 시 호출).
  Future<void> _stopAllRingtones() async {
    await _stopRingback();
    await _stopOsRingtone();
  }

  Future<void> _setupPeerConnection() async {
    _pc = await createPeerConnection(_rtcConfig);

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      chat.emit('webrtc_ice', {
        'to_user_id': _peerUserId,
        'call_id': _activeCallId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        notifyListeners();
      }
    };

    _pc!.onConnectionState = (state) {
      debugPrint('[call] pc state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _state = CallState.connected;
        _connectedAt = DateTime.now();
        // 양측 모두 통화 연결 → 발신음/수신 벨소리 즉시 정지
        _stopAllRingtones();
        notifyListeners();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (_state != CallState.ended && _state != CallState.idle) {
          _teardown(stateAfter: CallState.ended);
        }
      }
    };
  }

  Future<void> _addLocalAudio() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    for (final track in _localStream!.getAudioTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
  }

  Future<void> _createAndSendOffer() async {
    if (_pc == null) return;
    final offer = await _pc!.createOffer(_offerConstraints);
    await _pc!.setLocalDescription(offer);
    chat.emit('webrtc_offer', {
      'to_user_id': _peerUserId,
      'call_id': _activeCallId,
      'sdp': {'sdp': offer.sdp, 'type': offer.type},
    });
  }

  Future<void> _handleRemoteOffer(Map sdp) async {
    if (_pc == null) {
      await _setupPeerConnection();
      await _addLocalAudio();
    }
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()),
    );
    final answer = await _pc!.createAnswer(_offerConstraints);
    await _pc!.setLocalDescription(answer);
    chat.emit('webrtc_answer', {
      'to_user_id': _peerUserId,
      'call_id': _activeCallId,
      'sdp': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  Future<void> _handleRemoteAnswer(Map sdp) async {
    if (_pc == null) return;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()),
    );
  }

  Future<void> _teardown({required CallState stateAfter}) async {
    // 발신음/수신 벨소리 즉시 정지 (가장 먼저 — 끊긴 후에도 들리면 안 됨)
    await _stopAllRingtones();
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      await _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    _muted = false;
    _state = stateAfter;
    if (stateAfter != CallState.ended) {
      _activeCallId = null;
      _peerUserId = null;
      _peerNickname = null;
      _isCaller = false;
      _connectedAt = null;
    }
    notifyListeners();

    if (stateAfter == CallState.ended) {
      Future.delayed(const Duration(seconds: 3), clearEnded);
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
    _teardown(stateAfter: CallState.idle);
    // AudioPlayer 인스턴스 정리 (메모리 누수 방지)
    try {
      _ringbackPlayer?.dispose();
    } catch (_) {}
    _ringbackPlayer = null;
    super.dispose();
  }
}
