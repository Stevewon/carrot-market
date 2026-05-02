import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../models/product.dart';
import '../services/hidden_products_service.dart';
import '../services/product_service.dart';
import '../widgets/product_card.dart';

/// 사용자가 "이 게시물 가리기" 한 목록을 보여주고, 다시 보이게 할 수 있는 화면.
class HiddenProductsScreen extends StatefulWidget {
  const HiddenProductsScreen({super.key});

  @override
  State<HiddenProductsScreen> createState() => _HiddenProductsScreenState();
}

class _HiddenProductsScreenState extends State<HiddenProductsScreen> {
  final List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final hidden = context.read<HiddenProductsService>();
    final svc = context.read<ProductService>();

    try {
      await hidden.load(force: true).timeout(const Duration(seconds: 15));
      final ids = hidden.ids.toList();
      final results = <Product>[];
      // ID 별로 fetch — 보통 숨김 목록은 작아서(<100) 부담 적음.
      // 각 fetch 에 짧은 timeout 을 줘서 한 항목이 막혀도 전체가 멈추지 않게.
      for (final id in ids) {
        try {
          final p = await svc.fetchById(id).timeout(const Duration(seconds: 8));
          if (p != null) results.add(p);
        } on TimeoutException {
          // 한 건 실패는 건너뜀 — 무한 로딩 방지가 핵심.
          continue;
        } catch (_) {
          continue;
        }
      }
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(results);
      });
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서버 응답이 늦어요. 잠시 후 다시 시도해주세요 🕐')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('숨긴 게시물을 불러오지 못했어요')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unhide(Product p) async {
    final ok = await context.read<HiddenProductsService>().unhide(p.id);
    if (!mounted) return;
    if (ok) {
      setState(() => _products.removeWhere((x) => x.id == p.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${p.title}" 다시 보여요')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('숨김 해제 실패')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EggplantColors.background,
      appBar: AppBar(
        title: const Text('숨긴 게시물'),
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? const _Empty()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _products.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = _products[i];
                      return Stack(
                        children: [
                          ProductCard(
                            product: p,
                            onTap: () => context.push('/product/${p.id}'),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: TextButton.icon(
                              onPressed: () => _unhide(p),
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 18,
                              ),
                              label: const Text('숨김 해제'),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.9),
                                foregroundColor: EggplantColors.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(
                                    color: EggplantColors.border,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.visibility_off_outlined,
            size: 56,
            color: EggplantColors.textTertiary,
          ),
          SizedBox(height: 12),
          Text(
            '숨긴 게시물이 없어요',
            style: TextStyle(
              fontSize: 15,
              color: EggplantColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '게시물 우측 상단의 ⋯ 메뉴에서 가릴 수 있어요',
            style: TextStyle(
              fontSize: 13,
              color: EggplantColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
