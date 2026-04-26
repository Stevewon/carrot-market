import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
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
                decoration: const InputDecoration(
                  hintText: '상품명 검색',
                  border: InputBorder.none,
                  filled: false,
                ),
                onSubmitted: _submitSearch,
              )
            : InkWell(
                onTap: () => context.push('/region'),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        auth.user?.region ?? '동네 설정',
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
            tooltip: _searchMode ? '검색 닫기' : '검색',
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
            tooltip: 'QR 스캔',
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
                            ? _EmptyView(onRefresh: _load)
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
                  const Text(
                    '최근 검색어',
                    style: TextStyle(
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
                      child: const Text(
                        '전체 삭제',
                        style: TextStyle(
                          fontSize: 12,
                          color: EggplantColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (terms.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                child: Center(
                  child: Text(
                    '최근 검색 기록이 없어요',
                    style: TextStyle(
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
          const Text('거리',
              style: TextStyle(
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
                      label: Text(o.$2),
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
      height: 52,
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
  const _EmptyView({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🍆', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          const Text(
            '아직 상품이 없어요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: EggplantColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '첫 번째 상품을 등록해보세요!',
            style: TextStyle(
              fontSize: 13,
              color: EggplantColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('새로고침'),
          ),
        ],
      ),
    );
  }
}
