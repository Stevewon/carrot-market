import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/market.dart';
import '../app/responsive.dart';
import '../app/theme.dart';
import '../models/chat_message.dart';
import '../models/product.dart';
import '../models/review.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/permission_service.dart';
import '../services/product_service.dart';
import '../widgets/review_sheet.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;
  final String peerNickname;
  final String? productTitle;
  final String? peerUserId;
  /// productId가 주어지면 가격 제안(💰) 버튼을 노출한다 (구매자 측 UI).
  final String? productId;

  const ChatScreen({
    super.key,
    required this.roomId,
    required this.peerNickname,
    this.productTitle,
    this.peerUserId,
    this.productId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _ctl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatService>();
      chat.connect();
      chat.joinRoom(widget.roomId, peerNickname: widget.peerNickname);
      // Mark this conversation as read — clears the unread badge and tells
      // the peer (via WS read_receipt) that their messages are now read.
      // ignore: discarded_futures
      chat.markRoomAsRead(widget.roomId);
      // Android 13+ POST_NOTIFICATIONS / iOS UN — 알림 꺼져 있으면 친절하게 안내.
      // 이미 허용돼 있으면 조용히 통과. 한 번만 안내하면 충분하므로 await 없이 발사.
      // ignore: discarded_futures
      PermissionService.ensureNotificationOrGuide(context);
      // After history loads, scroll to bottom.
      Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
    });
  }

  void _scrollToBottom() {
    if (!_scrollCtl.hasClients) return;
    _scrollCtl.animateTo(
      _scrollCtl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    context.read<ChatService>().leaveRoom(widget.roomId);
    _ctl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    context.read<ChatService>().sendMessage(widget.roomId, text);
    _ctl.clear();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollCtl.hasClients) {
        _scrollCtl.animateTo(
          _scrollCtl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatService>();
    final auth = context.watch<AuthService>();
    final messages = chat.messagesFor(widget.roomId);

    return Scaffold(
      backgroundColor: EggplantColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🍆 ', style: TextStyle(fontSize: 16)),
                Flexible(
                  child: Text(
                    widget.peerNickname,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              context.l10n.chatLeaveWarningSubtitle,
              // 360폭·큰 글씨에서 2줄로 접혀 툴바(56dp)를 넘쳤다 → 1줄 말줄임.
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: EggplantColors.primary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.chatVoiceCallTooltip,
            icon: const Icon(Icons.call, color: EggplantColors.primary),
            onPressed: () => _startVoiceCall(context),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showOptions(context),
          ),
        ],
      ),
      // 태블릿/폴드 펼침 모드에서 채팅창이 가로로 무한정 늘어나지 않도록 600dp 제한.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.maxFeedWidth),
          child: Column(
            children: [
              if (widget.productTitle != null)
                _ProductBanner(
                  title: widget.productTitle!,
                  productId: _productId(chat),
                  peerUserId: _derivePeerUserId(auth.user?.id),
                ),
              if (chat.currentAppointment(widget.roomId) != null)
                _AppointmentBanner(
                  appointment: chat.currentAppointment(widget.roomId)!,
                  onTap: _openAppointmentSheet,
                ),
              Expanded(
                child: messages.isEmpty
                    ? _EmptyChat(peerNickname: widget.peerNickname)
                    : Builder(
                        builder: (_) {
                          // Look up this room's peerLastReadAt so each of my
                          // outgoing bubbles can show "읽음" once the peer's
                          // last_read_at >= that message's sent_at.
                          DateTime? peerReadAt;
                          try {
                            final room = chat.rooms.firstWhere(
                              (r) => r.id == widget.roomId,
                            );
                            peerReadAt = room.peerLastReadAt;
                          } catch (_) {
                            peerReadAt = null;
                          }
                          return ListView.builder(
                            controller: _scrollCtl,
                            padding: const EdgeInsets.all(16),
                            itemCount: messages.length,
                            itemBuilder: (_, i) {
                              final msg = messages[i];
                              if (msg.type == 'price_offer' && msg.offer != null) {
                                return _PriceOfferCard(
                                  message: msg,
                                  myUserId: auth.user?.id,
                                  market: AppMarket.of(auth.user),
                                  onRespond: (action) =>
                                      _respondToOffer(msg.offer!.id, action),
                                );
                              }
                              if (msg.type == 'appointment' && msg.appointment != null) {
                                return _AppointmentCard(message: msg);
                              }
                              if (msg.type == 'image' && msg.image != null) {
                                return _MessageBubble(
                                  message: msg,
                                  peerLastReadAt: peerReadAt,
                                  child: _ChatPhoto(message: msg),
                                );
                              }
                              return _MessageBubble(
                                message: msg,
                                peerLastReadAt: peerReadAt,
                              );
                            },
                          );
                        },
                      ),
              ),
              _InputBar(
                controller: _ctl,
                onSend: _send,
                connected: chat.connected,
                // Price-offer button only makes sense in product-tied rooms.
                onOffer: widget.productTitle != null ? () => _openOfferSheet() : null,
                onAttach: chat.connected ? _openAttachMenu : null,
                sendingPhoto: _sendingPhoto,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 사진 · 약속 ─────────────────────────────────────────────────────

  bool _sendingPhoto = false;

  Future<void> _openAttachMenu() async {
    final l10n = context.l10n;
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: EggplantColors.primary),
              title: Text(l10n.chatAttachGallery),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: EggplantColors.primary),
              title: Text(l10n.chatAttachCamera),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.event_available_outlined, color: EggplantColors.primary),
              title: Text(l10n.chatAttachAppointment),
              onTap: () => Navigator.pop(ctx, 'appointment'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || pick == null) return;
    if (pick == 'appointment') {
      await _openAppointmentSheet();
    } else {
      await _sendPhoto(pick == 'camera' ? ImageSource.camera : ImageSource.gallery);
    }
  }

  Future<void> _sendPhoto(ImageSource source) async {
    final XFile? x;
    try {
      // 1280px · 품질 75 로 줄여서 보낸다 (보통 200~400KB).
      x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
      );
    } catch (e) {
      debugPrint('[chat] pick photo failed: $e');
      return;
    }
    if (x == null || !mounted) return;
    setState(() => _sendingPhoto = true);
    final bytes = await x.readAsBytes();
    int w = 0, h = 0;
    try {
      final img = await decodeImageFromList(bytes);
      w = img.width;
      h = img.height;
      img.dispose();
    } catch (_) {}
    if (!mounted) return;
    final err = await context.read<ChatService>().sendImage(
          widget.roomId,
          Uint8List.fromList(bytes),
          width: w,
          height: h,
        );
    if (!mounted) return;
    setState(() => _sendingPhoto = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
  }

  Future<void> _openAppointmentSheet() async {
    final chat = context.read<ChatService>();
    final current = chat.currentAppointment(widget.roomId);
    final result = await showModalBottomSheet<_AppointmentResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AppointmentSheet(initial: current),
    );
    if (!mounted || result == null) return;
    final err = result.cancel
        ? await chat.sendAppointment(widget.roomId, current?.at ?? DateTime.now().add(const Duration(minutes: 5)),
            place: current?.place ?? '', cancel: true)
        : await chat.sendAppointment(widget.roomId, result.at!, place: result.place);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
  }

  // ── Price offer flow ────────────────────────────────────────────────

  Future<void> _openOfferSheet() async {
    final priceCtl = TextEditingController();
    final l10n = context.l10n;
    final market = AppMarket.of(context.read<AuthService>().user);
    final unit = AppMarket.isJp(market)
        ? l10n.chatCurrencyUnitJpy
        : AppMarket.isPh(market)
            ? l10n.chatCurrencyUnitPhp
            : l10n.chatCurrencyUnitKrw;
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            // 키보드가 닫힌 상태에선 제스처/3버튼 내비바 높이만큼 더 띄움.
            bottom: 20 + MediaQuery.of(sheetCtx).viewInsets.bottom + MediaQuery.of(sheetCtx).viewPadding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: EggplantColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.chatOfferSheetTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                widget.productTitle ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: EggplantColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceCtl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: l10n.chatOfferAmountHint(unit),
                  prefixIcon: const Icon(Icons.payments_outlined),
                  filled: true,
                  fillColor: EggplantColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n > 0) Navigator.pop(sheetCtx, n);
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EggplantColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    final n = int.tryParse(priceCtl.text);
                    if (n != null && n > 0) Navigator.pop(sheetCtx, n);
                  },
                  child: Text(
                    l10n.chatOfferSend,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.chatOfferAutoCancelNote,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: EggplantColors.textSecondary),
              ),
            ],
          ),
        );
      },
    );
    priceCtl.dispose();
    if (result == null || result <= 0) return;
    if (!mounted) return;
    final err = await context.read<ChatService>().sendPriceOffer(widget.roomId, result);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
    }
  }

  Future<void> _respondToOffer(String offerId, String action) async {
    final l10n = context.l10n;
    final label = action == 'accept'
        ? l10n.chatOfferAccept
        : action == 'reject'
            ? l10n.chatOfferReject
            : l10n.chatOfferCancelAction;
    // Confirm only the destructive ones.
    if (action != 'cancel') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.chatOfferDialogTitle(label)),
          content: Text(action == 'accept'
              ? l10n.chatOfferAcceptConfirm
              : l10n.chatOfferRejectConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(_, true),
              style: TextButton.styleFrom(
                foregroundColor: action == 'accept'
                    ? EggplantColors.primary
                    : EggplantColors.error,
              ),
              child: Text(label),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    final err = await context
        .read<ChatService>()
        .respondToOffer(offerId, action, roomId: widget.roomId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  /// 이 채팅방의 상품 id — 라우트 인자 또는 채팅방 목록에 저장된 값.
  String? _productId(ChatService chat) {
    final fromRoute = widget.productId;
    if (fromRoute != null && fromRoute.isNotEmpty) return fromRoute;
    for (final r in chat.rooms) {
      if (r.id == widget.roomId) {
        final id = r.productId;
        return (id != null && id.isNotEmpty) ? id : null;
      }
    }
    return null;
  }

  /// Derive the peer's userId from the deterministic room ID.
  /// roomId format: "userA_userB" or "userA_userB_productId"
  /// where userA < userB (sorted).
  String? _derivePeerUserId(String? myUserId) {
    if (myUserId == null) return null;
    if (widget.peerUserId != null && widget.peerUserId!.isNotEmpty) {
      return widget.peerUserId;
    }
    // Typical UUID has 36 chars including 4 hyphens
    final parts = widget.roomId.split('_');
    for (final p in parts) {
      if (p != myUserId && p.length >= 20) {
        return p;
      }
    }
    return null;
  }

  Future<void> _startVoiceCall(BuildContext context) async {
    final auth = context.read<AuthService>();
    final peerId = _derivePeerUserId(auth.user?.id);
    if (peerId == null || peerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.chatPeerNotFound)),
      );
      return;
    }
    // ★ Agora 채널명은 양쪽 지갑주소 sorted pair 로 결정 → 발신측이 상대 wallet
    //  을 갖고 들어가야 수신측과 동일 채널에 join 가능. 채팅 화면은 wallet 캐시가
    //  없으니 프로필 API 로 1회 조회 후 라우팅.
    String peerWallet = '';
    try {
      final prof =
          await context.read<ProductService>().fetchUserProfile(peerId);
      peerWallet = prof?['wallet_address']?.toString() ?? '';
    } catch (_) {/* fallback: 빈 wallet 그대로 진행, CallService 가 에러 처리 */}
    if (!context.mounted) return;
    final qWallet = Uri.encodeComponent(peerWallet);
    context.push(
      '/call?peerId=$peerId'
      '&peer=${Uri.encodeComponent(widget.peerNickname)}'
      '&peerWallet=$qWallet',
    );
  }

  void _showOptions(BuildContext context) {
    final rootContext = context;
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: Text(l10n.chatClearMessages),
              subtitle: Text(l10n.chatClearMessagesSubtitle),
              onTap: () async {
                Navigator.pop(context);
                await _confirmClearMessages(rootContext);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: EggplantColors.error),
              title: Text(l10n.chatLeaveRoom,
                  style: const TextStyle(color: EggplantColors.error, fontWeight: FontWeight.w700)),
              subtitle: Text(l10n.chatLeaveRoomSubtitle),
              onTap: () async {
                Navigator.pop(context);
                await _confirmDeleteRoom(rootContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteRoom(BuildContext ctx) async {
    final l10n = ctx.l10n;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(l10n.chatLeaveRoom),
        content: Text(
          l10n.chatLeaveRoomConfirm(widget.peerNickname),
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(_, true),
            style: TextButton.styleFrom(foregroundColor: EggplantColors.error),
            child: Text(l10n.chatDeletePermanently),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!ctx.mounted) return;
    final success = await ctx.read<ChatService>().deleteRoom(widget.roomId);
    if (!ctx.mounted) return;
    if (success) {
      ctx.pop();
    } else {
      ScaffoldMessenger.of(ctx)
          .showSnackBar(SnackBar(content: Text(l10n.chatDeleteFailedRetry)));
    }
  }

  Future<void> _confirmClearMessages(BuildContext ctx) async {
    final l10n = ctx.l10n;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(l10n.chatClearMessages),
        content: Text(l10n.chatClearMessagesConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(_, true),
            style: TextButton.styleFrom(foregroundColor: EggplantColors.error),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!ctx.mounted) return;
    final success = await ctx.read<ChatService>().clearMessages(widget.roomId);
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(success ? l10n.chatMessagesCleared : l10n.chatDeleteFailed)),
    );
  }
}

