import 'package:flutter/material.dart';

import '../app/l10n.dart';
import '../app/theme.dart';

/// 거래 금지 품목 안내 (당근식 운영정책).
///
/// 실제 판정은 서버(workers-server/src/prohibited.ts)가 한다 — 이 화면은 안내용.
/// 일본어 문구는 서버 PROHIBITED_GUIDE 의 labelJa/examplesJa 를 따른다.
class ProhibitedItemsScreen extends StatelessWidget {
  const ProhibitedItemsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProhibitedItemsScreen()),
    );
  }

  static List<(String, String, String)> _items(AppLocalizations t) => [
        ('💊', t.productBanMedicine, t.productBanMedicineEx),
        ('🚫', t.productBanDrugs, t.productBanDrugsEx),
        ('🍺', t.productBanAlcohol, t.productBanAlcoholEx),
        ('🚬', t.productBanTobacco, t.productBanTobaccoEx),
        ('🔫', t.productBanWeapons, t.productBanWeaponsEx),
        ('🔞', t.productBanAdult, t.productBanAdultEx),
        ('🪪', t.productBanAccounts, t.productBanAccountsEx),
        ('💸', t.productBanCashing, t.productBanCashingEx),
        ('🐶', t.productBanAnimals, t.productBanAnimalsEx),
        ('👜', t.productBanCounterfeit, t.productBanCounterfeitEx),
        ('🕵️', t.productBanStolen, t.productBanStolenEx),
        ('🩸', t.productBanBodily, t.productBanBodilyEx),
        ('🎖️', t.productBanMilitary, t.productBanMilitaryEx),
        ('📷', t.productBanSpycam, t.productBanSpycamEx),
        ('💻', t.productBanHacking, t.productBanHackingEx),
        ('🎫', t.productBanScalping, t.productBanScalpingEx),
        ('🗑️', t.productBanWasteBags, t.productBanWasteBagsEx),
      ];

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(t.productProhibitedGuide)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: EggplantColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EggplantColors.border),
            ),
            child: Text(
              t.productBanIntro,
              style: const TextStyle(fontSize: 13, height: 1.5, color: EggplantColors.textPrimary),
            ),
          ),
          const SizedBox(height: 12),
          for (final (emoji, title, desc) in _items(t))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Text(emoji, style: const TextStyle(fontSize: 24)),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: Text(desc, style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary)),
            ),
          const Divider(height: 32),
          Text(t.productBanInfoTitle,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          Text(
            t.productBanInfoBody,
            style: const TextStyle(fontSize: 13, height: 1.6, color: EggplantColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 서버의 운영정책 거절 메시지인지 (거래 금지 품목 / 외부 연락처 / 욕설).
/// 서버는 일본어 사용자에게 일본어 메시지를 보내므로 양쪽 표현을 모두 본다.
bool isPolicyRejection(String err) =>
    err.contains('거래 금지 품목') ||
    err.contains('외부 연락처') ||
    err.contains('욕설·비속어') ||
    err.contains('出品禁止物') ||
    err.contains('連絡先は投稿に記載できません') ||
    err.contains('暴言・不適切な表現');

/// 상품 등록/수정 오류 표시 — 정책 위반이면 안내 다이얼로그, 아니면 SnackBar.
void showProductError(BuildContext context, String err) {
  if (!isPolicyRejection(err)) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    return;
  }
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.productPolicyRejectedTitle),
      content: Text(err, style: const TextStyle(height: 1.5)),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            ProhibitedItemsScreen.open(context);
          },
          child: Text(ctx.l10n.productViewProhibited),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(ctx.l10n.commonConfirm),
        ),
      ],
    ),
  );
}
