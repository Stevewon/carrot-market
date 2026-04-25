import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Lightweight client for the /api/moderation/* endpoints.
///
/// Block:
///   • blockUser   — add the user to my block list (server-enforced both ways)
///   • unblockUser — undo
///   • myBlocks    — list of users I've blocked
///
/// Report:
///   • reportUser  — submit a report with a reason + optional product/detail
///
/// Reasons accepted by the server (must match migration 0009 CHECK):
///   spam | fraud | abuse | inappropriate | fake | other
class ModerationService extends ChangeNotifier {
  final AuthService auth;

  /// Local cache of blocked user IDs — kept in sync with the server so feed
  /// filters don't have to round-trip every render.
  final Set<String> _blockedIds = <String>{};
  bool _blocksLoaded = false;

  ModerationService(this.auth);

  Set<String> get blockedIds => _blockedIds;
  bool get blocksLoaded => _blocksLoaded;

  bool isBlocked(String userId) => _blockedIds.contains(userId);

  // ── Block / Unblock ────────────────────────────────────────────────

  /// Block a user. Returns null on success, error string on failure.
  Future<String?> blockUser(String userId) async {
    try {
      final res = await auth.api.post(
        '/api/moderation/block',
        data: {'user_id': userId},
      );
      if (res.statusCode == 200) {
        _blockedIds.add(userId);
        notifyListeners();
        return null;
      }
      return _err(res.data) ?? '차단 실패';
    } on DioException catch (e) {
      debugPrint('blockUser error: ${e.response?.data ?? e.message}');
      return _err(e.response?.data) ?? '차단 실패';
    } catch (e) {
      debugPrint('blockUser error: $e');
      return '차단 실패';
    }
  }

  Future<String?> unblockUser(String userId) async {
    try {
      final res = await auth.api.delete('/api/moderation/block/$userId');
      if (res.statusCode == 200) {
        _blockedIds.remove(userId);
        notifyListeners();
        return null;
      }
      return _err(res.data) ?? '차단 해제 실패';
    } on DioException catch (e) {
      debugPrint('unblockUser error: ${e.response?.data ?? e.message}');
      return _err(e.response?.data) ?? '차단 해제 실패';
    } catch (e) {
      debugPrint('unblockUser error: $e');
      return '차단 해제 실패';
    }
  }

  /// Pull the full block list from the server. Each entry includes the
  /// blocked user's nickname/region/manner_score for display.
  Future<List<Map<String, dynamic>>> fetchBlocks() async {
    try {
      final res = await auth.api.get('/api/moderation/blocks');
      final list = (res.data?['blocks'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _blockedIds
        ..clear()
        ..addAll(list.map((e) => e['blocked_id']?.toString() ?? ''));
      _blockedIds.remove('');
      _blocksLoaded = true;
      notifyListeners();
      return list;
    } catch (e) {
      debugPrint('fetchBlocks error: $e');
      return [];
    }
  }

  // ── Report ─────────────────────────────────────────────────────────

  /// Submit a user report. [reason] must be one of:
  ///   spam | fraud | abuse | inappropriate | fake | other
  /// Returns null on success, error string on failure.
  Future<String?> reportUser({
    required String userId,
    required String reason,
    String? productId,
    String detail = '',
  }) async {
    try {
      final res = await auth.api.post(
        '/api/moderation/report',
        data: {
          'user_id': userId,
          'reason': reason,
          if (productId != null && productId.isNotEmpty) 'product_id': productId,
          if (detail.isNotEmpty) 'detail': detail,
        },
      );
      return res.statusCode == 200 ? null : (_err(res.data) ?? '신고 접수 실패');
    } on DioException catch (e) {
      debugPrint('reportUser error: ${e.response?.data ?? e.message}');
      return _err(e.response?.data) ?? '신고 접수 실패';
    } catch (e) {
      debugPrint('reportUser error: $e');
      return '신고 접수 실패';
    }
  }

  /// Reset cached block list when the user logs out.
  void clear() {
    _blockedIds.clear();
    _blocksLoaded = false;
    notifyListeners();
  }

  String? _err(dynamic data) {
    if (data is Map && data['error'] != null) return data['error'].toString();
    return null;
  }
}
