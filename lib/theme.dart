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

/// 字級（2026-10-29 統一）：全 App 只用這幾種大小，畫面才整齊
/// micro 只給月曆格、時間軸這種很擠的格子用；一般文字最小 caption。
class AppType {
  static const double micro = 10;
  static const double caption = 12; // 補充說明、標籤
  static const double small = 13; // 次要文字、清單副標
  static const double body = 15; // 內文
  static const double title = 17; // 卡片標題、按鈕
  static const double heading = 20; // 區塊大標、重要數字
  static const double display = 26; // 統計數字
  static const double hero = 42; // 總覽最大的營收數字
}

/// 圓角（2026-10-29 統一）：xs 小色塊／進度條、sm 標籤／小按鈕、md 輸入框／按鈕、lg 卡片／面板
class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
}

/// 動態時間：狀態切換一律 180ms、減速曲線，安靜不搶戲
class AppMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Curve curve = Curves.easeOutCubic;
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: p.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.cardHigh,
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)), borderSide: BorderSide.none),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.nav,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.primary.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? p.primary : p.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: AppType.caption,
          color: s.contains(WidgetState.selected) ? p.primary : p.muted,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(color: p.cardHigh, surfaceTintColor: Colors.transparent),
    // 換頁：淡入＋微微上移（取代預設的放大縮小），手機上比較安靜
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: _FadeRiseTransitions(),
      TargetPlatform.iOS: _FadeRiseTransitions(),
      TargetPlatform.macOS: _FadeRiseTransitions(),
      TargetPlatform.windows: _FadeRiseTransitions(),
      TargetPlatform.linux: _FadeRiseTransitions(),
      TargetPlatform.fuchsia: _FadeRiseTransitions(),
    }),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.cardHigh, borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: p.line)),
      textStyle: TextStyle(color: p.text, fontSize: AppType.caption),
      waitDuration: const Duration(milliseconds: 400),
    ),
  );
}

class _FadeRiseTransitions extends PageTransitionsBuilder {
  const _FadeRiseTransitions();
  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final a = CurvedAnimation(parent: animation, curve: AppMotion.curve, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a),
        child: child,
      ),
    );
  }
}
