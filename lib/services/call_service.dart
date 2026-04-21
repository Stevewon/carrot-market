import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:uuid/uuid.dart';

import 'auth_service.dart';
import 'chat_service.dart';

enum CallState {
  idle,       // No call
  outgoing,   // I'm calling someone, waiting for answer
  incoming,   // Someone is calling me, I haven't answered yet
  connecting, // Accepted, WebRTC handshake in progress
  connected,  // Call is active (audio flowing)
  ended,      // Just ended - show brief "ended" state
}

/// Manages anonymous P2P voice calls over WebRTC.
/// - Signaling uses the existing Socket.io connection (in ChatService).
/// - Audio flows directly peer-to-peer. Server never hears it.
/// - No call history is stored anywhere.
class CallService extends ChangeNotifier {
  final AuthService auth;
  final ChatService chat;

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

  /// Attach socket listeners for call signaling.
  /// Safe to call multiple times; re-wires on reconnect.
  void _attachListeners() {
    // Wait until chat.connect() has been called and socket exists.
    chat.addListener(_rewireSocket);
    _rewireSocket();
  }

  IO.Socket? _wiredSocket;
  void _rewireSocket() {
    final socket = _socket;
    if (socket == null) return;
    if (identical(socket, _wiredSocket)) return;
    _wiredSocket = socket;

    socket.on('call_incoming', (data) {
      if (data is! Map) return;
      if (_state != CallState.idle) {
        // Already busy - auto-reject
        socket.emit('call_response', {
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
    });

    socket.on('call_response', (data) async {
      if (data is! Map) return;
      if (data['call_id'] != _activeCallId) return;
      final accepted = data['accepted'] == true;
      if (!accepted) {
        _setError('상대방이 통화를 거절했어요');
        await _teardown(stateAfter: CallState.ended);
        return;
      }
      // Caller: create offer now that callee accepted
      if (_isCaller) {
        _state = CallState.connecting;
        notifyListeners();
        await _createAndSendOffer();
      }
    });

    socket.on('webrtc_offer', (data) async {
      if (data is! Map) return;
      if (data['call_id'] != _activeCallId) return;
      await _handleRemoteOffer(data['sdp'] as Map);
    });

    socket.on('webrtc_answer', (data) async {
      if (data is! Map) return;
      if (data['call_id'] != _activeCallId) return;
      await _handleRemoteAnswer(data['sdp'] as Map);
    });

    socket.on('webrtc_ice', (data) async {
      if (data is! Map) return;
      if (data['call_id'] != _activeCallId) return;
      final c = data['candidate'];
      if (c is Map) {
        try {
          await _pc?.addCandidate(RTCIceCandidate(
            c['candidate']?.toString(),
            c['sdpMid']?.toString(),
            (c['sdpMLineIndex'] is int)
                ? c['sdpMLineIndex'] as int
                : int.tryParse(c['sdpMLineIndex']?.toString() ?? ''),
          ));
        } catch (e) {
          debugPrint('[call] addCandidate failed: $e');
        }
      }
    });

    socket.on('call_end', (data) async {
      if (data is! Map) return;
      if (data['call_id'] != _activeCallId) return;
      await _teardown(stateAfter: CallState.ended);
    });

    socket.on('call_failed', (data) async {
      if (data is! Map) return;
      if (data['call_id'] != _activeCallId) return;
      final reason = data['message']?.toString() ?? '통화 실패';
      _setError(reason);
      await _teardown(stateAfter: CallState.ended);
    });
  }

  IO.Socket? get _socket {
    // ChatService holds the socket privately; we trigger a connect
    // through the ChatService and then reuse the same underlying socket
    // via a dart MethodChannel-style reflection would be overkill.
    // Instead, ChatService exposes what we need via public helpers below.
    return chat.socketForCalls;
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
    final socket = _socket;
    if (socket == null || !socket.connected) {
      // Wait up to 3 seconds for connection
      await _waitForSocket();
    }
    if (_socket == null || !_socket!.connected) {
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

    _socket!.emit('call_invite', {
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

    _socket?.emit('call_response', {
      'to_user_id': _peerUserId,
      'call_id': _activeCallId,
      'accepted': true,
    });
    // Now wait for offer from caller...
  }

  /// Callee rejects the incoming call.
  Future<void> rejectCall({String? reason}) async {
    if (_activeCallId == null) return;
    _socket?.emit('call_response', {
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
    _socket?.emit('call_end', {
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
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _waitForSocket({int timeoutMs = 3000}) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start).inMilliseconds < timeoutMs) {
      if (_socket?.connected == true) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _setupPeerConnection() async {
    _pc = await createPeerConnection(_rtcConfig);

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _socket?.emit('webrtc_ice', {
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
    _socket?.emit('webrtc_offer', {
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
    _socket?.emit('webrtc_answer', {
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

    // Auto-clear "ended" state after a few seconds
    if (stateAfter == CallState.ended) {
      Future.delayed(const Duration(seconds: 3), clearEnded);
    }
  }

  void _setError(String msg) {
    _lastError = msg;
  }

  @override
  void dispose() {
    chat.removeListener(_rewireSocket);
    _teardown(stateAfter: CallState.idle);
    super.dispose();
  }
}
