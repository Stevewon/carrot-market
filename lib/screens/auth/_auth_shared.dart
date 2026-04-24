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
  if (s.length < 2) return '닉네임은 2자 이상이어야 해요';
  if (s.length > 12) return '닉네임은 12자 이하여야 해요';
  return null;
}

String? validatePassword(String? v) {
  if (v == null || v.isEmpty) return '비밀번호를 입력해주세요';
  if (v.length < 8) return '비밀번호는 8자 이상이어야 해요';
  if (v.length > 64) return '비밀번호는 64자 이하여야 해요';
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
