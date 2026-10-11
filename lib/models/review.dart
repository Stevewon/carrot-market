import '../app/l10n.dart';

/// 거래후기(Transaction review) — written by the seller about the buyer
/// (or vice versa) once a product has been marked as 'sold'.
///
/// Returned by:
///   GET /api/products/:id/review/me
///   GET /api/users/:id/reviews
class Review {
  final String id;
  final String rating; // 'best' | 'good' | 'soso'(예전 데이터) | 'bad'
  /// 매너 항목 코드 ('kind', 'late' …). 예전 데이터는 한국어 자유 입력 문구일 수 있다.
  final List<String> tags;
  final String comment;
  final DateTime createdAt;

  // Optional context — only populated by the per-user list endpoint.
  final String? reviewerId;
  final String? reviewerNickname;
  final String? productId;
  final String? productTitle;

  /// 후기를 쓴 사람이 그 거래에서 'buyer'(구매자) 였는지 'seller'(판매자) 였는지.
  final String? role;

  const Review({
    required this.id,
    required this.rating,
    required this.tags,
    required this.comment,
    required this.createdAt,
    this.reviewerId,
    this.reviewerNickname,
    this.productId,
    this.productTitle,
    this.role,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    final rawTags = (json['tags'] ?? '').toString();
    final tags = rawTags.isEmpty
        ? <String>[]
        : rawTags.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return Review(
      id: json['id']?.toString() ?? '',
      rating: (json['rating'] ?? 'soso').toString(),
      tags: tags,
      comment: (json['comment'] ?? '').toString(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      reviewerId: json['reviewer_id']?.toString(),
      reviewerNickname: json['reviewer_nickname']?.toString(),
      productId: json['product_id']?.toString(),
      productTitle: json['product_title']?.toString(),
      role: json['role']?.toString(),
    );
  }

  /// "최고예요" / "좋아요" / "보통이에요" / "별로예요".
  String get ratingLabel => reviewRatingLabel(L10n.current, rating);

  /// Emoji shortcut, used as a quick visual marker in lists.
  String get ratingEmoji => reviewRatingEmoji(rating);

  /// 역할 라벨 (구매자 / 판매자). 서버가 role 을 안 주면 null.
  String? roleLabel(AppLocalizations l) {
    switch (role) {
      case 'buyer':
        return l.reviewRoleBuyer;
      case 'seller':
        return l.reviewRoleSeller;
      default:
        return null;
    }
  }
}

/// 후기를 쓰는 사람의 역할. buyer = 구매자가 판매자를 평가.
enum ReviewerRole { buyer, seller }

/// 평가 코드 (서버 workers-server/src/reviews.ts 와 같음).
class ReviewRatings {
  static const bad = 'bad';
  static const good = 'good';
  static const best = 'best';
  static const soso = 'soso'; // 예전 데이터 전용
  static bool isPositive(String r) => r != bad;
}

String reviewRatingLabel(AppLocalizations l, String rating) {
  switch (rating) {
    case ReviewRatings.best:
      return l.reviewRatingBest;
    case ReviewRatings.good:
      return l.reviewRatingGood;
    case ReviewRatings.bad:
      return l.reviewRatingBad;
    default:
      return l.reviewRatingSoso;
  }
}

String reviewRatingEmoji(String rating) {
  switch (rating) {
    case ReviewRatings.best:
      return '😍';
    case ReviewRatings.good:
      return '😊';
    case ReviewRatings.bad:
      return '😞';
    default:
      return '😐';
  }
}

/// 매너 항목 목록 — 서버 allowedTags() 와 같은 규칙. 서버가 최종 검사한다.
class ReviewTags {
  static const _posCommon = ['kind', 'punctual', 'fast_reply'];
  static const _posForSeller = ['as_described', 'detailed_desc', 'good_price', 'free_share'];
  static const _posForBuyer = ['paid_on_time', 'no_haggle'];
  static const _negCommon = ['late', 'slow_reply', 'rude'];
  static const _negForSeller = ['not_as_described', 'price_change'];
  static const _negForBuyer = ['haggle'];

  /// [role] 이 [rating] 을 줄 때 고를 수 있는 항목 코드 (화면 순서).
  /// [free] — 0원(무료나눔) 상품일 때만 '무료로 나눠주셨어요'.
  static List<String> forRating(ReviewerRole role, String rating, {bool free = false}) {
    if (rating == ReviewRatings.bad) {
      return role == ReviewerRole.buyer
          ? [..._negCommon, ..._negForSeller, 'no_show']
          : [..._negCommon, ..._negForBuyer, 'no_show'];
    }
    if (role == ReviewerRole.buyer) {
      return [
        ..._posCommon,
        ..._posForSeller.where((t) => t != 'free_share' || free),
      ];
    }
    return [..._posCommon, ..._posForBuyer];
  }

  static const negativeCodes = {
    'late', 'slow_reply', 'rude', 'no_show', 'not_as_described', 'price_change', 'haggle',
  };
}

/// 항목 코드 → 언어별 문구. 모르는 값(예전 자유 입력 태그)은 그대로 보여준다.
String reviewTagLabel(AppLocalizations l, String code) {
  switch (code) {
    case 'kind':
      return l.reviewTagKind;
    case 'punctual':
      return l.reviewTagPunctual;
    case 'fast_reply':
      return l.reviewTagFastReply;
    case 'as_described':
      return l.reviewTagAsDescribed;
    case 'detailed_desc':
      return l.reviewTagDetailedDesc;
    case 'good_price':
      return l.reviewTagGoodPrice;
    case 'free_share':
      return l.reviewTagFreeShare;
    case 'paid_on_time':
      return l.reviewTagPaidOnTime;
    case 'no_haggle':
      return l.reviewTagNoHaggle;
    case 'late':
      return l.reviewTagLate;
    case 'slow_reply':
      return l.reviewTagSlowReply;
    case 'rude':
      return l.reviewTagRude;
    case 'not_as_described':
      return l.reviewTagNotAsDescribed;
    case 'price_change':
      return l.reviewTagPriceChange;
    case 'no_show':
      return l.reviewTagNoShow;
    case 'haggle':
      return l.reviewTagHaggle;
    default:
      return code;
  }
}
