import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
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
  void initState() {
    super.initState();
    // 강제 로그아웃(계정 정지 등) 사유가 있으면 한 번 보여준다.
    final auth = context.read<AuthService>();
    if (auth.logoutNotice != null) {
      _error = auth.logoutNotice;
      auth.logoutNotice = null;
    }
  }

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

    try {
      final err = await context
          .read<AuthService>()
          .login(
            nickname: _nicknameCtl.text,
            password: _passwordCtl.text,
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      if (err != null) {
        setState(() => _error = err);
      } else {
        context.go('/');
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = context.l10n.authServerSlow);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = context.l10n.authLoginFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
                Text(
                  l10n.authLoginTitle,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: EggplantColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.authLoginDesc,
                  style: const TextStyle(
                    fontSize: 14,
                    color: EggplantColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                FieldLabel(l10n.authNicknameLabel),
                TextFormField(
                  controller: _nicknameCtl,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 12,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: l10n.authLoginNicknameHint,
                    prefixIcon: const Icon(
                      Icons.person_outline,
                      color: EggplantColors.primary,
                    ),
                    counterText: '',
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return l10n.authNicknameRequired;
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                FieldLabel(l10n.authPasswordLabel),
                TextFormField(
                  controller: _passwordCtl,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: l10n.authMin8,
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
                    if (v == null || v.isEmpty) return l10n.authPasswordRequired;
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
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            l10n.authLoginButton,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                ),

                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => context.push('/find'),
                      child: Text(
                        l10n.authFindNicknamePassword,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
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
                      child: Text(
                        l10n.authRegisterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
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
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          color: EggplantColors.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.authSessionInfo,
                          style: const TextStyle(
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
