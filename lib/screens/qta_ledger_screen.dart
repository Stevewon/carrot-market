import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/market.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/qta_service.dart';

/// QTA 적립/사용 내역 화면. 마이페이지 지갑 카드의 "내역" 버튼에서 진입.
class QtaLedgerScreen extends StatefulWidget {
  const QtaLedgerScreen({super.key});

  @override
  State<QtaLedgerScreen> createState() => _QtaLedgerScreenState();
}

class _QtaLedgerScreenState extends State<QtaLedgerScreen> {
  /// ★ v1.0.115 (사장님 보고 — "잠깐 보였다가 사라지는" 깜빡임 수정):
  ///   - initState 에서 force=true 로 강제 재로드하면, 이미 캐시가 있어도
  ///     QtaService 가 _loading=true → notify 를 거쳐 build 가 한 번 더 돌고
  ///     items.isEmpty && loading=true 분기로 잠깐 빈 화면이 보였다 사라졌음.
  ///   - 이미 로드된 캐시가 있으면 force 없이 silent refresh 만 — 화면은 그대로.
  ///   - 캐시가 없을 때만 첫 진입으로 force 호출 → 정상적으로 로딩 인디케이터 1번만.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final qta = context.read<QtaService>();
      // 캐시 있으면 silent (force 없음) — 깜빡임 0건.
      // 캐시 없으면 정상 로드 (force 없음, _loaded=false 라 한 번만 fetch).
      qta.load(limit: 100);
    });
  }

  @override
  Widget build(BuildContext context) {
    final qta = context.watch<QtaService>();
    final df = DateFormat(context.l10n.myDateTimeFormat);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.myLedgerTitle),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/qta/withdraw'),
            icon: const Icon(Icons.send_rounded,
                size: 16, color: EggplantColors.primary),
            label: Text(
              context.l10n.myLedgerWithdraw,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: EggplantColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false, // AppBar 가 이미 status bar 영역을 차지함
        child: RefreshIndicator(
        color: EggplantColors.primary,
        onRefresh: () => qta.load(limit: 100, force: true).then((_) {}),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // Balance card
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
                  Text(context.l10n.myLedgerBalance,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_format(qta.balance),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          )),
                      const SizedBox(width: 6),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('QTA',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            )),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const _RuleBox(),

            const SizedBox(height: 20),
            Text(
              context.l10n.myLedgerRecent,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: EggplantColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // ★ v1.0.115: items 가 1개라도 있으면 절대 로딩 인디케이터 안 보임
            //   → "잠깐 보였다가 사라지는" 깜빡임 0건.
            if (qta.loading && qta.items.isEmpty && !qta.loaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (qta.items.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: EggplantColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  context.l10n.myLedgerEmpty,
                  style: const TextStyle(
                    fontSize: 13,
                    color: EggplantColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              )
            else
              ...qta.items.map((it) {
                final positive = it.amount >= 0;
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
                      _ReasonIcon(reason: it.reason),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.label,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: EggplantColors.textPrimary,
                                )),
                            const SizedBox(height: 2),
                            Text(df.format(it.createdAt.toLocal()),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: EggplantColors.textTertiary,
                                )),
                          ],
                        ),
                      ),
                      Text(
                        '${positive ? '+' : '-'}${_format(it.amount.abs())} QTA',
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

  static String _format(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return n < 0 ? '-$buf' : buf.toString();
  }
}

class _ReasonIcon extends StatelessWidget {
  final String reason;
  const _ReasonIcon({required this.reason});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    switch (reason) {
      case 'signup':
      case 'verify_bonus':
        icon = Icons.celebration_outlined;
        color = Colors.orange;
        break;
      case 'login_daily':
        icon = Icons.calendar_today_outlined;
        color = Colors.blue;
        break;
      case 'trade_seller':
        icon = Icons.sell_outlined;
        color = EggplantColors.primary;
        break;
      case 'trade_buyer':
        icon = Icons.shopping_bag_outlined;
        color = Colors.green;
        break;
      case 'withdrawal':
        icon = Icons.send_rounded;
        color = Colors.deepPurple;
        break;
      case 'withdrawal_refund':
        icon = Icons.undo_rounded;
        color = Colors.teal;
        break;
      case 'listing_reward':
      case 'mining_listing':
      case 'mining_browse':
        icon = Icons.bolt_rounded;
        color = EggplantColors.primary;
        break;
      case 'listing_reward_adjust':
      case 'listing_reward_clawback':
        icon = Icons.remove_circle_outline;
        color = Colors.red;
        break;
      default:
        icon = Icons.account_balance_wallet_outlined;
        color = Colors.grey;
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _RuleBox extends StatelessWidget {
  const _RuleBox();

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final market = AppMarket.of(context.watch<AuthService>().user);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EggplantColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline,
                  color: EggplantColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(t.myRuleTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: EggplantColors.textPrimary,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          _RuleLine(emoji: '🔒', text: t.myRuleVerifyRequired),
          const SizedBox(height: 4),
          _RuleLine(emoji: '🎁', text: t.myRuleVerify),
          const SizedBox(height: 4),
          _RuleLine(emoji: '⛏️', text: t.myRuleListing(AppMarket.moneyPerQta(market))),
          const SizedBox(height: 4),
          _RuleLine(emoji: '📅', text: t.myRuleLogin),
          const SizedBox(height: 4),
          _RuleLine(emoji: '🤝', text: t.myRuleTrade),
          const SizedBox(height: 4),
          _RuleLine(emoji: '💸', text: t.myRuleWithdraw),
        ],
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  final String emoji;
  final String text;
  const _RuleLine({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: EggplantColors.textSecondary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
