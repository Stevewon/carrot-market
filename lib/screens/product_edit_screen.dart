import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/constants.dart';
import '../app/responsive.dart';
import '../app/theme.dart';
import '../models/product.dart';
import '../services/product_service.dart';

/// Edit an existing product.
///
/// Fields you can change:
///   제목, 가격, 카테고리, 설명, 유튜브 링크 (또는 비우기)
///
/// Images / uploaded videos are intentionally not editable from here —
/// to replace media, delete the product and re-upload (keeps the backend
/// logic simple and avoids orphan R2 files).
class ProductEditScreen extends StatefulWidget {
  final String productId;
  const ProductEditScreen({super.key, required this.productId});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtl = TextEditingController();
  final _priceCtl = TextEditingController();
  final _qtaPriceCtl = TextEditingController();
  final _descCtl = TextEditingController();
  final _youtubeCtl = TextEditingController();

  String _category = 'digital';
  Product? _original;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _priceCtl.dispose();
    _qtaPriceCtl.dispose();
    _descCtl.dispose();
    _youtubeCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p =
        await context.read<ProductService>().fetchById(widget.productId);
    if (!mounted) return;
    if (p == null) {
      setState(() {
        _loading = false;
        _error = '상품을 찾을 수 없어요';
      });
      return;
    }
    setState(() {
      _original = p;
      _titleCtl.text = p.title;
      _priceCtl.text = p.price.toString();
      _qtaPriceCtl.text = p.qtaPrice > 0 ? p.qtaPrice.toString() : '';
      _descCtl.text = p.description;
      _category = p.category;
      // Only pre-fill YouTube URLs (not uploaded /uploads/ videos).
      if (p.videoUrl.startsWith('http')) {
        _youtubeCtl.text = p.videoUrl;
      }
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_original == null) return;

    final newTitle = _titleCtl.text.trim();
    final newDesc = _descCtl.text.trim();
    final newPrice = int.tryParse(
          _priceCtl.text.replaceAll(',', '').replaceAll(' ', ''),
        ) ??
        0;
    final newQtaPrice = int.tryParse(
          _qtaPriceCtl.text.replaceAll(',', '').replaceAll(' ', ''),
        ) ??
        0;
    final newYt = _youtubeCtl.text.trim();

    // Compute which fields actually changed.
    final data = <String, dynamic>{};
    if (newTitle != _original!.title) data['title'] = newTitle;
    if (newDesc != _original!.description) data['description'] = newDesc;
    if (newPrice != _original!.price) data['price'] = newPrice;
    if (newQtaPrice != _original!.qtaPrice) data['qta_price'] = newQtaPrice;
    if (_category != _original!.category) data['category'] = _category;

    final originalYt = _original!.videoUrl.startsWith('http')
        ? _original!.videoUrl
        : '';
    if (newYt != originalYt) data['youtube_url'] = newYt;

    if (data.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('변경된 내용이 없어요')));
      return;
    }

    setState(() => _submitting = true);
    final err = await context.read<ProductService>().updateProduct(
          widget.productId,
          title: data['title'] as String?,
          description: data['description'] as String?,
          price: data['price'] as int?,
          qtaPrice: data['qta_price'] as int?,
          category: data['category'] as String?,
          youtubeUrl: data['youtube_url'] as String?,
        );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('상품을 수정했어요 ✨')),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: EggplantColors.primary),
        ),
      );
    }
    if (_error != null || _original == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(_error ?? '상품을 찾을 수 없어요')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 수정'),
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
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Responsive.maxContentWidth),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
            _Banner(product: _original!),
            const SizedBox(height: 20),

            // Title
            TextFormField(
              controller: _titleCtl,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '상품명을 입력해주세요',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '제목을 입력해주세요';
                if (v.trim().length > 80) return '제목이 너무 길어요';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Category
            const Text('카테고리',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: Categories.all
                  .where((c) => c.id != 'all')
                  .map(
                    (c) => ChoiceChip(
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
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),

            // Price
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

            // QTA Price (optional)
            TextFormField(
              controller: _qtaPriceCtl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'QTA 결제 (선택)',
                hintText: '0 = 사용 안 함 / 거래완료 시 자동 차감',
                prefixIcon: Icon(Icons.token_outlined, size: 20),
                helperText: '예) 5000 → 거래완료 토글하면 구매자 잔액 5,000 QTA 가 자동 이체돼요',
              ),
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descCtl,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '자세한 설명',
                hintText: '상품의 상태, 사용기간 등을 자세히 적어주세요.',
                alignLabelWithHint: true,
              ),
              validator: (v) {
                if (v == null || v.trim().length < 10) return '10자 이상 입력해주세요';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // YouTube URL (optional) — uploaded videos can't be edited here
            if (_original!.videoUrl.isNotEmpty &&
                !_original!.videoUrl.startsWith('http'))
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EggplantColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.video_library_outlined,
                        color: EggplantColors.primary, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '업로드한 영상은 수정할 수 없어요.\n'
                        '변경하려면 상품을 삭제 후 다시 등록해주세요.',
                        style: TextStyle(
                          fontSize: 12,
                          color: EggplantColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              TextFormField(
                controller: _youtubeCtl,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '유튜브 링크 (선택)',
                  hintText: 'https://youtu.be/...',
                  prefixIcon: Icon(
                    Icons.play_circle_outline,
                    color: Colors.red,
                  ),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null; // allow clearing
                  final re = RegExp(
                    r'(?:youtu\.be/|youtube\.com/(?:watch\?v=|shorts/|embed/))([A-Za-z0-9_-]{6,20})',
                  );
                  if (!re.hasMatch(t)) return '유튜브 링크 형식이 올바르지 않아요';
                  return null;
                },
              ),

            const SizedBox(height: 40),
          ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Product product;
  const _Banner({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EggplantColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EggplantColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_note,
              color: EggplantColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '수정 중: ${product.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: EggplantColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
