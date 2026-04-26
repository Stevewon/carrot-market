import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../widgets/product_card.dart';

/// "찜" tab — backed by [ProductService.myLikes].
///
/// Because the service is a [ChangeNotifier] and every like/unlike/delete
/// updates the cache, this screen is automatically in sync with the rest of
/// the app. No manual re-fetch needed on tab switches.
class LikesTab extends StatefulWidget {
  const LikesTab({super.key});

  @override
  State<LikesTab> createState() => _LikesTabState();
}

class _LikesTabState extends State<LikesTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = context.read<ProductService>();
      svc.fetchMyLikes(silent: svc.myLikesLoaded);
    });
  }

  Future<void> _refresh() =>
      context.read<ProductService>().fetchMyLikes(silent: true);

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ProductService>();
    final items = svc.myLikes;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          items.isEmpty ? '찜한 상품' : '찜한 상품 ${items.length}',
        ),
      ),
      // 태블릿/폴드 펼침에서 600dp 가운데 정렬.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.maxFeedWidth),
          child: RefreshIndicator(
            color: EggplantColors.primary,
            onRefresh: _refresh,
            child: _body(svc, items),
          ),
        ),
      ),
    );
  }

  Widget _body(ProductService svc, List<Product> items) {
    if (svc.myLikesLoading && items.isEmpty) {
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('💜', style: TextStyle(fontSize: 56)),
                SizedBox(height: 12),
                Text(
                  '찜한 상품이 없어요',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: EggplantColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '관심있는 상품에 하트를 눌러보세요',
                  style: TextStyle(
                    fontSize: 13,
                    color: EggplantColors.textSecondary,
                  ),
                ),
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
        return ProductCard(
          product: p,
          onTap: () => context.push('/product/${p.id}'),
        );
      },
    );
  }
}
