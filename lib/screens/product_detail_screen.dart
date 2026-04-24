import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

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

  bool get _isMine {
    final p = _product;
    final u = context.read<AuthService>().user;
    return p != null && u != null && p.sellerId == u.id;
  }

  Future<void> _changeStatus(String status) async {
    final p = _product;
    if (p == null) return;
    final err = await context.read<ProductService>().updateStatus(p.id, status);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    // Refresh detail so UI shows new status.
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('상태를 ${_statusLabel(status)}(으)로 변경했어요')),
    );
  }

  String _statusLabel(String s) =>
      s == 'sale' ? '판매중' : s == 'reserved' ? '예약중' : '거래완료';

  Future<void> _confirmDelete() async {
    final p = _product;
    if (p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('상품 삭제'),
        content: Text('${p.title}을(를) 정말 삭제할까요?\n\n'
            '• 상품과 사진/영상이 영구 삭제돼요\n'
            '• 복구할 수 없어요'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: EggplantColors.error),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<ProductService>().deleteProduct(p.id);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('상품을 삭제했어요')),
    );
    // Refresh feed + pop.
    context.read<ProductService>().fetchProducts(
          category: context.read<ProductService>().currentCategory,
          region: context.read<AuthService>().user?.region,
        );
    context.pop();
  }

  void _showOwnerMenu() {
    final p = _product;
    if (p == null) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusTile(
              label: '판매중',
              icon: Icons.sell_outlined,
              selected: p.status == 'sale',
              onTap: () {
                Navigator.pop(ctx);
                _changeStatus('sale');
              },
            ),
            _StatusTile(
              label: '예약중',
              icon: Icons.schedule_outlined,
              selected: p.status == 'reserved',
              onTap: () {
                Navigator.pop(ctx);
                _changeStatus('reserved');
              },
            ),
            _StatusTile(
              label: '거래완료',
              icon: Icons.check_circle_outline,
              selected: p.status == 'sold',
              onTap: () {
                Navigator.pop(ctx);
                _changeStatus('sold');
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: EggplantColors.primary),
              title: const Text('상품 수정',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () async {
                Navigator.pop(ctx);
                await context.push('/product/${p.id}/edit');
                // Reload after returning so UI shows latest values.
                if (mounted) _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: EggplantColors.error),
              title: const Text('상품 삭제',
                  style: TextStyle(color: EggplantColors.error, fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startChat() async {
    final p = _product;
    final user = context.read<AuthService>().user;
    if (p == null || user == null) return;

    if (p.sellerId == user.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내가 등록한 상품이에요')),
      );
      return;
    }

    final chat = context.read<ChatService>();
    final room = await chat.openRoomWithPeer(
      peerUserId: p.sellerId,
      productId: p.id,
      productTitle: p.title,
      productThumb: p.images.isNotEmpty ? p.images.first : null,
    );
    if (!mounted) return;
    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('채팅방을 열지 못했어요. 잠시 후 다시 시도해주세요')),
      );
      return;
    }

    context.push(
      '/chat/${room.id}?peer=${Uri.encodeComponent(p.sellerNickname)}'
      '&product=${Uri.encodeComponent(p.title)}'
      '&peerId=${Uri.encodeComponent(p.sellerId)}',
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
            actions: [
              if (_isMine)
                Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    tooltip: '상태 변경 / 삭제',
                    onPressed: _showOwnerMenu,
                  ),
                ),
            ],
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
                  if (p.hasVideo) ...[
                    const SizedBox(height: 20),
                    const Text(
                      '영상',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: EggplantColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ProductVideo(product: p),
                  ],
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
        child: _isMine ? _OwnerBottomBar(product: p, onMenu: _showOwnerMenu)
            : Row(
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
        if (widget.images.length > 1) ...[
          // Page dots (bottom center)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.images.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: i == _index
                        ? Colors.white
                        : Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ),
          // Page counter (top right) "1 / 5"
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_index + 1} / ${widget.images.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
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

// ==================== Product Video (YouTube or MP4) ====================

class _ProductVideo extends StatefulWidget {
  final Product product;
  const _ProductVideo({required this.product});

  @override
  State<_ProductVideo> createState() => _ProductVideoState();
}

class _ProductVideoState extends State<_ProductVideo> {
  YoutubePlayerController? _ytCtl;
  VideoPlayerController? _vpCtl;
  ChewieController? _chewieCtl;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      if (widget.product.isYouTubeVideo) {
        final id = widget.product.youTubeId;
        if (id.isEmpty) {
          setState(() => _initError = true);
          return;
        }
        _ytCtl = YoutubePlayerController(
          initialVideoId: id,
          flags: const YoutubePlayerFlags(
            autoPlay: false,
            mute: false,
            enableCaption: true,
          ),
        );
        if (mounted) setState(() {});
      } else {
        final raw = widget.product.videoUrl;
        final url = raw.startsWith('http')
            ? raw
            : '${AppConfig.apiBase}${raw.startsWith('/') ? '' : '/'}$raw';
        _vpCtl = VideoPlayerController.networkUrl(Uri.parse(url));
        await _vpCtl!.initialize();
        _chewieCtl = ChewieController(
          videoPlayerController: _vpCtl!,
          autoPlay: false,
          looping: false,
          aspectRatio: _vpCtl!.value.aspectRatio == 0
              ? 16 / 9
              : _vpCtl!.value.aspectRatio,
          materialProgressColors: ChewieProgressColors(
            playedColor: EggplantColors.primary,
            handleColor: EggplantColors.primary,
            backgroundColor: Colors.grey.shade300,
            bufferedColor: Colors.grey.shade400,
          ),
          placeholder: Container(color: Colors.black),
        );
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('video setup error: $e');
      if (mounted) setState(() => _initError = true);
    }
  }

  @override
  void dispose() {
    _ytCtl?.dispose();
    _chewieCtl?.dispose();
    _vpCtl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: EggplantColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            '영상을 불러올 수 없어요',
            style: TextStyle(color: EggplantColors.textSecondary),
          ),
        ),
      );
    }

    if (widget.product.isYouTubeVideo) {
      if (_ytCtl == null) {
        return const SizedBox(
          height: 180,
          child: Center(
              child: CircularProgressIndicator(color: EggplantColors.primary)),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: YoutubePlayer(
          controller: _ytCtl!,
          showVideoProgressIndicator: true,
          progressIndicatorColor: EggplantColors.primary,
          progressColors: const ProgressBarColors(
            playedColor: EggplantColors.primary,
            handleColor: EggplantColors.primary,
          ),
        ),
      );
    }

    if (_chewieCtl == null ||
        _vpCtl == null ||
        !_vpCtl!.value.isInitialized) {
      return const SizedBox(
        height: 180,
        child: Center(
            child: CircularProgressIndicator(color: EggplantColors.primary)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: _vpCtl!.value.aspectRatio == 0
            ? 16 / 9
            : _vpCtl!.value.aspectRatio,
        child: Chewie(controller: _chewieCtl!),
      ),
    );
  }
}

class _OwnerBottomBar extends StatelessWidget {
  final Product product;
  final VoidCallback onMenu;
  const _OwnerBottomBar({required this.product, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;
    switch (product.status) {
      case 'reserved':
        badgeColor = EggplantColors.warning;
        badgeText = '예약중';
        badgeIcon = Icons.schedule;
        break;
      case 'sold':
        badgeColor = EggplantColors.textSecondary;
        badgeText = '거래완료';
        badgeIcon = Icons.check_circle;
        break;
      default:
        badgeColor = EggplantColors.success;
        badgeText = '판매중';
        badgeIcon = Icons.sell;
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badgeIcon, size: 14, color: badgeColor),
              const SizedBox(width: 4),
              Text(
                badgeText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: badgeColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            product.priceFormatted,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onMenu,
          icon: const Icon(Icons.edit_note, size: 20),
          label: const Text('상태/삭제', style: TextStyle(fontSize: 14)),
          style: OutlinedButton.styleFrom(
            foregroundColor: EggplantColors.primary,
            side: const BorderSide(color: EggplantColors.primary),
          ),
        ),
      ],
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _StatusTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
      onTap: onTap,
    );
  }
}
