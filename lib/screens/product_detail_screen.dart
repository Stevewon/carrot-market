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
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final p = _product;
                if (p == null) return;
                final ok = await context.read<ProductService>().deleteProduct(p.id);
                if (ok && mounted) context.pop();
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
                await context.read<ModerationService>().reportProduct(p.id);
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
          const SizedBox(height: 16),
          _buildTitleSection(item),
          const SizedBox(height: 16),
          _buildPriceSection(item),
          const SizedBox(height: 16),
          _buildSellerSection(item),
          const SizedBox(height: 16),
          _buildDescriptionSection(item),
        ],
      ),
    );
  }

  Widget _buildImageSection(MarketItem item) {
    if (item.imageUrls.isEmpty) {
      return Container(
        height: 240,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        alignment: Alignment.center,
        child: const Text(
          '이미지 없음',
          style: TextStyle(
            fontSize: 16,
            color: Colors.black54,
          ),
        ),
      );
    }

    return SizedBox(
      height: 240,
      child: PageView.builder(
        itemCount: item.imageUrls.length,
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              item.imageUrls[index],
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Text('이미지 로드 실패'),
                );
              },
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

  Widget _buildPriceSection(MarketItem item) {
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
          Text(
            '${_formatPrice(item.priceKrw)}원',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.priceQta != null ? '${item.priceQta} QTA' : 'QTA 환산값 없음',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.deepPurple,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
    final status = item?.status ?? '판매중';

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFE9FFF2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status,
                style: const TextStyle(
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item != null ? '${_formatPrice(item.priceKrw)}원' : '-',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item?.priceQta != null ? '${item!.priceQta} QTA' : '',
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: item == null
                  ? null
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('상품상세 버튼 클릭')),
                      );
                    },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.deepPurple),
                foregroundColor: Colors.deepPurple,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text(
                '상품상세',
                style: TextStyle(fontWeight: FontWeight.w700),
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
    return InkWell(
      onTap: () => context.push('/user/${product.sellerId}'),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
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
                  if (product.sellerWalletMasked != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined,
                            size: 11, color: EggplantColors.textTertiary),
                        const SizedBox(width: 3),
                        Text(
                          product.sellerWalletMasked!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: EggplantColors.textTertiary,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ],
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
                '${product.sellerMannerLabel}C',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: EggplantColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: EggplantColors.textTertiary),
          ],
        ),
      ),
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
    // 동영상 placeholder/오류 화면 높이도 화면 폭에 비례 (180 고정 → 9:16 비율).
    final w = MediaQuery.of(context).size.width;
    final fallbackHeight = (w * 9 / 16).clamp(180.0, 320.0).toDouble();
    if (_initError) {
      return Container(
        height: fallbackHeight,
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
        return SizedBox(
          height: fallbackHeight,
          child: const Center(
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
      return SizedBox(
        height: fallbackHeight,
        child: const Center(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                product.priceFormatted,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              if (product.hasQtaPrice)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.token_outlined,
                          size: 13, color: EggplantColors.primary),
                      const SizedBox(width: 3),
                      Text(
                        product.qtaPriceFormatted,
                        style: const TextStyle(
                          fontSize: 12,
                          color: EggplantColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
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

/// Fullscreen pinch‑zoom photo viewer (당근식).
///
/// • Pinch to zoom (1x–4x) via [InteractiveViewer].
/// • Swipe left/right to switch photos.
/// • Tap the close button or back gesture to dismiss.
class _PhotoViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _PhotoViewer({required this.images, required this.initialIndex});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _ctl =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_index + 1} / ${widget.images.length}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
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
                    Icons.broken_image_outlined,
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

/// Reusable rating chip used in the 거래후기 sheet.
class _RatingChip extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RatingChip({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? EggplantColors.primary.withOpacity(0.12)
              : Colors.transparent,
          border: Border.all(
            color: selected ? EggplantColors.primary : Colors.black12,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? EggplantColors.primary
                    : EggplantColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
