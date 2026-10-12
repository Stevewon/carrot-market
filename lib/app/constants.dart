import 'l10n.dart';

/// App-wide constants
class AppConfig {
  /// Backend REST base URL. Override with --dart-define=API_BASE=...
  ///
  /// Production default: `https://api.eggplant.life` (Cloudflare Workers).
  /// For local development against the Node server, run:
  ///   flutter run --dart-define=API_BASE=http://10.0.2.2:3001 \
  ///              --dart-define=SOCKET_URL=ws://10.0.2.2:3001/socket
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://api.eggplant.life',
  );

  /// WebSocket URL (raw WS, not Socket.IO). The JWT is appended as ?token=...
  /// by ChatService/CallService at connect time.
  ///
  /// Production default: `wss://api.eggplant.life/socket`
  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'wss://api.eggplant.life/socket',
  );

  /// 2단계 휴대폰 인증(Firebase 문자) 사용 여부. 끄면 휴대폰 인증이 필요한
  /// QTA 결제 거래·QTA 가격 설정·출금이 "준비 중" 으로 닫힌다 (원화 거래·후기는 가능).
  /// 문자 인증을 막아야 할 때만 `--dart-define=IDENTITY_ENABLED=false` 로 빌드.
  static const bool identityVerificationEnabled =
      bool.fromEnvironment('IDENTITY_ENABLED', defaultValue: true);

  /// 가지 안전결제(에스크로) 자동 임시예치 가능한 최대 금액 (시장 화폐).
  /// 이 금액 이상은 회사 미개입 → 당사자 직거래. 일본은 안전결제 없음.
  /// 백엔드 [ESCROW_MAX_AMOUNT] 와 동기화돼 있어야 함.
  static const int escrowMaxAmountKrw = 30000;
  static const int escrowMaxAmountPhp = 1000;
}

class Categories {
  static const List<CategoryInfo> all = [
    CategoryInfo('all', '전체', '🍆'),
    CategoryInfo('digital', '디지털기기', '📱'),
    CategoryInfo('appliance', '생활가전', '🔌'),
    CategoryInfo('furniture', '가구/인테리어', '🛋️'),
    CategoryInfo('clothing', '의류', '👕'),
    CategoryInfo('beauty', '뷰티/미용', '💄'),
    CategoryInfo('book', '도서/티켓', '📚'),
    CategoryInfo('sports', '스포츠/레저', '⚽'),
    CategoryInfo('hobby', '취미/게임', '🎮'),
    CategoryInfo('kids', '유아동', '🧸'),
    CategoryInfo('pet', '반려동물', '🐶'),
    CategoryInfo('food', '식품', '🥬'),
    CategoryInfo('etc', '기타', '📦'),
  ];

  /// 화면 표시용 카테고리 이름 (서버에는 [CategoryInfo.id] 를 보낸다).
  static String categoryLabel(String value) {
    final l = L10n.current;
    switch (value) {
      case 'all': return l.homeCategoryAll;
      case 'digital': return l.homeCategoryDigital;
      case 'appliance': return l.homeCategoryAppliance;
      case 'furniture': return l.homeCategoryFurniture;
      case 'clothing': return l.homeCategoryClothing;
      case 'beauty': return l.homeCategoryBeauty;
      case 'book': return l.homeCategoryBook;
      case 'sports': return l.homeCategorySports;
      case 'hobby': return l.homeCategoryHobby;
      case 'kids': return l.homeCategoryKids;
      case 'pet': return l.homeCategoryPet;
      case 'food': return l.homeCategoryFood;
      case 'etc': return l.homeCategoryEtc;
    }
    return value;
  }

  static CategoryInfo find(String id) {
    return all.firstWhere(
      (c) => c.id == id,
      orElse: () => all.last,
    );
  }
}

class CategoryInfo {
  final String id;
  /// 한국어 원문 이름 (참고용).
  final String koLabel;
  final String emoji;
  const CategoryInfo(this.id, this.koLabel, this.emoji);

  /// 현재 언어로 표시할 이름.
  String get label => Categories.categoryLabel(id);
}
