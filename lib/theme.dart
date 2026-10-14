import 'package:flutter/material.dart';

/// 每家店一套配色（老闆 2026-10-14 選定）：
///   小城外＝A「沉穩黑金」：黑底、金色重點
///   隱城＝C「品牌色系」：墨綠底、香檳金重點（顏色取自兩店 logo，老闆 2026-10-14 提供）
class StorePalette {
  const StorePalette({
    required this.style,
    required this.bg,
    required this.card,
    required this.cardHigh,
    required this.line,
    required this.primary,
    required this.onPrimary,
    required this.good,
    required this.warn,
    required this.bad,
    required this.muted,
    required this.text,
    required this.nav,
    required this.hero,
    required this.heroTrack,
    required this.heroMuted,
  });
  final DashboardStyle style;
  final Color bg, card, cardHigh, line, primary, onPrimary, good, warn, bad, muted, text, nav;
  // C 版營收大色塊
  final Color hero, heroTrack, heroMuted;

  // 小城外 logo：純黑底、金色（取自 logo）
  static const gold = StorePalette(
    style: DashboardStyle.gold,
    bg: Color(0xFF0A0A09),
    card: Color(0xFF161512),
    cardHigh: Color(0xFF211E19),
    line: Color(0xFF2B2822),
    primary: Color(0xFFD3B16E),
    onPrimary: Color(0xFF0A0A09),
    good: Color(0xFF7FC8A0),
    warn: Color(0xFFF0A35E),
    bad: Color(0xFFE58A7A),
    muted: Color(0xFF9C968A),
    text: Color(0xFFF2EEE6),
    nav: Color(0xFF100F0D),
    hero: Color(0xFF161512),
    heroTrack: Color(0xFF2B2822),
    heroMuted: Color(0xFF9C968A),
  );

  // 隱城 logo：墨綠底、香檳金線條（取自 logo）
  static const brand = StorePalette(
    style: DashboardStyle.brand,
    bg: Color(0xFF111A16),
    card: Color(0xFF19251F),
    cardHigh: Color(0xFF21302A),
    line: Color(0xFF2A3A33),
    primary: Color(0xFFCDBF98),
    onPrimary: Color(0xFF111A16),
    good: Color(0xFF8CCBA6),
    warn: Color(0xFFE9A866),
    bad: Color(0xFFEE8D80),
    muted: Color(0xFF98A69E),
    text: Color(0xFFEEF0EA),
    nav: Color(0xFF16211C),
    hero: Color(0xFF1D2A23),
    heroTrack: Color(0xFF131D18),
    heroMuted: Color(0xFFBDB9A4),
  );

    /// 老闆 2026-10-14 晚上：隱城也改成黑金（brand 配色保留備用）
  static StorePalette forStore(String? storeName) => gold;
}

enum DashboardStyle { gold, brand }

/// 店家 logo（老闆 2026-10-14 提供，去背成透明 PNG）
String? storeLogo(String? storeName) => switch (storeName) {
      '隱城' => 'assets/logos/yincheng.png',
      '小城外' => 'assets/logos/xcw.png',
      _ => null,
    };

/// 全 App 的顏色；切換店家時由 main.dart 換成該店的配色
class AppColors {
  static StorePalette p = StorePalette.gold;
  static Color get bg => p.bg;
  static Color get card => p.card;
  static Color get cardHigh => p.cardHigh;
  static Color get line => p.line;
  static Color get primary => p.primary;
  static Color get onPrimary => p.onPrimary;
  static Color get good => p.good;
  static Color get warn => p.warn;
  static Color get bad => p.bad;
  static Color get muted => p.muted;
  static Color get text => p.text;
}

/// 數字用等寬數字，上下對齊
const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme(StorePalette p) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(seedColor: p.primary, brightness: Brightness.dark).copyWith(
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.primary,
      surface: p.card,
      onSurface: p.text,
      error: p.bad,
      outlineVariant: p.line,
    ),
    scaffoldBackgroundColor: p.bg,
    dividerColor: p.line,
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(backgroundColor: p.bg, surfaceTintColor: Colors.transparent, elevation: 0, centerTitle: false),
    dividerTheme: DividerThemeData(color: p.line),
    cardTheme: CardThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.cardHigh,
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.nav,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.primary.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? p.primary : p.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 11,
          color: s.contains(WidgetState.selected) ? p.primary : p.muted,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(color: p.cardHigh, surfaceTintColor: Colors.transparent),
  );
}
