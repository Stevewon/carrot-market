import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '_auth_shared.dart';

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

    final res = await context
        .read<AuthService>()
        .recoverNickname(_walletCtl.text);

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.error != null) {
        _error = res.error;
      } else {
        _foundNickname = res.nickname;
      }
    });
  }

  Future<void> _resetPassword() async {
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final err = await context.read<AuthService>().resetPassword(
          walletAddress: _walletCtl.text,
          newPassword: _pwCtl.text,
          newPasswordConfirm: _pwConfirmCtl.text,
        );

    if (!mounted) return;
    setState(() => _loading = false);

    if (err != null) {
      setState(() => _error = err);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호를 새로 설정했어요 🔒')),
      );
      context.go('/');
    }
  }

  void _startOver() {
    setState(() {
      _foundNickname = null;
      _error = null;
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
        title: const Text('계정 찾기'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _foundNickname == null ? _buildStep1() : _buildStep2(),
        ),
      ),
    );
  }

  // -------- Step 1: look up wallet --------
  Widget _buildStep1() {
    return Form(
      key: _walletFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Text(
            '지갑주소로\n계정을 찾아요',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: EggplantColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '가입할 때 사용한 퀀타리움 지갑주소를 입력해주세요.\n'
            '지갑 소유를 인증하면 닉네임을 확인하고 비밀번호를 다시 설정할 수 있어요.',
            style: TextStyle(
              fontSize: 13,
              color: EggplantColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),

          const FieldLabel('퀀타리움 지갑주소'),
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
                tooltip: '붙여넣기',
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
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('계정 확인', style: TextStyle(fontSize: 16)),
                  ),
          ),
        ],
      ),
    );
  }

  // -------- Step 2: reset password --------
  Widget _buildStep2() {
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
                const Row(
                  children: [
                    Icon(Icons.verified_user_outlined,
                        color: EggplantColors.primary, size: 18),
                    SizedBox(width: 6),
                    Text(
                      '등록된 닉네임',
                      style: TextStyle(
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
          const Text(
            '새 비밀번호 설정',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: EggplantColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '재설정 후 기존에 로그인된 모든 기기는 자동으로 로그아웃돼요.',
            style: TextStyle(
              fontSize: 12,
              color: EggplantColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          const FieldLabel('새 비밀번호', hint: '8자 이상'),
          TextFormField(
            controller: _pwCtl,
            obscureText: _obscure1,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: '8자 이상',
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

          const FieldLabel('새 비밀번호 확인'),
          TextFormField(
            controller: _pwConfirmCtl,
            obscureText: _obscure2,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: '다시 한 번 입력',
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
              if (v == null || v.isEmpty) return '비밀번호 확인을 입력해주세요';
              if (v != _pwCtl.text) return '비밀번호가 일치하지 않아요';
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
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('비밀번호 재설정',
                        style: TextStyle(fontSize: 16)),
                  ),
          ),

          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _loading ? null : _startOver,
              child: const Text(
                '다른 지갑주소로 다시 찾기',
                style: TextStyle(
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
