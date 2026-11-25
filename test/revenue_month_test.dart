// 老闆 2026-11-25：營收頁加 ◀ ▶ 切換月份，每日清單和品項累計跟著換成那個月；星期平均維持以今天為準
// 數字都是測試用的假資料
// 營收頁要用 AppScope，而 AppState 會載入網頁專用的 load_timing（dart:js_interop），所以只能在瀏覽器跑：
//   flutter test --platform chrome test/revenue_month_test.dart
// 月份範圍（跨年、不能切到未來）的純計算另外在 test/month_switcher_test.dart，CI 一般 flutter test 會跑
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/main.dart';
import 'package:yincheng_ops/screens/revenue_screen.dart';
import 'package:yincheng_ops/theme.dart';
import 'package:yincheng_ops/widgets/format.dart';
import 'package:yincheng_ops/widgets/month_switcher.dart';

final _today = bizToday();
final _init = RevenueMonths.initial(_today);
final _prev = DateTime(_init.year, _init.month - 1);
final _dec = DateTime(_init.year - 1, 12);

class _Repo extends DemoRepository {
  final ranges = <String>[]; // 每次查每日營收的期間
  final itemMonths = <String>[]; // 每次查品項累計的月份
  // 來客 0：星期平均不顯示客單，金額大字在畫面上只出現在每日清單
  final entries = [
    RevenueEntry(id: 'a', bizDate: DateTime(_init.year, _init.month, 1), cash: 1111, guests: 0, source: 'import'),
    RevenueEntry(id: 'b', bizDate: DateTime(_prev.year, _prev.month, 15), cash: 2222, guests: 0, source: 'import'),
    RevenueEntry(id: 'c', bizDate: DateTime(_dec.year, 12, 20), cash: 3333, guests: 0, source: 'import'),
  ];

  static String _d(DateTime d) => '${d.year}-${d.month}-${d.day}';

  @override
  Future<List<RevenueEntry>> revenueEntriesBetween(String storeId, DateTime from, DateTime to) async {
    ranges.add('${_d(from)}~${_d(to)}');
    return [
      for (final e in entries)
        if (!e.bizDate.isBefore(from) && !e.bizDate.isAfter(to)) e
    ]..sort((a, b) => b.bizDate.compareTo(a.bizDate));
  }

  @override
  Future<DateTime?> firstRevenueDate(String storeId) async => DateTime(2025, 3, 1);

  @override
  Future<Set<DateTime>> ichefDays(String storeId, {int limit = 120, DateTime? from, DateTime? to}) async => {
        for (final e in entries)
          if ((from == null || !e.bizDate.isBefore(from)) && (to == null || !e.bizDate.isAfter(to))) e.bizDate
      };

  @override
  Future<List<ItemSale>> monthItemSales(String storeId, DateTime month) async {
    itemMonths.add('${month.year}-${month.month}');
    return [ItemSale(name: '品項${month.year}-${month.month}', qty: 1, amount: 100, listAmount: 100)];
  }

  @override
  Future<List<ItemSale>> itemSales(String storeId, DateTime bizDate) async => const [];
}

String _label(DateTime m) => '${m.year} 年 ${m.month} 月';
String _monthEnd(DateTime m) {
  final e = DateTime(m.year, m.month + 1, 0);
  return '${e.year}-${e.month}-${e.day}';
}

Future<_Repo> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  final m = Membership(storeId: 'yc', storeName: '隱城', role: Role.owner, displayName: '測試');
  await tester.pumpWidget(AppScope(
    state: AppState(repo),
    child: MaterialApp(theme: buildTheme(StorePalette.gold), home: RevenueScreen(membership: m)),
  ));
  await tester.pumpAndSettle();
  return repo;
}