/// 채팅방 상단 상품 배너. 거래완료된 상품이고 이 대화 상대가 거래 상대이면
/// "거래 후기 보내기" 버튼을 보여준다 (당근처럼 채팅방에서 바로 후기).
class _ProductBanner extends StatefulWidget {
  final String title;
  final String? productId;
  final String? peerUserId;
  const _ProductBanner({required this.title, this.productId, this.peerUserId});

  @override
  State<_ProductBanner> createState() => _ProductBannerState();
}

class _ProductBannerState extends State<_ProductBanner> {
  Product? _product;
  ReviewerRole? _role;
  bool _canReview = false;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _load();
  }

  @override
  void didUpdateWidget(covariant _ProductBanner old) {
    super.didUpdateWidget(old);
    if (old.productId != widget.productId || old.peerUserId != widget.peerUserId) {
      // ignore: discarded_futures
      _load();
    }
  }

  Future<void> _load() async {
    final pid = widget.productId;
    final peer = widget.peerUserId;
    final me = context.read<AuthService>().user?.id;
    if (pid == null || peer == null || me == null) return;
    final svc = context.read<ProductService>();
    final p = await svc.fetchById(pid, peek: true);
    if (!mounted || p == null || p.status != 'sold' || p.buyerId == null) return;
    ReviewerRole? role;
    if (p.buyerId == me && p.sellerId == peer) role = ReviewerRole.buyer;
    if (p.sellerId == me && p.buyerId == peer) role = ReviewerRole.seller;
    if (role == null) return;
    final mine = await svc.fetchMyReview(pid);
    if (!mounted) return;
    setState(() {
      _product = p;
      _role = role;
      _canReview = mine == null;
    });
  }

  Future<void> _review() async {
    final p = _product;
    final role = _role;
    if (p == null || role == null) return;
    final l = context.l10n;
    final nick = role == ReviewerRole.buyer ? p.sellerNickname : (p.buyerNickname ?? '');
    final sent = await showReviewSheet(
      context,
      productId: p.id,
      counterpartNickname: nick.isEmpty ? l.reviewCounterpartFallback : nick,
      role: role,
      isFree: p.price == 0,
    );
    if (sent && mounted) setState(() => _canReview = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: _canReview ? 4 : 10),
      color: EggplantColors.background,
      child: Row(
        children: [
          const Icon(Icons.shopping_bag_outlined,
              size: 16, color: EggplantColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: EggplantColors.textPrimary),
            ),
          ),
          if (_canReview)
            TextButton.icon(
              key: const Key('chat_review_send'),
              onPressed: _review,
              icon: const Icon(Icons.rate_review_outlined, size: 16),
              label: Text(
                context.l10n.reviewSendButton,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final String peerNickname;
  const _EmptyChat({required this.peerNickname});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💨', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              context.l10n.chatEmptyTitle(peerNickname),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: EggplantColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.chatEmptyNote,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: EggplantColors.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  /// When the peer last read THIS room. If non-null and >= message.sentAt,
  /// the bubble shows "읽음" instead of just the timestamp.
  final DateTime? peerLastReadAt;
  /// 글자 대신 그릴 내용 (사진 등). 있으면 말풍선 배경 없이 그대로 그린다.
  final Widget? child;
  const _MessageBubble({required this.message, this.peerLastReadAt, this.child});

  @override
  Widget build(BuildContext context) {
    if (message.type == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.text,
            style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary),
          ),
        ),
      );
    }

    final mine = message.isMine;
    final time = DateFormat('HH:mm').format(message.sentAt);
    // 당근식 읽음 표시 우선순위:
    //   1) 메시지 단위 `isRead` (read_receipt 수신 시 ChatService 가 갱신) — 정확.
    //   2) 방 단위 `peerLastReadAt` >= sent_at (fallback, 과거 메시지/리스트 진입 직전).
    // 둘 다 false 면 회색 '1' 을 보여줘서 "아직 안 읽음" 을 표시.
    final read = mine &&
        (message.isRead ||
            (peerLastReadAt != null &&
                !message.sentAt.isAfter(peerLastReadAt!)));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mine) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (read)
                  Text(
                    context.l10n.chatRead,
                    style: const TextStyle(
                      fontSize: 10,
                      color: EggplantColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  // 당근마켓식 회색 '1' — 상대가 아직 읽지 않은 내 메시지.
                  // read_receipt 수신 시 isRead=true 로 바뀌어 사라진다.
                  const Text(
                    '1',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFFB300), // 카카오/당근식 옅은 황색
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 10,
                    color: EggplantColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
          // 버블이 가로로 너무 길어지지 않도록 화면폭의 약 72% 까지만 사용.
          // (시간/읽음 표시를 위한 좌우 여백 확보 + 태블릿/폴드에서도 자연스러운 길이)
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: child ?? Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: mine ? EggplantColors.primary : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 16),
                  ),
                  border: mine ? null : Border.all(color: EggplantColors.border),
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 14,
                    color: mine ? Colors.white : EggplantColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          if (!mine) const SizedBox(width: 4),
          if (!mine)
            Text(time, style: const TextStyle(fontSize: 10, color: EggplantColors.textTertiary)),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool connected;
  /// 가격 제안 버튼 핸들러. null 이면 버튼 숨김 (상품 첨부되지 않은 방).
  final VoidCallback? onOffer;
  /// + 버튼 (사진 · 카메라 · 약속 잡기). null 이면 비활성.
  final VoidCallback? onAttach;
  final bool sendingPhoto;

  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.connected,
    this.onOffer,
    this.onAttach,
    this.sendingPhoto = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: EggplantColors.border)),
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 10,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          if (sendingPhoto)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: EggplantColors.primary),
              ),
            )
          else
            IconButton(
              tooltip: context.l10n.chatAttachTooltip,
              icon: const Icon(Icons.add_circle_outline, color: EggplantColors.primary),
              onPressed: onAttach,
            ),
          if (onOffer != null)
            IconButton(
              tooltip: context.l10n.chatOfferLabel,
              icon: const Icon(
                Icons.payments_outlined,
                color: EggplantColors.primary,
              ),
              onPressed: onOffer,
            ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: connected ? context.l10n.chatInputHint : context.l10n.chatConnecting,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: EggplantColors.background,
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: EggplantColors.primary,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: onSend,
            ),
          ),
        ],
      ),
    );
  }
}

