import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/user.dart';
import 'api_client.dart';

/// Anonymous authentication service.
/// Users log in with nickname + device UUID only.
/// No phone / email required.
class AuthService extends ChangeNotifier {
  static const _kToken = 'auth_token';
  static const _kNickname = 'nickname';
  static const _kUserId = 'user_id';
  static const _kDeviceUuid = 'device_uuid';
  static const _kRegion = 'region';
  static const _kMannerScore = 'manner_score';

  final SharedPreferences prefs;
  final ApiClient api = ApiClient();

  String? _token;
  User? _user;

  AuthService(this.prefs);

  User? get user => _user;
  String? get token => _token;
  bool get isLoggedIn => _token != null && _user != null;

  Future<void> loadFromStorage() async {
    _token = prefs.getString(_kToken);
    final userId = prefs.getString(_kUserId);
    final nickname = prefs.getString(_kNickname);
    final deviceUuid = prefs.getString(_kDeviceUuid);

    if (_token != null && userId != null && nickname != null && deviceUuid != null) {
      _user = User(
        id: userId,
        nickname: nickname,
        deviceUuid: deviceUuid,
        region: prefs.getString(_kRegion),
        mannerScore: prefs.getInt(_kMannerScore) ?? 36,
        createdAt: DateTime.now(),
      );
      api.setToken(_token);
    }
    notifyListeners();
  }

  /// Register a new anonymous user with just a nickname.
  /// Device UUID is auto-generated and persisted.
  Future<String?> register({
    required String nickname,
    String? region,
  }) async {
    try {
      String deviceUuid = prefs.getString(_kDeviceUuid) ?? const Uuid().v4();

      final res = await api.post('/api/auth/register', data: {
        'nickname': nickname.trim(),
        'device_uuid': deviceUuid,
        'region': region,
      });

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = res.data as Map<String, dynamic>;
        await _saveSession(
          token: data['token'] as String,
          user: User.fromJson(data['user'] as Map<String, dynamic>),
        );
        return null; // success
      }
      return (res.data is Map) ? (res.data['error']?.toString() ?? '가입 실패') : '가입 실패';
    } catch (e) {
      return _parseError(e);
    }
  }

  /// Login with existing device UUID (auto-login).
  Future<String?> loginWithDevice() async {
    final deviceUuid = prefs.getString(_kDeviceUuid);
    if (deviceUuid == null) return '기기 정보가 없어요';

    try {
      final res = await api.post('/api/auth/login', data: {
        'device_uuid': deviceUuid,
      });

      if (res.statusCode == 200) {
        final data = res.data as Map<String, dynamic>;
        await _saveSession(
          token: data['token'] as String,
          user: User.fromJson(data['user'] as Map<String, dynamic>),
        );
        return null;
      }
      return '로그인 실패';
    } catch (e) {
      return _parseError(e);
    }
  }

  Future<void> updateRegion(String region) async {
    if (_user == null) return;
    try {
      await api.put('/api/users/me', data: {'region': region});
    } catch (_) {}
    _user = User(
      id: _user!.id,
      nickname: _user!.nickname,
      deviceUuid: _user!.deviceUuid,
      region: region,
      mannerScore: _user!.mannerScore,
      createdAt: _user!.createdAt,
    );
    await prefs.setString(_kRegion, region);
    notifyListeners();
  }

  Future<void> _saveSession({required String token, required User user}) async {
    _token = token;
    _user = user;
    api.setToken(token);

    await prefs.setString(_kToken, token);
    await prefs.setString(_kUserId, user.id);
    await prefs.setString(_kNickname, user.nickname);
    await prefs.setString(_kDeviceUuid, user.deviceUuid);
    if (user.region != null) await prefs.setString(_kRegion, user.region!);
    await prefs.setInt(_kMannerScore, user.mannerScore);

    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    api.setToken(null);
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kNickname);
    // Keep device_uuid and region for re-login convenience
    notifyListeners();
  }

  String _parseError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return '서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요.';
    }
    if (msg.contains('timeout')) {
      return '응답 시간이 초과되었어요.';
    }
    return '오류가 발생했어요: $msg';
  }
}
