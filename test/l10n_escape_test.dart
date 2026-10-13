// 문구에 '\n' 이 글자 그대로 들어가면 화면에 "\n" 이 찍힌다 (v1.0.170~182 버그).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final lang in ['ko', 'ja', 'en']) {
    test('app_$lang.arb 에 글자 그대로의 \\n 이 없다', () {
      final arb = jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
          as Map<String, dynamic>;
      final bad = [
        for (final e in arb.entries)
          if (e.value is String && (e.value as String).contains(r'\n')) e.key,
      ];
      expect(bad, isEmpty);
    });
  }
}
