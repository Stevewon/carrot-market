import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../models/chat_message.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;
  final String peerNickname;
  final String? productTitle;
  final String? peerUserId;

  const ChatScreen({
    super.key,
    required this.roomId,
    required this.peerNickname,
    this.productTitle,
    this.peerUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _ctl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatService>();
      chat.connect();
      chat.joinRoom(widget.roomId, peerNickname: widget.peerNickname);
      // After history loads, scroll to bottom.
      Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
    });
  }

  void _scrollToBottom() {
    if (!_scrollCtl.hasClients) return;
    _scrollCtl.animateTo(
      _scrollCtl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    context.read<ChatService>().leaveRoom(widget.roomId);
    _ctl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    context.read<ChatService>().sendMessage(widget.roomId, text);
    _ctl.clear();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollCtl.hasClients) {
        _scrollCtl.animateTo(
          _scrollCtl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatService>();
    final auth = context.watch<AuthService>();
    final messages = chat.messagesFor(widget.roomId);

    return Scaffold(
      backgroundColor: EggplantColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🍆 ', style: TextStyle(fontSize: 16)),
                Flexible(
                  child: Text(
                    widget.peerNickname,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Text(
              '🔒 나가면 양쪽 모두 완전 삭제돼요',
              style: TextStyle(fontSize: 11, color: EggplantColors.primary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '익명 음성통화',
            icon: const Icon(Icons.call, color: EggplantColors.primary),
            onPressed: () => _startVoiceCall(context),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showOptions(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.productTitle != null) _ProductBanner(title: widget.productTitle!),
          Expanded(
            child: messages.isEmpty
                ? _EmptyChat(peerNickname: widget.peerNickname)
                : ListView.builder(
                    controller: _scrollCtl,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final msg = messages[i];
                      return _MessageBubble(message: msg);
                    },
                  ),
          ),
          _InputBar(controller: _ctl, onSend: _send, connected: chat.connected),
        ],
      ),
    );
  }

  /// Derive the peer's userId from the deterministic room ID.
  /// roomId format: "userA_userB" or "userA_userB_productId"
  /// where userA < userB (sorted).
  String? _derivePeerUserId(String? myUserId) {
    if (myUserId == null) return null;
    if (widget.peerUserId != null && widget.peerUserId!.isNotEmpty) {
      return widget.peerUserId;
    }
    // Typical UUID has 36 chars including 4 hyphens
    final parts = widget.roomId.split('_');
    for (final p in parts) {
      if (p != myUserId && p.length >= 20) {
        return p;
      }
    }
    return null;
  }

  void _startVoiceCall(BuildContext context) {
    final auth = context.read<AuthService>();
    final peerId = _derivePeerUserId(auth.user?.id);
    if (peerId == null || peerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상대방 정보를 찾을 수 없어요')),
      );
      return;
    }
    context.push(
      '/call?peerId=$peerId&peer=${Uri.encodeComponent(widget.peerNickname)}',
    );
  }

  void _showOptions(BuildContext context) {
    final rootContext = context;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('대화 내용 삭제'),
              subtitle: const Text('이 방의 메시지만 비워요 (방은 유지)'),
              onTap: () async {
                Navigator.pop(context);
                await _confirmClearMessages(rootContext);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: EggplantColors.error),
              title: const Text('채팅방 나가기',
                  style: TextStyle(color: EggplantColors.error, fontWeight: FontWeight.w700)),
              subtitle: const Text('양쪽 모두 대화 + 방을 완전 삭제해요 (복구 불가)'),
              onTap: () async {
                Navigator.pop(context);
                await _confirmDeleteRoom(rootContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteRoom(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('채팅방 나가기'),
        content: Text(
          '${widget.peerNickname}님과의 대화를 완전히 삭제할까요?\n\n'
          '• 메시지 전부 영구 삭제\n'
          '• 상대방 화면에서도 즉시 사라짐\n'
          '• 복구 불가',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(_, true),
            style: TextButton.styleFrom(foregroundColor: EggplantColors.error),
            child: const Text('완전히 삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!ctx.mounted) return;
    final success = await ctx.read<ChatService>().deleteRoom(widget.roomId);
    if (!ctx.mounted) return;
    if (success) {
      ctx.pop();
    } else {
      ScaffoldMessenger.of(ctx)
          .showSnackBar(const SnackBar(content: Text('삭제 실패. 잠시 후 다시 시도해주세요')));
    }
  }

  Future<void> _confirmClearMessages(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('대화 내용 삭제'),
        content: const Text('이 방의 모든 메시지를 지울까요?\n방은 유지되며 상대방 화면의 메시지도 같이 지워져요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(_, true),
            style: TextButton.styleFrom(foregroundColor: EggplantColors.error),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!ctx.mounted) return;
    final success = await ctx.read<ChatService>().clearMessages(widget.roomId);
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(success ? '대화 내용을 비웠어요' : '삭제 실패')),
    );
  }
}

class _ProductBanner extends StatelessWidget {
  final String title;
  const _ProductBanner({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: EggplantColors.background,
      child: Row(
        children: [
          const Icon(Icons.shopping_bag_outlined,
              size: 16, color: EggplantColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: EggplantColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final String peerNickname;
  const _EmptyChat({required this.peerNickname});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💨', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              '$peerNickname 님과\n익명 채팅이 시작되었어요',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: EggplantColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '이 대화는 서버/기기 어디에도 저장되지 않아요.\n화면을 벗어나면 내용이 사라져요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: EggplantColors.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.type == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.text,
            style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary),
          ),
        ),
      );
    }

    final mine = message.isMine;
    final time = DateFormat('HH:mm').format(message.sentAt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mine) Text(time, style: const TextStyle(fontSize: 10, color: EggplantColors.textTertiary)),
          if (mine) const SizedBox(width: 4),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? EggplantColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                border: mine ? null : Border.all(color: EggplantColors.border),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  fontSize: 14,
                  color: mine ? Colors.white : EggplantColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (!mine) const SizedBox(width: 4),
          if (!mine)
            Text(time, style: const TextStyle(fontSize: 10, color: EggplantColors.textTertiary)),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool connected;

  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: EggplantColors.border)),
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 10,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: connected ? '메시지 입력 (저장 안 됨)' : '연결 중...',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: EggplantColors.background,
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: EggplantColors.primary,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: onSend,
            ),
          ),
        ],
      ),
    );
  }
}
