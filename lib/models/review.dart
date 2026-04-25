/// 거래후기(Transaction review) — written by the seller about the buyer
/// (or vice versa) once a product has been marked as 'sold'.
///
/// Returned by:
///   GET /api/products/:id/review/me
///   GET /api/users/:id/reviews
class Review {
  final String id;
  final String rating; // 'good' | 'soso' | 'bad'
  final List<String> tags;
  final String comment;
  final DateTime createdAt;

  // Optional context — only populated by the per-user list endpoint.
  final String? reviewerId;
  final String? reviewerNickname;
  final String? productId;
  final String? productTitle;

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
    );
  }

  /// Korean label for the rating ("좋아요", "보통이에요", "별로예요").
  String get ratingLabel {
    switch (rating) {
      case 'good':
        return '좋아요';
      case 'bad':
        return '별로예요';
      default:
        return '보통이에요';
    }
  }

  /// Emoji shortcut, used as a quick visual marker in lists.
  String get ratingEmoji {
    switch (rating) {
      case 'good':
        return '😊';
      case 'bad':
        return '😣';
      default:
        return '😐';
    }
  }
}
