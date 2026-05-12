import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/call_service.dart';
import '../services/permission_service.dart';

/// Full-screen call UI.
/// - Shown for outgoing, incoming, connecting, connected, ended states.
/// - Closes automatically when the call ends.
class CallScreen extends StatefulWidget {
  final String peerUserId;
  final String peerNickname;
  final String peerWalletAddress; // Agora 채널명 산정에 사용 (sorted wallet pair)
  final bool startImmediately; // true = outgoing; false = incoming (already set)
  /// ★ v1.0.136: CallKit (백그라운드/잠금화면) 에서 "받기" 누른 후 라우팅된 케이스.
  ///   true 면 CallScreen 이 자동으로 acceptCall 호출 (사용자가 다시 수락 버튼
  ///   누를 필요 없음). startImmediately 와 별개 — fromPush 는 incoming 통화의
  ///   자동 accept 트리거고, startImmediately 는 outgoing 통화의 자동 발신 트리거.
  final bool fromPush;

  const CallScreen({
    super.key,
    required this.peerUserId,
    required this.peerNickname,
    this.peerWalletAddress = '',
    this.startImmediately = true,
    this.fromPush = false,
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
        // ★ v1.0.161 (2026-05-12): 발신 진입 시 FSI 권한 한 번 더 확인.
        //   splash 에서 이미 한 번 안내했지만, 발신자 본인이 안내를 놓쳤어도
        //   첫 발신 시점에 다시 알려서 다음 통화는 정상화되도록 보장.
        //   (oncePerSession=true 이므로 같은 세션 내 중복 팝업 없음)
        if (mounted) {
          // ignore: unawaited_futures
          PermissionService.ensureFullScreenIntentOrGuide(context);
        }
        final call = context.read<CallService>();
        try {
          await call.startCall(
            peerUserId: widget.peerUserId,
            peerNickname: widget.peerNickname,
            peerWalletAddress: widget.peerWalletAddress,
          );
        } catch (e) {
          // ★ v1.0.130 P0-#3: pop 먼저 → SnackBar 는 root scaffold 에서.
          //   기존: SnackBar 후 pop → 라우터 stack 꼬임으로 채팅 탭의 다음 push
          //   가 무효화되어 사장님 화면에서 채팅방이 안 들어가는 현상 발생.
          //   수정: 즉시 pop → 다음 frame 에서 SnackBar 표시 (root context).
          if (!mounted) return;
          final msg = e.toString();
          context.pop();
          // pop 직후 SnackBar — root navigator 위에서 띄움.
          Future.microtask(() {
            final rootCtx = context;
            if (!rootCtx.mounted) return;
            ScaffoldMessenger.maybeOf(rootCtx)?.showSnackBar(
              SnackBar(content: Text(msg)),
            );
          });
        }
      });
    } else if (widget.fromPush) {
      // ★ v1.0.137 (2026-05-08): CallKit "받기" 후 라우팅된 incoming 통화.
      //
      //   v1.0.136 의 문제: incoming 상태 진입은 chat.on('call_incoming') 이
      //   처리하지만 백그라운드/앱 종료 상태에서 push 로 깨워진 경우 WS 가
      //   아직 안 붙어 있어 이벤트가 안 옴 → 5초 대기 → acceptCall 가드 막힘
      //   → silent return → 사장님이 본 "메인 화면으로 들어가버림" 증상.
      //
      //   v1.0.137 해결: 라우터 쿼리로 받은 push data 만으로 CallService 의
      //   incoming 상태를 즉시 부트스트랩 (WS 안 붙어도 OK). 그 뒤 acceptCall
      //   내부에서 WS 재연결 후 emit('call_response') 보냄.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_startAttempted) return;
        _startAttempted = true;
        final call = context.read<CallService>();
        // 1) 푸시 데이터로 incoming 상태 강제 진입 (WS 미연결이어도 동작).
        //    이미 chat.on('call_incoming') 이 와서 incoming 으로 들어와 있으면
        //    bootstrapIncomingFromPush 가 자체 가드로 skip.
        //    activeCallId 가 비어 있으면 fromPush 라우트의 call_id 가 없는
        //    상태이므로 부트스트랩 못함 — 이 경우는 main.dart 의
        //    _attachCallkitAccept 가 router.push 할 때 이미 데이터 채워둠
        //    (peerId/peer/peerWallet) → CallScreen 도 동일 데이터 보유.
        if (call.state != CallState.incoming || call.activeCallId == null) {
          // call_id 는 라우터 쿼리로 안 옴 → CallService 가 push_service 로부터
          // _callAcceptCtrl 을 통해 받은 데이터에서 _attachCallkitAccept 가
          // 라우터 push 시점에 이미 알고 있음. 단 callId 자체는 query 에 안 실려
          // 있으니 부트스트랩 시 임시 callId 를 쓰면 서버 매칭 실패.
          // → 대신 CallService 가 chat.on('call_incoming') 을 받기까지 짧게
          //    기다린 뒤 (WS 재연결 후 서버가 retry push 안 보내도 상관없음 —
          //    아래 acceptCall 안의 _waitForSocket 가 WS 만 연결되면 OK),
          //    incoming 진입 못해도 acceptCall 호출 전에 마지막으로 한 번 더
          //    부트스트랩 시도.
          //
          //  ★ 최종 흐름: push_service 의 _callAcceptCtrl 에 call_id 포함됨 →
          //    main.dart 의 _attachCallkitAccept 가 라우터 push 직전에
          //    bootstrapIncomingFromPush 도 호출 (다음 patch 에서 추가).
          //    여기서는 그 결과 state 가 incoming 으로 진입돼 있을 것을 기대.
          //    1초 정도만 기다림 (WS reconnect 는 acceptCall 내부에서 처리).
          for (int i = 0; i < 5; i++) {
            if (call.state == CallState.incoming && call.activeCallId != null) {
              break;
            }
            await Future.delayed(const Duration(milliseconds: 200));
            if (!mounted) return;
          }
        }
        if (!mounted) return;
        // 2) acceptCall — 내부에서 WS 재연결 + 채널 join + response 전송.
        try {
          await call.acceptCall();
        } catch (e) {
          debugPrint('[call-screen] auto-accept from push failed: $e');
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
