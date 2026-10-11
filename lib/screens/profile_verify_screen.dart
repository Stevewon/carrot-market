import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/constants.dart';
import '../app/l10n.dart';
import '../app/responsive.dart';
import '../app/theme.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import 'auth/phone_verify_card.dart';
import 'auth/wallet_receive_card.dart';

/// 프로필 인증 단계 화면.
///
/// 정책:
///   가입              : 닉네임·비밀번호만. 둘러보기·채팅·통화·상품등록 가능.
///   1단계 지갑 인증    : 본사 지갑이 보낸 소수점 6자리 수량을 입력 → 지갑 등록.
///   2단계 휴대폰 인증  : 문자 인증 (1인 1계정). 1단계를 먼저 마쳐야 한다.
///   1·2단계 완료      : +1,000 QTA, QTA 결제 거래·출금 가능.
///
/// 서버에는 전화번호를 저장하지 않고 해시만 남긴다.
class ProfileVerifyScreen extends StatelessWidget {
  const ProfileVerifyScreen({super.key});

  static const int verifyBonus = 1000;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final walletDone = user.isWalletVerified;
    final phoneDone = user.isIdentityVerified;

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.authProfileVerifyTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Responsive.maxContentWidth),
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 40),
              children: [
                _ProgressCard(walletDone: walletDone, phoneDone: phoneDone),
                const SizedBox(height: 24),
                _SectionTitle(l10n.authProfileStepsTitle),
                const SizedBox(height: 8),
                _StepCard(
                  step: 0,
                  title: l10n.authProfileStep0Title,
                  description: l10n.authProfileStep0Desc,
                  achieved: true,
                  actionLabel: null,
                  onAction: null,
                ),
                const SizedBox(height: 12),
                _StepCard(
                  step: 1,
                  title: l10n.authWalletVerifyTitle,
                  description: l10n.authProfileStep1Desc,
                  achieved: walletDone,
                  actionLabel: walletDone ? l10n.authProfileDoneLabel : l10n.authWalletVerifyStart,
                  onAction: walletDone
                      ? null
                      : () => _showSheet(
                            context,
                            (close) => WalletReceiveCard(
                              initialWallet: user.walletAddress ?? '',
                              onVerified: () => _done(context, close, l10n.authProfileWalletDoneSnack),
                            ),
                          ),
                ),
                const SizedBox(height: 12),
                _StepCard(
                  step: 2,
                  title: l10n.authProfileStep2Title,
                  description: l10n.authProfileStep2Desc +
                      (walletDone ? '' : '\n\n${l10n.authProfileWalletFirst}'),
                  achieved: phoneDone,
                  actionLabel: phoneDone
                      ? l10n.authProfileDoneLabel
                      : !AppConfig.identityVerificationEnabled
                          ? l10n.authProfileComingSoon
                          : (walletDone ? l10n.authProfilePhoneStart : l10n.authProfileStep1First),
                  onAction: phoneDone || !walletDone || !AppConfig.identityVerificationEnabled
                      ? null
                      : () => _showSheet(
                            context,
                            (close) => PhoneVerifyCard(
                              onVerified: () => _done(context, close, l10n.authProfilePhoneDoneSnack),
                            ),
                          ),
                ),
                const SizedBox(height: 12),
                _BonusBox(done: walletDone && phoneDone),
                const SizedBox(height: 28),
                _SectionTitle(l10n.authProfilePolicyTitle),
                const SizedBox(height: 8),
                _PolicyBox(
                  icon: Icons.chat_bubble_outline,
                  text: l10n.authProfilePolicy1,
                ),
                const SizedBox(height: 8),
                _PolicyBox(
                  icon: Icons.lock_outline,
                  text: l10n.authProfilePolicy2,
                ),
                const SizedBox(height: 8),
                _PolicyBox(
                  icon: Icons.shield_moon_outlined,
                  text: l10n.authProfilePolicy3,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 인증 카드를 아래 시트로 띄운다. builder 에는 시트를 닫는 함수가 넘어간다.
  void _showSheet(BuildContext context, Widget Function(VoidCallback close) builder) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: builder(() => Navigator.of(ctx).pop()),
          ),
        ),
      ),
    );
  }

  void _done(BuildContext context, VoidCallback close, String message) {
    close();
    final auth = context.read<AuthService>();
    final bonus = auth.lastVerifyBonus;
    auth.lastVerifyBonus = 0;
    if (bonus > 0) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.authProfileBonusDialogTitle),
          content: Text(ctx.l10n.authProfileBonusDialogBody('$bonus')),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.l10n.commonConfirm)),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _ProgressCard extends StatelessWidget {
  final bool walletDone;
  final bool phoneDone;
  const _ProgressCard({required this.walletDone, required this.phoneDone});

  @override
  Widget build(BuildContext context) {
    final all = walletDone && phoneDone;
    final color = all
        ? EggplantColors.primary
        : walletDone
            ? const Color(0xFF22C55E)
            : const Color(0xFF9CA3AF);
    final l10n = context.l10n;
    final label = all
        ? l10n.authProfileAllDone
        : walletDone
            ? l10n.authProfileStep1Done
            : l10n.authProfileUnverified;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(all ? Icons.verified_user_outlined : Icons.person_outline, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.authProfileProgress('${(walletDone ? 1 : 0) + (phoneDone ? 1 : 0)}'),
                    style: const TextStyle(
                        fontSize: 13, color: EggplantColors.textSecondary)),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BonusBox extends StatelessWidget {
  final bool done;
  const _BonusBox({required this.done});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Text('🎁', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              done
                  ? context.l10n.authProfileBonusReceived('${ProfileVerifyScreen.verifyBonus}')
                  : context.l10n.authProfileBonusPending('${ProfileVerifyScreen.verifyBonus}'),
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: EggplantColors.textPrimary));
  }
}

