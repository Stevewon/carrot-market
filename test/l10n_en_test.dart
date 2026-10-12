// 영어(en) 문구 — 로케일 로드 · 대표 문구 · ko 와 자리표시자 일치 확인.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eggplant/l10n/gen/app_localizations.dart';

/// ICU 메시지의 최상위 인자 이름 ({amount}, {count, plural, ...} 의 count 등).
Set<String> placeholders(String msg) {
  final names = <String>{};
  var depth = 0;
  for (var i = 0; i < msg.length; i++) {
    final c = msg[i];
    if (c == '{') {
      if (depth == 0) {
        final m = RegExp(r'^\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*[,}]').firstMatch(msg.substring(i));
        if (m != null) names.add(m.group(1)!);
      }
      depth++;
    } else if (c == '}') {
      if (depth > 0) depth--;
    }
  }
  return names;
}

Map<String, dynamic> readArb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('en 로케일을 지원하고 영어 문구를 돌려준다', () {
    expect(AppLocalizations.supportedLocales, contains(const Locale('en')));
    final t = lookupAppLocalizations(const Locale('en'));
    expect(t.localeName, 'en');
    expect(t.commonCancel, 'Cancel');
    expect(t.commonSave, 'Save');
    expect(t.pricePhp('1,000'), '₱1,000');
    expect(t.homeTabHome, isNot(lookupAppLocalizations(const Locale('ko')).homeTabHome));
  });

  test('en 문구에 한글이 남아 있지 않다', () {
    final en = readArb('lib/l10n/app_en.arb');
    final hangul = RegExp(r'[가-힣]');
    final left = en.entries
        .where((e) => !e.key.startsWith('@') && hangul.hasMatch(e.value as String))
        .map((e) => e.key)
        .toList();
    expect(left, isEmpty);
  });

  test('en 키·자리표시자가 ko 와 같다', () {
    final ko = readArb('lib/l10n/app_ko.arb');
    final en = readArb('lib/l10n/app_en.arb');
    final koKeys = ko.keys.where((k) => !k.startsWith('@')).toSet();
    final enKeys = en.keys.where((k) => !k.startsWith('@')).toSet();
    expect(enKeys, koKeys);
    final mismatches = <String>[];
    for (final k in koKeys) {
      final a = placeholders(ko[k] as String);
      final b = placeholders(en[k] as String);
      if (a.length != b.length || !a.containsAll(b)) mismatches.add('$k: ko=$a en=$b');
    }
    expect(mismatches, isEmpty);
  });

  test('en 금지 품목 안내는 필리핀 기준 (폭죽 항목 · 현지 예시)', () {
    final t = lookupAppLocalizations(const Locale('en'));
    expect(t.productBanFireworks, contains('Firecrackers'));
    expect(t.productBanFireworksEx, contains('RA 7183'));
    expect(t.productBanDrugsEx, contains('Shabu'));
    expect(t.productBanAccountsEx, contains('PhilSys'));
    // 한국어 · 일본어 안내는 그대로
    expect(lookupAppLocalizations(const Locale('ko')).productBanWasteBags, '종량제 봉투');
  });
}
