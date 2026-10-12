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
import '../app/l10n.dart';
import '../app/market.dart';
import '../app/responsive.dart';
import '../app/theme.dart';
import '../models/product.dart';
import '../models/review.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/product_service.dart';
import '../services/qta_service.dart';
import '../services/moderation_service.dart';
import '../services/hidden_products_service.dart';
import '../widgets/review_sheet.dart';
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
  final String status; // 'sale' | 'reserved' | 'sold'
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

/// 상태 원본값('sale'|'reserved'|'sold') → 상세 화면 표시 문구.
String _statusDisplayLabel(BuildContext context, String raw) {
  switch (raw) {
    case 'reserved':
      return context.l10n.productStatusReserved;
    case 'sold':
      return context.l10n.productStatusSoldOut;
    case 'sale':
    default:
      return context.l10n.productStatusSale;
  }
}

/// 백엔드 Product → 화면용 MarketItem 어댑터.
String _statusKey(String raw) =>
    (raw == 'reserved' || raw == 'sold') ? raw : 'sale';

MarketItem _toMarketItem(Product p) {
  return MarketItem(
    id: p.id,
    title: p.title,
    description: p.description.isEmpty ? null : p.description,
    priceKrw: p.price,
    priceQta: p.qtaPrice > 0 ? p.qtaPrice : null,
    sellerName: p.sellerNickname,
    status: _statusKey(p.status),
    imageUrls: p.images,
  );
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  MarketItem? _item;
  Product? _product; // 정책 코드(_isMine, _changeStatus 등) 호환용 원본 보존.
  bool _liked = false;

  /// 이 거래에 내가 보낸 후기 (없으면 null). [_myReviewLoaded] 전에는 후기 카드를 숨긴다.
  Review? _myReview;
  bool _myReviewLoaded = false;

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
          _errorMessage = context.l10n.productDetailLoadFailed;
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
      // ignore: discarded_futures
      _loadMyReview();

      debugPrint('[GAJI_DETAIL] body widget rendered=true');
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _errorMessage = context.l10n.productDetailTimeout;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('[GAJI_DETAIL] error=$e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() {
        _errorMessage = context.l10n.productDetailLoadFailed;
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

  /// 판매자가 나를 구매자로 지정했고 아직 확인하지 않은 거래.
  bool get _awaitingMyConfirmation {
    final p = _product;
    final u = context.read<AuthService>().user;
    return p != null &&
        u != null &&
        p.status == 'sold' &&
        p.buyerId == u.id &&
        p.buyerConfirmedAt == null;
  }

  Future<void> _confirmPurchase() async {
    final p = _product;
    if (p == null) return;
    final user = context.read<AuthService>().user;
    // QTA 결제 거래만 본인인증 필요 (원화 거래는 인증 없이 확인 가능).
    if (p.hasQtaPrice && user != null && !user.verificationLevel.canTrade) {
      if (!AppConfig.identityVerificationEnabled) {
        // 본인인증이 아직 없는 빌드 — 인증하러 갈 수 없으므로 해결 방법을 안내.
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.l10n.productQtaConfirmUnavailableTitle),
            content: Text(ctx.l10n.productQtaConfirmUnavailableBody),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(ctx.l10n.commonConfirm)),
            ],
          ),
        );
        return;
      }
      await showVerificationGuard(
        context,
        current: user.verificationLevel,
        required: VerificationLevel.identity,
        customTitle: context.l10n.productConfirmVerifyTitle,
        customMessage: context.l10n.productConfirmVerifyBody,
      );
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.productConfirmDialogTitle),
        content: Text(p.hasQtaPrice
            ? ctx.l10n.productConfirmDialogBodyQta(p.qtaPriceFormatted)
            : ctx.l10n.productConfirmDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.productConfirmDeal),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final err = await context
        .read<ProductService>()
        .confirmPurchase(p.id, expectedQtaPrice: p.qtaPrice);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    await context.read<AuthService>().refreshFromServer();
    await _loadDetail();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.productConfirmDone)),
    );
  }

  Widget _buildBuyerConfirmCard() {
    final p = _product!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EggplantColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EggplantColors.primaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.productBuyerAssignedTitle,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            p.hasQtaPrice
                ? context.l10n.productBuyerAssignedBodyQta(p.qtaPriceFormatted)
                : context.l10n.productBuyerAssignedBody,
            style: const TextStyle(
                fontSize: 13, color: EggplantColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _confirmPurchase,
              child: Text(context.l10n.productConfirmDealButton),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeStatus(String status) async {
    final p = _product;
    if (p == null) return;

    String? buyerId;
    Map<String, dynamic>? buyer;
    if (status == 'sold') {
      final user = context.read<AuthService>().user;
      if (p.hasQtaPrice && user != null && !user.verificationLevel.canTrade) {
        await showVerificationGuard(
          context,
          current: user.verificationLevel,
          required: VerificationLevel.identity,
          customTitle: context.l10n.productSoldVerifyTitle,
          customMessage: context.l10n.productSoldVerifyBody,
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
      SnackBar(
        content: Text(status == 'sold' && buyerId != null
            ? context.l10n.productStatusChangedSold
            : context.l10n.productStatusChanged(_statusLabel(status))),
      ),
    );

    if (status == 'sold' && buyer != null) {
      await _showReviewSheet(
          counterpartNickname:
              buyer['nickname']?.toString() ?? context.l10n.productBuyer);
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'reserved':
        return context.l10n.productStatusReserved;
      case 'sold':
        return context.l10n.productStatusSold;
      case 'sale':
      default:
        return context.l10n.productStatusSale;
    }
  }

  /// 거래완료 구매자 선택 시트.
  ///   (1) 이 기기에 남아 있는 채팅방 중 이 상품으로 대화한 상대
  ///   (2) 닉네임 검색 (서버 /api/users/search)
  /// 휘발성 채팅이라 서버엔 대화 기록이 없으므로 둘을 함께 쓴다.
  Future<Map<String, dynamic>?> _pickBuyer(Product p) async {
    final me = context.read<AuthService>().user?.id;
    final chatPartners = context
        .read<ChatService>()
        .rooms
        .where(
            (r) => r.productId == p.id && r.peerId.isNotEmpty && r.peerId != me)
        .map((r) => <String, dynamic>{
              'id': r.peerId,
              'nickname': r.peerNickname,
              'manner_score': r.peerMannerScore,
            })
        .toList();
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BuyerPickerSheet(chatPartners: chatPartners),
    );
  }

  /// 거래완료된 상품의 거래 당사자인지 — 후기를 보낼 수 있는 사람.
  ///   구매자: buyer_id == 나 · 판매자: 내 상품이고 구매자가 지정됨.
  ReviewerRole? get _myReviewRole {
    final p = _product;
    final u = context.read<AuthService>().user;
    if (p == null || u == null || p.status != 'sold' || p.buyerId == null)
      return null;
    if (p.buyerId == u.id && p.sellerId != u.id) return ReviewerRole.buyer;
    if (p.sellerId == u.id && p.buyerId != u.id) return ReviewerRole.seller;
    return null;
  }

  /// 후기 상대 닉네임 — 구매자는 판매자, 판매자는 구매자.
  String _counterpartNickname(ReviewerRole role) {
    final p = _product!;
    final n =
        role == ReviewerRole.buyer ? p.sellerNickname : (p.buyerNickname ?? '');
    return n.isEmpty ? context.l10n.reviewCounterpartFallback : n;
  }

  Future<void> _loadMyReview() async {
    final p = _product;
    if (p == null || _myReviewRole == null) {
      if (mounted) setState(() => _myReviewLoaded = false);
      return;
    }
    final r = await context.read<ProductService>().fetchMyReview(p.id);
    if (!mounted || _product?.id != p.id) return;
    setState(() {
      _myReview = r;
      _myReviewLoaded = true;
    });
  }

  /// 거래 후기 보내기 (구매자 → 판매자, 판매자 → 구매자 공통 3단계 시트).
  Future<void> _showReviewSheet({String? counterpartNickname}) async {
    final p = _product;
    final role = _myReviewRole;
    if (p == null || role == null) return;
    final sent = await showReviewSheet(
      context,
      productId: p.id,
      counterpartNickname: counterpartNickname ?? _counterpartNickname(role),
      role: role,
      isFree: p.price == 0,
    );
    if (sent) await _loadMyReview();
  }

  /// 거래완료 후 당사자에게 보이는 후기 카드 — 아직 안 보냈으면 "거래 후기 보내기",
  /// 보냈으면 "보낸 후기 보기".
  Widget _buildReviewCard(ReviewerRole role) {
    final l = context.l10n;
    final nick = _counterpartNickname(role);
    final mine = _myReview;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mine == null ? EggplantColors.background : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              mine == null ? EggplantColors.primaryLight : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mine == null ? l.reviewQuestion(nick) : l.reviewSentTo(nick),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            mine == null
                ? l.reviewPromptBody
                : '${reviewRatingEmoji(mine.rating)} ${reviewRatingLabel(l, mine.rating)}',
            style: const TextStyle(
                fontSize: 13, color: EggplantColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: mine == null
                ? ElevatedButton.icon(
                    key: const Key('detail_review_send'),
                    onPressed: () => _showReviewSheet(),
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: Text(l.reviewSendButton),
                  )
                : OutlinedButton(
                    onPressed: () => showMyReviewSheet(
                      context,
                      review: mine,
                      counterpartNickname: nick,
                    ),
                    child: Text(l.reviewViewMine),
                  ),
          ),
        ],
      ),
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
          SnackBar(content: Text(context.l10n.productChatOpenFailed)),
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
        SnackBar(content: Text(context.l10n.productChatStartFailed)),
      );
    }
  }

  Future<void> _startEscrow() async {
    final p = _product;
    if (p == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.productEscrowNavigating)),
    );
  }

  void _showOwnerMenu() {
    showModalBottomSheet<void>(
      context: context,
      // 메뉴 5개 — 기본(화면 9/16 제한)이면 작은 폰·큰 글씨에서 잘림.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.local_offer),
              title: Text(ctx.l10n.productChangeToSale),
              onTap: () {
                Navigator.pop(ctx);
                _changeStatus('sale');
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_available),
              title: Text(ctx.l10n.productChangeToReserved),
              onTap: () {
                Navigator.pop(ctx);
                _changeStatus('reserved');
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle),
              title: Text(ctx.l10n.productChangeToSold),
              onTap: () {
                Navigator.pop(ctx);
                _changeStatus('sold');
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(ctx.l10n.productEdit),
              onTap: () async {
                Navigator.pop(ctx);
                final p = _product;
                if (p == null) return;
                final result =
                    await context.push<bool>('/product/${p.id}/edit');
                if (result == true && mounted) {
                  // 수정 완료 → 즉시 반영
                  _loadDetail();
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(ctx.l10n.commonDelete,
                  style: const TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final p = _product;
                if (p == null) return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: Text(dctx.l10n.productDeleteTitle),
                    content: Text(dctx.l10n.productDeleteBody),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dctx, false),
                          child: Text(dctx.l10n.commonCancel)),
                      TextButton(
                        onPressed: () => Navigator.pop(dctx, true),
                        style: TextButton.styleFrom(
                            foregroundColor: EggplantColors.error),
                        child: Text(dctx.l10n.commonDelete),
                      ),
                    ],
                  ),
                );
                if (ok != true || !mounted) return;
                final ps = context.read<ProductService>();
                final err = await ps.deleteProduct(p.id);
                if (!mounted) return;
                final clawback = err == null ? ps.lastListingClawback : 0;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(err ??
                      (clawback > 0
                          ? context.l10n.productDeletedWithClawback(clawback)
                          : context.l10n.productDeleted)),
                ));
                if (clawback > 0) context.read<QtaService>().load(force: true);
                if (err == null) context.pop();
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
              title: Text(ctx.l10n.productHide),
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
              title: Text(ctx.l10n.productReport),
              onTap: () async {
                Navigator.pop(ctx);
                final p = _product;
                if (p == null) return;
                // ModerationService는 reportUser만 존재. 상품 신고 API는 추후 추가.
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.productReportReceived)),
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
        title: Text(context.l10n.productDetailTitle),
        centerTitle: true,
        actions: [
          if (!_isLoading && _product != null)
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: _isMine
                  ? context.l10n.productOwnerMenuTooltip
                  : context.l10n.productMore,
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
                child: Text(context.l10n.commonRetry),
              ),
            ],
          ),
        ),
      );
    }

    if (_item == null) {
      return Center(
        child: Text(context.l10n.productDetailEmpty),
      );
    }

    final item = _item!;

    // 당근처럼: 맨 위에 화면 폭 가득 사진(옆으로 넘김 · "1 / 3"), 그 아래 내용.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImageSection(item),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_product != null && _product!.hasVideo) ...[
                  _ProductVideo(
                      key: ValueKey(_product!.videoUrl), product: _product!),
                  const SizedBox(height: 20),
                ],
                if (_awaitingMyConfirmation) ...[
                  _buildBuyerConfirmCard(),
                  const SizedBox(height: 20),
                ],
                if (_myReviewLoaded && _myReviewRole != null) ...[
                  _buildReviewCard(_myReviewRole!),
                  const SizedBox(height: 20),
                ],
                _buildSellerSection(item),
                const SizedBox(height: 20),
                _buildTitleSection(item),
                const SizedBox(height: 16),
                _buildDescriptionSection(item),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSection(MarketItem item) {
    // 화면 폭 정사각형 (넓은 화면에선 최대 600). 사진이 없으면 가지 마스코트.
    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        width: double.infinity,
        height: c.maxWidth.clamp(0, 600).toDouble(),
        child: _ImageCarousel(images: item.imageUrls),
      ),
    );
  }

  Widget _buildTitleSection(MarketItem item) {
    return Text(
      item.title.isEmpty ? context.l10n.productNoTitle : item.title,
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
                  item.sellerName.isEmpty
                      ? context.l10n.productNoSellerInfo
                      : item.sellerName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusDisplayLabel(context, item.status),
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
          Text(
            context.l10n.productDescriptionTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            desc.isEmpty ? context.l10n.productNoDescription : desc,
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
                    AppMarket.isJp(_product?.market ?? 'kr')
                        ? context.l10n.priceJpy(_formatPrice(item.priceKrw))
                        : context.l10n.priceKrw(_formatPrice(item.priceKrw)),
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
                    label: Text(context.l10n.productManage),
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
                    label: Text(context.l10n.productChatButton),
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
      case 'reserved':
        return Colors.orange;
      case 'sold':
        return Colors.grey;
      case 'sale':
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
            bottom: 20,
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
          // 장수 표시 (오른쪽 아래) "1 / 3" — 당근과 같은 위치.
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
    final iconColor =
        isMine ? Colors.grey : (liked ? Colors.red : Colors.grey.shade700);
    final icon = (!isMine && liked) ? Icons.favorite : Icons.favorite_border;

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

/// 거래완료 구매자 선택 시트 — 대화 상대 + 닉네임 검색.
/// 작은 화면·키보드에서도 넘치지 않도록 높이를 화면의 85% 로 제한하고 목록만 스크롤.
class _BuyerPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> chatPartners;
  const _BuyerPickerSheet({required this.chatPartners});

  @override
  State<_BuyerPickerSheet> createState() => _BuyerPickerSheetState();
}

class _BuyerPickerSheetState extends State<_BuyerPickerSheet> {
  final _searchCtl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    // 입력하자마자 "검색 중" 으로 바꿔, 디바운스 동안 대화 상대 목록이 남아 보이지 않게.
    setState(() => _searching = q.trim().isNotEmpty);
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 350), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    if (q == _lastQuery) return;
    _lastQuery = q;
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final r = await context.read<ProductService>().searchUsersByNickname(q);
    if (!mounted || q != _lastQuery) return;
    setState(() {
      _results = r;
      _searching = false;
    });
  }

  String _manner(dynamic raw) {
    final n = raw is num ? raw : num.tryParse('$raw') ?? 365;
    // 서버는 ×10 정수(365 = 36.5°)로 준다.
    final t = n > 100 ? n / 10 : n;
    return '${t.toStringAsFixed(1)}°';
  }

  Widget _tile(Map<String, dynamic> u) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFEEEEEE),
          child: Icon(Icons.person, color: Colors.black54),
        ),
        title: Text(
          u['nickname']?.toString() ?? context.l10n.productBuyer,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle:
            Text(context.l10n.productMannerTemp(_manner(u['manner_score']))),
        onTap: () => Navigator.of(context).pop(u),
      );

  @override
  Widget build(BuildContext context) {
    final searching = _searchCtl.text.trim().isNotEmpty;
    final list = searching ? _results : widget.chatPartners;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                Text(
                  context.l10n.productPickBuyerTitle,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.productPickBuyerHint,
                  style: const TextStyle(
                      fontSize: 12, color: EggplantColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtl,
                  onChanged: _onQueryChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: context.l10n.productPickBuyerSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                if (!searching && list.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      context.l10n.productPickBuyerChatPartners,
                      style: const TextStyle(
                          fontSize: 12, color: EggplantColors.textSecondary),
                    ),
                  ),
                Flexible(
                  child: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : list.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                searching
                                    ? context.l10n.productPickBuyerNoResults
                                    : context.l10n.productPickBuyerEmpty,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: EggplantColors.textSecondary),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: list.length,
                              itemBuilder: (_, i) => _tile(list[i]),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== Product Video (YouTube or MP4) ====================

class _ProductVideo extends StatefulWidget {
  final Product product;
  const _ProductVideo({super.key, required this.product});

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
        child: Center(
          child: Text(
            context.l10n.productVideoLoadFailed,
            style: const TextStyle(color: EggplantColors.textSecondary),
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

    if (_chewieCtl == null || _vpCtl == null || !_vpCtl!.value.isInitialized) {
      return SizedBox(
        height: fallbackHeight,
        child: const Center(
            child: CircularProgressIndicator(color: EggplantColors.primary)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio:
            _vpCtl!.value.aspectRatio == 0 ? 16 / 9 : _vpCtl!.value.aspectRatio,
        child: Chewie(controller: _chewieCtl!),
      ),
    );
  }
}
