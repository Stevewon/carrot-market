import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../app/constants.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';

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
  final _descCtl = TextEditingController();
  final _youtubeCtl = TextEditingController();

  String _category = 'digital';
  final List<File> _images = [];
  File? _videoFile;
  VideoPlayerController? _videoPreviewCtl;
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtl.dispose();
    _priceCtl.dispose();
    _descCtl.dispose();
    _youtubeCtl.dispose();
    _videoPreviewCtl?.dispose();
    super.dispose();
  }

  // ---------- Image picking ----------

  Future<void> _showImageSourceSheet() async {
    if (_images.length >= _maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('최대 $_maxImages장까지 등록 가능해요')),
      );
      return;
    }
    final source = await showModalBottomSheet<_PickSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => const _PickSourceSheet(
        title: '사진 추가',
        showGallery: true,
        showCamera: true,
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picker = ImagePicker();
      if (source == _PickSource.camera) {
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 80,
        );
        if (picked != null) {
          setState(() => _images.add(File(picked.path)));
        }
      } else {
        final remaining = _maxImages - _images.length;
        final picked = await picker.pickMultiImage(
          imageQuality: 80,
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
        SnackBar(content: Text('사진을 가져오지 못했어요: $e')),
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
      builder: (_) => const _PickSourceSheet(
        title: '영상 추가',
        showGallery: true,
        showCamera: true,
        showYouTube: true,
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picker = ImagePicker();
      if (source == _PickSource.camera) {
        final picked = await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 60),
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
        SnackBar(content: Text('영상을 가져오지 못했어요: $e')),
      );
    }
  }

  Future<void> _setVideoFile(File f) async {
    final size = await f.length();
    if (size > 50 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('영상 크기는 50MB 이하여야 해요')),
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
          title: const Text('유튜브 링크 추가'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '유튜브 영상 URL을 붙여넣어 주세요.\n예: https://youtu.be/xxxxxxxxxxx',
                style: TextStyle(fontSize: 13, color: EggplantColors.textSecondary),
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
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, ctl.text.trim()),
              child: const Text('확인'),
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
        const SnackBar(content: Text('유튜브 링크 형식이 올바르지 않아요')),
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
        const SnackBar(content: Text('먼저 동네를 설정해주세요')),
      );
      context.push('/region');
      return;
    }

    setState(() => _submitting = true);
    final price = int.tryParse(
          _priceCtl.text.replaceAll(',', '').replaceAll(' ', ''),
        ) ??
        0;

    final err = await context.read<ProductService>().createProduct(
          title: _titleCtl.text.trim(),
          description: _descCtl.text.trim(),
          price: price,
          category: _category,
          region: auth.user!.region!,
          imageFiles: _images,
          youtubeUrl: _youtubeCtl.text.trim(),
          videoFile: _videoFile,
        );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품이 등록되었어요 🍆')),
      );
      context.read<ProductService>().fetchProducts(region: auth.user!.region);
      context.pop();
    }
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('중고거래 글쓰기'),
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
                : const Text(
                    '완료',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: EggplantColors.primary,
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildImageStrip(),
            const SizedBox(height: 16),
            _buildVideoStrip(),
            const SizedBox(height: 24),
            TextFormField(
              controller: _titleCtl,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '상품명을 입력해주세요',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '제목을 입력해주세요';
                return null;
              },
            ),
            const SizedBox(height: 16),
            const Text('카테고리', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: Categories.all
                  .where((c) => c.id != 'all')
                  .map((c) => ChoiceChip(
                        label: Text('${c.emoji} ${c.label}'),
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
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '가격',
                hintText: '0 (나눔하려면 0원)',
                prefixText: '₩ ',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return '가격을 입력해주세요';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtl,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '자세한 설명',
                hintText:
                    '게시글 등록 전에 체크해주세요.\n- 판매금지물품인지 확인\n- 카테고리가 적절한지 확인\n\n상품의 상태, 사용기간 등을 자세히 적어주세요.',
                alignLabelWithHint: true,
              ),
              validator: (v) {
                if (v == null || v.trim().length < 10) return '10자 이상 입력해주세요';
                return null;
              },
            ),
            const SizedBox(height: 32),
          ],
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
            const Text('사진',
                style: TextStyle(
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
            const Text('영상',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            const Text(
              '(선택)',
              style: TextStyle(
                fontSize: 12,
                color: EggplantColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            if (hasYouTube || hasFile)
              TextButton.icon(
                onPressed: _removeVideo,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('제거'),
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
            label: '영상 추가',
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
                label: '카메라로 촬영',
                onTap: () => Navigator.pop(context, _PickSource.camera),
              ),
            if (showGallery)
              _SheetTile(
                icon: Icons.photo_library_rounded,
                label: '갤러리에서 선택',
                onTap: () => Navigator.pop(context, _PickSource.gallery),
              ),
            if (showYouTube)
              _SheetTile(
                icon: Icons.play_circle_fill_rounded,
                iconColor: Colors.red,
                label: '유튜브 링크 붙여넣기',
                onTap: () => Navigator.pop(context, _PickSource.youtube),
              ),
            const SizedBox(height: 4),
            _SheetTile(
              icon: Icons.close_rounded,
              label: '취소',
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
          child: Image.file(file, width: 92, height: 92, fit: BoxFit.cover),
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
              child: const Text(
                '대표',
                style: TextStyle(
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
                  const Text(
                    '유튜브 영상',
                    style: TextStyle(
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
