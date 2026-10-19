import 'package:flutter/services.dart';

/// 로그인 전에 받은 코인트립 연합 초대 — 로그인 · 가입이 끝나면 연합 화면으로 바로 보낸다.
///
///  - 앱이 있는데 로그아웃 상태로 초대 링크를 열면 → 라우터가 코드를 여기 맡겨 둔다.
///  - 앱이 없던 사람은 초대 페이지(/c/<코드>)가 버튼을 누를 때 클립보드에
///    `#eggplant-union=<코드>&ref=<연합장 닉네임>` 을 복사해 둔다.
///    설치 후 처음 열면 [checkClipboard] 가 그걸 읽어 코드 · 추천인을 채운다.
class PendingInvite {
  PendingInvite._();

  static String? unionCode;
  static String? referrer;
  static Future<bool>? _clip;

  static final _re = RegExp(r'#eggplant-union=([A-Za-z0-9]{4,16})(?:&ref=([^\s#]*))?');

  /// 클립보드에 초대 페이지가 남긴 표시가 있으면 읽고 지운다 (한 번만 본다).
  static Future<bool> checkClipboard() => _clip ??= _readClipboard();

  static Future<bool> _readClipboard() async {
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      final m = text == null ? null : _re.firstMatch(text);
      if (m == null) return false;
      unionCode = m.group(1)!.toUpperCase();
      final ref = Uri.decodeComponent(m.group(2) ?? '').trim();
      if (ref.isNotEmpty) referrer = ref;
      await Clipboard.setData(const ClipboardData(text: ''));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 맡겨 둔 연합 초대가 있으면 그 화면 경로를 돌려주고 비운다.
  static String? takeUnionLocation() {
    final code = unionCode;
    if (code == null) return null;
    unionCode = null;
    referrer = null;
    return '/cointrip/union?code=${Uri.encodeQueryComponent(code)}';
  }
}
