import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eggplant/app/l10n.dart';
import 'package:eggplant/screens/cointrip_ext_wallet_screen.dart';
import 'package:eggplant/services/auth_service.dart';
import 'package:eggplant/services/cointrip_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 코인트립 — 서버 응답 읽기, 오류 문구, 기존 지갑 주소 저장은 빨간 안내 확인 후에만.
class _Fake implements HttpClientAdapter {
  final List<RequestOptions> sent = [];
  Map<String, dynamic> status = {'open': false};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    sent.add(o);
    final p = o.path;
    int code = 200;
    Object body = {};
    if (p == '/api/cointrip/status') {
      body = status;
    } else if (p == '/api/cointrip/drops') {
      body = {
        'need_wallet': false,
        'drops': [
          {'id': 'd1', 'precise': true, 'lat': 37.5, 'lng': 127.0, 'distance_m': 12, 'is_black': false,
           'coin': {'id': 'k1', 'symbol': 'QKEY', 'name': 'Q', 'color': '#7C3AED'}, 'amount': '1.5'},
          {'id': 'd2', 'precise': false, 'lat': 37.5025, 'lng': 127.0025, 'distance_m': 900, 'is_black': true, 'coin': null, 'amount': null},
        ],
      };
    } else if (p.endsWith('/pick')) {
      code = 400;
      body = {'error': '30m 안으로 가까이 가야 주울 수 있어요', 'code': 'too_far', 'distance_m': 81};
    } else if (p == '/api/cointrip/ext-wallet') {
      body = {'ok': true};
    }
    return ResponseBody.fromString(jsonEncode(body), code, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthService auth;
  late _Fake fake;

  Future<CointripService> setup() async {
    SharedPreferences.setMockInitialValues({'auth_token': 't', 'user_id': 'u1', 'nickname': '나', 'device_uuid': 'dev', 'app_lang': 'ko'});
    final prefs = await SharedPreferences.getInstance();
    await L10n.init(prefs);
    auth = AuthService(prefs);
    // ignore: unawaited_futures
    auth.loadFromStorage();
    fake = _Fake();
    auth.api.dio.httpClientAdapter = fake;
    return CointripService(auth);
  }

  test('닫혀 있으면 탭을 안 띄우고, 열리면 설정·지갑·연합을 읽는다', () async {
    final svc = await setup();
    await svc.loadStatus();
    expect(svc.open, false);
    expect(svc.statusLoaded, true);

    fake.status = {
      'open': true, 'pick_radius_m': 25, 'precise_radius_m': 250, 'finder_multiplier': 2.5, 'union_max': 10,
      'wallet_kinds': ['quantarium'], 'quantarium_wallet': '0xabc', 'ext_wallet_address': null,
      'phone_verified': true, 'intro_acked': false,
      'union': {'id': 'u', 'name': '팀', 'code': 'ABCDEFGH', 'owner_id': 'u1', 'members': [{'user_id': 'u1', 'nickname': '나'}]},
    };
    await svc.loadStatus();
    expect(svc.open, true);
    expect(svc.pickRadiusM, 25);
    expect(svc.finderMultiplier, 2.5);
    expect(svc.hasAnyWallet, true);
    expect(svc.extWallet, isNull);
    expect(svc.union!.members.single.nickname, '나');
  });

  test('지도 코인: 블랙코인은 종류·수량이 없고, 멀면 대략 위치', () async {
    final svc = await setup();
    final r = await svc.drops(37.5, 127.0);
    expect(r.drops.length, 2);
    expect(r.drops.first.coin!.symbol, 'QKEY');
    expect(r.drops.first.coin!.argb, 0xFF7C3AED);
    expect(r.drops.last.isBlack, true);
    expect(r.drops.last.coin, isNull);
    expect(r.drops.last.precise, false);
  });

  test('줍기 실패는 서버 문구와 코드를 그대로', () async {
    final svc = await setup();
    final d = (await svc.drops(37.5, 127.0)).drops.first;
    try {
      await svc.pick(d, lat: 37.5, lng: 127.0, accuracy: 5, mocked: false);
      fail('should throw');
    } on CtError catch (e) {
      expect(e.code, 'too_far');
      expect(e.distanceM, 81);
      expect(e.message, contains('30m'));
    }
  });

  testWidgets('기존 지갑 주소: 올바른 주소 + 빨간 안내 확인이 있어야 저장 버튼이 켜진다', (t) async {
    final svc = await setup();
    await t.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<CointripService>.value(value: svc)],
      child: MaterialApp(
        locale: L10n.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CointripExtWalletScreen(),
      ),
    ));
    await t.pump();
    FilledButton save() => t.widget<FilledButton>(find.widgetWithText(FilledButton, '저장'));
    expect(find.textContaining('반드시 회원 본인의 책임'), findsOneWidget);

    await t.enterText(find.byType(TextField), '0x1234');
    await t.pump();
    expect(find.text('0x로 시작하는 42자리 주소가 아니에요'), findsOneWidget);
    expect(save().onPressed, isNull);

    await t.enterText(find.byType(TextField), '0x${'a' * 40}');
    await t.pump();
    expect(save().onPressed, isNull); // 아직 확인 안 함

    await t.tap(find.byType(Checkbox));
    await t.pump();
    expect(save().onPressed, isNotNull);

    await t.runAsync(() async {
      await t.tap(find.widgetWithText(FilledButton, '저장'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pump();
    final put = fake.sent.lastWhere((o) => o.path == '/api/cointrip/ext-wallet');
    expect(put.method, 'PUT');
    expect(put.data, {'address': '0x${'a' * 40}', 'ack': true});
    expect(svc.extWallet, '0x${'a' * 40}');
  });
}
