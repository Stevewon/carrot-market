import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/auth_service.dart';
import 'auth/_auth_shared.dart';

/// Wallet + password login screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _walletCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _walletCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final err = await context.read<AuthService>().login(
          walletAddress: _walletCtl.text,
          password: _passwordCtl.text,
        );

    if (!mounted) return;
    setState(() => _loading = false);

    if (err != null) {
      setState(() => _error = err);
    } else {
      context.go('/');
    }
  }

  Future<void> _pasteWallet() async {
    final data = await Clipboard.getData('text/plain');
    final s = data?.text?.trim() ?? '';
    if (s.isEmpty) return;
    setState(() => _walletCtl.text = s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                const Text(
                  '로그인',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: EggplantColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '퀀타리움 지갑주소와 비밀번호로 로그인하세요.',
                  style: TextStyle(
                    fontSize: 14,
                    color: EggplantColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

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

                const SizedBox(height: 20),

                const FieldLabel('비밀번호'),
                TextFormField(
                  controller: _passwordCtl,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: '8자 이상',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: EggplantColors.primary),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '비밀번호를 입력해주세요';
                    return null;
                  },
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  ErrorBox(message: _error!),
                ],

                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
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
                          child: Text('로그인', style: TextStyle(fontSize: 16)),
                        ),
                ),

                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => context.push('/find'),
                      child: const Text(
                        '닉네임 / 비밀번호 찾기',
                        style: TextStyle(
                          color: EggplantColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Text('·',
                        style:
                            TextStyle(color: EggplantColors.textTertiary)),
                    TextButton(
                      onPressed: () => context.push('/register'),
                      child: const Text(
                        '회원가입',
                        style: TextStyle(
                          color: EggplantColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: EggplantColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          color: EggplantColors.primary, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '같은 지갑으로 다른 기기에서 로그인하면 '
                          '이전 기기의 세션은 즉시 종료돼요.',
                          style: TextStyle(
                            fontSize: 12,
                            color: EggplantColors.textSecondary,
                            height: 1.5,
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
      ),
    );
  }
}
