import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/responsive.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/hidden_products_service.dart';
import '../services/keyword_alert_service.dart';
import '../services/moderation_service.dart';
import '../services/product_service.dart';
import '../services/qta_service.dart';
import '../services/search_history_service.dart';

/// 계정 영구 삭제 화면
///
/// "한 번 사라진 건 영구 보관 X" 정책:
///   - 비밀번호 재확인
///   - 친구 초대 보너스 즉시 회수 (탈퇴자 = inviter / referee 둘 다)
///   - users 행 DELETE → CASCADE 로 ledger / referrals / qta_daily_login /
///     hidden_products / keyword_alerts 등 모두 즉시 청소
///   - 클라 메모리/SharedPreferences 도 함께 비움
class AccountDeleteScreen extends StatefulWidget {
  const AccountDeleteScreen({super.key});

  @override
  State<AccountDeleteScreen> createState() => _AccountDeleteScreenState();
}

class _AccountDeleteScreenState extends State<AccountDeleteScreen> {
  final _pwCtl = TextEditingController();
  bool _obscure = true;
  bool _agreed = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pwCtl.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    if (!_agreed) {
      setState(() => _error = '안내 사항에 동의해야 탈퇴할 수 있어요.');
      return;
    }
    if (_pwCtl.text.isEmpty) {
      setState(() => _error = '비밀번호를 입력해주세요.');
      return;
    }

    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('정말 탈퇴할까요?'),
        content: const Text(
          '계정과 모든 데이터가 즉시 영구 삭제돼요.\n'
          '복구는 불가능하며, 잔여 QTA·받은 추천 보너스는 회수돼요.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: EggplantColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('영구 삭제'),
          ),
        ],
      ),
    );
    if (go != true) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthService>();
    String? err;
    try {
      err = await auth
          .deleteAccount(password: _pwCtl.text)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '서버 응답이 늦어요. 잠시 후 다시 시도해주세요 🕐';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '탈퇴 처리 중 문제가 생겼어요. 다시 시도해주세요.';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (err != null) {
      setState(() => _error = err);
      return;
    }

    // 클라이언트 측 캐시 모두 비움 (다른 사용자 자료가 남지 않도록)
    try {
      context.read<ProductService>().clearCaches();
      context.read<ChatService>().disconnect();
      context.read<ModerationService>().clear();
      context.read<KeywordAlertService>().clear();
      context.read<HiddenProductsService>().clear();
      context.read<QtaService>().clear();
      // ignore: unawaited_futures
      context.read<SearchHistoryService>().clear();
    } catch (_) {
      // 일부 Provider 가 트리에서 빠져있어도 무시.
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('탈퇴가 완료되었어요. 이용해주셔서 감사했어요. 🍆'),
        duration: Duration(seconds: 3),
      ),
    );
    context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final balance = user?.qtaBalance ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('계정 영구 삭제')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Responsive.maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // 경고 박스
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EggplantColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: EggplantColors.error.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: EggplantColors.error, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '탈퇴하면 즉시 영구 삭제돼요\n'
                        '한 번 사라진 데이터는 복구되지 않아요.',
                        style: TextStyle(
                          color: EggplantColors.error,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 어떤 데이터가 사라지는지
              const Text(
                '삭제되는 데이터',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: EggplantColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              _bullet('내 닉네임 · 동네 · 매너 점수 · 매너 리뷰'),
              _bullet('내가 등록한 모든 상품'),
              _bullet('잔여 QTA 잔액 ($balance QTA) 폐기'),
              _bullet('받은 친구 초대 보너스는 즉시 회수 (−200 QTA × 인원)'),
              _bullet('내가 추천인이 됐던 친구의 보너스도 즉시 회수'),
              _bullet('숨김/차단/키워드 알림/검색 기록 모두 사라짐'),
              _bullet('채팅 메시지·통화 기록은 원래부터 저장된 게 없어요 🔐'),

              const SizedBox(height: 18),

              // 동의 체크
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  '위 사항을 모두 이해했고, 영구 삭제에 동의해요.',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ),

              const SizedBox(height: 8),

              // 비밀번호 재확인
              const Text(
                '비밀번호 재확인',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
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
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: EggplantColors.primary),
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
                    color: EggplantColors.error.withValues(alpha: 0.08),
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
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: EggplantColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: _loading ? null : _confirmDelete,
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
                          '영구 삭제하기',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text(
                    '취소하고 돌아가기',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: EggplantColors.textSecondary),
                  ),
                ),
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  ',
                style: TextStyle(color: EggplantColors.textSecondary)),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: EggplantColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      );
}
