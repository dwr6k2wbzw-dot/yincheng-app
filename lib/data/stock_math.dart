// 盤點的純計算（不碰畫面，可以直接單元測試；老闆 2026-11-13 進貨與庫存改善第一版）
import 'models.dart';

int _daysSince(DateTime d) => bizToday().difference(DateTime(d.year, d.month, d.day)).inDays;

/// 「昨天盤・小明」「6 天前盤」「還沒盤過」
String countAge(LastCount? s, {bool who = true}) {
  if (s == null) return '還沒盤過';
  final n = _daysSince(s.date);
  final when = n <= 0 ? '今天盤' : (n == 1 ? '昨天盤' : '$n 天前盤');
  return !who || (s.by ?? '').isEmpty ? when : '$when・${s.by}';
}

/// 重點品項該盤了沒：每天盤的今天（營業日）還沒盤、每週盤的超過 7 天沒盤
bool isCountDue(Product p, LastCount? s) => switch (p.countCycle) {
      'daily' => s == null || _daysSince(s.date) >= 1,
      'weekly' => s == null || _daysSince(s.date) >= 7,
      _ => false,
    };

/// 很久沒盤（超過兩週）：數字可能不準，用淡色提醒
bool isStaleCount(LastCount? s) => s != null && _daysSince(s.date) > 14;

String cycleLabel(String? c) => switch (c) { 'daily' => '每天盤', 'weekly' => '每週盤', _ => '' };

/// 打數量：可以打小數（3.4＝3 瓶又剩 4 成），四捨五入到 0.1。不合理的回傳 null
double? parseQty(String text) {
  final v = double.tryParse(text.trim());
  if (v == null || v < 0 || v > 9999) return null;
  return (v * 10).round() / 10;
}
