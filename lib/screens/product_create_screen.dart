import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../app/constants.dart';
import '../app/l10n.dart';
import '../app/market.dart';
import '../app/responsive.dart';
import '../app/theme.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/qta_service.dart';
import 'prohibited_items_screen.dart';

class ProductCreateScreen extends StatefulWidget {
  const ProductCreateScreen({super.key});

  @override
  State<ProductCreateScreen> createState() => _ProductCreateScreenState();
}

class _ProductCreateScreenState extends State<ProductCreateScreen> {
  static const int _maxImages = 10; // 당근과 동일

  final _formKey = GlobalKey<FormState>();
  final _titleCtl = TextEditingController();
  final _priceCtl = TextEditingController();
  final _qtaPriceCtl = TextEditingController();

  /// QTA 가격 입력은 본인인증(Lv1) 판매자에게만 보인다.
  bool get _canSetQtaPrice =>
      context.read<AuthService>().user?.isIdentityVerified ?? false;

  /// 가격 입력 화폐 — 지금 회원의 시장(kr 원 / jp 엔).
  String get _market => AppMarket.of(context.read<AuthService>().user);
  final _descCtl = TextEditingController();
  final _youtubeCtl = TextEditingController();
  final _meetCtl = TextEditingController();

  String _category = 'digital';
  final List<File> _images = [];
  File? _videoFile;
  VideoPlayerController? _videoPreviewCtl;
  bool _submitting = false;

