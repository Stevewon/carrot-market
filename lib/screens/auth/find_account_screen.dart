import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/l10n.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '_auth_shared.dart';
import 'wallet_proof_card.dart';

/// Two-step screen:
///   Step 1: enter wallet -> show nickname on file
///   Step 2: reset password for same wallet
class FindAccountScreen extends StatefulWidget {
  const FindAccountScreen({super.key});

  @override
  State<FindAccountScreen> createState() => _FindAccountScreenState();
}

class _FindAccountScreenState extends State<FindAccountScreen> {
  final _walletCtl = TextEditingController();
  final _pwCtl = TextEditingController();
  final _pwConfirmCtl = TextEditingController();

  final _walletFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  // UI state
  bool _loading = false;
  String? _error;
  String? _foundNickname; // non-null once we've looked up the wallet
  /// 다른 기기에서 재설정할 때 필요한 지갑 소유 증명 challenge id.
  String? _walletChallengeId;

  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _walletCtl.dispose();
    _pwCtl.dispose();
    _pwConfirmCtl.dispose();
    super.dispose();
  }

  Future<void> _pasteWallet() async {
    final data = await Clipboard.getData('text/plain');
    final s = data?.text?.trim() ?? '';
    if (s.isEmpty) return;
    setState(() => _walletCtl.text = s);
  }

  Future<void> _lookup() async {
    if (!_walletFormKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await context
          .read<AuthService>()
          .recoverNickname(_walletCtl.text)
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      if (res.error != null) {
        setState(() => _error = res.error);
      } else {
        setState(() => _foundNickname = res.nickname);
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = context.l10n.authServerSlow);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = context.l10n.authLookupFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final err = await context
          .read<AuthService>()
          .resetPassword(
            walletAddress: _walletCtl.text,
            newPassword: _pwCtl.text,
            newPasswordConfirm: _pwConfirmCtl.text,
            walletChallengeId: _walletChallengeId,
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      if (err != null) {
        setState(() => _error = err);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.authPasswordResetDone)),
        );
        context.go('/');
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = context.l10n.authServerSlow);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = context.l10n.authResetFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startOver() {
    setState(() {
      _foundNickname = null;
      _error = null;
      _walletChallengeId = null;
      _pwCtl.clear();
      _pwConfirmCtl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(context.l10n.authFindAccountTitle),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Responsive.maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _foundNickname == null ? _buildStep1() : _buildStep2(),
            ),
          ),
        ),
      ),
    );
  }

  // -------- Step 1: look up wallet --------
  Widget _buildStep1() {
    final l10n = context.l10n;
    return Form(
      key: _walletFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(
            l10n.authFindHeadline,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: EggplantColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.authFindDesc,
            style: const TextStyle(
              fontSize: 13,
              color: EggplantColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),

          FieldLabel(l10n.authQuantariumWalletLabel),
          TextFormField(
            controller: _walletCtl,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: '0x...',
              prefixIcon: const Icon(
                Icons.account_balance_wallet_outlined,
                color: EggplantColors.primary,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste_rounded, size: 20),
                tooltip: l10n.authPaste,
                onPressed: _pasteWallet,
              ),
            ),
            validator: validateWalletAddress,
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            ErrorBox(message: _error!),
          ],

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _lookup,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      l10n.authCheckAccount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // -------- Step 2: reset password --------
  Widget _buildStep2() {
    final l10n = context.l10n;
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),

          // Found nickname card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: EggplantColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EggplantColors.primaryLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined,
                        color: EggplantColors.primary, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      l10n.authRegisteredNickname,
                      style: const TextStyle(
                        fontSize: 12,
                        color: EggplantColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _foundNickname!,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: EggplantColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _walletCtl.text,
                  style: const TextStyle(
                    fontSize: 11,
                    color: EggplantColors.textTertiary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Text(
            l10n.authNewPasswordTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: EggplantColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.authNewPasswordDesc,
            style: const TextStyle(
              fontSize: 12,
              color: EggplantColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          WalletProofCard(
            walletAddress: () => _walletCtl.text,
            purpose: 'reset',
            onVerified: (id) => setState(() => _walletChallengeId = id),
          ),
          const SizedBox(height: 20),

          FieldLabel(l10n.authNewPasswordLabel, hint: l10n.authMin8),
          TextFormField(
            controller: _pwCtl,
            obscureText: _obscure1,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: l10n.authMin8,
              prefixIcon: const Icon(Icons.lock_outline,
                  color: EggplantColors.primary),
              suffixIcon: IconButton(
                icon: Icon(_obscure1
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure1 = !_obscure1),
              ),
            ),
            validator: validatePassword,
          ),

          const SizedBox(height: 18),

          FieldLabel(l10n.authNewPasswordConfirmLabel),
          TextFormField(
            controller: _pwConfirmCtl,
            obscureText: _obscure2,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: l10n.authEnterAgain,
              prefixIcon: const Icon(Icons.lock_outline,
                  color: EggplantColors.primary),
              suffixIcon: IconButton(
                icon: Icon(_obscure2
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure2 = !_obscure2),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return l10n.authPasswordConfirmRequired;
              if (v != _pwCtl.text) return l10n.authPasswordMismatch;
              return null;
            },
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            ErrorBox(message: _error!),
          ],

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _resetPassword,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      l10n.authResetPasswordButton,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
          ),

          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _loading ? null : _startOver,
              child: Text(
                l10n.authFindAgain,
                style: const TextStyle(
                  color: EggplantColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
