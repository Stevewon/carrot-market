import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/l10n.dart';
import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '../../services/pending_invite.dart';
import '_auth_shared.dart';

/// Sign-up screen:
///   닉네임 + 비번 + 비번확인 (+ 추천인)
///   지갑은 가입 후 '내 정보 → 인증 관리 → 지갑 등록' 에서 연결한다.
class RegisterScreen extends StatefulWidget {
  /// 친구 초대 링크로 들어오면 초대한 사람 닉네임 — 추천인 칸에 미리 채운다.
  final String? referrer;
  const RegisterScreen({super.key, this.referrer});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nicknameCtl = TextEditingController();
  final _pwCtl = TextEditingController();
  final _pwConfirmCtl = TextEditingController();
  late final _referrerCtl = TextEditingController(text: (widget.referrer ?? PendingInvite.referrer)?.trim() ?? '');
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 온보딩을 거치지 않고 가입으로 바로 온 경우에도 연합 초대 페이지가 남긴 연합장 닉네임을 채운다.
    if (_referrerCtl.text.isEmpty) {
      PendingInvite.checkClipboard().then((_) {
        final ref = PendingInvite.referrer;
        if (mounted && ref != null && _referrerCtl.text.isEmpty) _referrerCtl.text = ref;
      });
    }
  }

  @override
  void dispose() {
    _nicknameCtl.dispose();
    _pwCtl.dispose();
    _pwConfirmCtl.dispose();
    _referrerCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n;
    setState(() {
      _loading = true;
      _error = null;
    });

    // 가입 요청 절대 데드라인 — 25초 안에 무조건 빙글빙글 풀린다.
    // (AuthService.register 가 이미 20초 timeout 을 갖지만, UI 단에서
    //  한 번 더 안전망을 건다. 어떤 일이 있어도 사용자 입장에서 무한 로딩 X.)
    RegisterResult result;
    try {
      result = await context
          .read<AuthService>()
          .register(
            nickname: _nicknameCtl.text,
            password: _pwCtl.text,
            passwordConfirm: _pwConfirmCtl.text,
            referrerNickname: _referrerCtl.text.trim().isEmpty
                ? null
                : _referrerCtl.text.trim(),
          )
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      result = RegisterResult(
        error: l10n.authResponseSlow,
        referral: null,
      );
    } catch (e) {
      debugPrint('[register] unexpected error: $e');
      result = RegisterResult(error: l10n.authRegisterFailed, referral: null);
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.error != null) {
      setState(() => _error = result.error);
    } else {
      // 친구 초대 결과 토스트 (성공/실패 모두 친절하게)
      final ref = result.referral;
      if (ref != null) {
        if (ref.credited) {
          _showSnack(l10n.authReferralCredited(ref.inviterNickname ?? ''));
        } else if (ref.reason == 'inviter_not_found') {
          _showSnack(l10n.authReferralNotFound);
        } else if (ref.reason == 'self_referral') {
          _showSnack(l10n.authReferralSelf);
        } else if (ref.reason == 'already_processed') {
          _showSnack(l10n.authReferralAlreadyProcessed);
        }
      }
      context.go('/');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
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
        title: Text(l10n.authRegisterTitle),
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
                const SizedBox(height: 8),
                Text(
                  l10n.authRegisterHeadline,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: EggplantColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.authRegisterDesc,
                  style: const TextStyle(
                    fontSize: 13,
                    color: EggplantColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                // Nickname
                FieldLabel(l10n.authNicknameLabel, hint: l10n.authNicknameHint),
                TextFormField(
                  controller: _nicknameCtl,
                  maxLength: 12,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: l10n.authNicknamePlaceholder,
                    prefixIcon: const Icon(Icons.person_outline,
                        color: EggplantColors.primary),
                    counterText: '',
                  ),
                  validator: validateNickname,
                ),

                const SizedBox(height: 18),

                // Password
                FieldLabel(l10n.authPasswordLabel, hint: l10n.authMin8),
                TextFormField(
                  controller: _pwCtl,
                  obscureText: _obscure1,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: l10n.authPasswordPlaceholder,
                    hintStyle: const TextStyle(fontSize: 12),
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

                FieldLabel(l10n.authPasswordConfirmLabel),
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

                const SizedBox(height: 18),

                // Referrer (선택)
                FieldLabel(
                  l10n.authReferrerLabel,
                  hint: l10n.authReferrerHint,
                ),
                TextFormField(
                  controller: _referrerCtl,
                  maxLength: 12,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: l10n.authReferrerPlaceholder,
                    prefixIcon: const Icon(Icons.card_giftcard_outlined,
                        color: EggplantColors.primary),
                    counterText: '',
                  ),
                  // 선택 사항이라 유효성검사는 비움. 서버에서 존재 여부 검사.
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  ErrorBox(message: _error!),
                ],

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: EggplantColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.card_giftcard,
                          color: EggplantColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.authRegisterBonusInfo,
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
                const SizedBox(height: 8),
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
                          l10n.authWalletImmutableInfo,
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
                            l10n.authRegisterButton,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                ),

                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: Text(
                      l10n.authHaveAccountLogin,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EggplantColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
