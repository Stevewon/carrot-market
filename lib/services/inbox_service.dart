import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// 알림함 한 줄.
class InboxItem {
  final String id;

  /// keyword_alert | price_drop | purchase_confirm | review_request | review_received
  final String type;
  final String title;
  final String body;
  final String? productId;
  final String? targetUserId;
  final String? thumb;
  final DateTime createdAt;
  final bool read;

  /// true 면 이 폰에만 있는 알림 (키워드 알림 — 서버에 남기지 않는다).
  final bool local;

  const InboxItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.productId,
    this.targetUserId,
    this.thumb,
    this.read = false,
    this.local = false,
  });

  factory InboxItem.fromJson(Map<String, dynamic> j, {bool local = false}) {
    String? s(Object? v) => (v == null || v.toString().isEmpty) ? null : v.toString();
    // 서버 datetime('now') 는 'YYYY-MM-DD HH:MM:SS' (UTC, 시간대 표시 없음).
    final raw = (j['created_at'] ?? '').toString();
    final at = DateTime.tryParse(raw.contains('T') ? raw : '${raw.replaceFirst(' ', 'T')}Z');
    return InboxItem(
      id: j['id'].toString(),
      type: (j['type'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      productId: s(j['product_id']),
      targetUserId: s(j['target_user_id']),
      thumb: s(j['thumb']),
      createdAt: (at ?? DateTime.now()).toLocal(),
      read: j['read'] == true || s(j['read_at']) != null,
      local: local,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'body': body,
        'product_id': productId,
        'thumb': thumb,
        'created_at': createdAt.toUtc().toIso8601String(),
        'read': read,
      };

  InboxItem asRead() => InboxItem(
        id: id,
        type: type,
        title: title,
        body: body,
        productId: productId,
        targetUserId: targetUserId,
        thumb: thumb,
        createdAt: createdAt,
        read: true,
        local: local,
      );
}

/// 알림함 (당근식) — 가격 내림·거래 확인·후기 알림은 서버에서 (30일 보관),
/// 키워드 알림은 사생활 보호로 이 폰에만 저장해서 한 목록으로 합쳐 보여준다.
class InboxService extends ChangeNotifier {
  InboxService(this.auth) {
    pings.addListener(_onPing);
  }

  final AuthService auth;

  /// 새 알림이 왔을 수 있을 때 (푸시 받음 · 앱 복귀) 아무 데서나 [ping] → 안 읽은 수 다시 확인.
  static final ValueNotifier<int> pings = ValueNotifier(0);
  static void ping() => pings.value++;

  static const int _maxLocal = 50;
  static const Duration _keep = Duration(days: 30);

  String get _localKey => 'inbox_local_v1_${auth.user?.id ?? ''}';

  List<InboxItem> _server = const [];
  int _serverUnread = 0;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  List<InboxItem> _localItems() {
    try {
      final raw = auth.prefs.getString(_localKey);
      if (raw == null) return const [];
      final cut = DateTime.now().subtract(_keep);
      return [
        for (final e in jsonDecode(raw) as List)
          InboxItem.fromJson(Map<String, dynamic>.from(e as Map), local: true),
      ].where((i) => i.createdAt.isAfter(cut)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveLocal(List<InboxItem> items) async {
    try {
      await auth.prefs.setString(_localKey, jsonEncode([for (final i in items.take(_maxLocal)) i.toJson()]));
    } catch (_) {}
  }

  /// 서버 + 이 폰 알림을 최신순으로.
  List<InboxItem> get items {
    final all = [..._server, ..._localItems()];
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  int get unread => _serverUnread + _localItems().where((i) => !i.read).length;

  void _onPing() {
    // ignore: discarded_futures
    refreshUnread();
  }

  /// 저장소만 쓰는 임시 객체 (ping 구독 없이).
  InboxService._peek(this.auth);

  /// 키워드 알림을 이 폰의 알림함에 넣는다. Provider 가 없는 곳(ChatService)에서도 부를 수 있게 static.
  static Future<void> recordLocal(
    AuthService auth, {
    required String type,
    required String title,
    required String body,
    String? productId,
    String? thumb,
  }) async {
    final box = InboxService._peek(auth);
    final list = box._localItems();
    // 같은 상품의 같은 알림이 두 번 오면 하나만.
    if (productId != null && list.any((i) => i.type == type && i.productId == productId)) return;
    final item = InboxItem(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      title: title,
      body: body,
      productId: productId,
      thumb: thumb,
      createdAt: DateTime.now(),
      local: true,
    );
    await box._saveLocal([item, ...list]);
    ping();
  }

  Future<void> refreshUnread() async {
    if (!auth.isLoggedIn) return;
    try {
      final res = await auth.api.get('/api/notifications/unread');
      final n = (res.data is Map) ? (res.data['unread'] as num?)?.toInt() : null;
      if (n != null && n != _serverUnread) {
        _serverUnread = n;
      }
    } catch (e) {
      debugPrint('[inbox] unread failed: $e');
    }
    notifyListeners();
  }

  Future<void> load() async {
    if (!auth.isLoggedIn) return;
    _loading = true;
    notifyListeners();
    try {
      final res = await auth.api.get('/api/notifications');
      final list = (res.data is Map ? res.data['notifications'] as List? : null) ?? const [];
      _server = [for (final e in list) InboxItem.fromJson(Map<String, dynamic>.from(e as Map))];
      _serverUnread = (res.data['unread'] as num?)?.toInt() ?? 0;
      _error = null;
      _loaded = true;
    } catch (e) {
      debugPrint('[inbox] load failed: $e');
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 알림함을 열면 모두 읽음으로.
  Future<void> markAllRead() async {
    await _saveLocal([for (final i in _localItems()) i.asRead()]);
    if (_serverUnread > 0) {
      try {
        await auth.api.post('/api/notifications/read-all');
        _serverUnread = 0;
      } catch (e) {
        debugPrint('[inbox] read-all failed: $e');
      }
    }
    notifyListeners();
  }

  Future<void> remove(InboxItem item) async {
    if (item.local) {
      // 밀어서 지운 줄은 바로 목록에서 빠져야 한다 (SharedPreferences 는 메모리에 먼저 반영된다).
      final saving = _saveLocal(_localItems().where((i) => i.id != item.id).toList());
      notifyListeners();
      await saving;
    } else {
      _server = _server.where((i) => i.id != item.id).toList();
      notifyListeners();
      try {
        await auth.api.delete('/api/notifications/${item.id}');
      } catch (e) {
        debugPrint('[inbox] delete failed: $e');
      }
    }
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _saveLocal(const []);
    _server = const [];
    _serverUnread = 0;
    notifyListeners();
    try {
      await auth.api.delete('/api/notifications');
    } catch (e) {
      debugPrint('[inbox] clear failed: $e');
    }
  }

  bool _disposed = false;

  /// 화면이 닫힌 뒤 늦게 끝난 요청(안 읽은 수 새로고침 등)이 알리지 않게.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    pings.removeListener(_onPing);
    super.dispose();
  }
}