class _StepCard extends StatelessWidget {
  final int step;
  final String title;
  final String description;
  final bool achieved;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StepCard({
    required this.step,
    required this.title,
    required this.description,
    required this.achieved,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final accent = achieved ? const Color(0xFF22C55E) : EggplantColors.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: achieved
                    ? Icon(Icons.check, color: accent, size: 18)
                    : Text('$step',
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              if (achieved)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(context.l10n.authProfileDoneBadge,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accent)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(description,
              style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: EggplantColors.textSecondary)),
          if (actionLabel != null) ...[
            const SizedBox(height: 14),
            // ⚠️ height:44 고정 → 폰트 스케일 1.3x 이상에서 글자 잘림 보고 받음.
            //    minimumSize 로 바꿔 텍스트가 박스를 넘으면 박스가 같이 늘어나게 함.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      onAction == null ? const Color(0xFFE5E7EB) : accent,
                  foregroundColor:
                      onAction == null ? const Color(0xFF9CA3AF) : Colors.white,
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  actionLabel!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14, height: 1.2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PolicyBox extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PolicyBox({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF5FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEDE9FE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: EggplantColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: EggplantColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// 결제·출금 가드 모달.
///
/// 인증 단계 부족으로 작업을 차단할 때 호출한다.
/// 사용자가 "인증하러 가기" 버튼을 누르면 `/profile/verify` 로 이동.
Future<void> showVerificationGuard(
  BuildContext context, {
  required VerificationLevel current,
  required VerificationLevel required,
  String? customTitle,
  String? customMessage,
}) async {
  final needIdentity = required == VerificationLevel.identity;
  final l10n = context.l10n;
  final title = customTitle ??
      (needIdentity ? l10n.authGuardPhoneTitle : l10n.authGuardWalletTitle);
  final message = customMessage ??
      (needIdentity ? l10n.authGuardPhoneMessage : l10n.authGuardWalletMessage);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    constraints:
        const BoxConstraints(maxWidth: Responsive.maxContentWidth),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: EggplantColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_user_outlined,
                      color: EggplantColors.primary, size: 28),
                ),
              ),
              const SizedBox(height: 14),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: EggplantColors.textSecondary)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        l10n.commonCancel,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: EggplantColors.textSecondary,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        context.push('/profile/verify');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EggplantColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        l10n.authGuardGoVerify,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
