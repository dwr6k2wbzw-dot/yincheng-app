// 程式審查 2026-11-15 第 4 項：薪資畫面切月時，舊月份的資料還在畫面上，但不能編輯、列印、發布（避免用新月份去存舊資料）。
// 人名、金額都是示範資料（虛構）。
// 畫面會載入網頁專用的程式（列印、載入速度），要用瀏覽器跑：
//   flutter test --platform chrome test/payroll_screen_test.dart
@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/payroll.dart';
import 'package:yincheng_ops/screens/payroll_screen.dart';
import 'package:yincheng_ops/theme.dart';

/// 指定月份的清單會卡住，直到測試放行
class _SlowRepo extends DemoRepository {
  DateTime? slowMonth;
  final gate = Completer<void>();
  @override
  Future<List<PayrollRow>> payrollMonth(String storeId, DateTime month) async {
    if (month == slowMonth) await gate.future;
    return super.payrollMonth(storeId, month);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW'));

  testWidgets('切月載入中：顯示「載入中」、所有操作停用；載入完才換成新月份', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _SlowRepo();
    final shown = DateTime(bizToday().year, bizToday().month - 1, 1); // 畫面預設上個月
    final prev = DateTime(shown.year, shown.month - 1, 1);
    await tester.runAsync(() async {
      await repo.signIn('owner@x', 'x');
      await repo.preparePayroll('yc', shown);
    });
    repo.slowMonth = prev;
    final m = Membership(storeId: 'yc', storeName: '隱城', role: Role.owner, displayName: '示範');
    await tester.pumpWidget(AppScope(
        state: AppState(repo),
        child: MaterialApp(
            theme: buildTheme(StorePalette.gold), home: Scaffold(body: PayrollScreen(membership: m, attendanceEnabled: true)))));
    await tester.pumpAndSettle();

    ButtonStyleButton btn(String label) =>
        tester.widget<ButtonStyleButton>(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()).first);
    final rowTitle = find.widgetWithText(ListTile, (await tester.runAsync(() => repo.payrollMonth('yc', shown)))!.first.name);

    expect(find.textContaining('${shown.year} 年 ${shown.month} 月・'), findsOneWidget);
    expect(btn('列印全部薪資單').onPressed, isNotNull);
    expect(btn('重新帶入').onPressed, isNotNull);
    expect(tester.widget<ListTile>(rowTitle).onTap, isNotNull);
    // 應計薪名單缺人：列出名字、不能發布
    expect(find.textContaining('新來的（示範）'), findsWidgets);
    expect(btn('發布給員工').onPressed, isNull);

    await tester.tap(find.byTooltip('上個月'));
    await tester.pump();
    // 還在載入上個月：畫面留著原本月份的資料，但全部停用
    expect(find.textContaining('載入 ${prev.year} 年 ${prev.month} 月中'), findsOneWidget);
    expect(find.textContaining('${shown.year} 年 ${shown.month} 月・'), findsOneWidget);
    expect(btn('列印全部薪資單').onPressed, isNull);
    expect(btn('重新帶入').onPressed, isNull);
    expect(btn('發布給員工').onPressed, isNull);
    expect(tester.widget<ListTile>(rowTitle).onTap, isNull);

    repo.gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('載入'), findsNothing);
    expect(find.text('${prev.month} 月薪資還沒建立'), findsOneWidget);
    expect(btn('建立 ${prev.month} 月薪資').onPressed, isNotNull);
  });
}
