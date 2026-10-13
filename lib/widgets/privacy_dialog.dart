import 'package:flutter/material.dart';

import '../app/l10n.dart';
import '../app/theme.dart';

/// 내 정보 → 개인정보 보호 팝업.
///
/// 수집하지 않는 것 / 휴대폰 번호 / 채팅 휘발성 을 항목별 카드로 보여준다.
Future<void> showPrivacyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _PrivacyDialog(),
  );
}

class _PrivacyDialog extends StatelessWidget {
  const _PrivacyDialog();

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: EggplantColors.background,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shield_outlined,
                            color: EggplantColors.primary, size: 24),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t.myPrivacyDialogTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: EggplantColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t.myPrivacyNoCollect,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: EggplantColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: EggplantColors.border),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          _Item(Icons.person_off_outlined, t.myPrivacyItemName, t.myPrivacyItemNameSub),
                          const Divider(height: 1, color: EggplantColors.border),
                          _Item(Icons.location_off_outlined, t.myPrivacyItemGps, t.myPrivacyItemGpsSub),
                          const Divider(height: 1, color: EggplantColors.border),
                          _Item(Icons.speaker_notes_off_outlined, t.myPrivacyItemChat, t.myPrivacyItemChatSub),
                          const Divider(height: 1, color: EggplantColors.border),
                          _Item(Icons.phone_disabled_outlined, t.myPrivacyItemCall, t.myPrivacyItemCallSub),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Box(Icons.lock_outline, t.myPrivacyPhoneTitle, t.myPrivacyPhoneSub),
                    const SizedBox(height: 8),
                    _Box(Icons.auto_delete_outlined, t.myPrivacyVolatileTitle, t.myPrivacyVolatileSub),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EggplantColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(t.commonConfirm,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 수집하지 않는 항목 한 줄.
class _Item extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const _Item(this.icon, this.title, this.sub);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: EggplantColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: EggplantColors.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(
                      fontSize: 12,
                      color: EggplantColors.textSecondary,
                      height: 1.4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 연보라 안내 박스 (휴대폰 번호 · 채팅 휘발성).
class _Box extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const _Box(this.icon, this.title, this.sub);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EggplantColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: EggplantColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: EggplantColors.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(
                      fontSize: 12,
                      color: EggplantColors.textSecondary,
                      height: 1.45,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
