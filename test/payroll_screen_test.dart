// 程式審查 2026-11-15 第 4 項：薪資畫面切月時，舊月份的資料還在畫面上，但不能編輯、列印、發布（避免用新月份去存舊資料）。
// 行銷審閱 2026-11-15 的 8 項畫面修改：不合法時數不試算、不計薪範圍、缺薪率提示、加班費比較、已手動調整、發布彙總、已發布唯讀；
// 手機尺寸（360×780）跑過，版面溢出會讓測試失敗。
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
import 'package:yincheng_ops/widgets/format.dart';

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

  group('行銷審閱修改（手機尺寸 360×780）', () {
    late DemoRepository repo;
    final month = DateTime(bizToday().year, bizToday().month - 1, 1);
    final owner = Membership(storeId: 'yc', storeName: '隱城', role: Role.owner, displayName: '示範');

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = DemoRepository();
    });

    Future<void> phone(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    Future<void> pump(WidgetTester tester, Widget home) async {
      await tester.pumpWidget(AppScope(
          state: AppState(repo), child: MaterialApp(theme: buildTheme(StorePalette.gold), home: home)));
      await tester.pumpAndSettle();
    }

    Future<T> io<T>(WidgetTester tester, Future<T> Function() f) async => (await tester.runAsync(f)) as T;

    // 先回到最上面再往下找（清單是懶載入，捲過頭的項目會被拆掉）
    Future<void> scrollTo(WidgetTester tester, Finder f) async {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }

    testWidgets('老闆：缺薪率提示＋前往員工資料、加班費每人一列、已手動調整、不計薪說明、發布彙總含總額', (tester) async {
      await phone(tester);
      var opened = 0;
      final hourly = await io(tester, () async {
        await repo.signIn('owner@x', 'x');
        await repo.preparePayroll('yc', month);
        final h = (await repo.payrollMonth('yc', month)).firstWhere((r) => r.payType == 'hourly' && r.gross != null);
        await repo.savePayrollEntry('yc', h.personId, month, hours: 10);
        return h;
      });
      await pump(tester, PayrollScreen(membership: owner, attendanceEnabled: true, onOpenStaff: () async => opened++));

      // 4. 缺薪率：總額寫「待補齊薪資資料」，另列人數與名字，可前往員工資料
      expect(find.text('待補齊薪資資料'), findsOneWidget);
      expect(find.text('算不出來'), findsNothing);
      expect(find.text('1 人缺少薪率，還不能發布'), findsOneWidget);
      await tester.tap(find.text('前往員工資料'));
      await tester.pumpAndSettle();
      expect(opened, 1);

      // 5. 加班費提醒：每個偏低的人一列，目前設定與依法比較（元／小時）
      expect(find.text('加班費可能低於勞基法第 24 條（元／小時）'), findsOneWidget);
      expect(find.text('目前設定 200'), findsWidgets);
      expect(find.textContaining('依法比較：前 2 小時 '), findsWidgets);

      // 6. 手動改過的時數：「已手動調整」標籤，原始帶入放下一行
      final row = find.widgetWithText(ListTile, hourly.name);
      await scrollTo(tester, row);
      expect(find.descendant(of: row, matching: find.text('已手動調整')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('原始帶入 ${_h(hourly.autoHours!)} 小時')), findsOneWidget);
      expect(find.textContaining('手動改，'), findsNothing);

      // 2. 不計薪確認視窗：寫清楚是員工層級、影響之後每個月、怎麼恢復
      final noRate = find.widgetWithText(ListTile, '新來的（示範）');
      await scrollTo(tester, noRate);
      await tester.tap(noRate);
      await tester.pumpAndSettle();
      expect(find.textContaining('是這個員工的設定，不只這個月：之後每個還沒發布的月份都不會帶入他的薪資'), findsOneWidget);
      expect(find.textContaining('要恢復：回到薪資清單點他的名字，按「取消不計薪」'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '設為不計薪'));
      await tester.pumpAndSettle();

      // 7. 發布確認：店別、年月、計薪人數、不計薪人數；老闆看得到總額
      final report = await io(tester, () => repo.payrollReport('yc', month));
      await scrollTo(tester, find.text('發布給員工'));
      await tester.tap(find.text('發布給員工'));
      await tester.pumpAndSettle();
      expect(find.text('店別：隱城'), findsOneWidget);
      expect(find.text('年月：${month.year} 年 ${month.month} 月'), findsOneWidget);
      expect(find.text('計薪人數：${report.people} 人'), findsOneWidget);
      expect(find.text('不計薪人數：1 人'), findsOneWidget);
      expect(find.text('薪資總額：${ntd(report.total!)}'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('個人薪資：時數不合法不試算、不能存；改回合法才顯示實發', (tester) async {
      await phone(tester);
      final h = await io(tester, () async {
        await repo.signIn('owner@x', 'x');
        await repo.preparePayroll('yc', month);
        return (await repo.payrollMonth('yc', month)).firstWhere((r) => r.payType == 'hourly' && r.gross != null);
      });
      await pump(tester, PayrollEditScreen(membership: owner, month: month, row: h));
      await tester.enterText(find.widgetWithText(TextField, '上班時數'), '73.52');
      await tester.pump();
      expect(find.text('實發金額：時數格式待修正，暫不計算'), findsOneWidget);
      expect(find.textContaining('實發金額 \$'), findsNothing);
      expect(find.textContaining('14,704'), findsNothing); // 200 × 73.52 不該出現
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '儲存')).onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, '上班時數'), '73.5');
      await tester.pump();
      expect(find.text('實發金額：時數格式待修正，暫不計算'), findsNothing);
      expect(find.textContaining('實發金額 \$'), findsOneWidget);
    });

    testWidgets('已發布的個人明細：唯讀文字、沒有輸入框、保留「已發布，無法編輯」', (tester) async {
      await phone(tester);
      final h = await io(tester, () async {
        await repo.signIn('owner@x', 'x');
        await repo.preparePayroll('yc', month);
        await repo.setPayrollExempt('yc', 'demo-no-rate', true);
        await repo.publishPayroll('yc', month);
        return (await repo.payrollMonth('yc', month)).firstWhere((r) => r.payType == 'hourly' && r.gross != null);
      });
      expect(h.editable, isFalse);
      await pump(tester, PayrollEditScreen(membership: owner, month: month, row: h));
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('已發布，無法編輯'), findsOneWidget);
      expect(find.text('上班時數'), findsOneWidget);
      expect(find.text(ntd(h.gross!)), findsOneWidget);
      expect(find.text('列印／存成 PDF'), findsOneWidget);
    });

    testWidgets('店長：看不到自己那一列與總額；發布彙總不顯示總額、不能設不計薪', (tester) async {
      await phone(tester);
      final self = await io(tester, () async {
        await repo.signIn('owner@x', 'x');
        await repo.setPayrollExempt('yc', 'demo-no-rate', true);
        await repo.signIn('manager@x', 'x');
        await repo.preparePayroll('yc', month);
        return (await repo.payrollMonth('yc', month)).first;
      });
      final mgr = Membership(storeId: 'yc', storeName: '隱城', role: Role.manager, displayName: '示範');
      await pump(tester, PayrollScreen(membership: mgr, attendanceEnabled: true));
      expect(find.textContaining('不含你自己那一列，看不到總計和成本率'), findsOneWidget);
      expect(find.text('待補齊薪資資料'), findsNothing);
      final selfRow = find.widgetWithText(ListTile, self.name);
      expect(find.descendant(of: selfRow, matching: find.text('你自己的薪資由老闆處理，這裡看不到')), findsOneWidget);
      expect(tester.widget<ListTile>(selfRow).onTap, isNull);
      await scrollTo(tester, find.text('發布給員工'));
      await tester.tap(find.text('發布給員工'));
      await tester.pumpAndSettle();
      expect(find.text('店別：隱城'), findsOneWidget);
      expect(find.textContaining('薪資總額'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });
  });
}

String _h(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
