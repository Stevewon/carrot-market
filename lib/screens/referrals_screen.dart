import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../services/auth_service.dart';

/// 친구 초대 화면
///
/// - 내 닉네임을 친구에게 알려주는 카드 (복사 버튼)
/// - 보너스 정책 안내 (+200 QTA, 무제한, 탈퇴 시 회수)
/// - 내가 초대한 사람 목록 + 누적 합계
class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _stats = {};
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AuthService>().api;
      final res = await api.dio
          .get('/api/referrals/me')
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (res.statusCode == 200 && res.data is Map) {
        final m = Map<String, dynamic>.from(res.data as Map);
        setState(() {
          _stats = m;
          _items = (m['items'] as List?) ?? [];
        });
      } else {
        setState(() => _error = context.l10n.myRefLoadFail);
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = context.l10n.myServerSlow);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = context.l10n.myRefNetworkError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final myNick = auth.user?.nickname ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.myRefTitle),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 내 닉네임 공유 카드 ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    EggplantColors.primary,
                    Color(0xFFA84DC9),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.card_giftcard, color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.myRefHeadline,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            myNick,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded,
                              color: Colors.white, size: 20),
                          tooltip: context.l10n.myRefCopyNick,
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: myNick));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(context.l10n.myRefNickCopied),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.myRefOncePerPerson,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 통계 요약 ──
            if (!_loading && _error == null)
              Row(
                children: [
                  _StatCard(
                    label: context.l10n.myRefStatValid,
                    value: '${_stats['granted_count'] ?? 0}',
                    color: EggplantColors.primary,
                  ),
                  const SizedBox(width: 8),
                  _StatCard(
                    label: context.l10n.myRefStatEarned,
                    value: '${_stats['total_earned'] ?? 0} QTA',
                    color: const Color(0xFFFF8800),
                  ),
                  const SizedBox(width: 8),
                  _StatCard(
                    label: context.l10n.myRefStatClawed,
                    value: '${_stats['total_clawed_back'] ?? 0} QTA',
                    color: EggplantColors.error,
                  ),
                ],
              ),

            const SizedBox(height: 20),

            // ── 정책 안내 ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: EggplantColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: EggplantColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.myRefRuleTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: EggplantColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.myRefRuleBody,
                    style: const TextStyle(
                      fontSize: 12,
                      color: EggplantColors.textSecondary,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 초대한 친구 목록 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                context.l10n.myRefListTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: EggplantColors.textPrimary,
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: EggplantColors.error),
                  ),
                ),
              )
            else if (_items.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: EggplantColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.group_add_outlined,
                        size: 36, color: EggplantColors.textSecondary),
                    const SizedBox(height: 10),
                    Text(
                      context.l10n.myRefEmpty,
                      style: const TextStyle(
                        color: EggplantColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._items.map((it) => _ReferralTile(item: it)),
            const SizedBox(height: 40),
          ],
        ),
      ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: EggplantColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferralTile extends StatelessWidget {
  final dynamic item;
  const _ReferralTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final m = (item is Map) ? Map<String, dynamic>.from(item as Map) : <String, dynamic>{};
    final status = m['status']?.toString() ?? 'granted';
    final isClawed = status == 'clawed_back';
    final nick = m['referee_nickname']?.toString();
    final createdAt = m['created_at']?.toString();
    DateTime? dt;
    try {
      if (createdAt != null) dt = DateTime.tryParse(createdAt)?.toLocal();
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          Icon(
            isClawed ? Icons.person_off_outlined : Icons.person_outline,
            color: isClawed
                ? EggplantColors.error
                : EggplantColors.primary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isClawed
                      ? (nick ?? context.l10n.myRefDeletedFriend)
                      : (nick ?? context.l10n.myRefUnknown),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dt != null
                      ? DateFormat('yyyy.MM.dd HH:mm').format(dt)
                      : '',
                  style: const TextStyle(
                    fontSize: 11,
                    color: EggplantColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isClawed
                  ? EggplantColors.error.withValues(alpha: 0.12)
                  : EggplantColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isClawed ? context.l10n.myRefClawedBadge : '+200 QTA',
              style: TextStyle(
                color: isClawed
                    ? EggplantColors.error
                    : EggplantColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
