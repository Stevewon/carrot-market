import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/theme.dart';
import '../../models/chat_room.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';

class ChatListTab extends StatefulWidget {
  const ChatListTab({super.key});

  @override
  State<ChatListTab> createState() => _ChatListTabState();
}

class _ChatListTabState extends State<ChatListTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatService>();
      chat.connect();
      chat.fetchRooms();
    });
  }

  Future<void> _confirmDelete(ChatRoom room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('채팅방 나가기'),
        content: Text(
          '${room.peerNickname}님과의 대화를 완전히 삭제할까요?\n\n'
          '• 주고받은 모든 메시지가 사라져요\n'
          '• 상대방 화면에서도 함께 삭제돼요\n'
          '• 복구할 수 없어요',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: EggplantColors.error),
            child: const Text('완전히 삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final ok = await context.read<ChatService>().deleteRoom(room.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '채팅방을 삭제했어요' : '삭제 실패. 잠시 후 다시 시도해주세요')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatService>();
    final auth = context.watch<AuthService>();
    final me = auth.user?.id;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('채팅', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'QR 스캔해서 대화 시작',
            onPressed: () => context.push('/qr/scan'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 사생활 보호 안내 배너 — 휘발성 채팅임을 항상 인식할 수 있도록.
          Container(
            width: double.infinity,
            color: EggplantColors.background,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: const Row(
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 14, color: EggplantColors.primary),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '대화는 어디에도 저장되지 않아요. 앱을 닫으면 사라져요.',
                    style: TextStyle(
                      fontSize: 12,
                      color: EggplantColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => chat.fetchRooms(silent: true),
              child: _buildBody(chat, me),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ChatService chat, String? me) {
    if (chat.roomsLoading && chat.rooms.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (chat.rooms.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: EggplantColors.background,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded,
                      size: 44, color: EggplantColors.primary),
                ),
                const SizedBox(height: 18),
                const Text('아직 대화가 없어요',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: EggplantColors.textPrimary)),
                const SizedBox(height: 6),
                const Text('관심있는 상품에서 "채팅하기"를 눌러보세요',
                    style: TextStyle(fontSize: 13, color: EggplantColors.textSecondary)),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      itemCount: chat.rooms.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 0.5,
        indent: 76,
        color: EggplantColors.border,
      ),
      itemBuilder: (context, i) {
        final room = chat.rooms[i];
        return _RoomTile(
          room: room,
          isMineLastMsg: me != null && room.lastSenderId == me,
          onTap: () {
            context.push(
              '/chat/${room.id}?peer=${Uri.encodeComponent(room.peerNickname)}'
              '${room.peerId.isNotEmpty ? '&peerId=${room.peerId}' : ''}'
              '${room.productTitle != null ? '&product=${Uri.encodeComponent(room.productTitle!)}' : ''}'
              '${room.productId != null ? '&productId=${Uri.encodeComponent(room.productId!)}' : ''}',
            );
          },
          onLongPress: () => _confirmDelete(room),
          onDelete: () => _confirmDelete(room),
        );
      },
    );
  }
}

class _RoomTile extends StatelessWidget {
  final ChatRoom room;
  final bool isMineLastMsg;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const _RoomTile({
    required this.room,
    required this.isMineLastMsg,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(room.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false; // onDelete triggers the dialog; don't auto-remove here
      },
      background: Container(
        color: EggplantColors.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white),
            SizedBox(width: 6),
            Text('나가기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              _Avatar(nickname: room.peerNickname, thumbPath: room.productThumb),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            room.peerNickname,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              // Unread rooms get bolder name + darker color.
                              fontWeight: room.unreadCount > 0
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: EggplantColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          room.timeAgo,
                          style: const TextStyle(
                            fontSize: 11,
                            color: EggplantColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      room.lastMessage.isEmpty
                          ? (room.productTitle != null
                              ? '${room.productTitle} 관련 대화'
                              : '메시지를 보내보세요')
                          : (isMineLastMsg ? '나: ${room.lastMessage}' : room.lastMessage),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        // Unread → darker preview text + slightly bolder.
                        color: room.unreadCount > 0
                            ? EggplantColors.textPrimary
                            : (room.lastMessage.isEmpty
                                ? EggplantColors.textTertiary
                                : EggplantColors.textSecondary),
                        fontWeight: room.unreadCount > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              // Right side: thumbnail + unread badge (당근식 빨간 점/숫자)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (room.productThumb != null && room.productThumb!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: _absUrl(room.productThumb!),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            width: 44,
                            height: 44,
                            color: EggplantColors.background,
                          ),
                        ),
                      ),
                    ),
                  if (room.unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: EggplantColors.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        room.unreadCount > 99 ? '99+' : '${room.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _absUrl(String path) {
    if (path.startsWith('http')) return path;
    return '${AppConfig.apiBase}${path.startsWith('/') ? '' : '/'}$path';
  }
}

class _Avatar extends StatelessWidget {
  final String nickname;
  final String? thumbPath;

  const _Avatar({required this.nickname, this.thumbPath});

  @override
  Widget build(BuildContext context) {
    final initial = nickname.isNotEmpty ? nickname.characters.first : '🍆';
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: EggplantColors.primaryLight.withValues(alpha: 0.25),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: EggplantColors.primaryDark,
        ),
      ),
    );
  }
}
