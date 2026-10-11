import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/qta_service.dart';
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
      final wait = h > 0
          ? context.l10n.productWaitHoursMinutes(h, m)
          : context.l10n.productWaitMinutes(m);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.productBumpWait(wait))),
      );
      return;
    }
    final err = await context.read<ProductService>().bumpProduct(p.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? context.l10n.productBumped)),
    );
  }

  Future<void> _confirmDelete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.productDeleteDialogTitle),
        content: Text('${ctx.l10n.productDeleteConfirmNamed(p.title)}\n\n'
            '${ctx.l10n.productDeleteBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: EggplantColors.error),
            child: Text(ctx.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ps = context.read<ProductService>();
    final err = await ps.deleteProduct(p.id);
    if (!mounted) return;
    final clawback = err == null ? ps.lastListingClawback : 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ??
            (clawback > 0
                ? context.l10n.productDeletedWithClawback(clawback)
                : context.l10n.productDeleted)),
      ),
    );
    if (clawback > 0) context.read<QtaService>().load(force: true);
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
            _statusTile(ctx, 'sale', ctx.l10n.productStatusSale, Icons.sell_outlined, p.status == 'sale'),
            _statusTile(ctx, 'reserved', ctx.l10n.productStatusReserved, Icons.schedule_outlined, p.status == 'reserved'),
            _statusTile(ctx, 'sold', ctx.l10n.productStatusSold, Icons.check_circle_outline, p.status == 'sold'),
          ],
        ),
      ),
    );
    if (picked == null || picked == p.status || !mounted) return;
    final err = await context.read<ProductService>().updateStatus(p.id, picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? context.l10n.productStatusChangedGeneric)),
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
          items.isEmpty
              ? context.l10n.productMySelling
              : context.l10n.productMySellingCount(items.length),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
        label: Text(context.l10n.productNewPost,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                const Text('🍆', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(context.l10n.productMySellingEmpty,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: EggplantColors.textPrimary,
                    )),
                const SizedBox(height: 6),
                Text(context.l10n.productMySellingEmptyHint,
                    style: const TextStyle(
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
                tooltip: context.l10n.productMyMenuTooltip,
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
                            p.canBump
                                ? context.l10n.productBump
                                : context.l10n.productBumpWaiting,
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
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text(context.l10n.productEdit),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'status',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_note, size: 20),
                        const SizedBox(width: 8),
                        Text(context.l10n.productChangeStatus),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline,
                            size: 20, color: EggplantColors.error),
                        const SizedBox(width: 8),
                        Text(context.l10n.commonDelete, style: const TextStyle(color: EggplantColors.error)),
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
