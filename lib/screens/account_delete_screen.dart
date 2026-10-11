import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
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
    final l10n = context.l10n;
    if (!_agreed) {
      setState(() => _error = l10n.authDeleteAgreeRequired);
      return;
    }
    if (_pwCtl.text.isEmpty) {
      setState(() => _error = l10n.authDeletePasswordRequired);
      return;
    }

    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.authDeleteDialogTitle),
        content: Text(
          l10n.authDeleteDialogBody,
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: EggplantColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.authDeleteDialogConfirm),
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
        _error = l10n.authServerSlow;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = l10n.authDeleteFailed;
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
      SnackBar(
        content: Text(l10n.authDeleteDone),
        duration: const Duration(seconds: 3),
      ),
    );
    context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final balance = user?.qtaBalance ?? 0;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.authDeleteTitle)),
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: EggplantColors.error, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.authDeleteWarning,
                        style: const TextStyle(
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
              Text(
                l10n.authDeleteDataTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: EggplantColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              _bullet(l10n.authDeleteBullet1),
              _bullet(l10n.authDeleteBullet2),
              _bullet(l10n.authDeleteBullet3('$balance')),
              _bullet(l10n.authDeleteBullet4),
              _bullet(l10n.authDeleteBullet5),
              _bullet(l10n.authDeleteBullet6),
              _bullet(l10n.authDeleteBullet7),

              const SizedBox(height: 18),

              // 동의 체크
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  l10n.authDeleteAgree,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),

              const SizedBox(height: 8),

              // 비밀번호 재확인
              Text(
                l10n.authDeletePasswordTitle,
                style: const TextStyle(
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
                  hintText: l10n.authPasswordLabel,
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
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          l10n.authDeleteButton,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => context.pop(),
                  child: Text(
                    l10n.authDeleteCancelBack,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: EggplantColors.textSecondary),
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
