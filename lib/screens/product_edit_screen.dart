import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/constants.dart';
import '../app/l10n.dart';
import '../app/market.dart';
import '../app/responsive.dart';
import '../app/theme.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import 'prohibited_items_screen.dart';

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

  /// QTA 가격 입력은 본인인증(Lv1) 판매자에게만 (이미 QTA 가격이 있는 상품은 그대로 보여줌).
  bool get _canSetQtaPrice =>
      (context.read<AuthService>().user?.isIdentityVerified ?? false) ||
      (_original?.qtaPrice ?? 0) > 0;
  final _descCtl = TextEditingController();
  final _youtubeCtl = TextEditingController();
  final _meetCtl = TextEditingController();

  String _category = 'digital';
  String _region = '';
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
    _meetCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p =
        await context.read<ProductService>().fetchById(widget.productId);
    if (!mounted) return;
    if (p == null) {
      setState(() {
        _loading = false;
        _error = context.l10n.productNotFound;
      });
      return;
    }
    setState(() {
      _original = p;
      _titleCtl.text = p.title;
      _priceCtl.text = _ThousandsSeparatorFormatter._withCommas(p.price.toString());
      _qtaPriceCtl.text = p.qtaPrice > 0
          ? _ThousandsSeparatorFormatter._withCommas(p.qtaPrice.toString())
          : '';
      _descCtl.text = p.description;
      _meetCtl.text = p.meetPlace;
      _category = p.category;
      _region = p.region;
      // Only pre-fill YouTube URLs (not uploaded /uploads/ videos).
      if (p.videoUrl.startsWith('http')) {
        _youtubeCtl.text = p.videoUrl;
      }
      _loading = false;
    });
  }

  /// 동네 변경 — `/region` 화면으로 이동하고 돌아오면 AuthService.user.region 가
  /// 이미 갱신된 상태이므로 그 값을 _region 에 반영. 당근마켓과 동일한 흐름.
  Future<void> _changeRegion() async {
    await context.push('/region');
    if (!mounted) return;
    final newRegion = context.read<AuthService>().user?.region ?? '';
    if (newRegion.isNotEmpty && newRegion != _region) {
      setState(() => _region = newRegion);
    }
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
    if (_region.isNotEmpty && _region != _original!.region) {
      data['region'] = _region;
    }

    final originalYt = _original!.videoUrl.startsWith('http')
        ? _original!.videoUrl
        : '';
    if (newYt != originalYt) data['youtube_url'] = newYt;
    final newMeet = _meetCtl.text.trim();
    if (newMeet != _original!.meetPlace) data['meet_place'] = newMeet;

    if (data.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.productNoChanges)));
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
          region: data['region'] as String?,
          youtubeUrl: data['youtube_url'] as String?,
          meetPlace: data['meet_place'] as String?,
        );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (err != null) {
      showProductError(context, err);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.productUpdated)),
    );
    // 상세화면에서 즉시 반영(_loadDetail) 트리거하기 위해 true 반환
    context.pop(true);
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
        body: Center(child: Text(_error ?? context.l10n.productNotFound)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.productEditTitle),
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
            _Banner(product: _original!),
            const SizedBox(height: 20),

            // Title
            TextFormField(
              controller: _titleCtl,
              decoration: InputDecoration(
                labelText: context.l10n.productFieldTitle,
                hintText: context.l10n.productFieldTitleHint,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return context.l10n.productFieldTitleRequired;
                if (v.trim().length > 80) return context.l10n.productFieldTitleTooLong;
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Category
            Text(context.l10n.productFieldCategory,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: Categories.all
                  .where((c) => c.id != 'all')
                  .map(
                    (c) => ChoiceChip(
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
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),

            // Region (당근마켓 스타일 — 동네 + 변경 버튼)
            Text(context.l10n.productFieldRegion,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _submitting ? null : _changeRegion,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: EggplantColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: EggplantColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 20, color: EggplantColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _region.isEmpty ? context.l10n.productSetRegion : _region,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _region.isEmpty
                              ? EggplantColors.textSecondary
                              : EggplantColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      context.l10n.productChange,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: EggplantColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        size: 18, color: EggplantColors.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Price
            TextFormField(
              controller: _priceCtl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _ThousandsSeparatorFormatter(),
              ],
              decoration: InputDecoration(
                labelText: context.l10n.productFieldPrice,
                hintText: AppMarket.isJp(_original!.market)
                    ? context.l10n.productFieldPriceHintJpy
                    : AppMarket.isPh(_original!.market)
                        ? context.l10n.productFieldPriceHintPhp
                        : context.l10n.productFieldPriceHintKrw,
                prefixText: AppMarket.currencyPrefix(_original!.market),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return context.l10n.productFieldPriceRequired;
                return null;
              },
            ),
            const SizedBox(height: 16),

            // QTA Price (optional)
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

            // Description
            TextFormField(
              controller: _descCtl,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: context.l10n.productFieldDescription,
                hintText: context.l10n.productFieldDescriptionEditHint,
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
            const SizedBox(height: 8),

            // YouTube URL (optional) — uploaded videos can't be edited here
            if (_original!.videoUrl.isNotEmpty &&
                !_original!.videoUrl.startsWith('http'))
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EggplantColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.video_library_outlined,
                        color: EggplantColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.productUploadedVideoLocked,
                        style: const TextStyle(
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
                decoration: InputDecoration(
                  labelText: context.l10n.productYoutubeLinkOptional,
                  hintText: 'https://youtu.be/...',
                  prefixIcon: const Icon(
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
                  if (!re.hasMatch(t)) return context.l10n.productYoutubeInvalid;
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
              context.l10n.productEditingBanner(product.title),
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
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
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
