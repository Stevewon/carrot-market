import 'dart:convert';

import 'package:eggplant/services/auth_service.dart';
import 'package:eggplant/services/chat_service.dart';
import 'package:eggplant/services/push_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 처음 말을 건 상대의 메시지가 알림을 눌러 들어간 채팅방에 보여야 한다.
// 서버엔 대화 기록이 없으므로 푸시에 실린 본문이 유일한 사본이다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const me = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const peer = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const room = '${me}_$peer';
  const sentAt = '2026-10-12T03:00:00.123Z';

  Future<ChatService> make(Map<String, Object> extra) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 't',
      'user_id': me,
      'nickname': '나',
      'device_uuid': 'dev-test-xxxx',
      ...extra,
    });
    final auth = AuthService(await SharedPreferences.getInstance());
    // ignore: unawaited_futures
    auth.loadFromStorage(); // 사용자 정보는 동기로 채워진다 (서버 확인은 뒤에서).
    return ChatService(auth);
  }

  test('백그라운드 큐 + 알림 탭 → 상대 메시지 1개', () async {
    final chat = await make({
      kPendingPushQueueKey: jsonEncode([
        {'room_id': room, 'sender_id': peer, 'sender_nickname': '상대', 'text': '안녕하세요', 'sent_at': sentAt},
      ]),
    });
    await chat.applyPendingPushMessages();
    // 알림 탭 경로도 같은 메시지를 들고 온다 — 중복되면 안 된다.
    chat.applyIncomingPushMessage(
      roomId: room,
      senderId: peer,
      senderNickname: '상대',
      text: '안녕하세요',
      sentAt: ChatService.parsePushSentAt(sentAt),
    );
    final msgs = chat.messagesFor(room);
    expect(msgs.length, 1);
    expect(msgs.first.text, '안녕하세요');
    expect(msgs.first.isMine, false);
    expect(chat.rooms.single.peerNickname, '상대');
  });
}
