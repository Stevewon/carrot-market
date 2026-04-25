import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// 사용자가 "이 게시물 가리기" 한 product id 를 캐시한다.
///
/// 서버 API:
///   - GET    /api/hidden            → { hidden: [productId, ...] }
///   - POST   /api/hidden/:productId → { ok }
///   - DELETE /api/hidden/:productId → { ok }
///
/// 서버는 피드(GET /api/products) 결과에서 자동으로 숨김 항목을 제외하므로
/// 클라이언트 캐시는 (a) 즉시 UI 반영(낙관적 갱신) (b) "숨긴 목록" 화면용으로만 쓴다.
class HiddenProductsService extends ChangeNotifier {
  final AuthService auth;
  HiddenProductsService(this.auth);

  final Set<String> _ids = {};
  bool _loaded = false;
  bool _loading = false;

  bool isHidden(String productId) => _ids.contains(productId);
  Set<String> get ids => Set.unmodifiable(_ids);
  bool get loaded => _loaded;
  bool get loading => _loading;

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (_loaded && !force) return;
    _loading = true;
    notifyListeners();
    try {
      final res = await auth.api.get('/api/hidden');
      final data = res.data;
      if (data is Map<String, dynamic>) {
        final list = (data['hidden'] as List?) ?? [];
        _ids
          ..clear()
          ..addAll(list.map((e) => e.toString()));
        _loaded = true;
      }
    } catch (e) {
      debugPrint('[hidden] load failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 게시물 숨기기. 즉시 로컬 set 에 추가하고 서버에 호출.
  Future<bool> hide(String productId) async {
    if (_ids.contains(productId)) return true;
    _ids.add(productId);
    notifyListeners();
    try {
      await auth.api.post('/api/hidden/$productId');
      return true;
    } catch (e) {
      debugPrint('[hidden] hide failed: $e');
      // 실패 시 롤백.
      _ids.remove(productId);
      notifyListeners();
      return false;
    }
  }

  /// 숨김 해제.
  Future<bool> unhide(String productId) async {
    if (!_ids.contains(productId)) return true;
    _ids.remove(productId);
    notifyListeners();
    try {
      await auth.api.delete('/api/hidden/$productId');
      return true;
    } catch (e) {
      debugPrint('[hidden] unhide failed: $e');
      _ids.add(productId);
      notifyListeners();
      return false;
    }
  }

  void clear() {
    _ids.clear();
    _loaded = false;
    notifyListeners();
  }
}
