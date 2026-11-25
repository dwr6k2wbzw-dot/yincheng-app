import 'package:flutter/material.dart';

import '../theme.dart';

/// 營收頁的月份範圍（老闆 2026-11-25）：純計算，可直接單元測試
class RevenueMonths {
  RevenueMonths._();

  /// 登記營收的日期選擇器從 2025 年開始，月份至少能切到 2025-01
  static final floor = DateTime(2025, 1);

  /// 最晚：營業日今天的月份（不能切到未來）
  static DateTime latest(DateTime today) => DateTime(today.year, today.month);

  /// 預設：到昨天為止的月份（1 號看上個月，跟「銷售品項累計」原本一樣，1 號當天還沒有資料）
  static DateTime initial(DateTime today) {
    final y = DateTime(today.year, today.month, today.day - 1);
    return DateTime(y.year, y.month);
  }

  /// 最早：最早一筆營收的月份和 2025-01 取比較早的
  static DateTime earliest(DateTime? firstEntry) {
    if (firstEntry == null) return floor;
    final m = DateTime(firstEntry.year, firstEntry.month);
    return m.isBefore(floor) ? m : floor;
  }

  /// 往前／往後切 [delta] 個月，超出範圍就停在邊界
  static DateTime shift(DateTime month, int delta, {required DateTime min, required DateTime max}) {
    final m = DateTime(month.year, month.month + delta);
    if (m.isBefore(min)) return min;
    if (m.isAfter(max)) return max;
    return m;
  }
}

/// ◀ yyyy 年 M 月 ▶：跟總覽（小城外）、進貨、班表、薪資同一種寫法；到邊界時箭頭變灰不能按
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.min, required this.max, required this.onChanged});
  final DateTime month;
  final DateTime min;
  final DateTime max;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final canPrev = month.isAfter(min);
    final canNext = month.isBefore(max);
    return Row(children: [
      IconButton(
          tooltip: '上個月',
          onPressed: canPrev ? () => onChanged(RevenueMonths.shift(month, -1, min: min, max: max)) : null,
          icon: const Icon(Icons.chevron_left)),
      Expanded(
        child: Text('${month.year} 年 ${month.month} 月', textAlign: TextAlign.center, style: const TextStyle(fontSize: AppType.title)),
      ),
      IconButton(
          tooltip: '下個月',
          onPressed: canNext ? () => onChanged(RevenueMonths.shift(month, 1, min: min, max: max)) : null,
          icon: const Icon(Icons.chevron_right)),
    ]);
  }
}
