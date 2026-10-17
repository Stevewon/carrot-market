import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/product.dart';
import 'auth_service.dart';

/// 최근 본 상품 (당근식) — 이 폰에만 저장, 서버로 보내지 않는다. 최대 30개.
class RecentViewedService extends ChangeNotifier {
  RecentViewedService(this.auth);

  final AuthService auth;
  static const int maxItems = 30;

  String get _key => 'recent_viewed_v1_${auth.user?.id ?? ''}';

  List<Map<String, dynamic>> _raw() {
    try {
      final s = auth.prefs.getString(_key);
      if (s == null) return [];
      return [for (final e in jsonDecode(s) as List) Map<String, dynamic>.from(e as Map)];
    } catch (_) {
      return [];
    }
  }

  List<Product> get items {
    final out = <Product>[];
    for (final m in _raw()) {
      try {
        out.add(Product.fromJson(m));
      } catch (_) {}
    }
    return out;
  }

  /// 상품 상세를 열 때 — 맨 앞으로 (이미 있으면 옮긴다). 목록에 필요한 것만 저장.
  Future<void> add(Product p) async {
    final snap = <String, dynamic>{
      'id': p.id,
      'title': p.title,
      'price': p.price,
      'qta_price': p.qtaPrice,
      'category': p.category,
      'region': p.region,
      'market': p.market,
      'images': p.images.take(1).toList(),
      'video_url': p.videoUrl,
      'seller_id': p.sellerId,
      'seller_nickname': p.sellerNickname,
      'status': p.status,
      'like_count': p.likeCount,
      'chat_count': p.chatCount,
      'created_at': p.createdAt.toUtc().toIso8601String(),
      if (p.bumpedAt != null) 'bumped_at': p.bumpedAt!.toUtc().toIso8601String(),
    };
    final list = [snap, ..._raw().where((m) => m['id']?.toString() != p.id)];
    await _save(list.take(maxItems).toList());
  }

  Future<void> remove(String id) => _save(_raw().where((m) => m['id']?.toString() != id).toList());

  Future<void> clear() => _save(const []);

  Future<void> _save(List<Map<String, dynamic>> list) async {
    try {
      // SharedPreferences 는 메모리에 먼저 반영 → 저장이 끝나기 전에 화면을 바꿔도 된다
      // (밀어서 지운 줄이 바로 빠져야 한다).
      final saving = list.isEmpty ? auth.prefs.remove(_key) : auth.prefs.setString(_key, jsonEncode(list));
      notifyListeners();
      await saving;
    } catch (e) {
      debugPrint('[recent] save failed: $e');
      notifyListeners();
    }
  }
}
