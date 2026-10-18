import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';

/// 내 QR 에 담기는 링크 — https://api.eggplant.life/u/<id>?n=<닉네임>.
/// 폰 카메라로 찍거나 카톡에서 누르면 웹 페이지 → "가지 앱에서 채팅하기" → eggplant://app/u/<id>?n=… → [PeerLinkScreen].
String peerLink(String apiBase, String userId, String nickname) =>
    '$apiBase/u/${Uri.encodeComponent(userId)}?n=${Uri.encodeComponent(nickname)}';

/// QR · 링크에서 (회원 id, 닉네임) 을 꺼낸다. 가지 링크가 아니면 null.
///  - https://…/u/<id>?n=<닉네임> · eggplant://app/u/<id>?n=<닉네임>
///  - 예전 QR: eggplant://<id>/<닉네임>
(String, String)? parsePeerLink(String code) {
  final uri = Uri.tryParse(code.trim());
  if (uri == null) return null;
  final seg = uri.pathSegments;
  final nick = uri.queryParameters['n'] ?? '';
  if ((uri.scheme == 'https' || uri.scheme == 'eggplant') && seg.length == 2 && seg[0] == 'u' && seg[1].isNotEmpty) {
    return (seg[1], nick);
  }
  if (uri.scheme == 'eggplant' && uri.host.isNotEmpty && uri.host != 'app' && seg.isNotEmpty) {
    return (uri.host, seg[0]);
  }
  return null;
}

/// 링크로 들어온 회원과 익명 채팅방을 열고 바로 채팅 화면으로 간다.
class PeerLinkScreen extends StatefulWidget {
  final String userId;
  final String nickname;
  const PeerLinkScreen({super.key, required this.userId, required this.nickname});

  @override
  State<PeerLinkScreen> createState() => _PeerLinkScreenState();
}

class _PeerLinkScreenState extends State<PeerLinkScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final l10n = context.l10n;
    final me = context.read<AuthService>().user;
    if (me != null && me.id == widget.userId) {
      setState(() => _error = l10n.homeQrOwn);
      return;
    }
    final nick = widget.nickname.isEmpty ? l10n.homeAnonymous : widget.nickname;
    final room = await context.read<ChatService>().openRoomWithPeer(peerUserId: widget.userId, peerNickname: nick);
    if (!mounted) return;
    if (room == null) {
      setState(() => _error = l10n.homeQrChatFailed);
      return;
    }
    context.go('/chat/${room.id}?peer=${Uri.encodeComponent(nick)}&peerId=${Uri.encodeComponent(widget.userId)}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => context.go('/'), child: Text(context.l10n.homeGoHome)),
                  ],
                ),
              ),
      ),
    );
  }
}
