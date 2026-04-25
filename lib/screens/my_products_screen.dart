import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../widgets/product_card.dart';

/// Shows the products the current user has uploaded.
///
/// Everything is backed by [ProductService.mySelling] so it stays in sync
/// across the app (delete / status change / new upload are reflected
/// immediately thanks to [ChangeNotifier]).
class MyProductsScreen extends StatefulWidget {
  const MyProductsScreen({super.key});

  @override
  State<MyProductsScreen> createState() => _MyProductsScreenState();
}

class _MyProductsScreenState extends State<MyProductsScreen> {
  @override
  void initState() {
    super.initState();
    // Always refetch on entry so the count / statuses are current.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductService>().fetchMyProducts(silent: false);
    });
  }

  Future<void> _refresh() =>
      context.read<ProductService>().fetchMyProducts(silent: true);

  Future<void> _bump(Product p) async {
    if (!p.canBump) {
      // Show how long until they can bump again.
      final remaining = p.bumpCooldownRemaining;
      final h = remaining.inHours;
      final m = remaining.inMinutes - h * 60;
      final wait = h > 0 ? '$h시간 ${m}분' : '${m}분';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$wait 후에 다시 끌어올릴 수 있어요')),
      );
      return;
    }
    final err = await context.read<ProductService>().bumpProduct(p.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? '🍆 끌어올렸어요! 피드 맨 위로 올라갔어요')),
    );
  }

  Future<void> _confirmDelete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('상품 삭제'),
        content: Text('${p.title}을(를) 정말 삭제할까요?\n\n'
            '• 상품과 사진/영상이 영구 삭제돼요\n'
            '• 복구할 수 없어요'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: EggplantColors.error),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<ProductService>().deleteProduct(p.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? '상품을 삭제했어요')),
    );
  }

  Future<void> _changeStatus(Product p) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusTile(ctx, 'sale', '판매중', Icons.sell_outlined, p.status == 'sale'),
            _statusTile(ctx, 'reserved', '예약중', Icons.schedule_outlined, p.status == 'reserved'),
            _statusTile(ctx, 'sold', '거래완료', Icons.check_circle_outline, p.status == 'sold'),
          ],
        ),
      ),
    );
    if (picked == null || picked == p.status || !mounted) return;
    final err = await context.read<ProductService>().updateStatus(p.id, picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? '상태를 변경했어요')),
    );
  }

  ListTile _statusTile(
    BuildContext ctx,
    String value,
    String label,
    IconData icon,
    bool selected,
  ) {
    return ListTile(
      leading: Icon(icon,
          color: selected ? EggplantColors.primary : EggplantColors.textSecondary),
      title: Text(label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? EggplantColors.primary : EggplantColors.textPrimary,
          )),
      trailing: selected
          ? const Icon(Icons.check, color: EggplantColors.primary)
          : null,
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ProductService>();
    final items = svc.mySelling;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          items.isEmpty ? '내 판매상품' : '내 판매상품 ${items.length}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        color: EggplantColors.primary,
        onRefresh: _refresh,
        child: _body(svc, items),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/product/new'),
        backgroundColor: EggplantColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_outlined, size: 20),
        label: const Text('새 글쓰기',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }

  Widget _body(ProductService svc, List<Product> items) {
    if (svc.mySellingLoading && items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: EggplantColors.primary),
      );
    }
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Text('🍆', style: TextStyle(fontSize: 56)),
                SizedBox(height: 12),
                Text('등록한 상품이 없어요',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: EggplantColors.textPrimary,
                    )),
                SizedBox(height: 6),
                Text('우측 하단 "새 글쓰기"로 올려보세요',
                    style: TextStyle(
                      fontSize: 13,
                      color: EggplantColors.textSecondary,
                    )),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: EggplantColors.border,
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (_, i) {
        final p = items[i];
        return Stack(
          children: [
            ProductCard(
              product: p,
              onTap: () => context.push('/product/${p.id}'),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: PopupMenuButton<String>(
                tooltip: '끌어올리기 / 상태 변경 / 삭제',
                icon: const Icon(Icons.more_vert, color: EggplantColors.textSecondary),
                onSelected: (v) {
                  if (v == 'bump') {
                    _bump(p);
                  } else if (v == 'status') {
                    _changeStatus(p);
                  } else if (v == 'edit') {
                    context.push('/product/${p.id}/edit');
                  } else if (v == 'delete') {
                    _confirmDelete(p);
                  }
                },
                itemBuilder: (_) => [
                  // Show "끌어올리기" only for items currently for sale —
                  // sold/reserved listings can't be bumped.
                  if (p.status == 'sale')
                    PopupMenuItem(
                      value: 'bump',
                      enabled: p.canBump,
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                            color: p.canBump
                                ? EggplantColors.primary
                                : EggplantColors.textTertiary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            p.canBump ? '끌어올리기' : '끌어올리기 (대기중)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: p.canBump
                                  ? EggplantColors.primary
                                  : EggplantColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('수정'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'status',
                    child: Row(
                      children: [
                        Icon(Icons.edit_note, size: 20),
                        SizedBox(width: 8),
                        Text('상태 변경'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 20, color: EggplantColors.error),
                        SizedBox(width: 8),
                        Text('삭제', style: TextStyle(color: EggplantColors.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