  // ---------- 임시저장 (당근식: 쓰다가 나가도 다음에 이어 쓰기) ----------
  static const _draftKey = 'product_draft_v1';
  bool _submitted = false;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    for (final c in [_titleCtl, _priceCtl, _qtaPriceCtl, _descCtl, _meetCtl]) {
      c.addListener(_scheduleDraftSave);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerDraft());
  }

  bool get _hasContent =>
      _titleCtl.text.trim().isNotEmpty ||
      _descCtl.text.trim().isNotEmpty ||
      _priceCtl.text.trim().isNotEmpty ||
      _meetCtl.text.trim().isNotEmpty ||
      _images.isNotEmpty;

  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 800), _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (_submitted) return;
    // dispose 중에도 불리므로 값은 기다리기 전에 먼저 읽어 둔다.
    final draft = _hasContent
        ? jsonEncode({
            'title': _titleCtl.text,
            'price': _priceCtl.text,
            'qta': _qtaPriceCtl.text,
            'desc': _descCtl.text,
            'meet': _meetCtl.text,
            'youtube': _youtubeCtl.text,
            'category': _category,
            'images': _images.map((f) => f.path).toList(),
            'saved_at': DateTime.now().toIso8601String(),
          })
        : null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (draft == null) {
        await prefs.remove(_draftKey);
      } else {
        await prefs.setString(_draftKey, draft);
      }
    } catch (e) {
      debugPrint('[product-draft] save failed: $e');
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  Future<void> _offerDraft() async {
    Map<String, dynamic>? d;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null) return;
      d = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.productDraftTitle),
        content: Text(ctx.l10n.productDraftBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.productDraftDiscard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.productDraftResume),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (resume != true) {
      await _clearDraft();
      return;
    }
    setState(() {
      _titleCtl.text = (d!['title'] ?? '').toString();
      _priceCtl.text = (d['price'] ?? '').toString();
      _qtaPriceCtl.text = (d['qta'] ?? '').toString();
      _descCtl.text = (d['desc'] ?? '').toString();
      _meetCtl.text = (d['meet'] ?? '').toString();
      _youtubeCtl.text = (d['youtube'] ?? '').toString();
      final cat = (d['category'] ?? '').toString();
      if (Categories.all.any((c) => c.id == cat && c.id != 'all')) _category = cat;
      // 사진은 폰 임시 폴더에 있어서 지워졌을 수 있다 → 남아 있는 것만.
      final paths = (d['images'] as List? ?? const []).map((e) => e.toString());
      _images
        ..clear()
        ..addAll(paths.map(File.new).where((f) => f.existsSync()).take(_maxImages));
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    // 화면을 나갈 때 마지막 내용 저장 (등록을 마쳤으면 저장 안 함).
    if (!_submitted) _saveDraft();
    _meetCtl.dispose();
    _titleCtl.dispose();
    _priceCtl.dispose();
    _qtaPriceCtl.dispose();
    _descCtl.dispose();
    _youtubeCtl.dispose();
    _videoPreviewCtl?.dispose();
    super.dispose();
  }

  // ---------- Image picking ----------

  Future<void> _showImageSourceSheet() async {
    if (_images.length >= _maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.productMaxImages(_maxImages))),
      );
      return;
    }
    final source = await showModalBottomSheet<_PickSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => _PickSourceSheet(
        title: context.l10n.productAddPhoto,
        showGallery: true,
        showCamera: true,
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picker = ImagePicker();
      if (source == _PickSource.camera) {
        // 상품 사진은 무조건 후면 카메라(셀카 모드 방지)
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 80,
          // 12~50MP 원본을 그대로 올리면 LTE 에서 느리고 타임아웃 위험 — 1600px 로 축소.
          maxWidth: 1600,
          maxHeight: 1600,
          preferredCameraDevice: CameraDevice.rear,
        );
        if (picked != null) {
          setState(() => _images.add(File(picked.path)));
        }
      } else {
        final remaining = _maxImages - _images.length;
        final picked = await picker.pickMultiImage(
          imageQuality: 80,
          // 12~50MP 원본을 그대로 올리면 LTE 에서 느리고 타임아웃 위험 — 1600px 로 축소.
          maxWidth: 1600,
          maxHeight: 1600,
          limit: remaining,
        );
        if (picked.isNotEmpty) {
          final take = picked.take(remaining).toList();
          setState(() {
            _images.addAll(take.map((x) => File(x.path)));
          });
        }
      }
    } catch (e) {
      debugPrint('image pick error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.productPhotoPickFailed)),
      );
    }
  }

  // ---------- Video picking ----------

  Future<void> _showVideoSourceSheet() async {
    final source = await showModalBottomSheet<_PickSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => _PickSourceSheet(
        title: context.l10n.productAddVideo,
        showGallery: true,
        showCamera: true,
        showYouTube: true,
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picker = ImagePicker();
      if (source == _PickSource.camera) {
        // 상품 영상도 무조건 후면 카메라(셀카 모드 방지)
        final picked = await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 60),
          preferredCameraDevice: CameraDevice.rear,
        );
        if (picked != null) await _setVideoFile(File(picked.path));
      } else if (source == _PickSource.gallery) {
        final picked = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 3),
        );
        if (picked != null) await _setVideoFile(File(picked.path));
      } else if (source == _PickSource.youtube) {
        await _showYouTubeDialog();
      }
    } catch (e) {
      debugPrint('video pick error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.productVideoPickFailed)),
      );
    }
  }

  Future<void> _setVideoFile(File f) async {
    final size = await f.length();
    if (size > 50 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.productVideoTooLarge)),
      );
      return;
    }
    _videoPreviewCtl?.dispose();
    final ctl = VideoPlayerController.file(f);
    await ctl.initialize();
    if (!mounted) {
      ctl.dispose();
      return;
    }
    setState(() {
      _videoFile = f;
      _youtubeCtl.clear(); // 영상 파일이 우선
      _videoPreviewCtl = ctl;
    });
  }

  Future<void> _showYouTubeDialog() async {
    final ctl = TextEditingController(text: _youtubeCtl.text);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(dialogCtx.l10n.productYoutubeAddTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dialogCtx.l10n.productYoutubeAddBody,
                style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'https://youtu.be/...',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(dialogCtx.l10n.commonCancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, ctl.text.trim()),
              child: Text(dialogCtx.l10n.commonConfirm),
            ),
          ],
        );
      },
    );
    if (result == null || !mounted) return;
    final trimmed = result.trim();
    if (trimmed.isEmpty) return;
    // Validate loosely
    final re = RegExp(
      r'(?:youtu\.be/|youtube\.com/(?:watch\?v=|shorts/|embed/))([A-Za-z0-9_-]{6,20})',
    );
    if (!re.hasMatch(trimmed)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.productYoutubeInvalid)),
      );
      return;
    }
    setState(() {
      _youtubeCtl.text = trimmed;
      _videoPreviewCtl?.dispose();
      _videoPreviewCtl = null;
      _videoFile = null; // 유튜브 링크가 우선
    });
  }

  void _removeVideo() {
    _videoPreviewCtl?.dispose();
    setState(() {
      _videoFile = null;
      _videoPreviewCtl = null;
      _youtubeCtl.clear();
    });
  }

  // ---------- Submit ----------

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    if (auth.user?.region == null || auth.user!.region!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.productSetRegionFirst)),
      );
      context.push('/region');
      return;
    }

    setState(() => _submitting = true);
    final price = int.tryParse(
          _priceCtl.text.replaceAll(',', '').replaceAll(' ', ''),
        ) ??
        0;
    final qtaPrice = int.tryParse(
          _qtaPriceCtl.text.replaceAll(',', '').replaceAll(' ', ''),
        ) ??
        0;

    // 절대 데드라인 — 영상·이미지 업로드는 5분(서버 timeout)이지만
    // 사용자 입장에서 무한로딩 인식 방지. 5분 30초 시점엔 무조건 풀고 안내.
    String? err;
    try {
      err = await context
          .read<ProductService>()
          .createProduct(
            title: _titleCtl.text.trim(),
            description: _descCtl.text.trim(),
            price: price,
            qtaPrice: qtaPrice,
            category: _category,
            region: auth.user!.region!,
            imageFiles: _images,
            youtubeUrl: _youtubeCtl.text.trim(),
            videoFile: _videoFile,
            meetPlace: _meetCtl.text.trim(),
          )
          .timeout(const Duration(minutes: 5, seconds: 30));
    } on TimeoutException {
      err = L10n.current.productUploadTimeout;
    } catch (e) {
      debugPrint('[product-create] unexpected error: $e');
      err = L10n.current.productCreateUnexpectedError;
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    if (err != null) {
      showProductError(context, err);
    } else {
      _submitted = true;
      _draftTimer?.cancel();
      await _clearDraft();
      if (!mounted) return;
      final reward = context.read<ProductService>().lastListingReward;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reward > 0
              ? context.l10n.productCreatedWithReward(reward)
              : context.l10n.productCreated),
        ),
      );
      if (reward > 0) context.read<QtaService>().load(force: true);
      context.read<ProductService>().refresh();
      context.pop();
    }
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.productCreateTitle),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: EggplantColors.primary),
                  )
                : Text(
                    context.l10n.productDone,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: EggplantColors.primary,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Responsive.maxContentWidth),
            child: Form(
              key: _formKey,
              // ListView 는 화면 밖 필드를 build 하지 않아서, 작은 폰에서 아래쪽 설명 필드의
              // 검증(10자 이상)이 건너뛰어졌다 → 모든 필드가 항상 만들어지는 스크롤 Column.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            _buildImageStrip(),
            const SizedBox(height: 16),
            _buildVideoStrip(),
            const SizedBox(height: 24),
            TextFormField(
              controller: _titleCtl,
              decoration: InputDecoration(
                labelText: context.l10n.productFieldTitle,
                hintText: context.l10n.productFieldTitleHint,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return context.l10n.productFieldTitleRequired;
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text(context.l10n.productFieldCategory, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: Categories.all
                  .where((c) => c.id != 'all')
                  .map((c) => ChoiceChip(
                        label: Text('${c.emoji} ${categoryLabel(c.id)}'),
                        selected: _category == c.id,
                        onSelected: (_) => setState(() => _category = c.id),
                        selectedColor: EggplantColors.primary,
                        labelStyle: TextStyle(
                          color: _category == c.id
                              ? Colors.white
                              : EggplantColors.textPrimary,
                          fontSize: 13,
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceCtl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _ThousandsSeparatorFormatter(),
              ],
              decoration: InputDecoration(
                labelText: context.l10n.productFieldPrice,
                hintText: AppMarket.isJp(_market)
                    ? context.l10n.productFieldPriceHintJpy
                    : AppMarket.isPh(_market)
                        ? context.l10n.productFieldPriceHintPhp
                        : context.l10n.productFieldPriceHintKrw,
                prefixText: AppMarket.currencyPrefix(_market),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return context.l10n.productFieldPriceRequired;
                return null;
              },
            ),
            const SizedBox(height: 16),
            // QTA 가격은 본인인증한 판매자만 (서버도 같은 기준). 1차 출시는 본인인증이
            // 준비 중이라 대부분 숨겨진다 — 원화 가격만으로 거래.
            if (_canSetQtaPrice) ...[
              TextFormField(
                controller: _qtaPriceCtl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _ThousandsSeparatorFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: context.l10n.productFieldQtaPrice,
                  hintText: context.l10n.productFieldQtaPriceHint,
                  prefixIcon: const Icon(Icons.token_outlined, size: 20),
                  helperText: context.l10n.productFieldQtaPriceHelper,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _descCtl,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: context.l10n.productFieldDescription,
                hintText: context.l10n.productFieldDescriptionHint,
                alignLabelWithHint: true,
              ),
              validator: (v) {
                if (v == null || v.trim().length < 10) return context.l10n.productFieldDescriptionMin;
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _meetCtl,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: context.l10n.productFieldMeetPlace,
                hintText: context.l10n.productFieldMeetPlaceHint,
                prefixIcon: const Icon(Icons.place_outlined, size: 20),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => ProhibitedItemsScreen.open(context),
                icon: const Icon(Icons.block, size: 16),
                label: Text(context.l10n.productProhibitedGuide),
                style: TextButton.styleFrom(
                  foregroundColor: EggplantColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(context.l10n.productPhotos,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text(
              '${_images.length} / $_maxImages',
              style: TextStyle(
                fontSize: 13,
                color: _images.length >= _maxImages
                    ? EggplantColors.error
                    : EggplantColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _images.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              if (i == 0) {
                return _AddThumbnail(
                  onTap: _showImageSourceSheet,
                  label: '${_images.length}/$_maxImages',
                  icon: Icons.camera_alt_outlined,
                );
              }
              final img = _images[i - 1];
              return _ImageThumbnail(
                file: img,
                isRepresentative: i == 1,
                onRemove: () => setState(() => _images.removeAt(i - 1)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVideoStrip() {
    final hasYouTube = _youtubeCtl.text.trim().isNotEmpty;
    final hasFile = _videoFile != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(context.l10n.productVideo,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(
              context.l10n.productOptional,
              style: const TextStyle(
                fontSize: 12,
                color: EggplantColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            if (hasYouTube || hasFile)
              TextButton.icon(
                onPressed: _removeVideo,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: Text(context.l10n.productRemove),
                style: TextButton.styleFrom(
                  foregroundColor: EggplantColors.error,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (!hasYouTube && !hasFile)
          _AddThumbnail(
            onTap: _showVideoSourceSheet,
            label: context.l10n.productAddVideo,
            icon: Icons.videocam_outlined,
            wide: true,
          )
        else if (hasYouTube)
          _YouTubeCard(url: _youtubeCtl.text, onChange: _showYouTubeDialog)
        else if (_videoPreviewCtl != null &&
            _videoPreviewCtl!.value.isInitialized)
          _VideoPreviewCard(controller: _videoPreviewCtl!)
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

// ===================== Sub widgets =====================

enum _PickSource { camera, gallery, youtube }

class _PickSourceSheet extends StatelessWidget {
  final String title;
  final bool showCamera;
  final bool showGallery;
  final bool showYouTube;

  const _PickSourceSheet({
    required this.title,
    this.showCamera = false,
    this.showGallery = false,
    this.showYouTube = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: EggplantColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (showCamera)
              _SheetTile(
                icon: Icons.camera_alt_rounded,
                label: context.l10n.productPickCamera,
                onTap: () => Navigator.pop(context, _PickSource.camera),
              ),
            if (showGallery)
              _SheetTile(
                icon: Icons.photo_library_rounded,
                label: context.l10n.productPickGallery,
                onTap: () => Navigator.pop(context, _PickSource.gallery),
              ),
            if (showYouTube)
              _SheetTile(
                icon: Icons.play_circle_fill_rounded,
                iconColor: Colors.red,
                label: context.l10n.productPickYoutube,
                onTap: () => Navigator.pop(context, _PickSource.youtube),
              ),
            const SizedBox(height: 4),
            _SheetTile(
              icon: Icons.close_rounded,
              label: context.l10n.commonCancel,
              onTap: () => Navigator.pop(context),
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool dense;

  const _SheetTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? EggplantColors.primary, size: 24),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: dense ? FontWeight.w500 : FontWeight.w600,
          color: dense ? EggplantColors.textSecondary : EggplantColors.textPrimary,
        ),
      ),
      onTap: onTap,
      dense: dense,
    );
  }
}

class _AddThumbnail extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final bool wide;

  const _AddThumbnail({
    required this.onTap,
    required this.label,
    required this.icon,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = wide ? double.infinity : 92.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: w,
          height: 92,
          decoration: BoxDecoration(
            color: EggplantColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: EggplantColors.primary.withOpacity(0.3),
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: EggplantColors.primary, size: 26),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: EggplantColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  final File file;
  final bool isRepresentative;
  final VoidCallback onRemove;

  const _ImageThumbnail({
    required this.file,
    required this.isRepresentative,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(file, width: 92, height: 92, fit: BoxFit.cover, cacheWidth: 276),
        ),
        if (isRepresentative)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                context.l10n.productCoverPhoto,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black54,
              ),
              padding: const EdgeInsets.all(3),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _YouTubeCard extends StatelessWidget {
  final String url;
  final VoidCallback onChange;
  const _YouTubeCard({required this.url, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChange,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.play_circle_fill_rounded,
                color: Colors.red, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.productYoutubeVideo,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: EggplantColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined,
                color: EggplantColors.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}

class _VideoPreviewCard extends StatelessWidget {
  final VideoPlayerController controller;
  const _VideoPreviewCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final aspect = controller.value.aspectRatio == 0
        ? 16 / 9
        : controller.value.aspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(controller),
            GestureDetector(
              onTap: () {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              },
              child: Container(
                color: Colors.black26,
                child: Center(
                  child: Icon(
                    controller.value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 입력 도중 천단위마다 콤마(,)를 자동 삽입하는 InputFormatter.
/// - 항상 digitsOnly 와 함께 사용 (콤마 외 비숫자 문자가 들어오지 않음을 가정)
/// - 0 으로 시작하는 입력은 1글자로 정규화 ("0", "00" → "0")
/// - 빈 문자열은 그대로 유지
/// - 백엔드 전송 시에는 호출부에서 ',' 를 제거하고 int 로 변환
class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) {
      return const TextEditingValue(text: '');
    }
    // 숫자만 남긴 뒤 정수로 변환 (앞쪽 0 제거)
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    // 앞쪽 0 제거하되 "0" 한 글자는 허용
    final normalized = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final formatted = _withCommas(normalized);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String _withCommas(String digits) {
    final buf = StringBuffer();
    final n = digits.length;
    for (var i = 0; i < n; i++) {
      final remain = n - i;
      buf.write(digits[i]);
      if (remain > 1 && remain % 3 == 1) {
        buf.write(',');
      }
    }
    return buf.toString();
  }
}
