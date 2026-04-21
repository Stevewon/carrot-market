import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/constants.dart';
import '../app/theme.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/product_service.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Product? _product;
  bool _loading = true;
  bool _liked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await context.read<ProductService>().fetchById(widget.productId);
    if (!mounted) return;
    setState(() {
      _product = p;
      _liked = p?.isLiked ?? false;
      _loading = false;
    });
  }

  Future<void> _toggleLike() async {
    final p = _product;
    if (p == null) return;
    final ok = await context.read<ProductService>().toggleLike(p.id);
    if (ok && mounted) setState(() => _liked = !_liked);
  }

  void _startChat() {
    final p = _product;
    final user = context.read<AuthService>().user;
    if (p == null || user == null) return;

    if (p.sellerId == user.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내가 등록한 상품이에요')),
      );
      return;
    }

    final roomId = ChatService.roomIdFor(user.id, p.sellerId, productId: p.id);
    context.push(
      '/chat/$roomId?peer=${Uri.encodeComponent(p.sellerNickname)}&product=${Uri.encodeComponent(p.title)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: EggplantColors.primary)),
      );
    }
    final p = _product;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('상품을 찾을 수 없어요')),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 360,
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.white,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.pop(),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _ImageCarousel(images: p.images),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SellerRow(product: p),
                  const Divider(height: 32),
                  Text(
                    p.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: EggplantColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${Categories.find(p.category).label} · ${p.timeAgo}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: EggplantColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    p.description,
                    style: const TextStyle(
                      fontSize: 15,
                      color: EggplantColors.textPrimary,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.visibility_outlined,
                          size: 14, color: EggplantColors.textTertiary),
                      const SizedBox(width: 4),
                      Text('조회 ${p.viewCount}',
                          style: const TextStyle(
                              fontSize: 12, color: EggplantColors.textTertiary)),
                      const SizedBox(width: 12),
                      const Icon(Icons.favorite_border,
                          size: 14, color: EggplantColors.textTertiary),
                      const SizedBox(width: 4),
                      Text('관심 ${p.likeCount}',
                          style: const TextStyle(
                              fontSize: 12, color: EggplantColors.textTertiary)),
                      const SizedBox(width: 12),
                      const Icon(Icons.chat_bubble_outline,
                          size: 14, color: EggplantColors.textTertiary),
                      const SizedBox(width: 4),
                      Text('채팅 ${p.chatCount}',
                          style: const TextStyle(
                              fontSize: 12, color: EggplantColors.textTertiary)),
                    ],
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: EggplantColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 12 + MediaQuery.of(context).padding.bottom,
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                _liked ? Icons.favorite : Icons.favorite_border,
                color: _liked ? EggplantColors.primary : EggplantColors.textSecondary,
                size: 28,
              ),
              onPressed: _toggleLike,
            ),
            Container(height: 32, width: 1, color: EggplantColors.border),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.priceFormatted,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  const Text('가격 제안 가능',
                      style: TextStyle(
                          fontSize: 12, color: EggplantColors.primary)),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _startChat,
              icon: const Icon(Icons.chat_bubble, color: Colors.white, size: 18),
              label: const Text('채팅하기', style: TextStyle(fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageCarousel extends StatefulWidget {
  final List<String> images;
  const _ImageCarousel({required this.images});

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  int _index = 0;
  final _ctl = PageController();

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Container(
        color: EggplantColors.background,
        child: Center(
          child: Image.asset('assets/images/eggplant-mascot.png',
              width: 120, height: 120),
        ),
      );
    }
    return Stack(
      children: [
        PageView.builder(
          controller: _ctl,
          itemCount: widget.images.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) {
            final url = widget.images[i];
            final fullUrl = url.startsWith('http')
                ? url
                : '${AppConfig.apiBase}${url.startsWith('/') ? '' : '/'}$url';
            return CachedNetworkImage(
              imageUrl: fullUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (_, __) => Container(color: EggplantColors.background),
              errorWidget: (_, __, ___) =>
                  Container(color: EggplantColors.background),
            );
          },
        ),
        if (widget.images.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.images.length,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SellerRow extends StatelessWidget {
  final Product product;
  const _SellerRow({required this.product});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: EggplantColors.background,
            border: Border.all(color: EggplantColors.primaryLight),
          ),
          child: ClipOval(
            child: Image.asset('assets/images/eggplant-mascot.png'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.sellerNickname,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              Text(product.region,
                  style: const TextStyle(
                      fontSize: 12, color: EggplantColors.textSecondary)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: EggplantColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${product.sellerMannerScore}.5°C',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: EggplantColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}
