import 'package:flutter/material.dart';

/// 依 PRD 畫面樣式：深色底、紫色主色
class AppColors {
  static const bg = Color(0xFF0F1115);
  static const card = Color(0xFF1A1D24);
  static const cardHigh = Color(0xFF232733);
  static const primary = Color(0xFF6C63FF);
  static const good = Color(0xFF3DDC97);
  static const warn = Color(0xFFFFB547);
  static const bad = Color(0xFFFF5C6C);
  static const muted = Color(0xFF9AA0AE);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.dark)
        .copyWith(primary: AppColors.primary, surface: AppColors.card),
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg, elevation: 0, centerTitle: false),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
    ),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: AppColors.card, indicatorColor: Color(0x336C63FF)),
  );
}
