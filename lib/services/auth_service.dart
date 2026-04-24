import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/user.dart';
import 'api_client.dart';

/// Wallet-based authentication service.
///
/// Users sign up / log in with:
///   - Quantarium wallet address  (0x + 40 hex chars) — their permanent ID
///   - nickname                    — must be unique
///   - password                    — hashed on server (PBKDF2)
///
/// Forgot nickname/password?  Prove wallet ownership to recover.
///
/// "Someone else logging in and staying logged in" is prevented by the server:
///   - A new device login bumps `token_version` — old device's JWT is dead
///     on its next request.
///   - Password reset bumps `token_version` too.
class AuthService extends ChangeNotifier {
  static const _kToken = 'auth_token';
  static const _kUserId = 'user_id';
  static const _kNickname = 'nickname';
  static const _kDeviceUuid = 'device_uuid';
  static const _kWallet = 'wallet_address';
  static const _kRegion = 'region';
  static const _kMannerScore = 'manner_score';

  final SharedPreferences prefs;
  final ApiClient api = ApiClient();

  String? _token;
  User? _user;

  AuthService(this.prefs) {
    // Whenever the API returns 401 with a "revoked" signal, we log out
    // locally so the app falls back to onboarding automatically.
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) async {
          final code = e.response?.statusCode;
          if (code == 401 && _token != null) {
            final data = e.response?.data;
            final errCode = (data is Map) ? data['code']?.toString() : null;
            if (errCode == 'token_revoked' || errCode == 'device_mismatch') {
              debugPrint('[auth] server revoked session: $errCode');
              await _localLogout();
            }
          }
          handler.next(e);
        },
      ),
    );
  }

  User? get user => _user;
  String? get token => _token;
  bool get isLoggedIn => _token != null && _user != null;

  /// Persisted device UUID (created lazily on first use).
  /// Wallet + password is the *credential*, but we still send a device UUID
  /// so the server can bind the session to this specific install.
  String get deviceUuid {
    var uuid = prefs.getString(_kDeviceUuid);
    if (uuid == null || uuid.isEmpty) {
      uuid = const Uuid().v4();
      prefs.setString(_kDeviceUuid, uuid);
    }
    return uuid;
  }

  Future<void> loadFromStorage() async {
    _token = prefs.getString(_kToken);
    final userId = prefs.getString(_kUserId);
    final nickname = prefs.getString(_kNickname);
    final deviceUuidStr = prefs.getString(_kDeviceUuid);

    if (_token != null && userId != null && nickname != null && deviceUuidStr != null) {
      _user = User(
        id: userId,
        nickname: nickname,
        deviceUuid: deviceUuidStr,
        walletAddress: prefs.getString(_kWallet),
        region: prefs.getString(_kRegion),
        mannerScore: prefs.getInt(_kMannerScore) ?? 36,
        createdAt: DateTime.now(),
      );
      api.setToken(_token);
    }
    notifyListeners();
  }

  // ================================================================
  // Sign up
  // ================================================================
  Future<String?> register({
    required String walletAddress,
    required String nickname,
    required String password,
    required String passwordConfirm,
    String? region,
  }) async {
    try {
      final res = await api.post('/api/auth/register', data: {
        'wallet_address': walletAddress.trim(),
        'nickname': nickname.trim(),
        'password': password,
        'password_confirm': passwordConfirm,
        'device_uuid': deviceUuid,
        'region': region,
      });

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = res.data as Map<String, dynamic>;
        await _saveSession(
          token: data['token'] as String,
          user: User.fromJson(data['user'] as Map<String, dynamic>),
        );
        return null;
      }
      return _errorOf(res.data) ?? '가입 실패';
    } catch (e) {
      return _parseError(e);
    }
  }

  // ================================================================
  // Log in
  // ================================================================
  Future<String?> login({
    required String walletAddress,
    required String password,
  }) async {
    try {
      final res = await api.post('/api/auth/login', data: {
        'wallet_address': walletAddress.trim(),
        'password': password,
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
      return _errorOf(res.data) ?? '로그인 실패';
    } catch (e) {
      return _parseError(e);
    }
  }

  // ================================================================
  // Recover: look up nickname from wallet address.
  // Returns the nickname on success, or throws with a message.
  // ================================================================
  Future<({String? nickname, String? error})> recoverNickname(String walletAddress) async {
    try {
      final res = await api.post('/api/auth/recover/nickname', data: {
        'wallet_address': walletAddress.trim(),
      });
      if (res.statusCode == 200) {
        return (nickname: res.data['nickname'] as String?, error: null);
      }
      return (nickname: null, error: _errorOf(res.data) ?? '찾을 수 없어요');
    } catch (e) {
      return (nickname: null, error: _parseError(e));
    }
  }

  // ================================================================
  // Reset password via wallet ownership.
  // On success, we're logged in with a fresh token.
  // ================================================================
  Future<String?> resetPassword({
    required String walletAddress,
    required String newPassword,
    required String newPasswordConfirm,
  }) async {
    try {
      final res = await api.post('/api/auth/reset-password', data: {
        'wallet_address': walletAddress.trim(),
        'new_password': newPassword,
        'new_password_confirm': newPasswordConfirm,
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
      return _errorOf(res.data) ?? '비밀번호 재설정 실패';
    } catch (e) {
      return _parseError(e);
    }
  }

  // ================================================================
  // Region update
  // ================================================================
  Future<void> updateRegion(String region) async {
    if (_user == null) return;
    try {
      await api.put('/api/users/me', data: {'region': region});
    } catch (_) {}
    _user = _user!.copyWith(region: region);
    await prefs.setString(_kRegion, region);
    notifyListeners();
  }

  // ================================================================
  // Logout
  // ================================================================
  Future<void> logout() async {
    // Tell the server to invalidate ALL tokens for this user (including ours).
    try {
      await api.post('/api/auth/logout');
    } catch (_) {}
    await _localLogout();
  }

  // ================================================================
  // Internal helpers
  // ================================================================
  Future<void> _saveSession({required String token, required User user}) async {
    _token = token;
    _user = user;
    api.setToken(token);

    await prefs.setString(_kToken, token);
    await prefs.setString(_kUserId, user.id);
    await prefs.setString(_kNickname, user.nickname);
    await prefs.setString(_kDeviceUuid, user.deviceUuid);
    if (user.walletAddress != null) {
      await prefs.setString(_kWallet, user.walletAddress!);
    }
    if (user.region != null) await prefs.setString(_kRegion, user.region!);
    await prefs.setInt(_kMannerScore, user.mannerScore);

    notifyListeners();
  }

  /// Clear local session without calling the server (e.g. when server
  /// already told us the token is revoked).
  Future<void> _localLogout() async {
    _token = null;
    _user = null;
    api.setToken(null);
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kNickname);
    // Keep device_uuid (stable device identity) + wallet (for login convenience)
    // + region (for immediate feed).
    notifyListeners();
  }

  String? _errorOf(dynamic data) {
    if (data is Map && data['error'] != null) return data['error'].toString();
    return null;
  }

  String _parseError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
    }
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return '서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요.';
    }
    if (msg.contains('timeout')) return '응답 시간이 초과되었어요.';
    return '오류가 발생했어요';
  }
}

// Small record-type polyfill note: `({String? nickname, String? error})` requires
// Dart 3.0+. The project already uses go_router 14+ which implies Dart 3.x,
// so this is safe.
