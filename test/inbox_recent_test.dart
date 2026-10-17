import 'package:eggplant/models/product.dart';
import 'package:eggplant/services/auth_service.dart';
import 'package:eggplant/services/inbox_service.dart';
import 'package:eggplant/services/recent_viewed_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 알림함(서버 + 이 폰 키워드 알림)과 최근 본 상품.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const me = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  Future<AuthService> login() async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 't',
      'user_id': me,
      'nickname': '나',
      'device_uuid': 'dev-test-xxxx',
    });
    final auth = AuthService(await SharedPreferences.getInstance());
    // ignore: unawaited_futures
    auth.loadFromStorage();
    return auth;
  }

  test('서버 알림 시각(UTC, 시간대 표시 없음)을 제대로 읽는다', () {
    final n = InboxItem.fromJson({
      'id': 'n1',
      'type': 'price_drop',
      'title': '찜한 상품의 가격이 내려갔어요',
      'body': '아이패드 · 50,000원 → 40,000원',
      'product_id': 'p1',
      'created_at': '2026-10-17 03:00:00',
      'read_at': null,
    });
    expect(n.createdAt.toUtc(), DateTime.utc(2026, 10, 17, 3));
    expect(n.read, false);
    expect(n.productId, 'p1');
    expect(n.targetUserId, isNull);
  });

  test('키워드 알림은 이 폰 알림함에 들어가고, 같은 상품은 한 번만', () async {
    final auth = await login();
    final box = InboxService(auth);
    await InboxService.recordLocal(auth, type: 'keyword_alert', title: '새 매물', body: '강남구 · 아이패드', productId: 'p1');
    await InboxService.recordLocal(auth, type: 'keyword_alert', title: '새 매물', body: '강남구 · 아이패드', productId: 'p1');
    await InboxService.recordLocal(auth, type: 'keyword_alert', title: '새 매물', body: '강남구 · 갤럭시', productId: 'p2');
    expect(box.items.length, 2);
    expect(box.items.first.productId, 'p2');
    expect(box.unread, 2);

    await box.remove(box.items.first);
    expect(box.items.single.productId, 'p1');
    box.dispose();
  });

  test('최근 본 상품 — 다시 보면 맨 앞으로, 30개까지', () async {
    final auth = await login();
    final svc = RecentViewedService(auth);
    Product p(String id) => Product.fromJson({
          'id': id,
          'title': '상품 $id',
          'price': 1000,
          'region': '서울 강남구',
          'images': ['uploads/a.jpg', 'uploads/b.jpg'],
          'created_at': '2026-10-16T03:00:00.000Z',
        });
    await svc.add(p('1'));
    await svc.add(p('2'));
    await svc.add(p('1'));
    expect(svc.items.map((e) => e.id), ['1', '2']);
    expect(svc.items.first.images, ['uploads/a.jpg']); // 목록용 첫 장만
    for (var i = 3; i < 40; i++) {
      await svc.add(p('$i'));
    }
    expect(svc.items.length, RecentViewedService.maxItems);
    expect(svc.items.first.id, '39');
    await svc.clear();
    expect(svc.items, isEmpty);
  });
}
