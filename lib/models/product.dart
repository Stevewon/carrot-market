class Product {
  final String id;
  final String title;
  final String description;
  final int price;
  final String category;
  final String region;
  final List<String> images;
  final String videoUrl; // '' | https://youtu.be/<id> | /uploads/<key>.mp4
  final String sellerId;
  final String sellerNickname;
  final int sellerMannerScore;
  final String status; // 'sale', 'reserved', 'sold'
  final int viewCount;
  final int likeCount;
  final int chatCount;
  final bool isLiked;
  final DateTime createdAt;

  Product({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.category,
    required this.region,
    required this.images,
    this.videoUrl = '',
    required this.sellerId,
    required this.sellerNickname,
    this.sellerMannerScore = 36,
    this.status = 'sale',
    this.viewCount = 0,
    this.likeCount = 0,
    this.chatCount = 0,
    this.isLiked = false,
    required this.createdAt,
  });

  /// True if [videoUrl] points to a YouTube video (not an uploaded file).
  bool get isYouTubeVideo =>
      videoUrl.contains('youtu.be/') || videoUrl.contains('youtube.com/');

  /// Extract YouTube video id from [videoUrl] (returns '' if not a YT url).
  String get youTubeId {
    if (!isYouTubeVideo) return '';
    final re = RegExp(
      r'(?:youtu\.be/|youtube\.com/(?:watch\?v=|shorts/|embed/))([A-Za-z0-9_-]{6,20})',
    );
    final m = re.firstMatch(videoUrl);
    return m?.group(1) ?? '';
  }

  bool get hasVideo => videoUrl.isNotEmpty;

  factory Product.fromJson(Map<String, dynamic> json) {
    List<String> parsedImages = [];
    final img = json['images'];
    if (img is List) {
      parsedImages = img.map((e) => e.toString()).toList();
    } else if (img is String && img.isNotEmpty) {
      // comma-separated
      parsedImages = img.split(',').where((s) => s.trim().isNotEmpty).toList();
    }

    return Product(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      price: (json['price'] is num)
          ? (json['price'] as num).toInt()
          : int.tryParse(json['price']?.toString() ?? '0') ?? 0,
      category: json['category'] ?? 'etc',
      region: json['region'] ?? '',
      images: parsedImages,
      videoUrl: (json['video_url'] ?? '').toString(),
      sellerId: json['seller_id']?.toString() ?? '',
      sellerNickname: json['seller_nickname'] ?? '익명가지',
      sellerMannerScore: (json['seller_manner_score'] ?? 36) is int
          ? json['seller_manner_score'] ?? 36
          : (json['seller_manner_score'] as num).toInt(),
      status: json['status'] ?? 'sale',
      viewCount: (json['view_count'] ?? 0) is int
          ? json['view_count'] ?? 0
          : (json['view_count'] as num).toInt(),
      likeCount: (json['like_count'] ?? 0) is int
          ? json['like_count'] ?? 0
          : (json['like_count'] as num).toInt(),
      chatCount: (json['chat_count'] ?? 0) is int
          ? json['chat_count'] ?? 0
          : (json['chat_count'] as num).toInt(),
      isLiked: json['is_liked'] == true || json['is_liked'] == 1,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  String get priceFormatted {
    if (price == 0) return '나눔';
    return '${_formatThousands(price)}원';
  }

  static String _formatThousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 30) return '${diff.inDays}일 전';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}개월 전';
    return '${(diff.inDays / 365).floor()}년 전';
  }

  String get statusLabel {
    switch (status) {
      case 'reserved':
        return '예약중';
      case 'sold':
        return '거래완료';
      default:
        return '';
    }
  }
}
