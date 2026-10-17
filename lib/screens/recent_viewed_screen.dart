import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../services/recent_viewed_service.dart';
import '../widgets/product_card.dart';

/// 최근 본 상품 (당근식) — 이 폰에만 저장된 최근 30개. 밀어서 하나 지우기.
class RecentViewedScreen extends StatelessWidget {
  const RecentViewedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<RecentViewedService>();
    final items = svc.items;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(context.l10n.recentTitle),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: svc.clear,
              child: Text(context.l10n.homeClearAll,
                  style: const TextStyle(color: EggplantColors.textSecondary)),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history_rounded, size: 56, color: EggplantColors.textTertiary),
                    const SizedBox(height: 12),
                    Text(context.l10n.recentEmpty,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: EggplantColors.border),
              itemBuilder: (_, i) {
                final p = items[i];
                return Dismissible(
                  key: ValueKey(p.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red[400],
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  onDismissed: (_) => svc.remove(p.id),
                  child: ProductCard(
                    product: p,
                    onTap: () => context.push('/product/${p.id}'),
                  ),
                );
              },
            ),
    );
  }
}
