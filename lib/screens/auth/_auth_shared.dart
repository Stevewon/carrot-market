import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Shared widgets + validators for login / register / find screens.

String? validateWalletAddress(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return '지갑주소를 입력해주세요';
  final re = RegExp(r'^0x[a-fA-F0-9]{40}$');
  if (!re.hasMatch(s)) return '0x로 시작하는 42자리 형식이어야 해요';
  return null;
}

String? validateNickname(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return '닉네임을 입력해주세요';
  if (s.length < 2) return '닉네임은 2자 이상이어야 해요';
  if (s.length > 12) return '닉네임은 12자 이하여야 해요';
  // 한글/영문/숫자/밑줄만 허용 — 공백/특수문자/이모지 차단
  final re = RegExp(r'^[가-힣a-zA-Z0-9_]{2,12}$');
  if (!re.hasMatch(s)) {
    return '한글·영문·숫자·_ 만 사용 가능해요 (공백·특수문자 금지)';
  }
  return null;
}

String? validatePassword(String? v) {
  if (v == null || v.isEmpty) return '비밀번호를 입력해주세요';
  if (v.length < 8) return '비밀번호는 8자 이상이어야 해요';
  if (v.length > 64) return '비밀번호는 64자 이하여야 해요';
  // 영문 + 숫자 혼합 강제 — "12345678", "aaaaaaaa" 같은 약한 비번 차단
  final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(v);
  final hasDigit = RegExp(r'[0-9]').hasMatch(v);
  if (!hasLetter || !hasDigit) {
    return '영문과 숫자를 모두 포함해야 해요';
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
