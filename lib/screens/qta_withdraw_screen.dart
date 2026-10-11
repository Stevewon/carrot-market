import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/constants.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/qta_service.dart';
import 'profile_verify_screen.dart';

/// QTA 출금 신청 + 신청 내역 화면.
///
/// 정책:
///   - 최소 5,000 QTA, 5,000 단위로만 신청 가능
///   - 신청 즉시 잔액 차감, 운영자 처리 후 wallet_address 로 송금
///   - 'requested' 상태에서만 사용자가 직접 취소 가능
class QtaWithdrawScreen extends StatefulWidget {
  const QtaWithdrawScreen({super.key});

  @override
  State<QtaWithdrawScreen> createState() => _QtaWithdrawScreenState();
}

class _QtaWithdrawScreenState extends State<QtaWithdrawScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 잔액·내역 동시 새로고침.
      context.read<QtaService>().load(force: true);
      context.read<QtaService>().loadWithdrawals(force: true);
    });
  }

  String _maskWallet(String w) {
    if (w.length < 12) return w;
    return '${w.substring(0, 6)}…${w.substring(w.length - 4)}';
  }

  Future<void> _showRequestSheet() async {
    final qta = context.read<QtaService>();
    final auth = context.read<AuthService>();
    final user = auth.user;
    // 출금 조건: 1단계 지갑 인증 + 2단계 휴대폰 인증. 서버(requestWithdrawal)도 같은 기준.
    if (user != null && !user.canWithdraw) {
      if (!user.isWalletVerified) {
        await showVerificationGuard(
          context,
          current: user.verificationLevel,
          required: VerificationLevel.bankAccount,
          customTitle: context.l10n.myWdNeedWalletTitle,
          customMessage: context.l10n.myWdNeedWalletBody,
        );
      } else {
        await showVerificationGuard(
          context,
          current: user.verificationLevel,
          required: VerificationLevel.identity,
          customTitle: AppConfig.identityVerificationEnabled
              ? context.l10n.myWdNeedPhoneTitle
              : context.l10n.myWdPreparingTitle,
          customMessage: AppConfig.identityVerificationEnabled
              ? context.l10n.myWdNeedPhoneBody
              : context.l10n.myWdPreparingBody,
        );
      }
      return;
    }
    final wallet = user?.walletAddress;
    if (wallet == null || wallet.isEmpty) {
      _toast(context.l10n.myWdNoWallet);
      return;
    }
    final maxAmount = qta.maxRequestableAmount;
    if (maxAmount < qta.withdrawalMin) {
      _toast(
        context.l10n.myWdInsufficientMin(_fmt(qta.withdrawalMin)),
      );
      return;
    }

    int amount = qta.withdrawalMin;
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _RequestSheet(
        unit: qta.withdrawalUnit,
        min: qta.withdrawalMin,
        max: maxAmount,
        wallet: wallet,
        initial: amount,
      ),
    );
    if (result == null || !mounted) return;

    // confirm
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.myWdConfirmTitle),
        content: Text(
          context.l10n.myWdConfirmBody(_fmt(result), _maskWallet(wallet)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.myWdApply),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final err = await qta.requestWithdrawal(result);
    if (!mounted) return;
    if (err == null) {
      _toast(context.l10n.myWdRequested, success: true);
    } else {
      _toast(err);
    }
  }

  Future<void> _confirmCancel(QtaWithdrawal w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.myWdCancelTitle),
        content: Text(
          context.l10n.myWdCancelBody(_fmt(w.amount)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.myWdNo),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.myWdCancelDo),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<QtaService>().cancelWithdrawal(w.id);
    if (!mounted) return;
    if (err == null) {
      _toast(context.l10n.myWdCancelled, success: true);
    } else {
      _toast(err);
    }
  }

  void _toast(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? EggplantColors.primary : null,
    ));
  }

  String _fmt(int n) => NumberFormat('#,###').format(n);

  @override
  Widget build(BuildContext context) {
    final qta = context.watch<QtaService>();
    final df = DateFormat(context.l10n.myDateTimeFormat);
    final pending = qta.pendingWithdrawal;
    final canRequest = pending == null && qta.maxRequestableAmount >= qta.withdrawalMin;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.myWdTitle),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
        onRefresh: () async {
          await qta.load(force: true);
          await qta.loadWithdrawals(force: true);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 잔액 카드
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [EggplantColors.primary, Color(0xFF7B3F00)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.myWdAvailable,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmt(qta.balance),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 5),
                        child: Text(
                          'QTA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.myWdRuleShort,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 진행 중 안내 또는 신청 버튼
            if (pending != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded,
                        color: Color(0xFFB07900)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.myWdPendingStatus(_fmt(pending.amount), pending.statusLabel),
                        style: const TextStyle(
                          color: Color(0xFF7A5500),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      canRequest ? context.l10n.myWdRequestBtn : context.l10n.myWdInsufficient,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  onPressed: canRequest ? _showRequestSheet : null,
                ),
              ),

            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                context.l10n.myWdHistory,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: EggplantColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 4),

            if (qta.withdrawalsLoading && qta.withdrawals.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (qta.withdrawals.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 28),
                alignment: Alignment.center,
                child: Text(
                  context.l10n.myWdHistoryEmpty,
                  style:
                      const TextStyle(color: EggplantColors.textTertiary, fontSize: 13),
                ),
              )
            else
              ...qta.withdrawals.map((w) => _WithdrawalTile(
                    w: w,
                    df: df,
                    onCancel: w.canCancel ? () => _confirmCancel(w) : null,
                  )),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EggplantColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      color: EggplantColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.myWdNotice,
                      style: const TextStyle(
                        fontSize: 12,
                        color: EggplantColors.textSecondary,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      ),
    );
  }
}

