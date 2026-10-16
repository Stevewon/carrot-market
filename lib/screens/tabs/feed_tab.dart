import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/l10n.dart';
import '../../app/market.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/product_service.dart';
import '../../services/search_history_service.dart';
import '../../widgets/product_card.dart';

class FeedTab extends StatefulWidget {
  const FeedTab({super.key});

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  String _category = 'all';
  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchMode = false;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _searchFocus.addListener(() {
      if (mounted) setState(() => _showHistory = _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// 내 동네 목록 (최대 10곳) — 바꾸기 · 추가 · 삭제.
  Future<void> _openMyRegions() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _MyRegionsSheet(),
    );
    if (!mounted) return;
    if (picked == '+') {
      await context.push('/region');
      if (!mounted) return;
    }
    _load();
  }

  void _load() {
    final auth = context.read<AuthService>();
    final productSvc = context.read<ProductService>();
    productSvc.fetchProducts(
      category: _category,
      region: auth.user?.region,
      search: _searchCtl.text.isEmpty ? null : _searchCtl.text,
      // 동네 인증된 사용자에 한해 현재 슬라이더 값 유지.
      rangeKm: (auth.user?.isRegionVerified ?? false) ? productSvc.rangeKm : 0,
    );
  }

  bool _hasFilters(ProductService s) =>
      s.availableOnly || s.hasPriceFilter || s.sort != 'recent';

  Future<void> _submitSearch(String raw) async {
    final term = raw.trim();
    if (term.isNotEmpty) {
      // ignore: use_build_context_synchronously
      await context.read<SearchHistoryService>().add(term);
    }
    _searchFocus.unfocus();
    setState(() => _showHistory = false);
    _load();
  }

  void _pickHistoryTerm(String term) {
    _searchCtl.text = term;
    _searchCtl.selection =
        TextSelection.collapsed(offset: _searchCtl.text.length);
    _submitSearch(term);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final productSvc = context.watch<ProductService>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: _searchMode
            ? TextField(
                controller: _searchCtl,
                focusNode: _searchFocus,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.l10n.homeSearchHint,
                  border: InputBorder.none,
                  filled: false,
                ),
                onSubmitted: _submitSearch,
              )
            : InkWell(
                onTap: _openMyRegions,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        auth.user?.region ?? context.l10n.homeSetRegion,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: EggplantColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: EggplantColors.textPrimary,
                      ),
                    ],
                  ),
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_searchMode ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _searchMode ? context.l10n.homeSearchClose : context.l10n.homeSearch,
            onPressed: () {
              setState(() {
                _searchMode = !_searchMode;
                if (!_searchMode) {
                  _searchCtl.clear();
                  _showHistory = false;
                  _searchFocus.unfocus();
                  _load();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: context.l10n.homeQrScan,
            onPressed: () => context.push('/qr/scan'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _CategoryBar(
                selected: _category,
                onSelected: (id) {
                  setState(() => _category = id);
                  _load();
                },
              ),
              // 동네 인증된 사용자에게만 거리 필터 노출.
              if (auth.user?.isRegionVerified ?? false)
                _RangeBar(
                  current: productSvc.rangeKm,
                  onChanged: (km) {
                    productSvc.rangeKm = km;
                    _load();
                  },
                ),
              _FilterBar(
                market: AppMarket.of(auth.user),
                onChanged: _load,
              ),
              const Divider(height: 1, color: EggplantColors.border),
              Expanded(
                // 태블릿/폴드 펼침에서 상품 카드 리스트가 가로로 무한정
                // 늘어나지 않도록 600dp 가운데 정렬.
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: Responsive.maxFeedWidth,
                    ),
                    child: productSvc.loading && productSvc.products.isEmpty
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: EggplantColors.primary),
                          )
                        : productSvc.products.isEmpty
                            ? _EmptyView(
                                onRefresh: _load,
                                error: productSvc.loadError,
                                onClearFilters: _hasFilters(productSvc)
                                    ? () {
                                        productSvc.setFilters(
                                          availableOnly: false,
                                          sort: 'recent',
                                          setPrice: true,
                                        );
                                        _load();
                                      }
                                    : null,
                              )
                            : RefreshIndicator(
                                color: EggplantColors.primary,
                                onRefresh: () async => _load(),
                                child: ListView.separated(
                                  // 마지막 카드가 FAB(글쓰기 버튼) 에 가리지 않도록
                                  // 끝에 80dp 여백.
                                  padding: const EdgeInsets.only(
                                      top: 8, bottom: 80),
                                  itemCount: productSvc.products.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    height: 1,
                                    color: EggplantColors.border,
                                    indent: 16,
                                    endIndent: 16,
                                  ),
                                  itemBuilder: (_, i) {
                                    final p = productSvc.products[i];
                                    return ProductCard(
                                      product: p,
                                      onTap: () =>
                                          context.push('/product/${p.id}'),
                                    );
                                  },
                                ),
                              ),
                  ),
                ),
              ),
            ],
          ),
          // 검색창 포커스 시 최근 검색어 오버레이 (당근식)
          if (_searchMode && _showHistory)
            Positioned.fill(
              child: _SearchHistoryPanel(
                onPick: _pickHistoryTerm,
              ),
            ),
        ],
      ),
    );
  }
}

