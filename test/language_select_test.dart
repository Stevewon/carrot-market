import 'package:eggplant/app/l10n.dart';
import 'package:eggplant/screens/language_select_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('첫 실행 언어 선택 → 日本語 저장', (t) async {
    SharedPreferences.setMockInitialValues({'app_market': 'kr'});
    final prefs = await SharedPreferences.getInstance();
    await L10n.init(prefs);
    expect(L10n.hasChosen, false);
    expect(L10n.lang, 'ko');
    await t.pumpWidget(MaterialApp(home: const LanguageSelectScreen()));
    expect(find.text('시작하기'), findsOneWidget);
    await t.tap(find.text('日本語'));
    await t.pump();
    expect(find.text('はじめる'), findsOneWidget);
    await t.tap(find.text('はじめる'));
    await t.pumpAndSettle();
    expect(L10n.hasChosen, true);
    expect(L10n.lang, 'ja');
    expect(L10n.market, 'jp');
    expect(prefs.getString('app_lang'), 'ja');
    // 다시 실행해도 기억
    await L10n.init(prefs);
    expect(L10n.isJapanese, true);
  });
  testWidgets('마이페이지에서 한국어로 변경', (t) async {
    SharedPreferences.setMockInitialValues({'app_lang': 'ja'});
    final prefs = await SharedPreferences.getInstance();
    await L10n.init(prefs);
    var done = false;
    await t.pumpWidget(MaterialApp(home: LanguageSelectScreen(onDone: () => done = true)));
    expect(find.text('保存'), findsOneWidget);
    await t.tap(find.text('한국어'));
    await t.pump();
    await t.tap(find.text('저장'));
    await t.pumpAndSettle();
    expect(done, true);
    expect(L10n.lang, 'ko');
    expect(L10n.market, 'kr');
  });
}
