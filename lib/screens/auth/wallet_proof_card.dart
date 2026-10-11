import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '_auth_shared.dart';

/// 지갑 소유 증명 카드 (소액 송금 인증).
///
/// 남의 지갑주소를 등록(선점)하지 못하도록, 그 지갑에서 서버가 정해준 랜덤
/// 소액(0.1 QTA 미만)을 가지 본사 인증 지갑으로 보내게 해서 개인키 소유를 확인한다.
///
/// [walletAddress] 는 부모 폼의 현재 지갑 입력값을 돌려준다. 인증 후 지갑을
/// 바꾸면 인증이 풀린다 ([onVerified] 에 null 전달).
/// [editableWallet] 이면 카드 안에 지갑주소 입력칸을 보여준다 (지갑 없이 가입한 회원의 지갑 등록).
class WalletProofCard extends StatefulWidget {
  final String Function() walletAddress;
  final String purpose; // 'register' | 'reset' | 'verify'
  final ValueChanged<String?> onVerified;
  final bool editableWallet;

  const WalletProofCard({
    super.key,
    required this.walletAddress,
    required this.purpose,
    required this.onVerified,
    this.editableWallet = false,
  });

  @override
  State<WalletProofCard> createState() => _WalletProofCardState();
}

class _WalletProofCardState extends State<WalletProofCard> {
  WalletChallenge? _challenge;
  bool _verified = false;
  bool _busy = false;
  String? _error;
  final _walletCtl = TextEditingController();

  @override
  void dispose() {
    _walletCtl.dispose();
    super.dispose();
  }

  String get _rawWallet => widget.editableWallet ? _walletCtl.text : widget.walletAddress();
  String get _currentWallet => _rawWallet.trim().toLowerCase();

  Future<void> _pasteWallet() async {
    final data = await Clipboard.getData('text/plain');
    final s = data?.text?.trim() ?? '';
    if (s.isEmpty) return;
    setState(() => _walletCtl.text = s);
  }

  /// 부모가 지갑 입력을 바꾸면 이전 인증은 무효.
  bool get _stale =>
      _challenge != null &&
      _currentWallet.isNotEmpty &&
      _challenge!.walletAddress.toLowerCase() != _currentWallet;

  void _reset() {
    setState(() {
      _challenge = null;
      _verified = false;
      _error = null;
    });
    widget.onVerified(null);
  }

  Future<void> _start() async {
    final wallet = _rawWallet.trim();
    // 'verify' 에서 입력칸이 없으면 서버가 로그인 계정의 지갑으로 정한다.
    final err = widget.purpose == 'verify' && !widget.editableWallet
        ? null
        : validateWalletAddress(wallet);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await context
        .read<AuthService>()
        .createWalletChallenge(walletAddress: wallet, purpose: widget.purpose);
    if (!mounted) return;
    // 'verify' 에서 챌린지도 오류도 없으면 = 이미 지갑 인증된 계정 → 완료로 처리.
    if (widget.purpose == 'verify' && r.challenge == null && r.error == null) {
      setState(() {
        _busy = false;
        _verified = true;
        _error = null;
      });
      widget.onVerified('already_verified');
      return;
    }
    setState(() {
      _busy = false;
      _challenge = r.challenge;
      _verified = false;
      _error = r.error;
    });
    widget.onVerified(null);
  }

  Future<void> _check() async {
    final ch = _challenge;
    if (ch == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await context
        .read<AuthService>()
        .checkWalletChallenge(ch.id, purpose: widget.purpose);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _verified = r.verified;
      _error = r.verified ? null : r.error;
    });
    widget.onVerified(r.verified ? ch.id : null);
  }

  String _shortWallet(String w) =>
      w.length < 12 ? w : '${w.substring(0, 6)}…${w.substring(w.length - 4)}';

  void _copy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_stale) {
      // build 중 setState 금지 → 다음 프레임에 초기화.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _stale) _reset();
      });
    }

    if (_verified && !_stale) {
      // 인증은 60분 동안만 유효 — 그 뒤 가입/재설정에서 "만료" 가 나면
      // 여기서 처음부터 다시 할 수 있어야 한다.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoBox(
            message: l10n.authWalletVerifiedInfo,
            icon: Icons.verified_outlined,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _reset,
              child: Text(l10n.authVerifyAgain, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      );
    }

    final ch = _stale ? null : _challenge;
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
          Text(
            switch (widget.purpose) {
              'register' => l10n.authWalletVerifyTitle,
              'verify' => widget.editableWallet ? l10n.authWalletRegisterTitle : l10n.authWalletVerifyTitle,
              _ => l10n.authWalletVerifyResetTitle,
            },
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            switch (widget.purpose) {
              'register' => l10n.authWalletVerifyDescRegister,
              'verify' => l10n.authWalletVerifyDescVerify,
              _ => l10n.authWalletVerifyDescReset,
            },
            style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (widget.editableWallet && ch == null) ...[
            TextField(
              controller: _walletCtl,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
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
          ],
          if (ch == null)
            OutlinedButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: Text(_busy ? l10n.authPreparing : l10n.authWalletVerifyStart),
            )
          else ...[
            _CopyRow(
              label: l10n.authAmountToSend,
              value: '${ch.amount} QTA',
              onCopy: () => _copy(ch.amount, l10n.authAmountCopied),
            ),
            const SizedBox(height: 8),
            _CopyRow(
              label: ch.sendTo.toLowerCase() == ch.walletAddress.toLowerCase()
                  ? l10n.authRecipientMyWallet
                  : l10n.authRecipientEggplantWallet,
              value: ch.sendTo,
              onCopy: () => _copy(ch.sendTo, l10n.authAddressCopied),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.authWalletSendInstruction(_shortWallet(ch.walletAddress)),
              style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _busy ? null : _check,
              child: Text(_busy ? l10n.authChecking : l10n.authSentCheck),
            ),
            TextButton(
              onPressed: _busy ? null : _start,
              child: Text(l10n.authNewAmount, style: const TextStyle(fontSize: 12)),
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

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;
  const _CopyRow({required this.label, required this.value, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                Text(label,
                    style: const TextStyle(fontSize: 11, color: EggplantColors.textTertiary)),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            tooltip: context.l10n.authCopy,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
