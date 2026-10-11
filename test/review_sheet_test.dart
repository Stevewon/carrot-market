import 'package:eggplant/app/l10n.dart';
import 'package:eggplant/models/review.dart';
import 'package:eggplant/widgets/review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 거래 후기 시트 (당근식 3단계) 위젯 테스트.
void main() {
  Widget host(Widget sheet, {Locale locale = const Locale('ko')}) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: sheet)),
      );

  ElevatedButton button(WidgetTester t, String key) =>
      t.widget<ElevatedButton>(find.byKey(Key(key)));

  testWidgets('구매자 → 판매자: 최고예요 → 항목 고르기 전엔 다음 비활성 → 후기 보내기', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);

    String? sentRating;
    List<String>? sentTags;
    String? sentComment;
    await t.pumpWidget(host(ReviewSheet(
      counterpartNickname: '가지판매자',
      role: ReviewerRole.buyer,
      onSubmit: (rating, tags, comment) async {
        sentRating = rating;
        sentTags = tags;
        sentComment = comment;
        return null;
      },
    )));

    // Step 1 — 질문 + 세 가지 평가
    expect(find.text('가지판매자님과 거래가 어떠셨나요?'), findsOneWidget);
    expect(find.text('별로예요'), findsOneWidget);
    expect(find.text('좋아요'), findsOneWidget);
    expect(find.text('최고예요'), findsOneWidget);
    expect(find.byKey(const Key('review_submit')), findsNothing);

    await t.tap(find.byKey(const Key('review_rating_best')));
    await t.pumpAndSettle();

    // Step 2 — 판매자 칭찬 항목 (유료 상품이라 무료나눔 항목 없음), 비매너 항목 없음
    expect(find.text('어떤 점이 좋았나요?'), findsOneWidget);
    expect(find.text('상품 상태가 설명한 것과 같아요'), findsOneWidget);
    expect(find.text('무료로 나눠주셨어요'), findsNothing);
    expect(find.text('제시간에 결제·수령했어요'), findsNothing);
    expect(find.text('시간 약속을 안 지켜요'), findsNothing);
    expect(button(t, 'review_next').onPressed, isNull, reason: '항목을 고르기 전에는 다음 비활성');

    await t.tap(find.byKey(const Key('review_tag_fast_reply')));
    await t.tap(find.byKey(const Key('review_tag_kind')));
    await t.pump();
    expect(button(t, 'review_next').onPressed, isNotNull);

    // 하나 해제해도 하나 남아 있으면 활성, 모두 해제하면 다시 비활성
    await t.tap(find.byKey(const Key('review_tag_fast_reply')));
    await t.pump();
    expect(button(t, 'review_next').onPressed, isNotNull);
    await t.tap(find.byKey(const Key('review_tag_kind')));
    await t.pump();
    expect(button(t, 'review_next').onPressed, isNull);
    await t.tap(find.byKey(const Key('review_tag_fast_reply')));
    await t.tap(find.byKey(const Key('review_tag_kind')));
    await t.pump();

    await t.tap(find.byKey(const Key('review_next')));
    await t.pumpAndSettle();

    // Step 3 — 후기 글 (선택) + 보내기
    expect(find.text('따뜻한 거래 후기를 남겨주세요'), findsOneWidget);
    expect(button(t, 'review_submit').onPressed, isNotNull);
    await t.enterText(find.byKey(const Key('review_comment')), '  친절했어요!  ');
    await t.tap(find.byKey(const Key('review_submit')));
    await t.pumpAndSettle();

    expect(sentRating, 'best');
    // 화면 순서대로 (kind 가 fast_reply 보다 앞)
    expect(sentTags, ['kind', 'fast_reply']);
    expect(sentComment, '친절했어요!');
  });

  testWidgets('뒤로 가서 별로예요로 바꾸면 고른 칭찬 항목은 지워지고 비공개 안내가 나온다', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    var calls = 0;
    await t.pumpWidget(host(ReviewSheet(
      counterpartNickname: 'buyer1',
      role: ReviewerRole.seller,
      onSubmit: (r, tags, c) async {
        calls++;
        return '서버 오류';
      },
    )));
    await t.tap(find.byKey(const Key('review_rating_good')));
    await t.pumpAndSettle();
    // 판매자 → 구매자 칭찬 항목
    expect(find.text('제시간에 결제·수령했어요'), findsOneWidget);
    expect(find.text('상품 상태가 설명한 것과 같아요'), findsNothing);
    await t.tap(find.byKey(const Key('review_tag_paid_on_time')));
    await t.pump();
    expect(button(t, 'review_next').onPressed, isNotNull);

    await t.tap(find.byKey(const Key('review_back')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('review_rating_bad')));
    await t.pumpAndSettle();
    expect(find.text('어떤 점이 별로였나요?'), findsOneWidget);
    expect(find.textContaining('공개되지 않고'), findsOneWidget);
    expect(find.text('무리하게 가격을 깎아요'), findsOneWidget);
    expect(find.text('가격을 갑자기 바꿔요'), findsNothing, reason: '판매자 전용 비매너 항목은 구매자 평가에 없음');
    expect(button(t, 'review_next').onPressed, isNull, reason: '긍정→부정 전환 시 항목 초기화');

    await t.tap(find.byKey(const Key('review_tag_no_show')));
    await t.pump();
    await t.tap(find.byKey(const Key('review_next')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('review_submit')));
    await t.pumpAndSettle();
    expect(calls, 1);
    // 실패하면 시트에 오류를 보여주고 다시 보낼 수 있다
    expect(find.text('서버 오류'), findsOneWidget);
    expect(button(t, 'review_submit').onPressed, isNotNull);
  });

  testWidgets('일본어 문구 + 0엔 상품이면 무료 나눔 항목', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(
      ReviewSheet(
        counterpartNickname: 'たろう',
        role: ReviewerRole.buyer,
        isFree: true,
        onSubmit: (r, tags, c) async => null,
      ),
      locale: const Locale('ja'),
    ));
    expect(find.text('たろうさんとの取引はいかがでしたか？'), findsOneWidget);
    await t.tap(find.text('最高だった'));
    await t.pumpAndSettle();
    expect(find.text('無料で譲ってくれました'), findsOneWidget);
    expect(find.text('次へ'), findsOneWidget);
  });

  test('예전 자유 입력 태그는 문구 그대로, 코드는 언어별 문구로', () async {
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));
    expect(reviewTagLabel(ko, 'kind'), '친절하고 매너가 좋아요');
    expect(reviewTagLabel(ja, 'kind'), '親切で丁寧な対応でした');
    expect(reviewTagLabel(ko, '시간약속을 잘 지켜요'), '시간약속을 잘 지켜요');
    expect(reviewRatingLabel(ko, 'soso'), '보통이에요');
    expect(reviewRatingLabel(ja, 'best'), '最高だった');
  });
}