/// 가격 제안(price_offer) 메시지 전용 풍선.
///
/// 상태(pending/accepted/rejected/cancelled)에 따라 색상과 액션 버튼이 달라진다.
///   - pending + 내가 판매자: [거절] [수락] 두 버튼
///   - pending + 내가 구매자: [제안 취소] 버튼
///   - 그 외(이미 처리된 제안): 상태 칩만
class _PriceOfferCard extends StatelessWidget {
  final ChatMessage message;
  final String? myUserId;
  final String market;
  final void Function(String action) onRespond;

  const _PriceOfferCard({
    required this.message,
    required this.myUserId,
    required this.market,
    required this.onRespond,
  });

  @override
  Widget build(BuildContext context) {
    final offer = message.offer!;
    final mine = message.isMine;
    final iAmSeller = myUserId != null && myUserId == offer.sellerId;
    final iAmBuyer = myUserId != null && myUserId == offer.buyerId;

    final time = DateFormat('HH:mm').format(message.sentAt);
    final accent = _accentForStatus(offer.status);
    final bg = _bgForStatus(offer.status);
    // 가격제안도 일반 메시지와 동일하게 읽음 표시 (메시지 단위 isRead 우선).
    final read = mine && message.isRead;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mine) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (read)
                  Text(
                    context.l10n.chatRead,
                    style: const TextStyle(
                      fontSize: 10,
                      color: EggplantColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  const Text(
                    '1',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFFB300),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 10,
                    color: EggplantColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 16),
                  ),
                  border: Border.all(color: accent.withOpacity(0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.payments_rounded, size: 16, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.chatOfferLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: EggplantColors.textSecondary,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            offer.statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      offer.priceLabelFor(market),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: EggplantColors.textPrimary,
                      ),
                    ),
                    if (offer.isPending) ...[
                      const SizedBox(height: 10),
                      _buildActionRow(context, iAmSeller, iAmBuyer),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (!mine) ...[
            const SizedBox(width: 4),
            Text(
              time,
              style: const TextStyle(
                fontSize: 10,
                color: EggplantColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, bool iAmSeller, bool iAmBuyer) {
    if (iAmSeller) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: EggplantColors.error,
                side: const BorderSide(color: EggplantColors.error),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => onRespond('reject'),
              child: Text(
                context.l10n.chatOfferReject,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: EggplantColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => onRespond('accept'),
              child: Text(
                context.l10n.chatOfferAccept,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      );
    }
    if (iAmBuyer) {
      return SizedBox(
        width: double.infinity,
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: EggplantColors.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 6),
          ),
          onPressed: () => onRespond('cancel'),
          child: Text(
            context.l10n.chatOfferCancelButton,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Color _accentForStatus(String status) {
    switch (status) {
      case 'accepted':
        return EggplantColors.primary;
      case 'rejected':
        return EggplantColors.error;
      case 'cancelled':
        return EggplantColors.textSecondary;
      case 'pending':
      default:
        return EggplantColors.primary;
    }
  }

  Color _bgForStatus(String status) {
    switch (status) {
      case 'accepted':
        return const Color(0xFFEEF7F0); // soft green-ish
      case 'rejected':
        return const Color(0xFFFDECEC);
      case 'cancelled':
        return const Color(0xFFF3F4F6);
      case 'pending':
      default:
        return Colors.white;
    }
  }
}


/// 채팅 사진 — 암호문을 받아 폰에서 연다. 누르면 크게 보기.
class _ChatPhoto extends StatefulWidget {
  final ChatMessage message;
  const _ChatPhoto({required this.message});

  @override
  State<_ChatPhoto> createState() => _ChatPhotoState();
}

class _ChatPhotoState extends State<_ChatPhoto> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = context
        .read<ChatService>()
        .loadImage(widget.message.image!, mine: widget.message.isMine);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.message.image!;
    final maxW = MediaQuery.of(context).size.width * 0.6;
    final ratio = (info.width > 0 && info.height > 0) ? info.width / info.height : 1.0;
    final w = maxW;
    final h = (w / ratio).clamp(120.0, maxW * 1.4);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: w,
        height: h,
        child: FutureBuilder<Uint8List?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Container(
                color: Colors.white,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: EggplantColors.primary),
                ),
              );
            }
            final bytes = snap.data;
            if (bytes == null) {
              return InkWell(
                onTap: () => setState(_load),
                child: Container(
                  color: Colors.white,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.image_not_supported_outlined, color: EggplantColors.textTertiary),
                      const SizedBox(height: 6),
                      Text(context.l10n.chatPhotoUnavailable,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary)),
                    ],
                  ),
                ),
              );
            }
            return GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => _ChatPhotoViewer(bytes: bytes),
              )),
              child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            );
          },
        ),
      ),
    );
  }
}

