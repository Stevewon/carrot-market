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

  static CategoryInfo find(String id) {
    return all.firstWhere(
      (c) => c.id == id,
      orElse: () => all.last,
    );
  }
}

class CategoryInfo {
  final String id;
  final String label;
  final String emoji;
  const CategoryInfo(this.id, this.label, this.emoji);
}
