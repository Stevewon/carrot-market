import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

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
  final _formKey = GlobalKey<FormState>();
  final _titleCtl = TextEditingController();
  final _priceCtl = TextEditingController();
  final _descCtl = TextEditingController();

  String _category = 'digital';
  final List<File> _images = [];
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtl.dispose();
    _priceCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_images.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최대 5장까지 등록 가능해요')),
      );
      return;
    }
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(imageQuality: 80, limit: 5 - _images.length);
      if (picked.isNotEmpty) {
        setState(() {
          _images.addAll(picked.map((x) => File(x.path)));
        });
      }
    } catch (e) {
      debugPrint('image pick error: $e');
    }
  }

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
    final price = int.tryParse(_priceCtl.text.replaceAll(',', '').replaceAll(' ', '')) ?? 0;

    final err = await context.read<ProductService>().createProduct(
          title: _titleCtl.text.trim(),
          description: _descCtl.text.trim(),
          price: price,
          category: _category,
          region: auth.user!.region!,
          imageFiles: _images,
        );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품이 등록되었어요 🍆')),
      );
      // Refresh feed
      context.read<ProductService>().fetchProducts(
            region: auth.user!.region,
          );
      context.pop();
    }
  }

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
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return InkWell(
                      onTap: _pickImage,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: EggplantColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: EggplantColors.border),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.camera_alt_outlined,
                                color: EggplantColors.primary, size: 28),
                            const SizedBox(height: 4),
                            Text('${_images.length}/5',
                                style: const TextStyle(
                                    fontSize: 12, color: EggplantColors.primary)),
                          ],
                        ),
                      ),
                    );
                  }
                  final img = _images[i - 1];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(img, width: 84, height: 84, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () => setState(() => _images.removeAt(i - 1)),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
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
                          color: _category == c.id ? Colors.white : EggplantColors.textPrimary,
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
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
