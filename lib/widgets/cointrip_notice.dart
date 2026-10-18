import 'package:flutter/material.dart';

import '../app/l10n.dart';

/// "지갑 주소를 잘못 넣어 잘못 지급된 코인은 회원 본인 책임" — 반드시 빨간 글씨로 (사장님 지시).
/// 지갑 주소 입력 · 출금 신청 · 코인트립 첫 안내에 띄운다.
class WalletResponsibilityNotice extends StatelessWidget {
  const WalletResponsibilityNotice({super.key});

  static const Color red = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: red.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.ctRedNotice,
              style: const TextStyle(color: red, fontSize: 14, fontWeight: FontWeight.w800, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 빨간 안내 + "위 내용을 확인했습니다" 체크.
class WalletResponsibilityAck extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const WalletResponsibilityAck({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WalletResponsibilityNotice(),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Checkbox(
                  value: value,
                  activeColor: WalletResponsibilityNotice.red,
                  onChanged: (v) => onChanged(v ?? false),
                ),
                Expanded(
                  child: Text(
                    context.l10n.ctAckCheck,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
