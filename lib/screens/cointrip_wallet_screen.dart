import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../services/cointrip_service.dart';
import '../widgets/cointrip_notice.dart';

/// 코인 지갑 — 받는 지갑 두 개(퀀타리움 월렛 · 기존 지갑 주소), 주운 코인 잔액, 출금 신청.
class CointripWalletScreen extends StatefulWidget {
  const CointripWalletScreen({super.key});

  @override
  State<CointripWalletScreen> createState() => _CointripWalletScreenState();
}

class _CointripWalletScreenState extends State<CointripWalletScreen> {
  List<CtBalance> _balances = const [];
  List<CtWithdrawal> _withdrawals = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final svc = context.read<CointripService>();
    setState(() => _loading = true);
    try {
      await svc.loadStatus();
      final r = await svc.wallet();
      if (!mounted) return;
      setState(() {
        _balances = r.balances;
        _withdrawals = r.withdrawals;
        _error = null;
      });
    } on CtError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _withdraw(CtBalance b) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WithdrawSheet(balance: b),
    );
    if (done == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.ctWithdrawDone)));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<CointripService>();
    final l10n = context.l10n;
    final pendingSymbols = {
      for (final w in _withdrawals)
        if (w.status == 'requested' || w.status == 'processing') w.symbol
    };
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(l10n.ctMyWallet)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _SectionTitle(l10n.ctReceiveWallets),
            _WalletRow(
              title: l10n.ctQuantariumWallet,
              sub: l10n.ctQuantariumWalletSub,
              address: svc.quantariumWallet,
              action: svc.quantariumWallet == null
                  ? TextButton(onPressed: () => context.push('/profile/verify'), child: Text(l10n.ctRegister))
                  : null,
            ),
            const SizedBox(height: 10),
            _WalletRow(
              title: l10n.ctExtWallet,
              sub: l10n.ctExtWalletSub,
              address: svc.extWallet,
              action: TextButton(
                onPressed: () async {
                  await context.push('/cointrip/ext-wallet');
                  if (mounted) _load();
                },
                child: Text(svc.extWallet == null ? l10n.ctRegister : l10n.ctChange),
              ),
            ),
            const SizedBox(height: 10),
            _WalletRow(
              title: l10n.ctSolWallet,
              sub: l10n.ctSolWalletSub,
              address: svc.solWallet,
              action: TextButton(
                onPressed: () async {
                  await context.push('/cointrip/sol-wallet');
                  if (mounted) _load();
                },
                child: Text(svc.solWallet == null ? l10n.ctRegister : l10n.ctChange),
              ),
            ),
            const SizedBox(height: 12),
            const WalletResponsibilityNotice(),
            const SizedBox(height: 24),
            _SectionTitle(l10n.ctMyCoins),
            if (_loading && _balances.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_error != null && _balances.isEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center))
            else if (_balances.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l10n.ctNoBalances, textAlign: TextAlign.center, style: const TextStyle(color: EggplantColors.textSecondary)),
              )
            else
              for (final b in _balances)
                _BalanceTile(
                  balance: b,
                  pending: pendingSymbols.contains(b.coin.symbol),
                  onWithdraw: () => _withdraw(b),
                ),
            if (_withdrawals.isNotEmpty) ...[
              const SizedBox(height: 24),
              _SectionTitle(l10n.ctWithdrawals),
              for (final w in _withdrawals) _WithdrawalTile(w: w),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );
}

