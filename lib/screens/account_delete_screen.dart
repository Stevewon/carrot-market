import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/moderation_service.dart';
import '../services/keyword_alert_service.dart';
import '../services/hidden_products_service.dart';
import '../services/search_history_service.dart';

/// 계정 영구 삭제 (탈퇴) 화면.
/// 정책:
///   1) 비밀번호 재인증
///   2) 계정·게시물·잔여 QTA·친구초대 보너스 전부 즉시 회수/삭제
///   3) 한 번 사라진 데이터는 영구 보관 X
class AccountDeleteScreen extends StatefulWidget {
  const AccountDeleteScreen({super.key});

  @override
  State<AccountDeleteScreen> createState() => _AccountDeleteScreenState();
}

class _AccountDeleteScreenState extends State<AccountDeleteScreen> {
  final _pwCtl = TextEditingController();
  bool _confirmed = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pwCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_confirmed) {
      setState(() => _error = '안내사항을 모두 확인해주세요');
      return;
    }
    if (_pwCtl.text.isEmpty) {
      setState(() => _error = '비밀번호를 입력해주세요');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('정말 탈퇴하시겠어요?'),
        content: const Text(
          '탈퇴 즉시 이 계정의 모든 정보가 사라져요.\n'
          '· 잔여 QTA 잔액\n'
          '· 친구초대로 받은 보너스 (회수)\n'
          '· 게시물·후기·차단 목록\n'
          '· 닉네임은 다른 사람이 사용할 수 있게 됩니다\n\n'
          '복구할 수 없어요.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: EggplantColors.error),
            child: const Text('영구 삭제'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthService>();
    final err = await auth.deleteAccount(password: _pwCtl.text);

    if (!mounted) return;

    if (err != null) {
      setState(() {
        _loading = false;
        _error = err;
      });
      return;
    }

    // 로컬 캐시 비우기
    if (context.mounted) {
      context.read<ProductService>().clearCaches();
      context.read<ModerationService>().clear();
      context.read<KeywordAlertService>().clear();
      context.read<HiddenProductsService>().clear();
      // ignore: unawaited_futures
      context.read<SearchHistoryService>().clear();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('탈퇴가 완료되었어요. 그동안 이용해주셔서 감사합니다.'),
        duration: Duration(seconds: 3),
      ),
    );

    // 온보딩으로 이동 (auth 가 ChangeNotifier 라 라우터가 자동 redirect 도 하지만
    // 안전하게 직접 이동)
    if (context.mounted) context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final nick = auth.user?.nickname ?? '-';
    final qta = auth.user?.qtaBalance ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('계정 영구 삭제')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 경고 카드
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EggplantColors.error.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: EggplantColors.error.withOpacity(0.25)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: EggplantColors.error, size: 22),
                        SizedBox(width: 8),
                        Text(
                          '탈퇴 안내',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: EggplantColors.error,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Text(
                      '한 번 사라진 데이터는 영구 보관하지 않아요.\n'
                      '복구가 불가능합니다.',
                      style: TextStyle(
                        fontSize: 13,
                        color: EggplantColors.textPrimary,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 현재 상태
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: EggplantColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '닉네임: $nick',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined,
                            size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '잔여 QTA: $qta',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              const _RuleRow(
                icon: Icons.delete_outline,
                text: '계정 정보·게시물·후기·차단 목록 즉시 삭제',
              ),
              const _RuleRow(
                icon: Icons.money_off_csred_outlined,
                text: '잔여 QTA 는 즉시 소멸 (출금 신청 후 탈퇴해주세요)',
              ),
              const _RuleRow(
                icon: Icons.card_giftcard_outlined,
                text: '내가 받았던 친구 초대 보너스는 즉시 회수돼요',
              ),
              const _RuleRow(
                icon: Icons.person_off_outlined,
                text: '나를 추천한 친구의 +200 QTA 도 회수돼요',
              ),
              const _RuleRow(
                icon: Icons.refresh,
                text: '닉네임은 다른 사람이 다시 사용할 수 있어요',
              ),
              const _RuleRow(
                icon: Icons.privacy_tip_outlined,
                text: '채팅·통화는 원래도 저장되지 않으므로 자동 정리',
              ),

              const SizedBox(height: 16),
              CheckboxListTile(
                value: _confirmed,
                onChanged: (v) => setState(() => _confirmed = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  '위 안내사항을 모두 확인했고, 영구 삭제에 동의해요',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                activeColor: EggplantColors.error,
              ),

              const SizedBox(height: 12),
              const Text(
                '비밀번호 재확인',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: EggplantColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _pwCtl,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: '비밀번호',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: EggplantColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: EggplantColors.error, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: EggplantColors.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: EggplantColors.error,
                  foregroundColor: Colors.white,
                ),
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
                        child: Text(
                          '계정 영구 삭제',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loading ? null : () => context.pop(),
                child: const Text('취소'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _RuleRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: EggplantColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: EggplantColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
