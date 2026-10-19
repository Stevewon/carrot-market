import 'package:eggplant/services/pending_invite.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('연합 초대 페이지가 클립보드에 남긴 코드 · 연합장을 읽고 지운다', () async {
    String? clip = '초대 코드 V8GXCBZB #eggplant-union=v8gxcbzb&ref=%EC%A4%8D%EB%8A%94%EC%9D%B4';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': clip};
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
      return null;
    });

    expect(await PendingInvite.checkClipboard(), isTrue);
    expect(PendingInvite.unionCode, 'V8GXCBZB');
    expect(PendingInvite.referrer, '줍는이');
    expect(clip, '');
    expect(PendingInvite.takeUnionLocation(), '/cointrip/union?code=V8GXCBZB');
    expect(PendingInvite.takeUnionLocation(), isNull);
    expect(PendingInvite.referrer, isNull);
  });
}
