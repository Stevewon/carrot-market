import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only recent search history (당근식 최근 검색어).
///
/// Anonymous market: we never sync this to the server, never tie it to a
/// wallet/user id. Lives only in SharedPreferences on this device. When the
/// user logs out we wipe it (call `clear()` from AuthService.logout flow).
class SearchHistoryService extends ChangeNotifier {
  static const _key = 'search_history_v1';
  static const int _maxItems = 10;

  final SharedPreferences _prefs;
  List<String> _terms = const [];

  SearchHistoryService(this._prefs) {
    _terms = _prefs.getStringList(_key) ?? const [];
  }

  List<String> get terms => List.unmodifiable(_terms);

  /// Adds a new search term to the front. De-dupes (case-insensitive) and
  /// caps at [_maxItems]. Empty / whitespace-only terms are ignored.
  Future<void> add(String raw) async {
    final term = raw.trim();
    if (term.isEmpty) return;

    final lower = term.toLowerCase();
    final next = <String>[term];
    for (final t in _terms) {
      if (t.toLowerCase() == lower) continue;
      next.add(t);
      if (next.length >= _maxItems) break;
    }
    _terms = next;
    await _prefs.setStringList(_key, _terms);
    notifyListeners();
  }

  /// Removes one term.
  Future<void> remove(String term) async {
    final next = _terms.where((t) => t != term).toList();
    if (next.length == _terms.length) return;
    _terms = next;
    await _prefs.setStringList(_key, _terms);
    notifyListeners();
  }

  /// Clears all stored terms (called on logout).
  Future<void> clear() async {
    if (_terms.isEmpty) return;
    _terms = const [];
    await _prefs.remove(_key);
    notifyListeners();
  }
}
