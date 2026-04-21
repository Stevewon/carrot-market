import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/theme.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/product_service.dart';
import '../../widgets/product_card.dart';

class FeedTab extends StatefulWidget {
  const FeedTab({super.key});

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  String _category = 'all';
  final TextEditingController _searchCtl = TextEditingController();
  bool _searchMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final auth = context.read<AuthService>();
    context.read<ProductService>().fetchProducts(
          category: _category,
          region: auth.user?.region,
          search: _searchCtl.text.isEmpty ? null : _searchCtl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final productSvc = context.watch<ProductService>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: _searchMode
            ? TextField(
                controller: _searchCtl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '상품명 검색',
                  border: InputBorder.none,
                  filled: false,
                ),
                onSubmitted: (_) => _load(),
              )
            : GestureDetector(
                onTap: () => context.push('/region'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      auth.user?.region ?? '동네 설정',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down),
                  ],
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_searchMode ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searchMode = !_searchMode;
                if (!_searchMode) {
                  _searchCtl.clear();
                  _load();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'QR 스캔',
            onPressed: () => context.push('/qr/scan'),
          ),
        ],
      ),
      body: Column(
        children: [
          _CategoryBar(
            selected: _category,
            onSelected: (id) {
              setState(() => _category = id);
              _load();
            },
          ),
          const Divider(height: 1, color: EggplantColors.border),
          Expanded(
            child: productSvc.loading && productSvc.products.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: EggplantColors.primary),
                  )
                : productSvc.products.isEmpty
                    ? _EmptyView(onRefresh: _load)
                    : RefreshIndicator(
                        color: EggplantColors.primary,
                        onRefresh: () async => _load(),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: productSvc.products.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            color: EggplantColors.border,
                            indent: 16,
                            endIndent: 16,
                          ),
                          itemBuilder: (_, i) {
                            final p = productSvc.products[i];
                            return ProductCard(
                              product: p,
                              onTap: () => context.push('/product/${p.id}'),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _CategoryBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: Categories.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final c = Categories.all[i];
          final isSelected = c.id == selected;
          return InkWell(
            onTap: () => onSelected(c.id),
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? EggplantColors.primary : EggplantColors.background,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: isSelected ? EggplantColors.primary : EggplantColors.border,
                ),
              ),
              child: Row(
                children: [
                  Text(c.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    c.label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : EggplantColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyView({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🍆', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          const Text(
            '아직 상품이 없어요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: EggplantColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '첫 번째 상품을 등록해보세요!',
            style: TextStyle(
              fontSize: 13,
              color: EggplantColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('새로고침'),
          ),
        ],
      ),
    );
  }
}
