import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/call_service.dart';

/// Full-screen call UI.
/// - Shown for outgoing, incoming, connecting, connected, ended states.
/// - Closes automatically when the call ends.
class CallScreen extends StatefulWidget {
  final String peerUserId;
  final String peerNickname;
  final bool startImmediately; // true = outgoing; false = incoming (already set)

  const CallScreen({
    super.key,
    required this.peerUserId,
    required this.peerNickname,
    this.startImmediately = true,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _startAttempted = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final call = context.read<CallService>();
      if (call.connectedAt != null) {
        setState(() {
          _elapsed = DateTime.now().difference(call.connectedAt!);
        });
      }
    });

    if (widget.startImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_startAttempted) return;
        _startAttempted = true;
        final call = context.read<CallService>();
        try {
          await call.startCall(
            peerUserId: widget.peerUserId,
            peerNickname: widget.peerNickname,
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString())),
            );
            context.pop();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hh = d.inHours.toString().padLeft(2, '0');
      return '$hh:$mm:$ss';
    }
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallService>();
    final state = call.state;

    // Auto-close when call fully ends and state returns to idle
    if (state == CallState.idle && _startAttempted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop();
      });
    }

    String statusText;
    Color statusColor = Colors.white70;
    switch (state) {
      case CallState.outgoing:
        statusText = '호출 중...';
        break;
      case CallState.incoming:
        statusText = '걸려온 익명 통화';
        break;
      case CallState.connecting:
        statusText = '연결 중...';
        break;
      case CallState.connected:
        statusText = _formatElapsed(_elapsed);
        statusColor = Colors.white;
        break;
      case CallState.ended:
        statusText = call.lastError ?? '통화 종료';
        statusColor = Colors.white54;
        break;
      case CallState.idle:
        statusText = '';
        break;
    }

    return WillPopScope(
      onWillPop: () async {
        // Don't let the user swipe-back out of an active call — they must end it
        if (state == CallState.connected || state == CallState.connecting) {
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A0B2E), // deep eggplant purple
        body: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.lock, size: 14, color: Colors.white54),
                    const SizedBox(width: 6),
                    const Text(
                      '완전 익명 음성 통화',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      '🍆',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),

              // Avatar
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      EggplantColors.primary,
                      EggplantColors.primaryDark,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: EggplantColors.primary.withOpacity(0.4),
                      blurRadius: 40,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text('🍆', style: TextStyle(fontSize: 64)),
              ),
              const SizedBox(height: 24),

              // Peer nickname
              Text(
                call.peerNickname ?? widget.peerNickname,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),

              // Status
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 16,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),

              const Spacer(flex: 3),

              // Controls
              _buildControls(call),

              const SizedBox(height: 48),

              // Security note
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  '이 통화는 P2P로 직접 연결돼요.\n서버에 녹음·저장되지 않아요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(CallService call) {
    final state = call.state;

    // Incoming call - reject / accept buttons
    if (state == CallState.incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            icon: Icons.call_end,
            label: '거절',
            color: Colors.red,
            onTap: () => call.rejectCall(),
          ),
          _RoundButton(
            icon: Icons.call,
            label: '수락',
            color: Colors.green,
            onTap: () => call.acceptCall(),
          ),
        ],
      );
    }

    // Active / outgoing / connecting - mute / speaker / hangup
    if (state == CallState.outgoing ||
        state == CallState.connecting ||
        state == CallState.connected) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            icon: call.muted ? Icons.mic_off : Icons.mic,
            label: call.muted ? '음소거 해제' : '음소거',
            color: call.muted ? Colors.orange : Colors.white24,
            iconColor: Colors.white,
            onTap: state == CallState.connected ? call.toggleMute : null,
          ),
          _RoundButton(
            icon: Icons.call_end,
            label: '종료',
            color: Colors.red,
            onTap: () => call.endCall(),
          ),
          _RoundButton(
            icon: call.speakerOn ? Icons.volume_up : Icons.volume_down,
            label: call.speakerOn ? '스피커' : '수화기',
            color: call.speakerOn ? EggplantColors.primary : Colors.white24,
            iconColor: Colors.white,
            onTap: call.toggleSpeaker,
          ),
        ],
      );
    }

    // Ended - just a close button
    return _RoundButton(
      icon: Icons.close,
      label: '닫기',
      color: Colors.white24,
      iconColor: Colors.white,
      onTap: () {
        call.clearEnded();
        context.pop();
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;

  const _RoundButton({
    required this.icon,
    required this.label,
    required this.color,
    this.iconColor = Colors.white,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
              child: Icon(icon, color: iconColor, size: 30),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