class _ChatPhotoViewer extends StatelessWidget {
  final Uint8List bytes;
  const _ChatPhotoViewer({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: Image.memory(bytes),
        ),
      ),
    );
  }
}

String _appointmentLabel(BuildContext context, DateTime at) {
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.MMMEd(locale).add_jm().format(at);
}

/// 방 맨 위 약속 띠 — 누르면 약속 바꾸기/취소.
class _AppointmentBanner extends StatelessWidget {
  final AppointmentInfo appointment;
  final VoidCallback onTap;
  const _AppointmentBanner({required this.appointment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final place = appointment.place;
    return Material(
      color: EggplantColors.primary.withOpacity(0.08),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.event_available, size: 18, color: EggplantColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  place.isEmpty
                      ? _appointmentLabel(context, appointment.at)
                      : '${_appointmentLabel(context, appointment.at)} · ${place}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: EggplantColors.primary,
                  ),
                ),
              ),
              Text(context.l10n.chatAppointmentChange,
                  style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 약속 메시지 카드 (가운데).
class _AppointmentCard extends StatelessWidget {
  final ChatMessage message;
  const _AppointmentCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final a = message.appointment!;
    final mine = message.isMine;
    final who = message.senderNickname;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: a.cancelled ? EggplantColors.border : EggplantColors.primary),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(a.cancelled ? Icons.event_busy : Icons.event_available,
                color: a.cancelled ? EggplantColors.textTertiary : EggplantColors.primary),
            const SizedBox(height: 6),
            Text(
              a.cancelled
                  ? (mine ? context.l10n.chatAppointmentCancelledByMe : context.l10n.chatAppointmentCancelledBy(who))
                  : (mine ? context.l10n.chatAppointmentSetByMe : context.l10n.chatAppointmentSetBy(who)),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary),
            ),
            if (!a.cancelled) ...[
              const SizedBox(height: 6),
              Text(_appointmentLabel(context, a.at),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              if (a.place.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(a.place,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: EggplantColors.textPrimary)),
              ],
              const SizedBox(height: 6),
              Text(context.l10n.chatAppointmentReminderNote,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, color: EggplantColors.textTertiary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppointmentResult {
  final DateTime? at;
  final String place;
  final bool cancel;
  const _AppointmentResult({this.at, this.place = '', this.cancel = false});
}

/// 약속 잡기 시트 — 날짜 · 시간 · 장소.
class _AppointmentSheet extends StatefulWidget {
  final AppointmentInfo? initial;
  const _AppointmentSheet({this.initial});

  @override
  State<_AppointmentSheet> createState() => _AppointmentSheetState();
}

class _AppointmentSheetState extends State<_AppointmentSheet> {
  late DateTime _date;
  late TimeOfDay _time;
  late final TextEditingController _placeCtl =
      TextEditingController(text: widget.initial?.place ?? '');
  String? _error;

  @override
  void initState() {
    super.initState();
    final base = widget.initial?.at ??
        DateTime.now().add(const Duration(hours: 1));
    _date = DateTime(base.year, base.month, base.day);
    _time = TimeOfDay(hour: base.hour, minute: widget.initial == null ? 0 : base.minute);
  }

  @override
  void dispose() {
    _placeCtl.dispose();
    super.dispose();
  }

  DateTime get _at => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(now) ? now : _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (d != null) setState(() { _date = d; _error = null; });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() { _time = t; _error = null; });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.initial == null ? l10n.chatAppointmentTitle : l10n.chatAppointmentEditTitle,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(DateFormat.MMMEd(locale).format(_date)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_time.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _placeCtl,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: l10n.chatAppointmentPlace,
                hintText: l10n.productFieldMeetPlaceHint,
                prefixIcon: const Icon(Icons.place_outlined, size: 20),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(fontSize: 12.5, color: Colors.redAccent)),
              ),
            Row(
              children: [
                if (widget.initial != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, const _AppointmentResult(cancel: true)),
                      child: Text(l10n.chatAppointmentCancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      if (!_at.isAfter(DateTime.now())) {
                        setState(() => _error = l10n.chatAppointmentPast);
                        return;
                      }
                      Navigator.pop(context, _AppointmentResult(at: _at, place: _placeCtl.text.trim()));
                    },
                    child: Text(l10n.chatAppointmentSend),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
