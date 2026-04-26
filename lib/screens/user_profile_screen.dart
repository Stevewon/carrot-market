import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/responsive.dart';
import '../app/theme.dart';
import '../models/review.dart';
import '../services/auth_service.dart';
import '../services/moderation_service.dart';
import '../services/product_service.dart';

/// Public profile of any user — opens when you tap the seller row on a
/// product detail, or a reviewer name on the profile.
///
/// Shows:
///   • Nickname, region, manner_score (당근식 매너온도)
///   • Aggregate review counts (좋아요 / 보통 / 별로)
///   • Top tags (most common feedback)
///   • Reviews list (paginated)
class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _stats;
  List<Review> _reviews = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = context.read<ProductService>();
      final results = await Future.wait([
        svc.fetchUserProfile(widget.userId),
        svc.fetchUserReviews(widget.userId, limit: 20),
      ]);
      final profile = results[0] as Map<String, dynamic>?;
      final reviews = (results[1] as List).cast<Review>();
      if (!mounted) return;
      if (profile == null) {
        setState(() {
          _loading = false;
          _error = '사용자를 찾을 수 없어요';
        });
        return;
      }
      setState(() {
        _profile = profile['profile'] as Map<String, dynamic>?;
        _stats = profile['stats'] as Map<String, dynamic>?;
        _reviews = reviews;
        _hasMore = reviews.length >= 20;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '불러오는 중 오류가 발생했어요';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _reviews.isEmpty) return;
    setState(() => _loadingMore = true);
    final more = await context.read<ProductService>().fetchUserReviews(
          widget.userId,
          limit: 20,
          before: _reviews.last.createdAt,
        );
    if (!mounted) return;
    setState(() {
      _reviews.addAll(more);
      _hasMore = more.length >= 20;
      _loadingMore = false;
    });
  }

  /// Pull the top 3 tags out of the loaded reviews — quick client-side
  /// aggregation since the dataset on this screen is already small.
  List<MapEntry<String, int>> get _topTags {
    final counts = <String, int>{};
    for (final r in _reviews) {
      for (final t in r.tags) {
        if (t.isEmpty) continue;
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final list = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(3).toList();
  }

  Future<void> _confirmBlock() async {
    final nick = _profile?['nickname']?.toString() ?? '이 사용자';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('차단할까요?'),
        content: Text(
          '$nick님을 차단하면 서로의 게시글과 채팅이 모두 안 보이게 돼요. 언제든 해제할 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '차단',
              style: TextStyle(color: EggplantColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final mod = context.read<ModerationService>();
    final err = await mod.blockUser(widget.userId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$nick님을 차단했어요')),
    );
    if (context.canPop()) context.pop();
  }

  Future<void> _confirmUnblock() async {
    final nick = _profile?['nickname']?.toString() ?? '이 사용자';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('차단 해제할까요?'),
        content: Text('$nick님을 다시 볼 수 있게 돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('해제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<ModerationService>().unblockUser(widget.userId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('차단을 해제했어요')),
    );
  }

  Future<void> _showReportSheet() async {
    final reasons = const <(String, String, String)>[
      ('spam', '🚫', '스팸·광고'),
      ('fraud', '💸', '사기 의심'),
      ('abuse', '😠', '욕설·비방'),
      ('inappropriate', '🔞', '부적절한 내용'),
      ('fake', '🎭', '허위 매물'),
      ('other', '📝', '기타'),
    ];
    String? selected;
    final detailCtl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    '신고 사유를 골라주세요',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '여러 명이 같은 사유로 신고하면 운영팀이 검토해요.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: EggplantColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final (code, emoji, label) in reasons)
                    RadioListTile<String>(
                      value: code,
                      groupValue: selected,
                      title: Text('$emoji  $label'),
                      activeColor: EggplantColors.primary,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onChanged: (v) => setSt(() => selected = v),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detailCtl,
                    maxLines: 2,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      hintText: '추가 설명 (선택)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: selected == null
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              final err = await context
                                  .read<ModerationService>()
                                  .reportUser(
                                    userId: widget.userId,
                                    reason: selected!,
                                    detail: detailCtl.text,
                                  );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(err ?? '신고를 접수했어요'),
                                ),
                              );
                            },
                      child: const Text('신고하기'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    detailCtl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.watch<AuthService>().user?.id;
    final isMe = myId != null && myId == widget.userId;
    final isBlocked = context.watch<ModerationService>().isBlocked(widget.userId);

    return Scaffold(
      appBar: AppBar(
        title: Text(isMe ? '내 프로필' : '판매자 정보'),
        elevation: 0,
        actions: [
          if (!isMe)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                switch (v) {
                  case 'block':
                    _confirmBlock();
                    break;
                  case 'unblock':
                    _confirmUnblock();
                    break;
                  case 'report':
                    _showReportSheet();
                    break;
                }
              },
              itemBuilder: (_) => [
                if (isBlocked)
                  const PopupMenuItem(
                    value: 'unblock',
                    child: Text('차단 해제'),
                  )
                else
                  const PopupMenuItem(
                    value: 'block',
                    child: Text('차단하기'),
                  ),
                const PopupMenuItem(
                  value: 'report',
                  child: Text('신고하기'),
                ),
              ],
            ),
        ],
      ),
      // 태블릿/폴드 펼침에서 프로필 본문이 600dp 로 가운데 정렬.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.maxFeedWidth),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: _loadAll,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                            _loadMore();
                          }
                          return false;
                        },
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          children: [
                        _Header(profile: _profile!, stats: _stats!),
                        const SizedBox(height: 16),
                        _StatsBreakdown(stats: _stats!),
                        if (_topTags.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Text(
                            '많이 받은 매너 칭찬',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final e in _topTags)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: EggplantColors.primaryLight
                                        .withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${e.key} · ${e.value}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: EggplantColors.primaryDark,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Text(
                              '받은 거래 후기',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_stats?['total'] ?? 0}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: EggplantColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_reviews.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                '아직 받은 후기가 없어요',
                                style: TextStyle(
                                  color: EggplantColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                        else
                          for (final r in _reviews) _ReviewCard(review: r),
                        if (_loadingMore)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child:
                                Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Map<String, dynamic> profile;
  final Map<String, dynamic> stats;
  const _Header({required this.profile, required this.stats});

  double get _temperature {
    final raw = profile['manner_score'];
    final v = (raw is num) ? raw.toInt() : int.tryParse('$raw') ?? 365;
    final scaled = v < 100 ? v * 10 : v;
    return scaled / 10.0;
  }

  Color get _temperatureColor {
    final t = _temperature;
    if (t >= 50) return const Color(0xFFE74C3C);
    if (t >= 40) return const Color(0xFFFF8C42);
    if (t >= 36.5) return EggplantColors.primary;
    if (t >= 30) return const Color(0xFF6B7280);
    return const Color(0xFF9CA3AF);
  }

  @override
  Widget build(BuildContext context) {
    final selling = stats['selling'] ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EggplantColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EggplantColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: EggplantColors.primaryLight, width: 2),
                ),
                child: ClipOval(
                  child: Image.asset('assets/images/eggplant-mascot.png'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile['nickname']?.toString() ?? '익명가지',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (profile['region']?.toString() ?? '').isEmpty
                          ? '동네 미설정'
                          : profile['region'].toString(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: EggplantColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCell(
                  label: '매너온도',
                  value: '${_temperature.toStringAsFixed(1)}°C',
                  valueColor: _temperatureColor,
                ),
              ),
              Container(
                  width: 1, height: 32, color: EggplantColors.border),
              Expanded(
                child: _StatCell(
                  label: '받은 후기',
                  value: '${stats['total'] ?? 0}',
                ),
              ),
              Container(
                  width: 1, height: 32, color: EggplantColors.border),
              Expanded(
                child: _StatCell(
                  label: '판매중',
                  value: '$selling',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _StatCell({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: valueColor ?? EggplantColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: EggplantColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _StatsBreakdown extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsBreakdown({required this.stats});

  int _intOf(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final good = _intOf(stats['good']);
    final soso = _intOf(stats['soso']);
    final bad = _intOf(stats['bad']);
    final total = good + soso + bad;
    if (total == 0) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Expanded(
          child: _RatingBar(
            emoji: '😊',
            label: '좋아요',
            count: good,
            total: total,
            color: EggplantColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RatingBar(
            emoji: '😐',
            label: '보통이에요',
            count: soso,
            total: total,
            color: const Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RatingBar(
            emoji: '😣',
            label: '별로예요',
            count: bad,
            total: total,
            color: const Color(0xFFE74C3C),
          ),
        ),
      ],
    );
  }
}

class _RatingBar extends StatelessWidget {
  final String emoji;
  final String label;
  final int count;
  final int total;
  final Color color;
  const _RatingBar({
    required this.emoji,
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EggplantColors.border),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: EggplantColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: EggplantColors.background,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Review review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EggplantColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(review.ratingEmoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.reviewerNickname ?? '익명가지',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    if (review.productTitle != null &&
                        review.productTitle!.isNotEmpty)
                      Text(
                        review.productTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: EggplantColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                _shortAgo(review.createdAt),
                style: const TextStyle(
                  fontSize: 11,
                  color: EggplantColors.textTertiary,
                ),
              ),
            ],
          ),
          if (review.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in review.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: EggplantColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontSize: 12,
                        color: EggplantColors.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              review.comment,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _shortAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}분 전';
    if (d.inHours < 24) return '${d.inHours}시간 전';
    if (d.inDays < 7) return '${d.inDays}일 전';
    if (d.inDays < 30) return '${(d.inDays / 7).floor()}주 전';
    return '${(d.inDays / 30).floor()}개월 전';
  }
}
