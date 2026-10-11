import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../models/review.dart';
import '../services/product_service.dart';

/// 서버로 후기를 보낸다. 성공하면 null, 실패하면 보여줄 오류 문구.
typedef ReviewSubmit = Future<String?> Function(
    String rating, List<String> tags, String comment);

/// 거래 후기 시트를 띄운다 (구매자 → 판매자, 판매자 → 구매자 공통).
/// 후기를 보냈으면 true.
Future<bool> showReviewSheet(
  BuildContext context, {
  required String productId,
  required String counterpartNickname,
  required ReviewerRole role,
  bool isFree = false,
}) async {
  final svc = context.read<ProductService>();
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ReviewSheet(
      counterpartNickname: counterpartNickname,
      role: role,
      isFree: isFree,
      onSubmit: (rating, tags, comment) => svc.postReview(
        productId,
        rating: rating,
        tags: tags,
        comment: comment,
      ),
    ),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.reviewPromptDone)),
    );
  }
  return sent == true;
}

/// 당근식 3단계 거래 후기.
///   1) 별로예요 / 좋아요 / 최고예요
///   2) 매너 항목 (평가·역할별, 최소 1개)
///   3) 후기 글 (선택, 300자)
class ReviewSheet extends StatefulWidget {
  final String counterpartNickname;
  final ReviewerRole role;
  final bool isFree;
  final ReviewSubmit onSubmit;

  const ReviewSheet({
    super.key,
    required this.counterpartNickname,
    required this.role,
    required this.onSubmit,
    this.isFree = false,
  });

  static const int commentMax = 300;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  int _step = 0;
  String? _rating;
  final Set<String> _tags = {};
  final _comment = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  bool get _isBad => _rating == ReviewRatings.bad;

  void _pickRating(String r) {
    setState(() {
      // 긍정 ↔ 부정이 바뀌면 고른 항목은 의미가 없어진다.
      if (_rating != null && ReviewRatings.isPositive(_rating!) != ReviewRatings.isPositive(r)) {
        _tags.clear();
      }
      _rating = r;
      _step = 1;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_rating == null || _tags.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final options = ReviewTags.forRating(widget.role, _rating!, free: widget.isFree);
    // 화면 순서대로 보낸다.
    final tags = options.where(_tags.contains).toList();
    final err = await widget.onSubmit(_rating!, tags, _comment.text.trim());
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _sending = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  if (_step > 0)
                    IconButton(
                      key: const Key('review_back'),
                      tooltip: l.reviewBack,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _sending ? null : () => setState(() => _step -= 1),
                    ),
                  const Spacer(),
                  Text(
                    '${_step + 1}/3',
                    style: const TextStyle(fontSize: 12, color: EggplantColors.textTertiary),
                  ),
                ],
              ),
              if (_step == 0) _buildRatingStep(l),
              if (_step == 1) _buildTagsStep(l),
              if (_step == 2) _buildCommentStep(l),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('review_error'),
                  style: const TextStyle(color: EggplantColors.error, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatingStep(AppLocalizations l) {
    Widget option(String rating, String emoji, String label) {
      final selected = _rating == rating;
      return Expanded(
        child: InkWell(
          key: Key('review_rating_$rating'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => _pickRating(rating),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: selected ? EggplantColors.background : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? EggplantColors.primary : EggplantColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 34)),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? EggplantColors.primaryDark : EggplantColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.reviewQuestion(widget.counterpartNickname),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          l.reviewQuestionSub,
          style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            option(ReviewRatings.bad, reviewRatingEmoji(ReviewRatings.bad), l.reviewRatingBad),
            const SizedBox(width: 10),
            option(ReviewRatings.good, reviewRatingEmoji(ReviewRatings.good), l.reviewRatingGood),
            const SizedBox(width: 10),
            option(ReviewRatings.best, reviewRatingEmoji(ReviewRatings.best), l.reviewRatingBest),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTagsStep(AppLocalizations l) {
    final options = ReviewTags.forRating(widget.role, _rating!, free: widget.isFree);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isBad ? l.reviewTagsTitleBad : l.reviewTagsTitleGood,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          l.reviewTagsSub,
          style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary),
        ),
        if (_isBad) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline, size: 16, color: EggplantColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.reviewBadPrivateNotice,
                    style: const TextStyle(fontSize: 12, color: EggplantColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        for (final code in options)
          CheckboxListTile(
            key: Key('review_tag_$code'),
            value: _tags.contains(code),
            onChanged: (v) => setState(() {
              if (v == true) {
                _tags.add(code);
              } else {
                _tags.remove(code);
              }
            }),
            title: Text(reviewTagLabel(l, code), style: const TextStyle(fontSize: 14.5)),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: EggplantColors.primary,
          ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            key: const Key('review_next'),
            onPressed: _tags.isEmpty ? null : () => setState(() => _step = 2),
            child: Text(l.reviewNext),
          ),
        ),
      ],
    );
  }

  Widget _buildCommentStep(AppLocalizations l) {
    final canSubmit = _rating != null && _tags.isNotEmpty && !_sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isBad ? l.reviewCommentTitleBad : l.reviewCommentTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          _isBad
              ? l.reviewCommentOptionalBad
              : l.reviewCommentOptional(widget.counterpartNickname),
          style: const TextStyle(fontSize: 13, color: EggplantColors.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('review_comment'),
          controller: _comment,
          maxLines: 5,
          minLines: 3,
          maxLength: ReviewSheet.commentMax,
          decoration: InputDecoration(
            hintText: _isBad
                ? l.reviewCommentHintBad
                : l.reviewCommentHint(widget.counterpartNickname),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            key: const Key('review_submit'),
            onPressed: canSubmit ? _submit : null,
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(l.reviewSubmit),
          ),
        ),
      ],
    );
  }
}

/// 내가 보낸 후기를 보여주는 간단한 시트.
Future<void> showMyReviewSheet(
  BuildContext context, {
  required Review review,
  required String counterpartNickname,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final l = ctx.l10n;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.reviewSentTo(counterpartNickname),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(reviewRatingEmoji(review.rating), style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Text(
                    reviewRatingLabel(l, review.rating),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (review.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in review.tags)
                      Chip(
                        label: Text(reviewTagLabel(l, t), style: const TextStyle(fontSize: 12.5)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: EggplantColors.background,
                        side: BorderSide.none,
                      ),
                  ],
                ),
              ],
              if (review.comment.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(review.comment, style: const TextStyle(fontSize: 14, height: 1.5)),
              ],
            ],
          ),
        ),
      );
    },
  );
}
