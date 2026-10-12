import 'package:eggplant/app/l10n.dart';
import 'package:eggplant/app/regions.dart';
import 'package:eggplant/app/regions_ph.dart';
import 'package:eggplant/models/user.dart';
import 'package:eggplant/screens/region_select_screen.dart';
import 'package:eggplant/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 서버 대신 메모리에서 동네 목록을 바꾸는 AuthService (필리핀 회원).
class _FakeAuth extends AuthService {
  _FakeAuth(super.prefs);
  User _u = User(
    id: 'u1',
    nickname: 'me',
    deviceUuid: 'dev-test-xxxx',
    region: 'Metro Manila · Makati City',
    regions: const ['Metro Manila · Makati City'],
    market: 'ph',
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
  group('필리핀 지역 데이터', () {
    test('개수·중복·구분자', () {
      expect(AppRegions.phProvinces.length, 84); // 82 Province + Metro Manila + Special Geographic Area
      expect(AppRegions.phProvinces.first, 'Metro Manila');
      expect(AppRegions.ph.length, greaterThan(1600));
      expect(AppRegions.ph.toSet().length, AppRegions.ph.length);
      expect(AppRegions.forMarket('ph'), same(AppRegions.ph));
      for (final p in AppRegions.phProvinces) {
        expect(p.contains(PhRegionData.sep), false, reason: p);
        expect(AppRegions.phCities(p), isNotEmpty, reason: p);
      }
      for (final r in AppRegions.ph) {
        expect(PhRegionData.sep.allMatches(r).length, 1, reason: r);
      }
      // 한국·일본 이름과 겹치지 않는다.
      final ph = AppRegions.ph.toSet();
      expect(AppRegions.kr.where(ph.contains), isEmpty);
      expect(AppRegions.jp.where(ph.contains), isEmpty);
    });

    test('Metro Manila 와 대표 도시', () {
      final mm = AppRegions.phCities('Metro Manila').map((c) => c.$2).toList();
      expect(mm, containsAll(['Quezon City', 'Makati City', 'Taguig City', 'Pasig City', 'Pateros']));
      expect(mm.length, 30); // 16 시·군 + 마닐라 구 14
      // 마닐라는 PSGC sub-municipality 14곳으로 나뉜다. 예전 통째 이름은 앱 목록에 없다 (서버 별칭만).
      const districts = [
        'Binondo', 'Ermita', 'Intramuros', 'Malate', 'Paco', 'Pandacan', 'Port Area',
        'Quiapo', 'Sampaloc', 'San Miguel', 'San Nicolas', 'Santa Ana', 'Santa Cruz', 'Tondo',
      ];
      expect(mm.where((c) => c.startsWith('Manila (')).toList(),
          [for (final d in districts) 'Manila ($d)']);
      expect(mm, isNot(contains('Manila City')));
      expect(AppRegions.ph, isNot(contains('Metro Manila · Manila City')));
      expect(AppRegions.ph, contains('Metro Manila · Manila (Tondo)'));
      expect(AppRegions.phProvinceOf('Metro Manila · Manila (Sampaloc)'), 'Metro Manila');
      // 예전에 저장된 이름도 Province 는 알아본다.
      expect(AppRegions.phProvinceOf('Metro Manila · Manila City'), 'Metro Manila');
      for (final r in [
        'Metro Manila · Makati City',
        'Cebu · Cebu City',
        'Davao del Sur · Davao City',
        'Palawan · Brooke\'s Point',
      ]) {
        expect(AppRegions.ph, contains(r));
      }
      expect(AppRegions.phProvinceOf('Cebu · Cebu City'), 'Cebu');
      expect(AppRegions.phProvinceOf('Metro Manila · Makati City'), 'Metro Manila');
      expect(AppRegions.phProvinceOf('서울 강남구'), isNull);
      expect(AppRegions.phProvinceOf('大阪府 大阪市北区'), isNull);
      // 같은 이름은 Province 로 구분된다.
      final sanJose = AppRegions.ph.where((r) => r.endsWith('${PhRegionData.sep}San Jose')).toList();
      expect(sanJose.length, greaterThan(1));
    });
  });

  testWidgets('필리핀 회원 — Province 단계 → 시·군 단계, 추가', (t) async {
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

    // 1단계: Province 목록 (한국 동네·일본 都道府県은 없음).
    expect(find.widgetWithText(ListTile, 'Metro Manila'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Abra'), findsOneWidget);
    expect(find.text('서울 강남구'), findsNothing);
    expect(find.text('北海道'), findsNothing);

    // 검색 — 영어, ñ 없이도 찾는다.
    await t.enterText(find.byType(TextField), 'paranaque');
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Metro Manila · Parañaque City'), findsOneWidget);
    await t.enterText(find.byType(TextField), '');
    await t.pumpAndSettle();

    // 2단계: Cebu 의 시·군.
    await t.scrollUntilVisible(find.widgetWithText(ListTile, 'Cebu'), 300,
        scrollable: find.byType(Scrollable).last);
    await t.tap(find.widgetWithText(ListTile, 'Cebu'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Alcantara'), findsOneWidget); // 첫 시·군
    expect(find.widgetWithText(ListTile, 'Metro Manila'), findsNothing);
    await t.scrollUntilVisible(find.widgetWithText(ListTile, 'Cebu City'), 300,
        scrollable: find.byType(Scrollable).last);
    await t.tap(find.widgetWithText(ListTile, 'Cebu City'));
    await t.pumpAndSettle();
    expect(auth.user!.regions, ['Metro Manila · Makati City', 'Cebu · Cebu City']);
    expect(auth.user!.region, 'Cebu · Cebu City');
  });
}
