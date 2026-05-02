import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '_auth_shared.dart';

/// Sign-up screen:
///   퀀타리움 지갑주소 + 닉네임 + 비번 + 비번확인
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _walletCtl = TextEditingController();
  final _nicknameCtl = TextEditingController();
  final _pwCtl = TextEditingController();
  final _pwConfirmCtl = TextEditingController();
  final _referrerCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;

  @override
  void dispose() {
    _walletCtl.dispose();
    _nicknameCtl.dispose();
    _pwCtl.dispose();
    _pwConfirmCtl.dispose();
    _referrerCtl.dispose();
    super.dispose();
  }

  Future<void> _pasteWallet() async {
    final data = await Clipboard.getData('text/plain');
    final s = data?.text?.trim() ?? '';
    if (s.isEmpty) return;
    setState(() => _walletCtl.text = s);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
            walletAddress: _walletCtl.text,
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
        error: '응답이 너무 느려요. 네트워크 상태를 확인하고 다시 시도해주세요.',
        referral: null,
      );
    } catch (e) {
      result = RegisterResult(error: '가입 중 오류: $e', referral: null);
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
          _showSnack('🎉 추천인 ${ref.inviterNickname ?? ""}님께 +200 QTA 지급 완료!');
        } else if (ref.reason == 'inviter_not_found') {
          _showSnack('추천인 닉네임을 찾을 수 없어 초대 보너스가 적용되지 않았어요.');
        } else if (ref.reason == 'self_referral') {
          _showSnack('자기 자신은 추천인으로 입력할 수 없어요.');
        } else if (ref.reason == 'already_processed') {
          _showSnack('이미 처리된 초대예요.');
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('회원가입'),
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
                const Text(
                  '퀀타리움 지갑으로\n회원가입 🍆',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: EggplantColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '지갑주소 하나로 로그인·닉네임 찾기·비밀번호 재설정을 모두 할 수 있어요.',
                  style: TextStyle(
                    fontSize: 13,
                    color: EggplantColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                // Wallet
                const FieldLabel('퀀타리움 지갑주소',
                    hint: '0x + 40자리 (총 42자)'),
                TextFormField(
                  controller: _walletCtl,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: '0xE0c166B147a742E4FbCf5e5BCf73aCA631f14f0e',
                    hintStyle: const TextStyle(fontSize: 12),
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

                const SizedBox(height: 18),

                // Nickname
                const FieldLabel('닉네임', hint: '2~12자, 중복 불가'),
                TextFormField(
                  controller: _nicknameCtl,
                  maxLength: 12,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    hintText: '익명가지123',
                    prefixIcon: Icon(Icons.person_outline,
                        color: EggplantColors.primary),
                    counterText: '',
                  ),
                  validator: validateNickname,
                ),

                const SizedBox(height: 18),

                // Password
                const FieldLabel('비밀번호', hint: '8자 이상'),
                TextFormField(
                  controller: _pwCtl,
                  obscureText: _obscure1,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: '영문·숫자·특수문자 조합 권장',
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

                const FieldLabel('비밀번호 확인'),
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

                const SizedBox(height: 18),

                // Referrer (선택)
                const FieldLabel(
                  '추천인 닉네임 (선택)',
                  hint: '친구가 +200 QTA 받아요 · 무제한',
                ),
                TextFormField(
                  controller: _referrerCtl,
                  maxLength: 12,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    hintText: '추천해주신 분의 닉네임',
                    prefixIcon: Icon(Icons.card_giftcard_outlined,
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
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.card_giftcard,
                          color: EggplantColors.primary, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '가입 즉시 +500 QTA 지급! 추천인을 입력하면 추천인에게 +200 QTA가 무제한으로 지급돼요.\n'
                          '※ 가입 후 탈퇴하면 추천인의 보너스는 즉시 회수돼요.',
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
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: EggplantColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: EggplantColors.primary, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '지갑주소는 변경할 수 없어요. 닉네임/비밀번호 분실 시 '
                          '같은 지갑으로만 복구할 수 있습니다.',
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
                          child:
                              Text('가입하기', style: TextStyle(fontSize: 16)),
                        ),
                ),

                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: const Text(
                      '이미 계정이 있어요 — 로그인',
                      style: TextStyle(
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
