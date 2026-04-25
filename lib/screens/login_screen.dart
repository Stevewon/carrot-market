import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/responsive.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';
import 'auth/_auth_shared.dart';

/// Nickname + password login screen.
///
/// Wallet address is only used for signup / recovery, not here.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nicknameCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _nicknameCtl.dispose();
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
          nickname: _nicknameCtl.text,
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Responsive.maxContentWidth),
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
                  '닉네임과 비밀번호로 로그인하세요.',
                  style: TextStyle(
                    fontSize: 14,
                    color: EggplantColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                const FieldLabel('닉네임'),
                TextFormField(
                  controller: _nicknameCtl,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 12,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: '가입할 때 설정한 닉네임',
                    prefixIcon: Icon(
                      Icons.person_outline,
                      color: EggplantColors.primary,
                    ),
                    counterText: '',
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return '닉네임을 입력해주세요';
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                const FieldLabel('비밀번호'),
                TextFormField(
                  controller: _passwordCtl,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
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
                          '다른 기기에서 같은 계정으로 로그인하면 '
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
        ),
      ),
    );
  }
}
