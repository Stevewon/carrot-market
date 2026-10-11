import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/responsive.dart';
import '../app/theme.dart';
import '../models/product.dart';
import '../models/review.dart';
import '../services/product_service.dart';
import '../widgets/product_card.dart';
import '../widgets/review_sheet.dart';

/// 구매 내역 — 판매자가 나를 구매자로 지정한 거래완료 상품.
/// 각 상품에서 바로 "거래 후기 보내기" / "보낸 후기 보기" (당근 구매내역과 같은 흐름).
class MyPurchasesScreen extends StatefulWidget {
  const MyPurchasesScreen({super.key});

  @override
  State<MyPurchasesScreen> createState() => _MyPurchasesScreenState();
}

class _MyPurchasesScreenState extends State<MyPurchasesScreen> {
  List<Product>? _items;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final list = await context.read<ProductService>().fetchMyPurchases();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = list == null;
      _items = list ?? _items;
    });
  }

  Future<void> _sendReview(Product p) async {
    final l = context.l10n;
    final sent = await showReviewSheet(
      context,
      productId: p.id,
      counterpartNickname: p.sellerNickname.isEmpty ? l.reviewCounterpartFallback : p.sellerNickname,
      role: ReviewerRole.buyer,
      isFree: p.price == 0,
    );
    if (sent) await _load();
  }

  Future<void> _viewReview(Product p) async {
    final r = await context.read<ProductService>().fetchMyReview(p.id);
    if (!mounted || r == null) return;
    await showMyReviewSheet(context, review: r, counterpartNickname: p.sellerNickname);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final items = _items ?? const <Product>[];
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(l.reviewPurchasesTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.maxFeedWidth),
          child: RefreshIndicator(
            color: EggplantColors.primary,
            onRefresh: _load,
            child: _loading && _items == null
                ? const Center(child: CircularProgressIndicator(color: EggplantColors.primary))
                : items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 140),
                          Center(
                            child: Text(
                              _failed ? l.reviewPurchasesLoadFailed : l.reviewPurchasesEmpty,
                              style: const TextStyle(fontSize: 15, color: EggplantColors.textSecondary),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = items[i];
                          final reviewed = p.myReviewRating != null;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ProductCard(
                                product: p,
                                onTap: () => context.push('/product/${p.id}'),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                                child: reviewed
                                    ? OutlinedButton(
                                        onPressed: () => _viewReview(p),
                                        child: Text(l.reviewViewMine),
                                      )
                                    : ElevatedButton.icon(
                                        onPressed: () => _sendReview(p),
                                        icon: const Icon(Icons.rate_review_outlined, size: 18),
                                        label: Text(l.reviewSendButton),
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ),
      ),
    );
  }
}
