import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/cointrip_service.dart';

/// 코인트립 연합 단톡방 — 연합원끼리만. 서버에 저장하지 않아 들어와 있을 때(앱이 켜져 있을 때) 대화만 보인다.
class CointripUnionChatScreen extends StatefulWidget {
  const CointripUnionChatScreen({super.key});

  @override
  State<CointripUnionChatScreen> createState() => _CointripUnionChatScreenState();
}

class _CointripUnionChatScreenState extends State<CointripUnionChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final ChatService _chat;
  StreamSubscription<Map<String, dynamic>>? _errSub;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _chat = context.read<ChatService>();
    _errSub = _chat.on('union_error', (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((e['message'] ?? '').toString())));
    });
    // 안 읽음 0 으로 바꾸면 화면을 다시 그리므로 첫 화면을 그린 다음에.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chat.unionChatOpen = true;
      context.read<CointripService>().refreshUnion().catchError((_) {});
    });
  }

  @override
  void dispose() {
    _chat.unionChatOpen = false;
    _errSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final l10n = context.l10n;
    if (_input.text.trim().isEmpty) return;
    if (_chat.sendUnionMessage(_input.text)) {
      _input.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.ctUnionChatOffline)));
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final union = context.watch<CointripService>().union;
    final chat = context.watch<ChatService>();
    final me = context.watch<AuthService>().user?.id;
    final msgs = union == null ? const <UnionChatMessage>[] : chat.unionMessagesFor(union.id);
    if (msgs.length != _lastCount) {
      _lastCount = msgs.length;
      _toBottom();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          union == null ? l10n.ctUnionChat : '${union.name} (${union.members.length})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: union == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.ctUnionChatNoUnion, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
              ),
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: EggplantColors.primary.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    l10n.ctUnionChatNote,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: EggplantColors.textSecondary, height: 1.4),
                  ),
                ),
                if (!chat.connected)
                  Container(
                    width: double.infinity,
                    color: EggplantColors.error.withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(l10n.ctUnionChatOffline,
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: EggplantColors.error)),
                  ),
                Expanded(
                  child: msgs.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(l10n.ctUnionChatEmpty,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: EggplantColors.textSecondary, height: 1.5)),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          itemCount: msgs.length,
                          itemBuilder: (_, i) {
                            final m = msgs[i];
                            final mine = m.senderId == me;
                            final showName = !mine && (i == 0 || msgs[i - 1].senderId != m.senderId);
                            return _Bubble(msg: m, mine: mine, showName: showName, time: _time(m.sentAt));
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 1000,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: l10n.ctUnionChatHint,
                              counterText: '',
                              isDense: true,
                              filled: true,
                              fillColor: EggplantColors.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _send,
                          tooltip: l10n.ctUnionChatSend,
                          icon: const Icon(Icons.send_rounded, color: EggplantColors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final UnionChatMessage msg;
  final bool mine;
  final bool showName;
  final String time;
  const _Bubble({required this.msg, required this.mine, required this.showName, required this.time});

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.72;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxW),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: mine ? EggplantColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: mine ? null : Border.all(color: EggplantColors.border),
      ),
      child: Text(msg.text, style: TextStyle(fontSize: 15, height: 1.35, color: mine ? Colors.white : EggplantColors.textPrimary)),
    );
    final timeText = Text(time, style: const TextStyle(fontSize: 11, color: EggplantColors.textTertiary));
    return Padding(
      padding: EdgeInsets.only(top: showName ? 10 : 3),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(msg.senderNickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: EggplantColors.textSecondary)),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: mine
                ? [timeText, const SizedBox(width: 4), Flexible(child: bubble)]
                : [Flexible(child: bubble), const SizedBox(width: 4), timeText],
          ),
        ],
      ),
    );
  }
}
