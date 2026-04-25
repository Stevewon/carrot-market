import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Block (차단) + report (신고) operations.
///
/// We keep a local cache of blocked user IDs so the UI can short-circuit
/// (e.g. hide a chat row immediately) without waiting for the next API call.
class ModerationService extends ChangeNotifier {
  final AuthService auth;
  Set<String> _blockedIds = <String>{};
  bool _loaded = false;

  ModerationService(this.auth);

  /// True once the cache has been populated at least once.
  bool get loaded => _loaded;

  /// All users I've blocked.
  Set<String> get blockedIds => _blockedIds;

  bool isBlocked(String userId) => _blockedIds.contains(userId);

  /// Refresh the block cache from the server. Safe to call repeatedly.
  Future<List<Map<String, dynamic>>> fetchBlocks() async {
    try {
      final res = await auth.api.get('/api/moderation/blocks');
      final list = (res.data?['blocks'] as List?) ?? [];
      final maps = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _blockedIds = maps
          .map((m) => m['blocked_id']?.toString())
          .whereType<String>()
          .toSet();
      _loaded = true;
      notifyListeners();
      return maps;
    } catch (e) {
      debugPrint('[moderation] fetchBlocks failed: $e');
      return [];
    }
  }

  /// Block a user. Returns null on success, error message on failure.
  Future<String?> block(String userId) async {
    try {
      await auth.api.post(
        '/api/moderation/block',
        data: {'user_id': userId},
      );
      _blockedIds = {..._blockedIds, userId};
      notifyListeners();
      return null;
    } on DioException catch (e) {
      final msg = (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? '차단 실패')
          : '차단 실패';
      debugPrint('[moderation] block error: $msg');
      return msg;
    } catch (e) {
      debugPrint('[moderation] block error: $e');
      return '차단 실패';
    }
  }

  /// Unblock a user. Returns null on success.
  Future<String?> unblock(String userId) async {
    try {
      await auth.api.delete('/api/moderation/block/$userId');
      _blockedIds = {..._blockedIds}..remove(userId);
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('[moderation] unblock error: $e');
      return '차단 해제 실패';
    }
  }

  /// Report a user. `reason` must be one of:
  ///   spam | fraud | abuse | inappropriate | fake | other
  Future<String?> report({
    required String userId,
    required String reason,
    String? productId,
    String detail = '',
  }) async {
    try {
      await auth.api.post('/api/moderation/report', data: {
        'user_id': userId,
        'reason': reason,
        if (productId != null && productId.isNotEmpty) 'product_id': productId,
        if (detail.trim().isNotEmpty) 'detail': detail.trim(),
      });
      return null;
    } on DioException catch (e) {
      final msg = (e.response?.data is Map)
          ? (e.response!.data['error']?.toString() ?? '신고 접수 실패')
          : '신고 접수 실패';
      debugPrint('[moderation] report error: $msg');
      return msg;
    } catch (e) {
      debugPrint('[moderation] report error: $e');
      return '신고 접수 실패';
    }
  }

  /// Clear cache (called from logout).
  void clear() {
    _blockedIds = <String>{};
    _loaded = false;
    notifyListeners();
  }
}