IconButton _arrow(WidgetTester tester, IconData icon) => tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW'));

  testWidgets('預設本月；只列這個月的每日營收；不能切到未來', (tester) async {
    final repo = await _pump(tester);
    expect(find.text(_label(_init)), findsOneWidget);
    expect(find.text(ntd(1111)), findsOneWidget);
    expect(find.text(ntd(2222)), findsNothing);
    expect(repo.ranges, contains('${_init.year}-${_init.month}-1~${_monthEnd(_init)}'));
    expect(repo.itemMonths, ['${_init.year}-${_init.month}']);
    expect(find.text('${_init.month} 月銷售品項累計'), findsOneWidget);
    expect(_init, DateTime(_today.year, _today.month), reason: '1 號也是本月（老闆 2026-11-25）');
    expect(_arrow(tester, Icons.chevron_right).onPressed, isNull);
  });

  testWidgets('◀ 切到上個月：每日清單、品項累計換成那個月；星期平均仍查近 12 週', (tester) async {
    final repo = await _pump(tester);
    final weekQuery = repo.ranges.where((r) => r != '${_init.year}-${_init.month}-1~${_monthEnd(_init)}').single;
    repo.ranges.clear();
    await tester.tap(find.byTooltip('上個月'));
    await tester.pumpAndSettle();
    expect(find.text(_label(_prev)), findsOneWidget);
    expect(find.text(ntd(2222)), findsOneWidget);
    expect(find.text(ntd(1111)), findsNothing);
    expect(find.text('${_prev.month} 月銷售品項累計'), findsOneWidget);
    expect(repo.itemMonths, ['${_init.year}-${_init.month}', '${_prev.year}-${_prev.month}']); // 每個月只查一次
    expect(repo.ranges, containsAll(['${_prev.year}-${_prev.month}-1~${_monthEnd(_prev)}', weekQuery]));
    expect(find.text('星期平均'), findsOneWidget);
  });

  testWidgets('跨年：一路 ◀ 到前一年 12 月，再 ▶ 回本月', (tester) async {
    await _pump(tester);
    for (var i = 0; i < _init.month; i++) {
      await tester.tap(find.byTooltip('上個月'));
      await tester.pumpAndSettle();
    }
    expect(find.text(_label(_dec)), findsOneWidget);
    expect(find.text(ntd(3333)), findsOneWidget);
    expect(find.text('12 月銷售品項累計'), findsOneWidget);
    for (var i = 0; i < _init.month; i++) {
      await tester.tap(find.byTooltip('下個月'));
      await tester.pumpAndSettle();
    }
    expect(find.text(_label(_init)), findsOneWidget);
    expect(find.text(ntd(1111)), findsOneWidget);
  });

  testWidgets('沒有營收的月份顯示「沒有營收紀錄」，月份列還在可以切回來', (tester) async {
    await _pump(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('上個月'));
      await tester.pumpAndSettle();
    }
    final m = DateTime(_init.year, _init.month - 2);
    if (m != _dec) {
      expect(find.text('${m.year} 年 ${m.month} 月沒有營收紀錄'), findsOneWidget);
    }
    expect(find.byTooltip('下個月'), findsOneWidget);
  });

  testWidgets('下拉更新留在目前看的月份並重新查那個月', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.byTooltip('上個月'));
    await tester.pumpAndSettle();
    repo.ranges.clear();
    repo.itemMonths.clear();
    // 瀏覽器測試的平台跟著電腦（macOS 是彈性捲動），模擬手指下拉不穩定，直接觸發下拉更新
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pumpAndSettle();
    expect(find.text(_label(_prev)), findsOneWidget);
    expect(repo.ranges, contains('${_prev.year}-${_prev.month}-1~${_monthEnd(_prev)}'));
    expect(repo.itemMonths, ['${_prev.year}-${_prev.month}']);
  });

  testWidgets('切換店家：月份停在原本看的月份，兩家店對照（老闆 2026-11-25）', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final repo = _Repo(); // 兩家店都回同一批假營收（示範資料的小城外沒有營收，畫面不會出現月份列）
    final state = AppState(repo);
    await tester.pumpWidget(YinchengApp(state: state));
    await tester.pump();
    await tester.runAsync(() => repo.signIn('owner@x', 'x'));
    await _settle(tester);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('營收')));
    await _settle(tester);
    expect(find.text(_label(_init)), findsOneWidget);
    await tester.tap(find.byTooltip('上個月'));
    await _settle(tester);
    expect(find.text(_label(_prev)), findsOneWidget);

    Membership store(String id) => state.memberships.firstWhere((m) => m.storeId == id);
    await tester.runAsync(() => state.switchStore(store('xc')));
    await _settle(tester);
    expect(tester.widget<RevenueScreen>(find.byType(RevenueScreen)).membership.storeId, 'xc');
    expect(find.text(_label(_prev)), findsOneWidget);
    expect(find.text(_label(_init)), findsNothing);

    // 在小城外再往前切一個月，切回隱城也停在那個月
    final prev2 = DateTime(_prev.year, _prev.month - 1);
    await tester.tap(find.byTooltip('上個月'));
    await _settle(tester);
    await tester.runAsync(() => state.switchStore(store('yc')));
    await _settle(tester);
    expect(tester.widget<RevenueScreen>(find.byType(RevenueScreen)).membership.storeId, 'yc');
    expect(find.text(_label(prev2)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(seconds: 90)));
}

/// 整個 App 有載入動畫，不能用 pumpAndSettle 等到全部停
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
