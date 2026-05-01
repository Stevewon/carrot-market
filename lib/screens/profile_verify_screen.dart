import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/responsive.dart';
import '../app/theme.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

/// 프로필 인증 단계 화면.
///
/// 정책:
///   Lv0 (none)         : 익명, 둘러보기·채팅·통화·상품등록 가능. 결제·출금 불가.
///   Lv1 (identity)     : 본인인증 완료. KRW/QTA 결제 가능. QTA 출금 불가.
///   Lv2 (bankAccount)  : 계좌 등록 완료. QTA → KRW 출금 가능.
///
/// 본 화면은 현재 더미(UI only)다.
/// 실제 본인인증 SDK(PASS/SMS) 연동은 추후 작업이며,
/// 서버에는 본인인증 토큰(CI)의 SHA-256 해시만 저장한다(전화번호 자체는 저장 X).
class ProfileVerifyScreen extends StatelessWidget {
  const ProfileVerifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final lv = user.verificationLevel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('프로필 인증'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _CurrentLevelCard(level: lv),
              const SizedBox(height: 24),
              const _SectionTitle('인증 단계'),
              const SizedBox(height: 8),
              _StepCard(
                step: 0,
                title: '익명 가입',
                description: '닉네임·지갑주소·비밀번호로 가입하면 자동 완료.\n'
                    '둘러보기 · 채팅 · 통화 · 상품 등록 가능.',
                achieved: true,
                actionLabel: null,
                onAction: null,
              ),
              const SizedBox(height: 12),
              _StepCard(
                step: 1,
                title: '본인 인증',
                description: '실명 휴대폰 본인인증을 통해 1인 1계정을 보장.\n'
                    'KRW · QTA 결제, 상품 구매가 활성화돼요.\n\n'
                    '⚠️ 휴대폰 번호 자체는 저장하지 않으며, '
                    '본인인증 토큰(CI)의 SHA-256 해시만 저장됩니다.',
                achieved: lv.value >= 1,
                actionLabel: lv.value >= 1 ? '완료됨' : '본인 인증 시작',
                onAction: lv.value >= 1
                    ? null
                    : () => _showDummyDialog(
                          context,
                          title: '본인 인증',
                          message:
                              '실서비스에서는 PASS / SMS 본인인증 SDK가 호출됩니다.\n'
                              '현재는 더미 화면이라 인증 단계가 변경되지 않아요.',
                        ),
              ),
              const SizedBox(height: 12),
              _StepCard(
                step: 2,
                title: '계좌 등록 (출금)',
                description: 'QTA → KRW 출금을 위해 본인 명의 계좌를 등록.\n'
                    '5,000 QTA 단위로 출금 가능 (최소 5,000).\n\n'
                    '⚠️ 계좌번호 자체는 저장하지 않고 (은행+계좌)의 '
                    'SHA-256 해시만 저장합니다.',
                achieved: lv.value >= 2,
                actionLabel: lv.value >= 2
                    ? '완료됨'
                    : (lv.value >= 1 ? '계좌 등록' : '본인 인증 후 가능'),
                onAction: (lv.value >= 1 && lv.value < 2)
                    ? () => _showDummyDialog(
                          context,
                          title: '계좌 등록',
                          message: '실서비스에서는 1원 인증 절차가 진행됩니다.\n'
                              '현재는 더미 화면입니다.',
                        )
                    : null,
              ),
              const SizedBox(height: 28),
              const _SectionTitle('익명성 정책'),
              const SizedBox(height: 8),
              _PolicyBox(
                icon: Icons.chat_bubble_outline,
                text: '채팅 / 음성통화는 인증 단계와 무관하게 항상 닉네임만 노출됩니다.',
              ),
              const SizedBox(height: 8),
              _PolicyBox(
                icon: Icons.lock_outline,
                text: '본인인증 정보는 거래 자격 확인 용도로만 쓰이며, '
                    '거래 상대방·다른 사용자에게 절대 노출되지 않습니다.',
              ),
              const SizedBox(height: 8),
              _PolicyBox(
                icon: Icons.shield_moon_outlined,
                text: '같은 사람이 여러 계정으로 인증을 통과할 수 없도록 '
                    'CI 해시에 UNIQUE 제약이 걸립니다.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDummyDialog(BuildContext context,
      {required String title, required String message}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

class _CurrentLevelCard extends StatelessWidget {
  final VerificationLevel level;
  const _CurrentLevelCard({required this.level});

  @override
  Widget build(BuildContext context) {
    final color = level.value == 0
        ? const Color(0xFF9CA3AF)
        : level.value == 1
            ? const Color(0xFF22C55E)
            : EggplantColors.primary;
    final icon = level.value == 0
        ? Icons.person_outline
        : level.value == 1
            ? Icons.verified_user_outlined
            : Icons.account_balance_outlined;
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
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('현재 단계: Lv${level.value}',
                    style: const TextStyle(
                        fontSize: 13, color: EggplantColors.textSecondary)),
                const SizedBox(height: 4),
                Text(level.label,
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
                  child: Text('완료',
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
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      onAction == null ? const Color(0xFFE5E7EB) : accent,
                  foregroundColor:
                      onAction == null ? const Color(0xFF9CA3AF) : Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(actionLabel!,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
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
  final title = customTitle ??
      (needIdentity ? '본인 인증이 필요해요' : '계좌 등록이 필요해요');
  final message = customMessage ??
      (needIdentity
          ? '거래(결제)는 1인 1계정 보장을 위해 본인 인증이 필수입니다.\n'
              '인증해도 채팅·통화는 익명 그대로 유지돼요.'
          : 'QTA 출금을 위해 본인 명의 계좌 등록이 필요합니다.\n'
              '본인 인증이 먼저 완료돼야 해요.');

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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('취소',
                          style: TextStyle(
                              color: EggplantColors.textSecondary,
                              fontWeight: FontWeight.w600)),
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('인증하러 가기',
                          style: TextStyle(fontWeight: FontWeight.w700)),
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
