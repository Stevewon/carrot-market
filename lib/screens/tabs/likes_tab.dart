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
  /// ★ v1.0.113 (이슈 2): IndexedStack 으로 다른 탭과 함께 살아있어서
  ///   initState 가 1회만 실행됨 → 한두 번 본 뒤 갱신이 안 됐음.
  ///   build() 마다 dependencies 변화를 감지해 강제 fetch 하도록 수정.
  ///
  ///   - dependOnInheritedWidgetOfExactType 가 호출되는 build 단계에서
  ///     ProductService 를 watch 하므로, 좋아요/찜 해제 등 어떤 변화든
  ///     자동으로 다시 그려진다.
  ///   - 추가로 didChangeDependencies 에서 1회 silent fetch 를 걸어
  ///     탭 진입 직후에도 stale 캐시를 강제로 갱신.
  bool _firstFetchScheduled = false;
  DateTime _lastBackgroundFetch = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_firstFetchScheduled) {
      _firstFetchScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final svc = context.read<ProductService>();
        // 첫 진입: 화면이 비어있으면 로딩 표시, 캐시가 있으면 silent.
        svc.fetchMyLikes(silent: svc.myLikesLoaded);
        _lastBackgroundFetch = DateTime.now();
      });
    }
  }

  /// ★ v1.0.113 (이슈 2): build 마다 호출되는 백그라운드 리프레시.
  ///   - 5초 이상 지난 경우만 silent fetch → 빠른 build 연쇄 시 폭주 방지.
  ///   - 사용자가 BottomNav 로 찜 탭에 다시 들어오는 순간 stale 캐시가 갱신.
  void _maybeBackgroundRefresh(ProductService svc) {
    if (svc.myLikesLoading) return;
    final now = DateTime.now();
    if (now.difference(_lastBackgroundFetch).inSeconds < 5) return;
    _lastBackgroundFetch = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      svc.fetchMyLikes(silent: true);
    });
  }

  Future<void> _refresh() =>
      context.read<ProductService>().fetchMyLikes(silent: false);

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ProductService>();
    final items = svc.myLikes;
    // ★ v1.0.113 (이슈 2): build 마다 background-stale 갱신 트리거.
    _maybeBackgroundRefresh(svc);

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
