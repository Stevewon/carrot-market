import 'package:eggplant/app/l10n.dart';
import 'package:eggplant/services/auth_service.dart';
import 'package:eggplant/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 코인트립 연합 단톡방 — 서버가 보낸 대화를 연합별로 담고, 단톡방 밖에서 받은 남의 메시지만 안 읽음으로 센다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('연합 단톡방 메시지 받기 · 안 읽음 · 중복 무시', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 't', 'user_id': 'me', 'nickname': '나', 'device_uuid': 'dev', 'app_lang': 'ko'});
    final prefs = await SharedPreferences.getInstance();
    await L10n.init(prefs);
    final auth = AuthService(prefs);
    await auth.loadFromStorage();
    final chat = ChatService(auth);

    Map<String, dynamic> m(String id, String from, {String union = 'u1'}) => {
          'type': 'union_message', 'id': id, 'union_id': union, 'sender_id': from,
          'sender_nickname': from == 'me' ? '나' : '친구', 'text': 'hi $id', 'sent_at': '2026-10-19T03:00:00.000Z',
        };
    chat.debugReceive(m('1', 'peer'));
    chat.debugReceive(m('1', 'peer')); // 같은 id 는 한 번만
    chat.debugReceive(m('2', 'me')); // 내가 보낸 건 안 읽음 아님
    chat.debugReceive(m('3', 'peer', union: 'u2'));
    expect(chat.unionMessagesFor('u1').map((x) => x.id), ['1', '2']);
    expect(chat.unionUnread, 2);

    chat.unionChatOpen = true;
    expect(chat.unionUnread, 0);
    chat.debugReceive(m('4', 'peer'));
    expect(chat.unionUnread, 0);
    chat.unionChatOpen = false;
    expect(chat.sendUnionMessage('hello'), false); // 연결 안 됨
  });
}