/// 최근 검색어 패널 — 검색창에 포커스가 있을 때만 표시.
/// 빈 상태면 안내 문구만 보여 준다.
class _SearchHistoryPanel extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _SearchHistoryPanel({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<SearchHistoryService>();
    final terms = history.terms;

    return GestureDetector(
      // 패널 바깥 탭 시 키보드 닫고 패널 닫기 효과 (포커스 해제로 자동 처리)
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text(
                    context.l10n.homeRecentSearches,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: EggplantColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (terms.isNotEmpty)
                    TextButton(
                      onPressed: () => history.clear(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        context.l10n.homeClearAll,
                        style: const TextStyle(
                          fontSize: 12,
                          color: EggplantColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (terms.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                child: Center(
                  child: Text(
                    context.l10n.homeNoRecentSearches,
                    style: const TextStyle(
                      fontSize: 13,
                      color: EggplantColors.textSecondary,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: terms.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: EggplantColors.border,
                    indent: 16,
                    endIndent: 16,
                  ),
                  itemBuilder: (_, i) {
                    final t = terms[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.history_rounded,
                        size: 20,
                        color: EggplantColors.textSecondary,
                      ),
                      title: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 14,
                          color: EggplantColors.textPrimary,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: EggplantColors.textSecondary,
                        ),
                        onPressed: () => history.remove(t),
                      ),
                      onTap: () => onPick(t),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 거리 필터 (당근식 동네 범위 슬라이더). 동네 인증 통과자만 노출.
/// 0 = 전체, 2/4/6/10 km.
class _RangeBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onChanged;
  const _RangeBar({required this.current, required this.onChanged});

  static const _options = <(int, String)>[
    (0, '전체'),
    (2, '2km'),
    (4, '4km'),
    (6, '6km'),
    (10, '10km'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: Colors.white,
      child: Row(
        children: [
          const Icon(Icons.near_me_rounded,
              size: 16, color: EggplantColors.textSecondary),
          const SizedBox(width: 6),
          Text(context.l10n.homeDistance,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: EggplantColors.textSecondary,
              )),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _options.map((o) {
                  final selected = o.$1 == current;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(o.$1 == 0 ? context.l10n.homeRangeAll : o.$2),
                      selected: selected,
                      onSelected: (_) => onChanged(o.$1),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : EggplantColors.textSecondary,
                      ),
                      selectedColor: EggplantColors.primary,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: selected
                            ? EggplantColors.primary
                            : EggplantColors.border,
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 당근식 필터 줄 — 거래 가능만 · 가격 · 정렬. 값은 ProductService 에 둔다.
class _FilterBar extends StatelessWidget {
  final String market;
  final VoidCallback onChanged;
  const _FilterBar({required this.market, required this.onChanged});

  String _sortLabel(BuildContext context, String sort) {
    switch (sort) {
      case 'price_asc':
        return context.l10n.homeSortPriceAsc;
      case 'price_desc':
        return context.l10n.homeSortPriceDesc;
      default:
        return context.l10n.homeSortRecent;
    }
  }

  String _priceLabel(BuildContext context, ProductService s) {
    if (!s.hasPriceFilter) return context.l10n.homeFilterPrice;
    final lo = s.minPrice != null ? AppMarket.money(s.minPrice!, market) : '';
    final hi = s.maxPrice != null ? AppMarket.money(s.maxPrice!, market) : '';
    return '$lo ~ $hi';
  }

  Future<void> _pickSort(BuildContext context, ProductService s) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(ctx.l10n.homeSortTitle,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
            for (final v in const ['recent', 'price_asc', 'price_desc'])
              ListTile(
                title: Text(_sortLabel(ctx, v),
                    style: TextStyle(
                      fontWeight: v == s.sort ? FontWeight.w800 : FontWeight.w500,
                      color: v == s.sort ? EggplantColors.primary : EggplantColors.textPrimary,
                    )),
                trailing: v == s.sort
                    ? const Icon(Icons.check_rounded, color: EggplantColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == s.sort) return;
    s.setFilters(sort: picked);
    onChanged();
  }

  Future<void> _pickPrice(BuildContext context, ProductService s) async {
    final result = await showModalBottomSheet<(int?, int?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PriceRangeSheet(
        market: market,
        initialMin: s.minPrice,
        initialMax: s.maxPrice,
      ),
    );
    if (result == null) return;
    s.setFilters(setPrice: true, minPrice: result.$1, maxPrice: result.$2);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ProductService>();
    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(44).clamp(44.0, 64.0),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        children: [
          _FilterChip(
            label: context.l10n.homeFilterAvailable,
            selected: s.availableOnly,
            icon: s.availableOnly ? Icons.check_rounded : null,
            onTap: () {
              s.setFilters(availableOnly: !s.availableOnly);
              onChanged();
            },
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: _priceLabel(context, s),
            selected: s.hasPriceFilter,
            trailing: Icons.keyboard_arrow_down_rounded,
            onTap: () => _pickPrice(context, s),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: _sortLabel(context, s.sort),
            selected: s.sort != 'recent',
            icon: Icons.swap_vert_rounded,
            trailing: Icons.keyboard_arrow_down_rounded,
            onTap: () => _pickSort(context, s),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final IconData? trailing;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? EggplantColors.primary : EggplantColors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? EggplantColors.primary.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? EggplantColors.primary : EggplantColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 3),
              ],
              Text(label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
              if (trailing != null) Icon(trailing, size: 17, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// 가격 범위 입력 시트. 비워 두면 그쪽 제한 없음. 결과 (최소, 최대).
class _PriceRangeSheet extends StatefulWidget {
  final String market;
  final int? initialMin;
  final int? initialMax;
  const _PriceRangeSheet({required this.market, this.initialMin, this.initialMax});

  @override
  State<_PriceRangeSheet> createState() => _PriceRangeSheetState();
}

class _PriceRangeSheetState extends State<_PriceRangeSheet> {
  late final TextEditingController _minCtl =
      TextEditingController(text: widget.initialMin?.toString() ?? '');
  late final TextEditingController _maxCtl =
      TextEditingController(text: widget.initialMax?.toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _minCtl.dispose();
    _maxCtl.dispose();
    super.dispose();
  }

  int? _parse(String s) {
    final d = s.replaceAll(RegExp(r'\D'), '');
    return d.isEmpty ? null : int.tryParse(d);
  }

  Widget _field(TextEditingController ctl, String hint) => TextField(
        controller: ctl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: hint,
          prefixText: AppMarket.currencyPrefix(widget.market),
          isDense: true,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n.homePriceTitle,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _field(_minCtl, context.l10n.homePriceMin)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('~'),
                ),
                Expanded(child: _field(_maxCtl, context.l10n.homePriceMax)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(fontSize: 12.5, color: Colors.redAccent)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, (null, null)),
                    child: Text(context.l10n.homePriceReset),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      final lo = _parse(_minCtl.text);
                      final hi = _parse(_maxCtl.text);
                      if (lo != null && hi != null && lo > hi) {
                        setState(() => _error = context.l10n.homePriceInvalid);
                        return;
                      }
                      Navigator.pop(context, (lo, hi));
                    },
                    child: Text(context.l10n.homePriceApply),
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

class _CategoryBar extends StatefulWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _CategoryBar({required this.selected, required this.onSelected});

  @override
  State<_CategoryBar> createState() => _CategoryBarState();
}

class _CategoryBarState extends State<_CategoryBar> {
  final ScrollController _scrollCtl = ScrollController();
  bool _canScrollRight = true;
  bool _canScrollLeft = false;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_updateFadeState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFadeState());
  }

  void _updateFadeState() {
    if (!_scrollCtl.hasClients) return;
    final pos = _scrollCtl.position;
    final left = pos.pixels > 8;
    final right = pos.pixels < pos.maxScrollExtent - 8;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  @override
  void dispose() {
    _scrollCtl.removeListener(_updateFadeState);
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CategoryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      // 선택된 칩이 시야 안에 들어오도록 부드럽게 스크롤
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  void _scrollToSelected() {
    final idx = Categories.all.indexWhere((c) => c.id == widget.selected);
    if (idx < 0 || !_scrollCtl.hasClients) return;
    // 칩 평균 폭 대략 100px로 가정, 선택 칩을 화면 가운데 근처로
    final target = (idx * 100.0 - 120).clamp(
      0.0,
      _scrollCtl.position.maxScrollExtent,
    );
    _scrollCtl.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 고정 52 는 큰 글씨(1.15~1.3배)에서 칩 글자 아래가 잘렸다 → 글자 배율만큼 키움.
      height: MediaQuery.textScalerOf(context).scale(52).clamp(52.0, 72.0),
      child: Stack(
        children: [
          ListView.separated(
            controller: _scrollCtl,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: Categories.all.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = Categories.all[i];
              final isSelected = c.id == widget.selected;
              return _CategoryChip(
                info: c,
                isSelected: isSelected,
                onTap: () => widget.onSelected(c.id),
              );
            },
          ),
          // 좌우 페이드 그라데이션 — 스크롤 가능 힌트
          if (_canScrollLeft)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 24,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.white, Colors.white.withOpacity(0)],
                    ),
                  ),
                ),
              ),
            ),
          if (_canScrollRight)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 24,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [Colors.white, Colors.white.withOpacity(0)],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final CategoryInfo info;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.info,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? EggplantColors.primary
                : EggplantColors.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? EggplantColors.primary
                  : EggplantColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(info.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 5),
              Text(
                info.label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : EggplantColors.textPrimary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onRefresh;
  /// 로드 실패 문구 — 있으면 "상품 없음" 대신 오류와 다시 시도를 보여준다.
  final String? error;
  /// 필터가 걸려 있을 때만 — "조건에 맞는 상품이 없어요" + 필터 지우기.
  final VoidCallback? onClearFilters;
  const _EmptyView({required this.onRefresh, this.error, this.onClearFilters});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error != null ? '📡' : '🍆', style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text(
            error ??
                (onClearFilters != null
                    ? context.l10n.homeFilterNoResult
                    : context.l10n.homeNoProducts),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: EggplantColors.textPrimary,
            ),
          ),
          if (error != null || onClearFilters == null) ...[
            const SizedBox(height: 4),
            Text(
              error != null ? context.l10n.homeCheckNetwork : context.l10n.homeFirstProduct,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: EggplantColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (error == null && onClearFilters != null)
            OutlinedButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: Text(context.l10n.homeFilterClear),
            )
          else
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(error != null ? context.l10n.commonRetry : context.l10n.homeRefresh),
            ),
        ],
      ),
    );
  }
}

/// 내 동네 목록 시트. 누르면 그 동네로 바꾸고, ✕ 로 빼고, 아래 버튼으로 추가.
/// 닫힐 때 '+' 를 돌려주면 동네 추가 화면으로 간다.
class _MyRegionsSheet extends StatelessWidget {
  const _MyRegionsSheet();

  static const int maxRegions = 10;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    final regions = user?.regions ?? const <String>[];
    final active = user?.region;

    Future<void> show(String? err) async {
      if (err != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n.homeMyRegionsTitle(regions.length, maxRegions),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(context.l10n.homeMyRegionsHint,
                style: const TextStyle(fontSize: 12.5, color: EggplantColors.textSecondary)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in regions)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        r == active ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: r == active ? EggplantColors.primary : EggplantColors.textTertiary,
                      ),
                      title: Text(r,
                          style: TextStyle(
                            fontWeight: r == active ? FontWeight.w800 : FontWeight.w500,
                            color: r == active ? EggplantColors.primary : EggplantColors.textPrimary,
                          )),
                      trailing: regions.length > 1
                          ? IconButton(
                              tooltip: context.l10n.homeRemoveRegion,
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () async {
                                final next = [...regions]..remove(r);
                                await show(await auth.setRegions(next,
                                    active: r == active ? next.first : active));
                              },
                            )
                          : null,
                      onTap: () async {
                        if (r != active) await show(await auth.updateRegion(r));
                        if (context.mounted) Navigator.pop(context, r);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: regions.length >= maxRegions
                  ? null
                  : () => Navigator.pop(context, '+'),
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: Text(regions.length >= maxRegions
                  ? context.l10n.homeMaxRegions(maxRegions)
                  : context.l10n.homeAddRegion),
            ),
          ],
        ),
      ),
    );
  }
}
