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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
    // ★ 7차 푸시 (이슈 1): 에러 상태 분기 — 사용자에게 재시도 버튼 노출.
    //  네트워크 일시 오류 시 빈 화면 고착 방지.
    if (svc.myLikesError != null && items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(
                  svc.myLikesError ?? '불러올 수 없어요',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: EggplantColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  '잠시 후 다시 시도해주세요',
                  style: TextStyle(
                    fontSize: 13,
                    color: EggplantColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => svc.fetchMyLikes(silent: false),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('다시 시도'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EggplantColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(140, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
