import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../app/constants.dart';
import '../app/responsive.dart';
import '../app/theme.dart';
import '../models/product.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/product_service.dart';
import '../services/moderation_service.dart';
import '../services/hidden_products_service.dart';
import 'profile_verify_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

/// 상세 화면 내부에서만 쓰는 가벼운 어댑터 모델.
/// (사장님 명령 코드 그대로 — 본문 UI 가 의존하는 형태로 통일.)
class MarketItem {
  final String id;
  final String title;
  final String? description;
  final int priceKrw;
  final int? priceQta;
  final String sellerName;
  final String status; // 판매중, 예약중, 판매완료
  final List<String> imageUrls;

  const MarketItem({
    required this.id,
    required this.title,
    this.description,
    required this.priceKrw,
    this.priceQta,
    required this.sellerName,
    required this.status,
    required this.imageUrls,
  });
}

/// 백엔드 Product → 화면용 MarketItem 어댑터.
String _statusKoLabel(String raw) {
  switch (raw) {
    case 'reserved':
      return '예약중';
    case 'sold':
      return '판매완료';
    case 'sale':
    default:
      return '판매중';
  }
}

MarketItem _toMarketItem(Product p) {
  return MarketItem(
    id: p.id,
    title: p.title,
    description: p.description.isEmpty ? null : p.description,
    priceKrw: p.price,
    priceQta: p.qtaPrice > 0 ? p.qtaPrice : null,
    sellerName: p.sellerNickname,
    status: _statusKoLabel(p.status),
    imageUrls: p.images,
  );
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  MarketItem? _item;
  Product? _product; // 정책 코드(_isMine, _changeStatus 등) 호환용 원본 보존.
  bool _liked = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    debugPrint('[GAJI_DETAIL] build start itemId=${widget.productId}');

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final p = await context
          .read<ProductService>()
          .fetchById(widget.productId)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (p == null) {
        setState(() {
          _errorMessage = '상품 정보를 불러오지 못했습니다.';
          _isLoading = false;
        });
        return;
      }

      final item = _toMarketItem(p);

      debugPrint('[GAJI_DETAIL] item loaded id=${item.id}');
      debugPrint('[GAJI_DETAIL] title=${item.title}');
      debugPrint(
        '[GAJI_DETAIL] description length=${item.description?.length ?? 0}',
      );
      debugPrint('[GAJI_DETAIL] image count=${item.imageUrls.length}');
      debugPrint('[GAJI_DETAIL] price=${item.priceKrw}');
      debugPrint('[GAJI_DETAIL] qtaPrice=${item.priceQta ?? 0}');

      setState(() {
        _item = item;
        _product = p;
        _liked = p.isLiked;
        _isLoading = false;
      });

      debugPrint('[GAJI_DETAIL] body widget rendered=true');
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _errorMessage = '서버 응답이 늦어요. 잠시 후 다시 시도해주세요.';
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('[GAJI_DETAIL] error=$e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() {
        _errorMessage = '상품 정보를 불러오지 못했습니다.';
        _isLoading = false;
      });
    }
  }

  // ------------------------------------------------------------------
  // 정책 보존: 좋아요/내 상품 판단/상태 변경/구매자 픽/후기/채팅/에스크로
  // (기존 정책 716줄 로직을 본문에 묶지 않고 메뉴/하단바에서만 호출.)
  // ------------------------------------------------------------------
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

    String? buyerId;
    Map<String, dynamic>? buyer;
    if (status == 'sold') {
      final user = context.read<AuthService>().user;
      if (user != null && !user.verificationLevel.canTrade) {
        await showVerificationGuard(
          context,
          current: user.verificationLevel,
          required: VerificationLevel.identity,
          customTitle: '거래완료에는 본인 인증이 필요해요',
          customMessage: '돈(KRW·QTA)이 오가는 단계라 1인 1계정 보장을 위해 '
              '판매자 본인 인증이 필수입니다.\n'
              '인증해도 채팅·통화는 익명 그대로 유지돼요.',
        );
        return;
      }
      buyer = await _pickBuyer(p);
      if (buyer == null) return;
      buyerId = buyer['id']?.toString();
    }

    final err = await context
        .read<ProductService>()
        .updateStatus(p.id, status, buyerId: buyerId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    await _loadDetail();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('상태를 ${_statusLabel(status)}(으)로 변경했어요')),
    );

    if (status == 'sold' && buyer != null) {
      await _showReviewSheet(buyerNickname: buyer['nickname']?.toString() ?? '구매자');
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'reserved':
        return '예약중';
      case 'sold':
        return '거래완료';
      case 'sale':
      default:
        return '판매중';
    }
  }

  Future<Map<String, dynamic>?> _pickBuyer(Product p) async {
    final candidates =
        await context.read<ProductService>().fetchBuyerCandidates(p.id);
    if (!mounted) return null;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('구매자와 채팅한 기록이 없어요. 먼저 채팅을 열어주세요.'),
        ),
      );
      return null;
    }
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '거래한 구매자를 선택해주세요',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              ...candidates.map((c) => ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEEEEEE),
                      child: Icon(Icons.person, color: Colors.black54),
                    ),
                    title: Text(c['nickname']?.toString() ?? '구매자'),
                    subtitle:
                        Text('매너온도 ${c['manner_score'] ?? 36.5}'),
                    onTap: () => Navigator.of(ctx).pop(c),
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReviewSheet({required String buyerNickname}) async {
    final p = _product;
    if (p == null) return;
    int score = 5;
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: StatefulBuilder(
                builder: (ctx, setSt) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text('$buyerNickname 님과의 거래는 어떠셨나요?',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Row(
                      children: List.generate(5, (i) {
                        final filled = i < score;
                        return IconButton(
                          icon: Icon(
                            filled ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 32,
                          ),
                          onPressed: () => setSt(() => score = i + 1),
                        );
                      }),
                    ),
                    TextField(
                      controller: controller,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: '거래 후기를 남겨주세요 (선택)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          // rating: 'good' (4~5) / 'soso' (3) / 'bad' (1~2)
                          final ratingLabel = score >= 4
                              ? 'good'
                              : (score == 3 ? 'soso' : 'bad');
                          await context.read<ProductService>().postReview(
                                p.id,
                                rating: ratingLabel,
                                comment: controller.text.trim(),
                              );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('후기 등록 감사합니다 🙏')),
                            );
                          }
                        },
                        child: const Text('후기 등록'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startChat() async {
    final p = _product;
    final u = context.read<AuthService>().user;
    if (p == null || u == null) return;
    if (p.sellerId == u.id) return;
    final chat = context.read<ChatService>();
    try {
      final room = await chat.openRoomWithPeer(
        peerUserId: p.sellerId,
        peerNickname: p.sellerNickname,
        productId: p.id,
        productTitle: p.title,
        productThumb: p.images.isNotEmpty ? p.images.first : null,
      );
      if (!mounted) return;
      if (room == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채팅방을 열 수 없어요')),
        );
        return;
      }
      final qPeerNick = Uri.encodeQueryComponent(p.sellerNickname);
      final qTitle = Uri.encodeQueryComponent(p.title);
      context.push(
        '/chat/${room.id}?peerNick=$qPeerNick&title=$qTitle&peerId=${p.sellerId}&pid=${p.id}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('채팅을 시작하지 못했어요: $e')),
      );
    }
  }

  Future<void> _startEscrow() async {
    final p = _product;
    if (p == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('안전결제 화면으로 이동합니다')),
    );
  }

  void _showOwnerMenu() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.local_offer),
              title: const Text('판매중으로 변경'),
              onTap: () { Navigator.pop(ctx); _changeStatus('sale'); },
            ),
            ListTile(
              leading: const Icon(Icons.event_available),
              title: const Text('예약중으로 변경'),
              onTap: () { Navigator.pop(ctx); _changeStatus('reserved'); },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle),
              title: const Text('거래완료로 변경'),
              onTap: () { Navigator.pop(ctx); _changeStatus('sold'); },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('수정'),
              onTap: () async {
                Navigator.pop(ctx);
                final p = _product;
                if (p == null) return;
                final result = await context.push<bool>('/product/${p.id}/edit');
                if (result == true && mounted) {
                  // 수정 완료 → 즉시 반영
                  _loadDetail();
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final p = _product;
                if (p == null) return;
                final err = await context.read<ProductService>().deleteProduct(p.id);
                if (err == null && mounted) context.pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showViewerMenu() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('숨기기'),
              onTap: () async {
                Navigator.pop(ctx);
                final p = _product;
                if (p == null) return;
                await context.read<HiddenProductsService>().hide(p.id);
                if (mounted) context.pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('신고'),
              onTap: () async {
                Navigator.pop(ctx);
                final p = _product;
                if (p == null) return;
                // ModerationService는 reportUser만 존재. 상품 신고 API는 추후 추가.
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('신고가 접수되었습니다')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 사장님 명령 코드 그대로 — build / _buildBody / _buildBottomBar
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품상세'),
        centerTitle: true,
        actions: [
          if (!_isLoading && _product != null)
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: _isMine ? '상태 변경 / 삭제' : '더보기',
              onPressed: _isMine ? _showOwnerMenu : _showViewerMenu,
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      debugPrint('[GAJI_DETAIL] entered loading branch=true');
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      debugPrint('[GAJI_DETAIL] entered empty branch=true');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadDetail,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    if (_item == null) {
      return const Center(
        child: Text('상품 정보가 없습니다.'),
      );
    }

    final item = _item!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImageSection(item),
          const SizedBox(height: 20),
          _buildSellerSection(item),
          const SizedBox(height: 20),
          _buildTitleSection(item),
          const SizedBox(height: 16),
          _buildDescriptionSection(item),
        ],
      ),
    );
  }

  Widget _buildImageSection(MarketItem item) {
    if (item.imageUrls.isEmpty) {
      return Container(
        height: 280,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.image_outlined,
          size: 56,
          color: Colors.grey.shade400,
        ),
      );
    }

    return SizedBox(
      height: 320,
      child: PageView.builder(
        itemCount: item.imageUrls.length,
        itemBuilder: (context, index) {
          final raw = item.imageUrls[index];
          final url = raw.startsWith('http')
              ? raw
              : '${AppConfig.apiBase}${raw.startsWith('/') ? '' : '/'}$raw';
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (_, __) => Container(color: Colors.grey.shade100),
              errorWidget: (_, __, ___) => Container(
                color: Colors.grey.shade100,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTitleSection(MarketItem item) {
    return Text(
      item.title.isEmpty ? '제목 없음' : item.title,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.black,
      ),
    );
  }



  Widget _buildSellerSection(MarketItem item) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey.shade300,
            child: const Icon(Icons.person, color: Colors.black54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.sellerName.isEmpty ? '판매자 정보 없음' : item.sellerName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.status,
                  style: TextStyle(
                    fontSize: 13,
                    color: _statusColor(item.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(MarketItem item) {
    final desc = (item.description ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '상품 설명',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            desc.isEmpty ? '설명 없음' : desc,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final item = _item;
    if (item == null) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade300),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 좌측: 찜(하트) — 당근마켓 기준. 본인 매물은 카운트만 회색으로 표시.
            _LikeButton(
              liked: _liked,
              count: _product?.likeCount ?? 0,
              isMine: _isMine,
              onTap: _toggleLike,
            ),
            const SizedBox(width: 12),
            // 좌측 하트와 가격 사이 세로 구분선
            Container(
              width: 1,
              height: 32,
              color: Colors.grey.shade300,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_formatPrice(item.priceKrw)}원',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  if (item.priceQta != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${item.priceQta} QTA',
                      style: const TextStyle(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _isMine
                ? OutlinedButton.icon(
                    onPressed: _showOwnerMenu,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('관리'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.deepPurple),
                      foregroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _startChat,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('채팅하기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      elevation: 0,
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(int value) {
    final text = value.toString();
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final reverseIndex = text.length - i;
      buffer.write(text[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }

  Color _statusColor(String status) {
    switch (status) {
      case '예약중':
        return Colors.orange;
      case '판매완료':
        return Colors.grey;
      case '판매중':
      default:
        return const Color(0xFF16A34A);
    }
  }
}

/// 안전결제 모달 안의 한 줄 정보 행 (라벨 + 값 [+ trailing 버튼]).
class _EscrowRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Widget? trailing;
  const _EscrowRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: EggplantColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 14,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              color: EggplantColors.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
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
            return GestureDetector(
              onTap: () {
                // Build the absolute list once, open fullscreen viewer.
                final urls = widget.images.map((u) {
                  return u.startsWith('http')
                      ? u
                      : '${AppConfig.apiBase}${u.startsWith('/') ? '' : '/'}$u';
                }).toList();
                Navigator.of(context).push(
                  PageRouteBuilder(
                    opaque: false,
                    barrierColor: Colors.black,
                    pageBuilder: (_, __, ___) => _PhotoViewer(
                      images: urls,
                      initialIndex: i,
                    ),
                  ),
                );
              },
              child: Hero(
                tag: 'product-img-$i-$fullUrl',
                child: CachedNetworkImage(
                  imageUrl: fullUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (_, __) =>
                      Container(color: EggplantColors.background),
                  errorWidget: (_, __, ___) =>
                      Container(color: EggplantColors.background),
                ),
              ),
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
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_index + 1} / ${widget.images.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }
}

class _PhotoViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _PhotoViewer({required this.images, required this.initialIndex});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _ctl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _ctl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${_index + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
      body: PageView.builder(
        controller: _ctl,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          final url = widget.images[i];
          return Center(
            child: Hero(
              tag: 'product-img-$i-$url',
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 하단바 좌측 찜(하트) 버튼 — 당근마켓 기준.
/// - 타인 매물: 활성 (탭 시 toggleLike), liked=true 면 빨간 하트, false 면 회색 외곽선
/// - 본인 매물: 비활성(터치 무시), 회색 외곽선 + 카운트만 표시
class _LikeButton extends StatelessWidget {
  final bool liked;
  final int count;
  final bool isMine;
  final VoidCallback onTap;

  const _LikeButton({
    required this.liked,
    required this.count,
    required this.isMine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isMine
        ? Colors.grey
        : (liked ? Colors.red : Colors.grey.shade700);
    final icon = (!isMine && liked)
        ? Icons.favorite
        : Icons.favorite_border;

    return InkWell(
      onTap: isMine ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: iconColor),
            if (count > 0) ...[
              const SizedBox(height: 2),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
