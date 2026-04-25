import 'package:flutter/material.dart';

/// 모바일/태블릿 반응형 헬퍼.
///
/// Eggplant 는 1차로 모바일 폰을 타겟으로 한다.
/// 다만 다음 케이스에서 깨지지 않도록 보호한다:
///   - 갤럭시 폴드(가로 270dp 펼친 후 좁은 모드)
///   - 일반 폰(360~412dp)
///   - 큰 폰/Pro Max 류(414~480dp)
///   - 태블릿(600dp+) - 폼이 옆으로 무한정 늘어나지 않도록 max-width 적용
///   - 가로 모드(landscape) - 폼은 중앙 정렬 + 최대폭 제한
///
/// 사용 예:
///   // 어떤 화면이든 본문을 감쌀 때
///   body: ResponsiveBody(child: ListView(...))
///
///   // 폼 화면을 감쌀 때 (입력 필드가 들어가는 화면)
///   body: ResponsiveForm(child: Column(...))
class Responsive {
  /// 일반 폼/콘텐츠가 가질 수 있는 최대 가로폭. 태블릿/가로모드에서 적용.
  static const double maxContentWidth = 480;

  /// 채팅/피드 같이 좀 더 넓게 보여도 되는 콘텐츠의 최대 폭.
  static const double maxFeedWidth = 600;

  /// 폰트 스케일 안전 상한. 시스템 글자 크기를 너무 크게 잡으면
  /// UI 가 깨지므로 1.3 배 까지만 허용.
  static const double maxTextScale = 1.3;

  /// 컴팩트 폰(폴드 닫힘, 5인치 이하 등)인지.
  static bool isCompact(BuildContext context) =>
      MediaQuery.of(context).size.width < 360;

  /// 태블릿 / 큰 화면인지. 600dp 가 안드로이드 sw600dp 기준.
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;

  /// 현재 가로 모드인지.
  static bool isLandscape(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  /// 화면 폭 기준으로 적절한 패딩 계산.
  static EdgeInsets pagePadding(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= maxContentWidth + 32) {
      // 태블릿: 좌우 충분히 띄우고 폼 가운데 정렬은 ResponsiveForm 이 처리
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 16);
    }
    if (w < 360) {
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 12);
    }
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 16);
  }
}

/// 어떤 화면이든 본문(입력 필드 외 빈 영역)을 탭하면 키보드가 닫히게 한다.
///
/// `MaterialApp.builder` 에서 한 번 감싸면 앱 전역에 적용된다.
/// translucent HitTest 라서 버튼/리스트 탭은 정상 작동한다.
class KeyboardDismissOnTap extends StatelessWidget {
  final Widget child;
  const KeyboardDismissOnTap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final focus = FocusManager.instance.primaryFocus;
        if (focus != null && focus.hasFocus) {
          focus.unfocus();
        }
      },
      child: child,
    );
  }
}

/// 시스템 글자 크기가 너무 크게 설정되었을 때 UI 가 깨지지 않도록 보호.
///
/// `MaterialApp.builder` 에서 한 번 감싸면 앱 전역에 적용된다.
class TextScaleClamper extends StatelessWidget {
  final Widget child;
  final double max;

  const TextScaleClamper({
    super.key,
    required this.child,
    this.max = Responsive.maxTextScale,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final clamped = mq.textScaler.clamp(
      minScaleFactor: 0.85,
      maxScaleFactor: max,
    );
    return MediaQuery(
      data: mq.copyWith(textScaler: clamped),
      child: child,
    );
  }
}

/// 일반 본문(피드, 리스트 등) 영역을 감싼다.
/// SafeArea + 태블릿 max-width 적용.
class ResponsiveBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final bool top;
  final bool bottom;
  final bool left;
  final bool right;

  const ResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = Responsive.maxFeedWidth,
    this.top = true,
    this.bottom = true,
    this.left = true,
    this.right = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// 폼/입력이 있는 화면을 감싼다.
/// SafeArea + 좁은 max-width(480) + 키보드 빈 곳 탭하면 닫기 제스처.
class ResponsiveForm extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final bool dismissKeyboardOnTap;

  const ResponsiveForm({
    super.key,
    required this.child,
    this.maxWidth = Responsive.maxContentWidth,
    this.dismissKeyboardOnTap = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget body = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
    if (dismissKeyboardOnTap) {
      body = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: body,
      );
    }
    return body;
  }
}