class _WithdrawalTile extends StatelessWidget {
  final QtaWithdrawal w;
  final DateFormat df;
  final VoidCallback? onCancel;

  const _WithdrawalTile({
    required this.w,
    required this.df,
    required this.onCancel,
  });

  Color get _statusColor {
    switch (w.status) {
      case 'completed':
        return Colors.green;
      case 'rejected':
        return EggplantColors.textTertiary;
      case 'processing':
        return Colors.blue;
      default:
        return EggplantColors.primary;
    }
  }

  IconData get _statusIcon {
    switch (w.status) {
      case 'completed':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'processing':
        return Icons.local_shipping_outlined;
      default:
        return Icons.hourglass_top_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###').format(w.amount);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EggplantColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_statusIcon, color: _statusColor, size: 18),
              const SizedBox(width: 6),
              Text(
                w.statusLabel,
                style: TextStyle(
                  color: _statusColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                df.format(w.requestedAt),
                style: const TextStyle(
                  color: EggplantColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$fmt QTA',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: EggplantColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (onCancel != null)
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text(context.l10n.commonCancel),
                ),
            ],
          ),
          if (w.txHash != null && w.txHash!.isNotEmpty) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: w.txHash!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.myWdTxCopied)),
                  );
                }
              },
              child: Row(
                children: [
                  const Icon(Icons.link, size: 14, color: EggplantColors.textTertiary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      w.txHash!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EggplantColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const Icon(Icons.content_copy,
                      size: 12, color: EggplantColors.textTertiary),
                ],
              ),
            ),
          ],
          if (w.rejectReason != null && w.rejectReason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              context.l10n.myWdReason(w.rejectReason!),
              style: const TextStyle(
                color: EggplantColors.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 출금 금액 입력 시트.
/// - 5,000 단위 +/- 버튼
/// - "전액(가능)" 버튼
class _RequestSheet extends StatefulWidget {
  final int unit;
  final int min;
  final int max;
  final String wallet;
  final int initial;

  const _RequestSheet({
    required this.unit,
    required this.min,
    required this.max,
    required this.wallet,
    required this.initial,
  });

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  late int _amount = widget.initial.clamp(widget.min, widget.max);

  String _fmt(int n) => NumberFormat('#,###').format(n);

  String _maskWallet(String w) {
    if (w.length < 12) return w;
    return '${w.substring(0, 6)}…${w.substring(w.length - 4)}';
  }

  void _setSafe(int v) {
    final clamped = v.clamp(widget.min, widget.max);
    setState(() => _amount = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final canDec = _amount - widget.unit >= widget.min;
    final canInc = _amount + widget.unit <= widget.max;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: EggplantColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            context.l10n.myWdAmountTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: EggplantColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.myWdAmountRule(_fmt(widget.min), _fmt(widget.unit)),
            style: const TextStyle(
              fontSize: 12,
              color: EggplantColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          // 금액 입력 + 버튼
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            decoration: BoxDecoration(
              color: EggplantColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _RoundIconButton(
                  icon: Icons.remove,
                  onTap: canDec ? () => _setSafe(_amount - widget.unit) : null,
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          _fmt(_amount),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: EggplantColors.primary,
                          ),
                        ),
                        const Text(
                          'QTA',
                          style: TextStyle(
                            fontSize: 11,
                            color: EggplantColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _RoundIconButton(
                  icon: Icons.add,
                  onTap: canInc ? () => _setSafe(_amount + widget.unit) : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _setSafe(widget.min),
                  child: Text(
                    context.l10n.myWdMinBtn(_fmt(widget.min)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _setSafe(widget.max),
                  child: Text(
                    context.l10n.myWdMaxBtn(_fmt(widget.max)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: EggplantColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    color: EggplantColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  context.l10n.myWdToWallet,
                  style: const TextStyle(
                    fontSize: 13,
                    color: EggplantColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  _maskWallet(widget.wallet),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: EggplantColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _amount),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  context.l10n.myWdSubmitAmount(_fmt(_amount)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: disabled
              ? EggplantColors.border.withOpacity(0.3)
              : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: disabled
                ? EggplantColors.border
                : EggplantColors.primary.withOpacity(0.4),
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: disabled
              ? EggplantColors.textTertiary
              : EggplantColors.primary,
        ),
      ),
    );
  }
}
