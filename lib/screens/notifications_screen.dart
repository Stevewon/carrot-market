import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/constants.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../services/inbox_service.dart';

/// 알림함 (당근식) — 가격 내림 · 거래 확인 · 거래 후기 · 키워드 알림을 한곳에서.
/// 열면 모두 읽음, 밀어서 하나 지우기, 위 버튼으로 모두 지우기.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// 화면을 열 때 안 읽었던 알림 — 읽음 처리한 뒤에도 이번에는 계속 표시해 준다.
  Set<String> _fresh = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final box = context.read<InboxService>();
      await box.load();
      if (!mounted) return;
      setState(() => _fresh = {for (final n in box.items) if (!n.read) n.id});
      await box.markAllRead();
    });
  }

  Future<void> _clearAll(InboxService box) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.l10n.inboxClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok == true) await box.clearAll();
  }

  void _open(InboxItem n) {
    if (n.productId != null) {
      context.push('/product/${n.productId}');
    } else if (n.targetUserId != null) {
      context.push('/user/${n.targetUserId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = context.watch<InboxService>();
    final items = box.items;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(context.l10n.inboxTitle),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => _clearAll(box),
              child: Text(context.l10n.homeClearAll,
                  style: const TextStyle(color: EggplantColors.textSecondary)),
            ),
        ],
      ),
      body: box.loading && !box.loaded && items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: EggplantColors.primary,
              onRefresh: box.load,
              child: items.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        const Icon(Icons.notifications_none_rounded,
                            size: 56, color: EggplantColors.textTertiary),
                        const SizedBox(height: 12),
                        Text(
                          box.error != null && !box.loaded
                              ? context.l10n.inboxLoadFailed
                              : context.l10n.inboxEmpty,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            context.l10n.inboxEmptyHint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 13, color: EggplantColors.textSecondary),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: EggplantColors.border),
                      itemBuilder: (_, i) {
                        final n = items[i];
                        return Dismissible(
                          key: ValueKey(n.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red[400],
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                          onDismissed: (_) => box.remove(n),
                          child: _InboxTile(item: n, fresh: _fresh.contains(n.id), onTap: () => _open(n)),
                        );
                      },
                    ),
            ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  final InboxItem item;
  final bool fresh;
  final VoidCallback onTap;
  const _InboxTile({required this.item, required this.fresh, required this.onTap});

  static (IconData, Color) _icon(String type) {
    switch (type) {
      case 'price_drop':
        return (Icons.trending_down_rounded, const Color(0xFF16A34A));
      case 'purchase_confirm':
        return (Icons.handshake_outlined, EggplantColors.primary);
      case 'review_request':
      case 'review_received':
        return (Icons.rate_review_outlined, const Color(0xFFF59E0B));
      case 'keyword_alert':
        return (Icons.sell_outlined, EggplantColors.primary);
      default:
        return (Icons.notifications_none_rounded, EggplantColors.textSecondary);
    }
  }

  String _ago(BuildContext context) {
    final t = context.l10n;
    final d = DateTime.now().difference(item.createdAt);
    if (d.inMinutes < 1) return t.productTimeJustNow;
    if (d.inHours < 1) return t.productTimeMinutesAgo(d.inMinutes);
    if (d.inDays < 1) return t.productTimeHoursAgo(d.inHours);
    return t.productTimeDaysAgo(d.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _icon(item.type);
    final thumb = item.thumb;
    final thumbUrl = thumb == null
        ? null
        : thumb.startsWith('http')
            ? thumb
            : '${AppConfig.apiBase}${thumb.startsWith('/') ? '' : '/'}$thumb';
    return InkWell(
      onTap: onTap,
      child: Container(
        color: fresh ? EggplantColors.primary.withValues(alpha: 0.05) : Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: fresh ? FontWeight.w800 : FontWeight.w600,
                      color: EggplantColors.textPrimary,
                    ),
                  ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _ago(context),
                    style: const TextStyle(fontSize: 12, color: EggplantColors.textTertiary),
                  ),
                ],
              ),
            ),
            if (thumbUrl != null) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: thumbUrl,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox(width: 52, height: 52),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
