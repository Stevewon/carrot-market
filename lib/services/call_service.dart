import 'dart:async';

import 'package:flutter/foundation.dart';
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
    _subs.add(chat.on('call_incoming', (data) {
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
  }

  /// Callee accepts the incoming call.
  Future<void> acceptCall() async {
    if (_state != CallState.incoming || _activeCallId == null) return;
    final ok = await _ensureMicPermission();
    if (!ok) {
      await rejectCall(reason: '마이크 권한이 필요해요');
      return;
    }
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
    super.dispose();
  }
}