class _WalletRow extends StatelessWidget {
  final String title;
  final String sub;
  final String? address;
  final Widget? action;
  const _WalletRow({required this.title, required this.sub, required this.address, this.action});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final a = address;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        border: Border.all(color: EggplantColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 12.5, color: EggplantColors.textSecondary)),
                const SizedBox(height: 6),
                Text(
                  a == null ? l10n.ctNotRegistered : '${a.substring(0, 6)}…${a.substring(a.length - 4)}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: a == null ? null : 'monospace',
                    color: a == null ? EggplantColors.error : EggplantColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  final CtBalance balance;
  final bool pending;
  final VoidCallback onWithdraw;
  const _BalanceTile({required this.balance, required this.pending, required this.onWithdraw});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final b = balance;
    final enough = (double.tryParse(b.amount) ?? 0) >= (double.tryParse(b.withdrawMin) ?? 0) && (double.tryParse(b.amount) ?? 0) > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(color: EggplantColors.background, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Color(b.coin.argb), shape: BoxShape.circle),
                child: Text(b.coin.symbol.length > 4 ? b.coin.symbol.substring(0, 4) : b.coin.symbol,
                    style: TextStyle(color: Colors.white, fontSize: b.coin.symbol.length >= 4 ? 10 : 12, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 긴 수량(소수 6자리)이 큰 글씨에서 숫자 중간에 줄바꿈되지 않게 한 줄로 줄여 맞춘다.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('${b.amount} ${b.coin.symbol}',
                          maxLines: 1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    Text(
                      [b.coin.name, l10n.ctWithdrawMin(b.withdrawMin, b.coin.symbol)].join(' · '),
                      style: const TextStyle(fontSize: 12.5, color: EggplantColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: enough && !pending ? onWithdraw : null,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18)),
            child: Text(pending ? l10n.ctWdRequested : l10n.ctWithdraw),
          ),
        ],
      ),
    );
  }
}

class _WithdrawalTile extends StatelessWidget {
  final CtWithdrawal w;
  const _WithdrawalTile({required this.w});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, color) = switch (w.status) {
      'requested' => (l10n.ctWdRequested, EggplantColors.warning),
      'processing' => (l10n.ctWdProcessing, EggplantColors.primary),
      'completed' => (l10n.ctWdCompleted, EggplantColors.success),
      _ => (l10n.ctWdRejected, EggplantColors.error),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${w.amount} ${w.symbol}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        [
          DateFormat(l10n.myDateTimeFormat).format(w.requestedAt),
          if (w.rejectReason != null && w.rejectReason!.isNotEmpty) w.rejectReason!,
        ].join(' · '),
        style: const TextStyle(fontSize: 12.5),
      ),
      trailing: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    );
  }
}

/// 출금 신청 — 수량, 받는 주소, 빨간 안내 확인.
class _WithdrawSheet extends StatefulWidget {
  final CtBalance balance;
  const _WithdrawSheet({required this.balance});

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  late final TextEditingController _amount = TextEditingController(text: widget.balance.amount);
  bool _ack = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await context.read<CointripService>().withdraw(widget.balance.coin.id, _amount.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on CtError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final b = widget.balance;
    final address = b.address;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.ctWithdrawTitle(b.coin.symbol), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}'))],
                decoration: InputDecoration(
                  labelText: l10n.ctWithdrawAmount,
                  suffixText: b.coin.symbol,
                  helperText: l10n.ctWithdrawRange(b.withdrawMin, b.amount, b.coin.symbol),
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Text(l10n.ctWithdrawTo, style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary)),
              const SizedBox(height: 4),
              SelectableText(
                address ?? l10n.ctWithdrawNoAddress,
                style: TextStyle(
                  fontFamily: address == null ? null : 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: address == null ? EggplantColors.error : EggplantColors.textPrimary,
                ),
              ),
              Text(
                [
                  switch (b.walletKind) {
                    'quantarium' => l10n.ctQuantariumWallet,
                    'solana' => l10n.ctSolWallet,
                    _ => l10n.ctExtWallet,
                  },
                  if (b.network.isNotEmpty) b.network,
                ].join(' · '),
                style: const TextStyle(fontSize: 12.5, color: EggplantColors.textSecondary),
              ),
              const SizedBox(height: 14),
              WalletResponsibilityAck(value: _ack, onChanged: (v) => setState(() => _ack = v)),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: const TextStyle(color: EggplantColors.error, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _ack && !_sending && address != null ? _submit : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(l10n.ctWithdrawSubmit, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
