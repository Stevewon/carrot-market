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
  static const _kQtaBalance = 'qta_balance';

  final SharedPreferences prefs;
  final ApiClient api = ApiClient();

  String? _token;
  User? _user;

  /// 마지막 가입/로그인 직후 받은 QTA 보너스 정보.
  /// UI 가 한 번 읽고 `consumeQtaBonus()` 로 비우는 식으로 1회성으로 사용.
  ///   { reason, amount, credited?, today_count?, today_max?, remaining? }
  Map<String, dynamic>? _pendingQtaBonus;
  Map<String, dynamic>? get pendingQtaBonus => _pendingQtaBonus;
  void consumeQtaBonus() {
    _pendingQtaBonus = null;
  }

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

  /// Hydrate session from SharedPreferences, then silently re-validate the
  /// token against the server. If the server bumped `token_version` (e.g. the
  /// same wallet logged in from another device, or the password was reset),
  /// this call forces a local logout so the app snaps to the login screen
  /// instead of pretending to be signed-in until the user hits an API.
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
        qtaBalance: prefs.getInt(_kQtaBalance) ?? 0,
        createdAt: DateTime.now(),
      );
      api.setToken(_token);
      notifyListeners();

      // Re-validate with the server. If the error interceptor already fires on
      // 401 with code=token_revoked/device_mismatch, it will call _localLogout
      // for us. We still handle other 401s (e.g. raw "Unauthorized") here.
      //
      // Short per-call timeout so a slow network never delays app cold-start
      // by more than ~5s — if the call times out we just keep the cached
      // session and move on; the next real API request will re-check.
      try {
        final res = await api.dio.get(
          '/api/auth/me',
          options: Options(
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        if (res.statusCode == 200) {
          final data = res.data as Map<String, dynamic>;
          final u = data['user'] as Map<String, dynamic>?;
          if (u != null) {
            _user = User.fromJson(u);
            // Persist any server-side updates (region, manner_score, etc.).
            await prefs.setString(_kNickname, _user!.nickname);
            if (_user!.walletAddress != null) {
              await prefs.setString(_kWallet, _user!.walletAddress!);
            }
            if (_user!.region != null) {
              await prefs.setString(_kRegion, _user!.region!);
            }
            await prefs.setInt(_kMannerScore, _user!.mannerScore);
            await prefs.setInt(_kQtaBalance, _user!.qtaBalance);
            notifyListeners();
          }
        }
      } on DioException catch (e) {
        // 401 with a known revoke code is handled by the interceptor.
        // For anything else we stay logged-in locally so a flaky network
        // doesn't log users out every cold start.
        if (e.response?.statusCode == 401) {
          await _localLogout();
        } else {
          debugPrint('[auth] loadFromStorage: /me failed (keeping session): $e');
        }
      } catch (e) {
        debugPrint('[auth] loadFromStorage: /me error (keeping session): $e');
      }
    } else {
      notifyListeners();
    }
  }

  // ================================================================
  // Manual session refresh (splash 등에서 호출)
  //
  // /api/auth/me 를 한 번 더 찍어서 서버가 user 를 못 찾으면 (404/401)
  // 즉시 _localLogout 한다. loadFromStorage 와 다르게 짧은 timeout 으로
  // 실패 시 그냥 무시 (예외는 호출자 측에서 catch).
  // ================================================================
  Future<void> refreshFromServer() async {
    if (_token == null) return;
    try {
      final res = await api.dio.get(
        '/api/auth/me',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final u = (res.data as Map)['user'];
        if (u is Map<String, dynamic>) {
          _user = User.fromJson(u);
          notifyListeners();
        }
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // 서버에서 user 가 사라졌거나 (404/401) 토큰이 무효면 즉시 로그아웃.
      if (code == 401 || code == 404) {
        await _localLogout();
      }
    } catch (_) {/* 네트워크 등 일시 오류는 세션 유지 */}
  }

  // ================================================================
  // Sign up
  // ================================================================
  Future<RegisterResult> register({
    required String walletAddress,
    required String nickname,
    required String password,
    required String passwordConfirm,
    String? region,
    String? referrerNickname,
  }) async {
    try {
      final res = await api.post('/api/auth/register', data: {
        'wallet_address': walletAddress.trim(),
        'nickname': nickname.trim(),
        'password': password,
        'password_confirm': passwordConfirm,
        'device_uuid': deviceUuid,
        'region': region,
        if (referrerNickname != null && referrerNickname.isNotEmpty)
          'referrer_nickname': referrerNickname.trim(),
      });

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = res.data as Map<String, dynamic>;
        await _saveSession(
          token: data['token'] as String,
          user: User.fromJson(data['user'] as Map<String, dynamic>),
        );
        if (data['qta_bonus'] is Map) {
          _pendingQtaBonus = Map<String, dynamic>.from(data['qta_bonus'] as Map);
        }
        ReferralOutcome? ref;
        if (data['referral'] is Map) {
          ref = ReferralOutcome.fromJson(
              Map<String, dynamic>.from(data['referral'] as Map));
        }
        return RegisterResult(error: null, referral: ref);
      }
      return RegisterResult(
          error: _errorOf(res.data) ?? '가입 실패', referral: null);
    } catch (e) {
      return RegisterResult(error: _parseError(e), referral: null);
    }
  }

  // ================================================================
  // Account deletion (영구 삭제 — "한 번 사라진 건 영구 보관 X")
  // ================================================================
  Future<String?> deleteAccount({required String password}) async {
    try {
      final res = await api.dio.delete(
        '/api/auth/me',
        data: {'password': password},
      );
      if (res.statusCode == 200) {
        await _localLogout();
        return null;
      }
      return _errorOf(res.data) ?? '탈퇴 처리 실패';
    } catch (e) {
      return _parseError(e);
    }
  }

  // ================================================================
  // Check if a nickname exists (for referrer field on signup screen)
  // ================================================================
  Future<bool> checkNicknameExists(String nickname) async {
    try {
      final res = await api.dio.get(
        '/api/auth/check-nickname',
        queryParameters: {'nickname': nickname.trim()},
      );
      if (res.statusCode == 200 && res.data is Map) {
        return res.data['exists'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ================================================================
  // Log in (nickname + password)
  // ================================================================
  Future<String?> login({
    required String nickname,
    required String password,
  }) async {
    try {
      final res = await api.post('/api/auth/login', data: {
        'nickname': nickname.trim(),
        'password': password,
        'device_uuid': deviceUuid,
      });

      if (res.statusCode == 200) {
        final data = res.data as Map<String, dynamic>;
        await _saveSession(
          token: data['token'] as String,
          user: User.fromJson(data['user'] as Map<String, dynamic>),
        );
        if (data['qta_bonus'] is Map) {
          _pendingQtaBonus = Map<String, dynamic>.from(data['qta_bonus'] as Map);
        }
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

  /// 동네 인증 — GPS 좌표를 서버에 보내고 region 중심점에서 4km 안인지 검증.
  /// 통과 시 region 과 region_verified_at 이 업데이트된다.
  /// 사생활: 정확한 GPS 는 서버 검증 직후 폐기되고 DB 에 저장되지 않는다.
  ///
  /// 반환: null = 성공, 그 외 = 사용자에게 보여줄 에러 메시지.
  Future<String?> verifyRegion({
    required double lat,
    required double lng,
    String? region,
  }) async {
    if (_user == null) return '로그인이 필요해요';
    try {
      final res = await api.post(
        '/api/users/me/region/verify',
        data: {
          'lat': lat,
          'lng': lng,
          if (region != null && region.isNotEmpty) 'region': region,
        },
      );
      final data = res.data is Map ? res.data as Map : {};
      final newRegion = (data['region'] ?? region ?? _user!.region) as String?;
      final verifiedAtStr = data['region_verified_at'] as String?;
      _user = _user!.copyWith(
        region: newRegion,
        regionVerifiedAt: verifiedAtStr != null
            ? DateTime.tryParse(verifiedAtStr)
            : DateTime.now(),
      );
      if (newRegion != null) await prefs.setString(_kRegion, newRegion);
      notifyListeners();
      return null;
    } catch (e) {
      return _parseError(e);
    }
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
    await prefs.setInt(_kQtaBalance, user.qtaBalance);

    notifyListeners();
  }

  /// 잔액만 갱신 (보너스 수령 직후, ledger 새로고침 후 등).
  Future<void> updateQtaBalance(int newBalance) async {
    if (_user == null) return;
    _user = _user!.copyWith(qtaBalance: newBalance);
    await prefs.setInt(_kQtaBalance, newBalance);
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

/// 회원가입 결과 (에러 또는 친구 초대 처리 결과 포함)
class RegisterResult {
  final String? error;
  final ReferralOutcome? referral;
  const RegisterResult({this.error, this.referral});
}

/// 친구 초대 처리 결과
class ReferralOutcome {
  final bool credited;
  final String? inviterNickname;
  final int inviterBonus;
  final String? reason; // 'self_referral' | 'inviter_not_found' | 'already_processed' | null
  const ReferralOutcome({
    required this.credited,
    this.inviterNickname,
    this.inviterBonus = 0,
    this.reason,
  });
  factory ReferralOutcome.fromJson(Map<String, dynamic> j) => ReferralOutcome(
        credited: j['credited'] == true,
        inviterNickname: j['inviter_nickname']?.toString(),
        inviterBonus: (j['inviter_bonus'] as num?)?.toInt() ?? 0,
        reason: j['reason']?.toString(),
      );
}
