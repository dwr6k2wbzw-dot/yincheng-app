// 老闆 2026-11-25：營收頁加 ◀ ▶ 切換月份。這裡測月份範圍（跨年、不能切到未來、最早到哪）和月份列的按鈕
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/theme.dart';
import 'package:yincheng_ops/widgets/month_switcher.dart';

void main() {
  group('RevenueMonths', () {
    test('跨年：1 月往前是前一年 12 月，12 月往後是隔年 1 月', () {
      final min = DateTime(2025, 1), max = DateTime(2027, 6);
      expect(RevenueMonths.shift(DateTime(2026, 1), -1, min: min, max: max), DateTime(2025, 12));
      expect(RevenueMonths.shift(DateTime(2025, 12), 1, min: min, max: max), DateTime(2026, 1));
    });

    test('不能切到未來：最晚是營業日今天的月份，再往後停在本月', () {
      final today = DateTime(2026, 11, 25);
      final max = RevenueMonths.latest(today);
      expect(max, DateTime(2026, 11));
      expect(RevenueMonths.shift(max, 1, min: RevenueMonths.floor, max: max), DateTime(2026, 11));
      // 12 月 31 日：本月是 12 月，不能切到隔年 1 月
      final dec = RevenueMonths.latest(DateTime(2026, 12, 31));
      expect(RevenueMonths.shift(dec, 1, min: RevenueMonths.floor, max: dec), DateTime(2026, 12));
    });

    test('預設：平常是本月；1 號還沒有資料，看上個月（1 月 1 日看前一年 12 月）', () {
      expect(RevenueMonths.initial(DateTime(2026, 11, 25)), DateTime(2026, 11));
      expect(RevenueMonths.initial(DateTime(2026, 11, 2)), DateTime(2026, 11));
      expect(RevenueMonths.initial(DateTime(2026, 11, 1)), DateTime(2026, 10));
      expect(RevenueMonths.initial(DateTime(2027, 1, 1)), DateTime(2026, 12));
    });

    test('最早：至少到 2025-01；資料更早就到資料最早的月份', () {
      expect(RevenueMonths.earliest(null), DateTime(2025, 1));
      expect(RevenueMonths.earliest(DateTime(2026, 3, 9)), DateTime(2025, 1));
      expect(RevenueMonths.earliest(DateTime(2024, 7, 15)), DateTime(2024, 7));
      expect(RevenueMonths.shift(DateTime(2025, 1), -1, min: DateTime(2025, 1), max: DateTime(2026, 11)), DateTime(2025, 1));
    });
  });

  group('MonthSwitcher', () {
    Future<List<DateTime>> pump(WidgetTester tester, DateTime month, {DateTime? min, DateTime? max}) async {
      final changes = <DateTime>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(StorePalette.gold),
        home: Scaffold(
          body: MonthSwitcher(month: month, min: min ?? DateTime(2025, 1), max: max ?? DateTime(2026, 11), onChanged: changes.add),
        ),
      ));
      return changes;
    }

    IconButton btn(WidgetTester tester, String tip) =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, tip == '上個月' ? Icons.chevron_left : Icons.chevron_right));

    testWidgets('顯示年月；1 月按 ◀ 換成前一年 12 月', (tester) async {
      final changes = await pump(tester, DateTime(2026, 1));
      expect(find.text('2026 年 1 月'), findsOneWidget);
      await tester.tap(find.byTooltip('上個月'));
      expect(changes, [DateTime(2025, 12)]);
      await tester.tap(find.byTooltip('下個月'));
      expect(changes.last, DateTime(2026, 2));
    });

    testWidgets('本月時 ▶ 不能按（不能切到未來）', (tester) async {
      final changes = await pump(tester, DateTime(2026, 11));
      expect(btn(tester, '下個月').onPressed, isNull);
      expect(btn(tester, '上個月').onPressed, isNotNull);
      await tester.tap(find.byTooltip('下個月'));
      expect(changes, isEmpty);
    });

    testWidgets('最早的月份時 ◀ 不能按', (tester) async {
      final changes = await pump(tester, DateTime(2025, 1));
      expect(btn(tester, '上個月').onPressed, isNull);
      await tester.tap(find.byTooltip('上個月'));
      expect(changes, isEmpty);
    });
  });
}
