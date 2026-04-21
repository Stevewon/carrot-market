/// App-wide constants
class AppConfig {
  /// Backend server URL. Override with --dart-define=API_BASE=...
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:3001', // Android emulator -> host localhost
  );

  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://10.0.2.2:3001',
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
