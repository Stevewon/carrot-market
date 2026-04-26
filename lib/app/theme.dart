import 'package:flutter/material.dart';

/// Eggplant brand colors (purple theme)
class EggplantColors {
  static const Color primary = Color(0xFF9333EA); // eggplant-600
  static const Color primaryDark = Color(0xFF7E22CE); // eggplant-700
  static const Color primaryLight = Color(0xFFC084FC); // eggplant-400
  static const Color accent = Color(0xFF22C55E); // green leaf
  static const Color background = Color(0xFFFAF5FF); // eggplant-50
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color border = Color(0xFFE5E7EB);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
}

final ThemeData eggplantTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'Pretendard',
  colorScheme: ColorScheme.fromSeed(
    seedColor: EggplantColors.primary,
    primary: EggplantColors.primary,
    brightness: Brightness.light,
  ),
  scaffoldBackgroundColor: Colors.white,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: EggplantColors.textPrimary,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      color: EggplantColors.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: EggplantColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: EggplantColors.primary,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: EggplantColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: EggplantColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: EggplantColors.primary, width: 2),
    ),
    hintStyle: const TextStyle(color: EggplantColors.textTertiary),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: EggplantColors.border),
    ),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Colors.white,
    selectedItemColor: EggplantColors.primary,
    unselectedItemColor: EggplantColors.textTertiary,
    type: BottomNavigationBarType.fixed,
    showUnselectedLabels: true,
    elevation: 8,
  ),
  // 태블릿/폴드 가로 모드에서 모달 바텀시트가 화면 전체로 늘어나지 않도록 max-width 600dp 로 제한.
  // (모바일 폰에서는 화면이 600dp 보다 작으므로 영향 없음.)
  // 다이얼로그(AlertDialog/Dialog)는 Flutter 기본값이 이미 가로 패딩을 적용하여 가운데 정렬되므로
  // 별도 max-width 처리 불필요.
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    constraints: BoxConstraints(maxWidth: 600),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
  ),
);
