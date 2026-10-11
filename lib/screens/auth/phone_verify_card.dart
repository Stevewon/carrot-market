import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '_auth_shared.dart';

/// 2단계 휴대폰 인증 카드 — 문자로 받은 6자리 코드 입력.
///
/// Firebase 문자 인증으로 번호를 확인하고, 받은 ID 토큰을 가지 서버로 보낸다.
/// 서버는 전화번호를 해시로만 저장한다 (1인 1계정). Firebase 로그인 상태는
/// 인증 직후 바로 지운다 — 가지 로그인은 가지 서버 계정만 쓴다.
class PhoneVerifyCard extends StatefulWidget {
  final VoidCallback onVerified;
  const PhoneVerifyCard({super.key, required this.onVerified});

  @override
  State<PhoneVerifyCard> createState() => _PhoneVerifyCardState();
}

class _PhoneVerifyCardState extends State<PhoneVerifyCard> {
  final _phoneCtl = TextEditingController();
  final _codeCtl = TextEditingController();
  String? _verificationId;
  int? _resendToken;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtl.dispose();
    _codeCtl.dispose();
    super.dispose();
  }

  /// 010-1234-5678 → +821012345678.
  /// 일본 휴대폰(070/080/090): 090-1234-5678 / 09012345678 / +819012345678 → +819012345678.
  /// 형식이 아니면 null.
  String? _e164(String input) {
    final d = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (RegExp(r'^\+8210\d{7,8}$').hasMatch(d)) return d;
    if (RegExp(r'^01[016789]\d{7,8}$').hasMatch(d)) return '+82${d.substring(1)}';
    if (RegExp(r'^\+81[789]0\d{8}$').hasMatch(d)) return d;
    if (RegExp(r'^\+810[789]0\d{8}$').hasMatch(d)) return '+81${d.substring(4)}';
    if (RegExp(r'^0[789]0\d{8}$').hasMatch(d)) return '+81${d.substring(1)}';
    return null;
  }

  String get _phoneExample => L10n.isJapanese ? '090-1234-5678' : '010-1234-5678';

  Future<fb.FirebaseAuth> _auth() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    return fb.FirebaseAuth.instance;
  }

  Future<void> _sendCode() async {
    final phone = _e164(_phoneCtl.text);
    if (phone == null) {
      setState(() => _error = context.l10n.authPhoneCheckExample(_phoneExample));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = await _auth();
      await auth.setLanguageCode(L10n.isJapanese ? 'ja' : 'ko');
      await auth.verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: _resendToken,
        timeout: const Duration(seconds: 60),
        // 일부 안드로이드 폰은 문자를 자동으로 읽어 바로 끝난다.
        verificationCompleted: (cred) => _finish(cred),
        verificationFailed: (e) {
          if (!mounted) return;
          debugPrint('[phone] verificationFailed ${e.code} ${e.message}');
          setState(() {
            _busy = false;
            _error = switch (e.code) {
              'invalid-phone-number' => context.l10n.authPhoneCheck,
              'too-many-requests' => context.l10n.authTooManyRequests,
              'quota-exceeded' => context.l10n.authSmsQuotaExceeded,
              _ => context.l10n.authSmsSendFailedCode(e.code),
            };
          });
        },
        codeSent: (id, token) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _verificationId = id;
            _resendToken = token;
          });
        },
        codeAutoRetrievalTimeout: (id) => _verificationId ??= id,
      );
    } catch (e) {
      debugPrint('[phone] send error $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10n.authSmsSendFailed;
      });
    }
  }

  Future<void> _submitCode() async {
    final id = _verificationId;
    final code = _codeCtl.text.trim();
    if (id == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = context.l10n.authSmsCodeInvalid);
      return;
    }
    await _finish(fb.PhoneAuthProvider.credential(verificationId: id, smsCode: code));
  }

  Future<void> _finish(fb.PhoneAuthCredential cred) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final authService = context.read<AuthService>();
    final l10n = context.l10n;
    String? err;
    try {
      final auth = await _auth();
      final res = await auth.signInWithCredential(cred);
      final idToken = await res.user?.getIdToken(true);
      if (idToken == null) {
        err = l10n.authPhoneVerifyFailedRetry;
      } else {
        err = await authService.verifyPhone(idToken);
      }
      await auth.signOut();
    } on fb.FirebaseAuthException catch (e) {
      err = switch (e.code) {
        'invalid-verification-code' => l10n.authSmsCodeWrong,
        'session-expired' => l10n.authSmsCodeExpired,
        _ => l10n.authPhoneVerifyFailedCode(e.code),
      };
    } catch (e) {
      debugPrint('[phone] finish error $e');
      err = l10n.authPhoneVerifyFailedLater;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) widget.onVerified();
  }

  @override
  Widget build(BuildContext context) {
    final codeSent = _verificationId != null;
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
          Text(l10n.authPhoneStepTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            l10n.authPhoneStepDesc,
            style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtl,
            enabled: !codeSent,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\- +]'))],
            decoration: InputDecoration(
              labelText: l10n.authPhoneNumberLabel,
              hintText: _phoneExample,
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          if (!codeSent)
            ElevatedButton(
              onPressed: _busy ? null : _sendCode,
              child: Text(_busy ? l10n.authSending : l10n.authGetCode),
            )
          else ...[
            TextField(
              controller: _codeCtl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofillHints: kIsWeb ? null : const [AutofillHints.oneTimeCode],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 4),
              decoration: InputDecoration(labelText: l10n.authCodeLabel, counterText: ''),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy ? null : _submitCode,
              child: Text(_busy ? l10n.authChecking : l10n.authVerify),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _verificationId = null;
                            _codeCtl.clear();
                          }),
                  child: Text(l10n.authChangeNumber, style: const TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: _busy ? null : _sendCode,
                  child: Text(l10n.authResendCode, style: const TextStyle(fontSize: 12)),
                ),
              ],
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
