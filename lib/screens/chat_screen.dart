import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/responsive.dart';
import '../app/theme.dart';
import '../models/chat_message.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;
  final String peerNickname;
  final String? productTitle;
  final String? peerUserId;
  /// productId가 주어지면 가격 제안(💰) 버튼을 노출한다 (구매자 측 UI).
  final String? productId;

  const ChatScreen({
    super.key,
    required this.roomId,
    required this.peerNickname,
    this.productTitle,
    this.peerUserId,
    this.productId,
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
      // Mark this conversation as read — clears the unread badge and tells
      // the peer (via WS read_receipt) that their messages are now read.
      // ignore: discarded_futures
      chat.markRoomAsRead(widget.roomId);
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
      // 태블릿/폴드 펼침 모드에서 채팅창이 가로로 무한정 늘어나지 않도록 600dp 제한.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.maxFeedWidth),
          child: Column(
            children: [
              if (widget.productTitle != null) _ProductBanner(title: widget.productTitle!),
              Expanded(
                child: messages.isEmpty
                    ? _EmptyChat(peerNickname: widget.peerNickname)
                    : Builder(
                        builder: (_) {
                          // Look up this room's peerLastReadAt so each of my
                          // outgoing bubbles can show "읽음" once the peer's
                          // last_read_at >= that message's sent_at.
                          DateTime? peerReadAt;
                          try {
                            final room = chat.rooms.firstWhere(
                              (r) => r.id == widget.roomId,
                            );
                            peerReadAt = room.peerLastReadAt;
                          } catch (_) {
                            peerReadAt = null;
                          }
                          return ListView.builder(
                            controller: _scrollCtl,
                            padding: const EdgeInsets.all(16),
                            itemCount: messages.length,
                            itemBuilder: (_, i) {
                              final msg = messages[i];
                              if (msg.type == 'price_offer' && msg.offer != null) {
                                return _PriceOfferCard(
                                  message: msg,
                                  myUserId: auth.user?.id,
                                  onRespond: (action) =>
                                      _respondToOffer(msg.offer!.id, action),
                                );
                              }
                              return _MessageBubble(
                                message: msg,
                                peerLastReadAt: peerReadAt,
                              );
                            },
                          );
                        },
                      ),
              ),
              _InputBar(
                controller: _ctl,
                onSend: _send,
                connected: chat.connected,
                // Price-offer button only makes sense in product-tied rooms.
                onOffer: widget.productTitle != null ? () => _openOfferSheet() : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Price offer flow ────────────────────────────────────────────────

  Future<void> _openOfferSheet() async {
    final priceCtl = TextEditingController();
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: EggplantColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '💰 가격 제안하기',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                widget.productTitle ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: EggplantColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceCtl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: '제안 금액 (원)',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  filled: true,
                  fillColor: EggplantColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n > 0) Navigator.pop(sheetCtx, n);
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EggplantColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    final n = int.tryParse(priceCtl.text);
                    if (n != null && n > 0) Navigator.pop(sheetCtx, n);
                  },
                  child: const Text(
                    '제안 보내기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '이전에 보낸 미응답 제안은 자동으로 취소돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: EggplantColors.textSecondary),
              ),
            ],
          ),
        );
      },
    );
    priceCtl.dispose();
    if (result == null || result <= 0) return;
    if (!mounted) return;
    final err = await context.read<ChatService>().sendPriceOffer(widget.roomId, result);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
    }
  }

  Future<void> _respondToOffer(String offerId, String action) async {
    final label = action == 'accept'
        ? '수락'
        : action == 'reject'
            ? '거절'
            : '취소';
    // Confirm only the destructive ones.
    if (action != 'cancel') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('가격 제안 $label'),
          content: Text(action == 'accept'
              ? '이 가격에 거래를 진행하시겠어요?'
              : '제안을 거절할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(_, true),
              style: TextButton.styleFrom(
                foregroundColor: action == 'accept'
                    ? EggplantColors.primary
                    : EggplantColors.error,
              ),
              child: Text(label),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    final err = await context
        .read<ChatService>()
        .respondToOffer(offerId, action, roomId: widget.roomId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
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
  /// When the peer last read THIS room. If non-null and >= message.sentAt,
  /// the bubble shows "읽음" instead of just the timestamp.
  final DateTime? peerLastReadAt;
  const _MessageBubble({required this.message, this.peerLastReadAt});

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
    // For my own messages: was this seen by the peer yet?
    final read = mine &&
        peerLastReadAt != null &&
        !message.sentAt.isAfter(peerLastReadAt!);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mine) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (read)
                  const Text(
                    '읽음',
                    style: TextStyle(
                      fontSize: 10,
                      color: EggplantColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 10,
                    color: EggplantColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
          // 버블이 가로로 너무 길어지지 않도록 화면폭의 약 72% 까지만 사용.
          // (시간/읽음 표시를 위한 좌우 여백 확보 + 태블릿/폴드에서도 자연스러운 길이)
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
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
  /// 가격 제안 버튼 핸들러. null 이면 버튼 숨김 (상품 첨부되지 않은 방).
  final VoidCallback? onOffer;

  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.connected,
    this.onOffer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: EggplantColors.border)),
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 10,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          if (onOffer != null)
            IconButton(
              tooltip: '가격 제안',
              icon: const Icon(
                Icons.payments_outlined,
                color: EggplantColors.primary,
              ),
              onPressed: onOffer,
            ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: connected ? '메시지 입력' : '연결 중...',
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

/// 가격 제안(price_offer) 메시지 전용 풍선.
///
/// 상태(pending/accepted/rejected/cancelled)에 따라 색상과 액션 버튼이 달라진다.
///   - pending + 내가 판매자: [거절] [수락] 두 버튼
///   - pending + 내가 구매자: [제안 취소] 버튼
///   - 그 외(이미 처리된 제안): 상태 칩만
class _PriceOfferCard extends StatelessWidget {
  final ChatMessage message;
  final String? myUserId;
  final void Function(String action) onRespond;

  const _PriceOfferCard({
    required this.message,
    required this.myUserId,
    required this.onRespond,
  });

  @override
  Widget build(BuildContext context) {
    final offer = message.offer!;
    final mine = message.isMine;
    final iAmSeller = myUserId != null && myUserId == offer.sellerId;
    final iAmBuyer = myUserId != null && myUserId == offer.buyerId;

    final time = DateFormat('HH:mm').format(message.sentAt);
    final accent = _accentForStatus(offer.status);
    final bg = _bgForStatus(offer.status);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mine) ...[
            Text(
              time,
              style: const TextStyle(
                fontSize: 10,
                color: EggplantColors.textTertiary,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 16),
                  ),
                  border: Border.all(color: accent.withOpacity(0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.payments_rounded, size: 16, color: accent),
                        const SizedBox(width: 6),
                        const Text(
                          '가격 제안',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: EggplantColors.textSecondary,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            offer.statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      offer.priceLabel,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: EggplantColors.textPrimary,
                      ),
                    ),
                    if (offer.isPending) ...[
                      const SizedBox(height: 10),
                      _buildActionRow(iAmSeller, iAmBuyer),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (!mine) ...[
            const SizedBox(width: 4),
            Text(
              time,
              style: const TextStyle(
                fontSize: 10,
                color: EggplantColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionRow(bool iAmSeller, bool iAmBuyer) {
    if (iAmSeller) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: EggplantColors.error,
                side: const BorderSide(color: EggplantColors.error),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => onRespond('reject'),
              child: const Text(
                '거절',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: EggplantColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => onRespond('accept'),
              child: const Text(
                '수락',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      );
    }
    if (iAmBuyer) {
      return SizedBox(
        width: double.infinity,
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: EggplantColors.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 6),
          ),
          onPressed: () => onRespond('cancel'),
          child: const Text(
            '제안 취소하기',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Color _accentForStatus(String status) {
    switch (status) {
      case 'accepted':
        return EggplantColors.primary;
      case 'rejected':
        return EggplantColors.error;
      case 'cancelled':
        return EggplantColors.textSecondary;
      case 'pending':
      default:
        return EggplantColors.primary;
    }
  }

  Color _bgForStatus(String status) {
    switch (status) {
      case 'accepted':
        return const Color(0xFFEEF7F0); // soft green-ish
      case 'rejected':
        return const Color(0xFFFDECEC);
      case 'cancelled':
        return const Color(0xFFF3F4F6);
      case 'pending':
      default:
        return Colors.white;
    }
  }
}
