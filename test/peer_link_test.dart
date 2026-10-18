import 'package:eggplant/screens/peer_link_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('내 QR 링크 만들기 · 읽기 (새 https · 앱 링크 · 예전 QR)', () {
    const id = 'af293f4a-6183-4e11-acba-e8c059901c7d';
    final link = peerLink('https://api.eggplant.life', id, '바람의나그네');
    expect(link, startsWith('https://api.eggplant.life/u/$id?n='));
    expect(parsePeerLink(link), (id, '바람의나그네'));
    expect(parsePeerLink('eggplant://app/u/$id?n=%EB%B0%94%EB%9E%8C'), (id, '바람'));
    expect(parsePeerLink('eggplant://$id/%EB%B0%94%EB%9E%8C%EC%9D%98%EB%82%98%EA%B7%B8%EB%84%A4'), (id, '바람의나그네'));
    expect(parsePeerLink('eggplant://app/product/123'), isNull);
    expect(parsePeerLink('https://example.com/hello'), isNull);
    expect(parsePeerLink('그냥 글자'), isNull);
  });
}
