/// App-wide constants
class AppConfig {
  /// Backend server URL. Override with --dart-define=API_BASE=...
  ///
  /// Default: `http://localhost:3001`
  /// This works with `adb reverse tcp:3001 tcp:3001` which forwards the
  /// emulator's localhost to the host PC's localhost. Bypasses all
  /// Windows firewall / 10.0.2.2 routing issues.
  ///
  /// If you prefer the classic Android emulator approach without adb
  /// reverse, run:
  ///   flutter run --dart-define=API_BASE=http://10.0.2.2:3001 \
  ///              --dart-define=SOCKET_URL=http://10.0.2.2:3001
  /// Or for a real phone on the same Wi-Fi, use your PC's LAN IP:
  ///   flutter run --dart-define=API_BASE=http://192.168.x.x:3001 ...
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:3001',
  );

  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://localhost:3001',
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
