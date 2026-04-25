import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// 사용자가 등록한 키워드 알림을 관리한다.
///
/// 서버 동작:
///   - GET    /api/alerts/keywords             → 내 키워드 목록 + max
///   - POST   /api/alerts/keywords             → 추가 (max 5)
///   - DELETE /api/alerts/keywords/:id         → 삭제
///
/// 매칭된 새 상품은 WebSocket(type:'keyword_alert') 으로 실시간 도착하며
/// NotificationService 가 로컬 알림으로 띄운다 (이력은 DB 에 안 남는다).
class KeywordAlertItem {
  final String id;
  final String keyword;
  final DateTime createdAt;

  KeywordAlertItem({
    required this.id,
    required this.keyword,
    required this.createdAt,
  });

  factory KeywordAlertItem.fromJson(Map<String, dynamic> j) {
    return KeywordAlertItem(
      id: j['id']?.toString() ?? '',
      keyword: j['keyword']?.toString() ?? '',
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class KeywordAlertService extends ChangeNotifier {
  final AuthService auth;
  KeywordAlertService(this.auth);

  final List<KeywordAlertItem> _items = [];
  int _max = 5;
  bool _loading = false;
  bool _loaded = false;

  List<KeywordAlertItem> get items => List.unmodifiable(_items);
  int get max => _max;
  bool get loading => _loading;
  bool get loaded => _loaded;
  bool get isFull => _items.length >= _max;

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (_loaded && !force) return;
    _loading = true;
    notifyListeners();
    try {
      final res = await auth.api.get('/api/alerts/keywords');
      final data = res.data;
      if (data is Map<String, dynamic>) {
        _max = (data['max'] as int?) ?? 5;
        final list = (data['keywords'] as List?) ?? [];
        _items
          ..clear()
          ..addAll(list
              .whereType<Map>()
              .map((e) => KeywordAlertItem.fromJson(Map<String, dynamic>.from(e))));
        _loaded = true;
      }
    } catch (e) {
      debugPrint('[alerts] load failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 추가. 성공 시 null, 실패 시 에러 문자열 반환.
  Future<String?> add(String raw) async {
    final keyword = raw.trim();
    if (keyword.length < 2) return '키워드는 2자 이상이어야 해요';
    if (keyword.length > 30) return '키워드는 30자 이하로 입력해주세요';
    if (_items.length >= _max) return '키워드는 최대 $_max개까지 등록할 수 있어요';
    try {
      final res = await auth.api.post('/api/alerts/keywords',
          data: {'keyword': keyword});
      final data = res.data;
      if (data is Map<String, dynamic> && data['keyword'] is Map) {
        _items.insert(
          0,
          KeywordAlertItem.fromJson(Map<String, dynamic>.from(data['keyword'])),
        );
        notifyListeners();
        return null;
      }
      return '등록 실패';
    } catch (e) {
      // dio Error 는 response.data 의 error 메시지를 반환.
      try {
        // ignore: avoid_dynamic_calls
        final msg = (e as dynamic).response?.data?['error']?.toString();
        if (msg != null && msg.isNotEmpty) return msg;
      } catch (_) {}
      return '등록 실패: $e';
    }
  }

  Future<bool> remove(String id) async {
    try {
      await auth.api.delete('/api/alerts/keywords/$id');
      _items.removeWhere((k) => k.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[alerts] delete failed: $e');
      return false;
    }
  }

  void clear() {
    _items.clear();
    _loaded = false;
    notifyListeners();
  }
}
