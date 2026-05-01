class Product {
  final String id;
  final String title;
  final String description;
  final int price;
  /// QTA 거래 가격 (정수). 0 = KRW 거래(기본). >0 이면 거래완료 시
  /// 자동 buyer→seller 잔액 이체.
  final int qtaPrice;
  final String category;
  final String region;
  final List<String> images;
  final String videoUrl; // '' | https://youtu.be/<id> | /uploads/<key>.mp4
  final String sellerId;
  final String sellerNickname;
  /// 판매자의 퀀타리움 지갑주소 (Universal User ID, SSO 식별자).
  /// 상품 상세에 마스킹된 형태로만 노출. 서버는 이 값을 옵션으로 내려줄 수 있음.
  final String? sellerWalletAddress;
  /// ×10 scale (e.g. 365 = 36.5°). See [User.mannerScore].
  final int sellerMannerScore;
  final String status; // 'sale', 'reserved', 'sold'
  final int viewCount;
  final int likeCount;
  final int chatCount;
  final bool isLiked;
  final DateTime createdAt;
  /// Last "끌어올리기" timestamp. NULL = never bumped.
  /// Used to compute the "방금 끌어올림" hint and the 24h cooldown.
  final DateTime? bumpedAt;
  /// Set by the server when the seller marks the listing as 'sold'
  /// and picks a buyer (used for the 거래후기 flow).
  final String? buyerId;

  Product({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.qtaPrice = 0,
    required this.category,
    required this.region,
    required this.images,
    this.videoUrl = '',
    required this.sellerId,
    required this.sellerNickname,
    this.sellerWalletAddress,
    this.sellerMannerScore = 365,
    this.status = 'sale',
    this.viewCount = 0,
    this.likeCount = 0,
    this.chatCount = 0,
    this.isLiked = false,
    required this.createdAt,
    this.bumpedAt,
    this.buyerId,
  });

  /// Display-friendly seller temperature, e.g. `36.5`.
  double get sellerMannerTemperature => sellerMannerScore / 10.0;
  String get sellerMannerLabel =>
      '${sellerMannerTemperature.toStringAsFixed(1)}°';

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
      qtaPrice: (json['qta_price'] is num)
          ? (json['qta_price'] as num).toInt()
          : int.tryParse(json['qta_price']?.toString() ?? '0') ?? 0,
      category: json['category'] ?? 'etc',
      region: json['region'] ?? '',
      images: parsedImages,
      videoUrl: (json['video_url'] ?? '').toString(),
      sellerId: json['seller_id']?.toString() ?? '',
      sellerNickname: json['seller_nickname'] ?? '익명가지',
      sellerWalletAddress: (json['seller_wallet_address']?.toString().isNotEmpty == true)
          ? json['seller_wallet_address'].toString()
          : null,
      sellerMannerScore: _parseMannerScore(json['seller_manner_score']),
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
      bumpedAt: json['bumped_at'] != null
          ? DateTime.tryParse(json['bumped_at'].toString())
          : null,
      buyerId: (json['buyer_id'] ?? '').toString().isEmpty
          ? null
          : json['buyer_id'].toString(),
    );
  }

  /// Coerces seller_manner_score from any of the legacy formats:
  ///   • null            → 365
  ///   • int 0..99       → ×10 upgrade (e.g. 36 → 365)
  ///   • int >= 100      → already on the new scale
  ///   • num (double)    → toInt() with the same rules
  static int _parseMannerScore(dynamic raw) {
    if (raw == null) return 365;
    int v;
    if (raw is int) v = raw;
    else if (raw is num) v = raw.toInt();
    else v = int.tryParse(raw.toString()) ?? 365;
    if (v > 0 && v < 100) v *= 10;
    return v;
  }

  /// Effective "shown timestamp" for sorting / display — most recent of
  /// (bumpedAt, createdAt). Mirrors the server's COALESCE in the feed query.
  DateTime get effectiveAt => bumpedAt ?? createdAt;

  /// Whether 24h has elapsed since the last bump (or it was never bumped),
  /// i.e. whether the seller can press "끌어올리기" right now.
  bool get canBump {
    if (bumpedAt == null) return true;
    return DateTime.now().difference(bumpedAt!).inHours >= 24;
  }

  /// Time until the next bump is allowed. Duration.zero if available now.
  Duration get bumpCooldownRemaining {
    if (bumpedAt == null) return Duration.zero;
    final next = bumpedAt!.add(const Duration(hours: 24));
    final remaining = next.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// QTA 거래 가능 여부 (qta_price > 0).
  bool get hasQtaPrice => qtaPrice > 0;

  String get qtaPriceFormatted {
    if (qtaPrice <= 0) return '';
    return '${_formatThousands(qtaPrice)} QTA';
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

  /// Human-readable freshness — uses [effectiveAt] so a bumped product reads
  /// as "방금 전" right after the seller끌어올림 (matches 당근).
  String get timeAgo {
    final diff = DateTime.now().difference(effectiveAt);
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

  /// 판매자 지갑주소(SSO Universal User ID) 의 마스킹 표기.
  /// 정책: 앞 6자 + … + 뒤 4자만 노출. 길이가 너무 짧으면 전체 마스킹.
  /// 예: 0xA1B2c3D4e5F6...d3F1
  String? get sellerWalletMasked {
    final w = sellerWalletAddress;
    if (w == null || w.isEmpty) return null;
    if (w.length <= 12) return '${w.substring(0, 2)}…${w.substring(w.length - 2)}';
    return '${w.substring(0, 6)}…${w.substring(w.length - 4)}';
  }
}
