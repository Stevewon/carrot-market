import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '_auth_shared.dart';

/// 지갑 인증 카드 (가입 1단계 · 계정 찾기).
///
/// 1) 회원이 지갑주소를 넣으면 가지 본사 지갑이 그 지갑으로 5.xxxxxx QTA 를 보낸다 (가스비 포함).
/// 2) 앱이 돌려보낼 수량 1.xxxxxx 를 알려주고, 회원이 자기 지갑에서 본사 지갑으로 보낸다.
/// 3) "보냈어요" 를 누르면 서버가 블록 탐색기에서 그 송금을 찾아 인증한다.
/// 본사가 보낸 수량은 scan 에 공개돼 증명이 안 된다 — 그 지갑에서 나간 송금만이 주인 증명이다.
class WalletReceiveCard extends StatefulWidget {
  /// 이미 등록된(인증 전) 지갑주소 — 입력칸 기본값.
  final String initialWallet;

  /// 인증이 끝나면 호출 (사용자 정보는 AuthService 가 갱신).
  final VoidCallback onVerified;

  /// 계정 찾기(비밀번호 재설정) 용 — 로그인 전. 서버가 이 지갑이 가입 때 등록한 지갑과
  /// 같은지 먼저 확인하고, 맞으면 본사 지갑이 보낸다. 끝나면 challenge id 를 넘긴다.
  final ValueChanged<String>? onResetVerified;

  bool get isReset => onResetVerified != null;

  const WalletReceiveCard({super.key, this.initialWallet = '', required this.onVerified})
      : onResetVerified = null;

  const WalletReceiveCard.reset({super.key, required String wallet, required ValueChanged<String> onVerified})
      : initialWallet = wallet,
        onResetVerified = onVerified,
        onVerified = _noop;

  static void _noop() {}

  @override
  State<WalletReceiveCard> createState() => _WalletReceiveCardState();
}

class _WalletReceiveCardState extends State<WalletReceiveCard> {
  late final TextEditingController _walletCtl = TextEditingController(text: widget.initialWallet);
  WalletReceive? _req;
  bool _busy = false;
  bool _done = false; // 계정 찾기: 인증 완료
  String? _error;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    _walletCtl.dispose();
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
    final auth = context.read<AuthService>();
    if (widget.isReset) {
      final r = await auth.requestResetWalletReceive(wallet);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _req = r.request;
        _error = r.error;
      });
      _startPolling();
      return;
    }
    final r = await auth.requestWalletReceive(wallet);
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
      final auth = context.read<AuthService>();
      final next = widget.isReset
          ? await auth.getResetWalletReceive(cur.id)
          : await auth.getWalletReceive(cur.id);
      if (!mounted || next == null) return;
      setState(() => _req = next);
      if (next.isSent) _poll?.cancel();
    });
  }

  Future<void> _confirm() async {
    final req = _req;
    if (req == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    final r = widget.isReset
        ? await auth.confirmResetWalletReceive(req.id, '')
        : await auth.confirmWalletReceive(req.id, '');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = r.verified ? null : r.error;
      if (r.verified && widget.isReset) _done = true;
    });
    if (r.verified) {
      if (widget.isReset) {
        widget.onResetVerified!(req.id);
      } else {
        widget.onVerified();
      }
    }
  }

  Future<void> _copy(String text, String toast) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast), duration: const Duration(seconds: 1)));
  }

  /// 복사 버튼이 달린 한 줄 (돌려보낼 수량 · 본사 지갑 주소).
  Widget _copyRow(String label, String value, String toast, {bool big = false}) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: EggplantColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11, color: EggplantColors.textSecondary)),
                  const SizedBox(height: 2),
                  SelectableText(value,
                      style: TextStyle(
                          fontSize: big ? 20 : 12.5,
                          fontWeight: big ? FontWeight.w800 : FontWeight.w600,
                          color: big ? EggplantColors.primary : EggplantColors.textPrimary)),
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.authCopy,
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () => _copy(value.replaceAll(' QTA', ''), toast),
            ),
          ],
        ),
      );

  void _restart() {
    _poll?.cancel();
    setState(() {
      _req = null;
      _error = null;
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
          Text(widget.isReset ? l10n.authResetWalletTitle : l10n.authWalletStepTitle,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            widget.isReset ? l10n.authResetWalletDesc : l10n.authWalletStepDesc,
            style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (_done) ...[
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: EggplantColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.authResetWalletVerified,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ] else if (req == null) ...[
            TextField(
              controller: _walletCtl,
              // 계정 찾기에선 위에서 확인한 지갑으로만 받는다.
              readOnly: widget.isReset,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l10n.authMyQuantariumWalletLabel,
                hintText: l10n.authWalletHint42,
                hintStyle: const TextStyle(fontSize: 12),
                isDense: true,
                suffixIcon: widget.isReset ? null : IconButton(
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
                l10n.authReturnSent(_short(req.walletAddress), req.sendAmount ?? ''),
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
                const SizedBox(height: 8),
                // 지갑 앱에 바로 안 보여도 scan 거래 화면에서 본사 송금을 확인할 수 있다.
                OutlinedButton.icon(
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
            if (req.isSent && req.returnAmount != null) ...[
              const SizedBox(height: 14),
              Text(l10n.authReturnTitle,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(l10n.authReturnDesc,
                  style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary, height: 1.5)),
              const SizedBox(height: 8),
              _copyRow(l10n.authReturnAmountLabel, '${req.returnAmount} QTA', l10n.authAmountCopied, big: true),
              const SizedBox(height: 6),
              _copyRow(l10n.authReturnToLabel, req.returnTo, l10n.authAddressCopied),
              const SizedBox(height: 6),
              Text(l10n.authReturnNote,
                  style: const TextStyle(fontSize: 11, color: EggplantColors.textTertiary, height: 1.5)),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _busy ? null : _confirm,
                child: Text(_busy ? l10n.authChecking : l10n.authReturnSentButton),
              ),
            ],
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
