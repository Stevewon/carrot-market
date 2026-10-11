import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '_auth_shared.dart';

/// 1단계 지갑 인증 카드.
///
/// 회원이 지갑주소를 넣으면 가지 본사 지갑이 그 지갑으로 소수점 6자리 임의 수량
/// (예: 0.234567 QTA)을 보낸다. 회원이 지갑 앱에서 들어온 수량을 보고 입력하면 통과.
/// 수량은 서버가 알려주지 않는다 — 지갑 주인만 볼 수 있다.
class WalletReceiveCard extends StatefulWidget {
  /// 이미 등록된(인증 전) 지갑주소 — 입력칸 기본값.
  final String initialWallet;

  /// 인증이 끝나면 호출 (사용자 정보는 AuthService 가 갱신).
  final VoidCallback onVerified;

  const WalletReceiveCard({super.key, this.initialWallet = '', required this.onVerified});

  @override
  State<WalletReceiveCard> createState() => _WalletReceiveCardState();
}

class _WalletReceiveCardState extends State<WalletReceiveCard> {
  late final TextEditingController _walletCtl = TextEditingController(text: widget.initialWallet);
  final _amountCtl = TextEditingController();
  WalletReceive? _req;
  bool _busy = false;
  String? _error;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    _walletCtl.dispose();
    _amountCtl.dispose();
    super.dispose();
  }

  Future<void> _pasteWallet() async {
    final data = await Clipboard.getData('text/plain');
    final s = data?.text?.trim() ?? '';
    if (s.isEmpty) return;
    setState(() => _walletCtl.text = s);
  }

  Future<void> _request() async {
    final wallet = _walletCtl.text.trim();
    final err = validateWalletAddress(wallet);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await context.read<AuthService>().requestWalletReceive(wallet);
    if (!mounted) return;
    if (r.alreadyVerified) {
      setState(() => _busy = false);
      widget.onVerified();
      return;
    }
    setState(() {
      _busy = false;
      _req = r.request;
      _error = r.error;
    });
    _startPolling();
  }

  /// 본사 지갑 송금이 끝날 때까지 상태 확인 (서명·전송에 수 초~1분).
  void _startPolling() {
    _poll?.cancel();
    if (_req == null || _req!.isSent) return;
    _poll = Timer.periodic(const Duration(seconds: 4), (_) async {
      final cur = _req;
      if (cur == null) return;
      final next = await context.read<AuthService>().getWalletReceive(cur.id);
      if (!mounted || next == null) return;
      setState(() => _req = next);
      if (next.isSent) _poll?.cancel();
    });
  }

  Future<void> _confirm() async {
    final req = _req;
    if (req == null) return;
    final raw = _amountCtl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(raw)) {
      setState(() => _error = context.l10n.authReceiveAmountInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await context.read<AuthService>().confirmWalletReceive(req.id, '0.$raw');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = r.verified ? null : r.error;
    });
    if (r.verified) {
      widget.onVerified();
    } else if (r.attemptsLeft == 0) {
      // 기회를 다 썼으면 처음부터 다시 요청.
      setState(() {
        _req = null;
        _amountCtl.clear();
      });
    } else if (r.attemptsLeft != null) {
      final next = await context.read<AuthService>().getWalletReceive(req.id);
      if (mounted && next != null) setState(() => _req = next);
    }
  }

  void _restart() {
    _poll?.cancel();
    setState(() {
      _req = null;
      _error = null;
      _amountCtl.clear();
    });
  }

  String _short(String w) => w.length < 12 ? w : '${w.substring(0, 6)}…${w.substring(w.length - 4)}';

  @override
  Widget build(BuildContext context) {
    final req = _req;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EggplantColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EggplantColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.authWalletStepTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            l10n.authWalletStepDesc,
            style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (req == null) ...[
            TextField(
              controller: _walletCtl,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l10n.authMyQuantariumWalletLabel,
                hintText: l10n.authWalletHint42,
                hintStyle: const TextStyle(fontSize: 12),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded, size: 20),
                  tooltip: l10n.authPaste,
                  onPressed: _pasteWallet,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _busy ? null : _request,
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: Text(_busy ? l10n.authRequesting : l10n.authReceiveCoinButton),
            ),
          ] else ...[
            // 송금 상태 — 실패해도 다시 요청할 수 있게, 입력칸은 처음부터 항상 보인다.
            if (req.isFailed) ...[
              ErrorBox(
                  message: l10n.authReceiveSendFailed),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _restart, child: Text(l10n.authRequestAgain)),
            ] else if (!req.isSent)
              Row(
                children: [
                  const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.authReceiveSending(_short(req.walletAddress)),
                      style: const TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ],
              )
            else ...[
              Text(
                l10n.authReceiveSent(_short(req.walletAddress)),
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
              if (req.txHash != null && req.txHash!.isNotEmpty) ...[
                const SizedBox(height: 8),
                // 본사 지갑 송금은 SPHINCS+ (type 0x7f) — scan 거래 화면에 "(SPHINCS+)" 로 보인다.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFE7FB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_rounded,
                          size: 18, color: EggplantColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.authQuantumBadge,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: EggplantColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://scan.quantarium.io/tx/${req.txHash}'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: Text(l10n.authViewTxOnScan),
                ),
              ],
            ],
            const SizedBox(height: 8),
            // 블록 탐색기에서 내 지갑 주소 페이지를 바로 열어 들어온 수량을 확인.
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://scan.quantarium.io/address/${req.walletAddress}'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(l10n.authCheckWalletCode),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountCtl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2),
              decoration: InputDecoration(
                labelText: l10n.authReceivedAmount,
                prefixText: '0.',
                suffixText: 'QTA',
                hintText: '234567',
                counterText: '',
              ),
            ),
            const SizedBox(height: 4),
            Text(l10n.authAttemptsLeft('${req.attemptsLeft}'),
                style: const TextStyle(fontSize: 11, color: EggplantColors.textTertiary)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _busy ? null : _confirm,
              child: Text(_busy ? l10n.authChecking : l10n.authVerify),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            ErrorBox(message: _error!),
          ],
        ],
      ),
    );
  }
}
