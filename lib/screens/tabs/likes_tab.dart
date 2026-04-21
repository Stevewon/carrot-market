import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../widgets/product_card.dart';

class LikesTab extends StatefulWidget {
  const LikesTab({super.key});

  @override
  State<LikesTab> createState() => _LikesTabState();
}

class _LikesTabState extends State<LikesTab> {
  List<Product> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await context.read<ProductService>().fetchMyLikes();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('찜한 상품')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: EggplantColors.primary))
          : _items.isEmpty
              ? const Center(
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
                )
              : RefreshIndicator(
                  color: EggplantColors.primary,
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: EggplantColors.border,
                      indent: 16,
                      endIndent: 16,
                    ),
                    itemBuilder: (_, i) {
                      final p = _items[i];
                      return ProductCard(
                        product: p,
                        onTap: () => context.push('/product/${p.id}'),
                      );
                    },
                  ),
                ),
    );
  }
}
