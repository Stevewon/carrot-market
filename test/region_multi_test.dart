import 'package:eggplant/app/l10n.dart';
import 'package:eggplant/models/user.dart';
import 'package:eggplant/screens/region_select_screen.dart';
import 'package:eggplant/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 서버 대신 메모리에서 동네 목록을 바꾸는 AuthService.
class _FakeAuth extends AuthService {
  _FakeAuth(super.prefs);
  User _u = User(
    id: 'u1',
    nickname: '나',
    deviceUuid: 'dev-test-xxxx',
    region: '서울 강남구',
    regions: const ['서울 강남구'],
    createdAt: DateTime(2026),
  );
  @override
  User? get user => _u;
  @override
  Future<String?> updateRegion(String region) async {
    final list = _u.regions.contains(region) ? _u.regions : [..._u.regions, region];
    if (list.length > 10) return 'max';
    _u = _u.copyWith(region: region, regions: list);
    notifyListeners();
    return null;
  }

  @override
  Future<String?> setRegions(List<String> regions, {String? active}) async {
    _u = _u.copyWith(region: active ?? _u.region, regions: regions);
    notifyListeners();
    return null;
  }
}

void main() {
  testWidgets('내 동네 설정 — 여러 곳 추가·빼기, 10곳 제한', (t) async {
    SharedPreferences.setMockInitialValues({'app_lang': 'ko'});
    final prefs = await SharedPreferences.getInstance();
    await L10n.init(prefs);
    final auth = _FakeAuth(prefs);
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RegionSelectScreen(),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('내 동네 1/10'), findsOneWidget);

    // 목록에서 두 곳 더 누르면 고른 목록에만 들어가고, 화면도 그대로 · 저장은 아직 안 된다.
    await t.tap(find.widgetWithText(ListTile, '서울 강동구'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, '서울 강북구'));
    await t.pumpAndSettle();
    expect(find.text('내 동네 3/10'), findsOneWidget);
    expect(find.byType(RegionSelectScreen), findsOneWidget);
    expect(auth.user!.regions, ['서울 강남구']);

    // 다시 누르면 빠진다.
    await t.tap(find.widgetWithText(ListTile, '서울 강동구'));
    await t.pumpAndSettle();
    expect(find.text('내 동네 2/10'), findsOneWidget);

    // 10곳까지 채우고, 11번째는 막힌다.
    for (final r in ['서울 강서구', '서울 관악구', '서울 광진구', '서울 구로구', '서울 금천구', '서울 노원구', '서울 도봉구', '서울 동대문구']) {
      await t.ensureVisible(find.widgetWithText(ListTile, r));
      await t.tap(find.widgetWithText(ListTile, r));
      await t.pumpAndSettle();
    }
    expect(find.text('내 동네 10/10'), findsOneWidget);
    await t.ensureVisible(find.widgetWithText(ListTile, '서울 동작구'));
    await t.tap(find.widgetWithText(ListTile, '서울 동작구'));
    await t.pumpAndSettle();
    expect(find.text('내 동네 10/10'), findsOneWidget);
    expect(auth.user!.regions, ['서울 강남구']);

    // 확인을 눌러야 한 번에 저장된다.
    await t.tap(find.text('확인 (10/10)'));
    await t.pumpAndSettle();
    expect(auth.user!.regions.length, 10);
    expect(auth.user!.regions.contains('서울 강북구'), true);
    expect(auth.user!.regions.contains('서울 동작구'), false);
    expect(auth.user!.region, '서울 강남구');
  });
}
