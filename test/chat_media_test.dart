import 'dart:convert';

import 'package:eggplant/models/chat_message.dart';
import 'package:eggplant/services/auth_service.dart';
import 'package:eggplant/services/chat_service.dart';
import 'package:eggplant/services/push_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 채팅 사진 · 거래 약속 · 가격 제안 메시지가 WebSocket 과 푸시 양쪽에서 제 종류로 들어오는지,
// 사진 암호화가 열쇠로만 열리는지.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const me = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const peer = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const room = '${me}_$peer';
  const mediaId = '0f8fad5b-d9cb-469f-a165-70867728950e';

  test('WS 가격 제안은 type=message 여도 price_offer 로 읽힌다', () {
    final m = ChatMessage.fromJson({
      'type': 'message',
      'id': 'o1',
      'room_id': room,
      'sender_id': peer,
      'text': '10,000원에 어떠세요?',
      'msg_type': 'price_offer',
      'sent_at': '2026-10-17T03:00:00.000Z',
      'offer': {'id': 'o1', 'price': 10000, 'status': 'pending', 'buyer_id': peer},
    }, currentUserId: me);
    expect(m.type, 'price_offer');
    expect(m.offer?.price, 10000);
  });

  test('WS 사진 · 약속 메시지', () {
    final img = ChatMessage.fromJson({
      'type': 'message',
      'id': 'i1',
      'room_id': room,
      'sender_id': peer,
      'text': '📷 사진',
      'msg_type': 'image',
      'sent_at': '2026-10-17T03:00:00.000Z',
      'image': {'media_id': mediaId, 'key': 'k' * 44, 'w': 1280, 'h': 960},
    }, currentUserId: me);
    expect(img.type, 'image');
    expect(img.image?.mediaId, mediaId);
    expect(img.image?.width, 1280);

    final appt = ChatMessage.fromJson({
      'type': 'message',
      'id': 'a1',
      'room_id': room,
      'sender_id': me,
      'text': '📅 거래 약속을 잡았어요',
      'msg_type': 'appointment',
      'sent_at': '2026-10-17T03:00:00.000Z',
      'appointment': {'at': '2026-10-18T06:30:00.000Z', 'place': '강남역 2번 출구', 'action': 'set'},
    }, currentUserId: me);
    expect(appt.type, 'appointment');
    expect(appt.isMine, true);
    expect(appt.appointment?.place, '강남역 2번 출구');
    expect(appt.appointment?.cancelled, false);
    expect(appt.appointment?.at.toUtc(), DateTime.utc(2026, 10, 18, 6, 30));
  });

  test('일반 글자 메시지는 그대로 text', () {
    final m = ChatMessage.fromJson({
      'type': 'message',
      'id': 't1',
      'room_id': room,
      'sender_id': peer,
      'text': '안녕하세요',
      'msg_type': 'text',
      'sent_at': '2026-10-17T03:00:00.000Z',
    }, currentUserId: me);
    expect(m.type, 'text');
    expect(m.image, isNull);
  });

  test('사진 암호화 — 맞는 열쇠로만 열린다', () async {
    final original = List<int>.generate(5000, (i) => i % 251);
    final (sealed, key) = await ChatService.sealImage(original);
    expect(sealed.length, original.length + 12 + 16);
    // 암호문에 원본이 그대로 보이면 안 된다.
    expect(sealed.sublist(12, 112), isNot(original.sublist(0, 100)));
    final opened = await ChatService.openImage(sealed, key);
    expect(opened, original);

    final (_, otherKey) = await ChatService.sealImage([1, 2, 3]);
    expect(await ChatService.openImage(sealed, otherKey), isNull);
    final tampered = [...sealed]..[20] ^= 1;
    expect(await ChatService.openImage(tampered, key), isNull);
  });

  test('앱이 꺼져 있을 때 받은 사진 · 약속 푸시도 제 종류로 채팅방에 들어간다', () async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 't',
      'user_id': me,
      'nickname': '나',
      'device_uuid': 'dev-test-xxxx',
      kPendingPushQueueKey: jsonEncode([
        {
          'room_id': room,
          'sender_id': peer,
          'sender_nickname': '상대',
          'text': '📷 사진',
          'msg_type': 'image',
          'image': jsonEncode({'media_id': mediaId, 'key': 'k' * 44, 'w': 10, 'h': 20}),
          'appointment': '',
          'sent_at': '2026-10-17T03:00:00.000Z',
        },
      ]),
    });
    final auth = AuthService(await SharedPreferences.getInstance());
    // ignore: unawaited_futures
    auth.loadFromStorage();
    final chat = ChatService(auth);
    await chat.applyPendingPushMessages();
    final msgs = chat.messagesFor(room);
    expect(msgs.length, 1);
    expect(msgs.single.type, 'image');
    expect(msgs.single.image?.mediaId, mediaId);
    expect(msgs.single.image?.height, 20);
  });
}
