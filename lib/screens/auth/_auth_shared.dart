import 'package:flutter/material.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';

/// Shared widgets + validators for login / register / find screens.

String? validateWalletAddress(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return L10n.current.authWalletRequired;
  final re = RegExp(r'^0x[a-fA-F0-9]{40}$');
  if (!re.hasMatch(s)) return L10n.current.authWalletFormat;
  return null;
}

String? validateNickname(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return L10n.current.authNicknameRequired;
  if (s.length < 2) return L10n.current.authNicknameTooShort;
  if (s.length > 12) return L10n.current.authNicknameTooLong;
  // 한글·일본어(히라가나·가타카나·한자)·영문·숫자·밑줄만 — 공백/특수문자/이모지 차단
  final re = RegExp(r'^[가-힣ぁ-ゖァ-ヺー一-龯々a-zA-Z0-9_]{2,12}$');
  if (!re.hasMatch(s)) {
    return L10n.current.authNicknameCharset;
  }
  return null;
}

String? validatePassword(String? v) {
  if (v == null || v.isEmpty) return L10n.current.authPasswordRequired;
  if (v.length < 8) return L10n.current.authPasswordTooShort;
  if (v.length > 64) return L10n.current.authPasswordTooLong;
  // 영문 + 숫자 혼합 강제 — "12345678", "aaaaaaaa" 같은 약한 비번 차단
  final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(v);
  final hasDigit = RegExp(r'[0-9]').hasMatch(v);
  if (!hasLetter || !hasDigit) {
    return L10n.current.authPasswordMix;
  }
  return null;
}

class FieldLabel extends StatelessWidget {
  final String text;
  final String? hint;
  const FieldLabel(this.text, {super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: EggplantColors.textSecondary,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Text(
              hint!,
              style: const TextStyle(
                fontSize: 11,
                color: EggplantColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  final String message;
  const ErrorBox({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EggplantColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: EggplantColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: EggplantColors.error,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InfoBox extends StatelessWidget {
  final String message;
  final IconData icon;
  const InfoBox({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EggplantColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: EggplantColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: EggplantColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
