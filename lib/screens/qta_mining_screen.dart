import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/market.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/qta_service.dart';

/// 채굴 내역 — 상품 등록 채굴(가격의 10%, 1 QTA = 10원) · 가격 인하/삭제 차감 ·
/// 7일 유지 · 둘러보기. 마이페이지 채굴 카드의 "채굴 내역"에서 진입.
///   GET /api/users/me/qta/mining
class QtaMiningScreen extends StatefulWidget {
  const QtaMiningScreen({super.key});

  @override
  State<QtaMiningScreen> createState() => _QtaMiningScreenState();
}

class _QtaMiningScreenState extends State<QtaMiningScreen> {
  bool _loading = true;
  String? _error;
  int _total = 0;
  int _listingTotal = 0;
  /// 'kr' | 'jp' — 서버 rule.currency 로 확정, 그 전엔 회원 시장.
  late String _market;
  /// 현지 화폐 몇 단위가 1 QTA 인가 — 서버 rule.money_per_qta 우선.
  late int _moneyPerQta;
  int _percent = 10;
  int _maxPerListing = 1000;
  int _maxPerDay = 3000;
  List<QtaLedgerItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _market = AppMarket.of(context.read<AuthService>().user);
    _moneyPerQta = AppMarket.moneyPerQta(_market);
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await context
          .read<AuthService>()
          .api
          .get('/api/users/me/qta/mining', query: {'limit': 200});
      final d = Map<String, dynamic>.from(res.data as Map);
      final rule = Map<String, dynamic>.from((d['rule'] as Map?) ?? const {});
      if (!mounted) return;
      setState(() {
        _total = (d['total'] as num?)?.toInt() ?? 0;
        _listingTotal = (d['listing_total'] as num?)?.toInt() ?? 0;
        final currency = rule['currency']?.toString();
        if (currency == 'JPY') {
          _market = 'jp';
        } else if (currency == 'KRW') {
          _market = 'kr';
        }
        _moneyPerQta = (rule['money_per_qta'] as num?)?.toInt() ??
            (_market == 'kr' ? (rule['krw_per_qta'] as num?)?.toInt() : null) ??
            AppMarket.moneyPerQta(_market);
        _percent = (rule['percent'] as num?)?.toInt() ?? _percent;
        _maxPerListing = (rule['max_per_listing'] as num?)?.toInt() ?? _maxPerListing;
        _maxPerDay = (rule['max_per_day'] as num?)?.toInt() ?? _maxPerDay;
        _items = ((d['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => QtaLedgerItem.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[mining] load error $e');
      if (!mounted) return;
      setState(() {
        _error = context.l10n.myMiningLoadFail;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final df = DateFormat(t.myDateTimeFormat);
    final perQta = _moneyPerQta <= 0 ? 1 : _moneyPerQta;
    return Scaffold(
      appBar: AppBar(title: Text(t.myMiningTitle)),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: EggplantColors.primary,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6E3CC4), Color(0xFF9559E0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.myMiningTotalLabel,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('${_fmt(_total)} QTA',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(
                        t.myMiningTotalSub(_fmt(_listingTotal), _money(_total * _moneyPerQta)),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: EggplantColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '🔒 ${t.myRuleVerifyRequired}\n' +
                  t.myMiningRule(
                    _percent,
                    _moneyPerQta,
                    _money(10000),
                    _fmt(10000 * _percent ~/ 100 ~/ perQta),
                    _fmt(_maxPerListing),
                    _fmt(_maxPerDay),
                  ),
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: EggplantColors.textSecondary,
                      height: 1.6),
                ),
              ),
              const SizedBox(height: 20),
              Text(t.myMiningRecords,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: EggplantColors.textPrimary)),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: EggplantColors.textSecondary)),
                )
              else if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(t.myMiningEmpty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: EggplantColors.textSecondary)),
                )
              else
                ..._items.map((it) {
                  final positive = it.amount >= 0;
                  final title = it.meta?['title']?.toString() ?? '';
                  final price = (it.meta?['price'] as num?)?.toInt();
                  final sub = [
                    if (title.isNotEmpty) title,
                    if (price != null) _money(price),
                    df.format(it.createdAt.toLocal()),
                  ].join(' · ');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: EggplantColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          positive
                              ? Icons.bolt_rounded
                              : Icons.remove_circle_outline,
                          color: positive
                              ? EggplantColors.primary
                              : Colors.red.shade400,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(it.label,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: EggplantColors.textPrimary)),
                              const SizedBox(height: 2),
                              Text(sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: EggplantColors.textTertiary)),
                            ],
                          ),
                        ),
                        Text(
                          '${positive ? '+' : '-'}${_fmt(it.amount.abs())} QTA',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: positive
                                ? EggplantColors.primary
                                : Colors.red.shade400,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(int n) => NumberFormat('#,###').format(n);

  /// 10,000원 / ¥10,000 — 0 도 금액으로 표시 (formatPrice 는 0 을 '나눔' 으로 바꿈).
  String _money(int n) {
    return AppMarket.money(n, _market);
  }
}
