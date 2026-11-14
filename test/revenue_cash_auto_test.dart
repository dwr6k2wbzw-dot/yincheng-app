// 老闆 2026-11-14：小城外 App 手動輸入的咖啡、拉麵，要自動加進現金（iCHEF 現金＋咖啡＋拉麵）
// 數字都是測試用的假資料
// 表單要用 AppScope，而 AppState 會載入網頁專用的 load_timing（dart:js_interop），所以只能在瀏覽器跑：
//   flutter test --platform chrome test/revenue_cash_auto_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/screens/revenue_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  _Repo(this.ichef);
  final double? ichef;
  RevenueEntry? saved;
  final day = DateTime(2026, 1, 5);

  @override
  Future<DateTime> businessDate(String storeId) async => day;
  @override
  Future<RevenueEntry?> revenueEntryFor(String storeId, DateTime bizDate) async => RevenueEntry(
      id: 'r1', bizDate: day, cash: 3000, creditCard: 5000, guests: 6, drinks: 8000, food: 0, source: 'app');
  @override
  Future<double?> ichefCash(String storeId, DateTime bizDate) async => ichef;
  @override
  Future<void> saveRevenueEntry(String storeId, RevenueEntry e) async => saved = e;
}

Future<_Repo> _open(WidgetTester tester, {required String store, double? ichef}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo(ichef);
  final m = Membership(storeId: 's', storeName: store, role: Role.staff, displayName: '測試');
  await tester.pumpWidget(AppScope(
    state: AppState(repo),
    child: MaterialApp(theme: buildTheme(StorePalette.gold), home: RevenueFormScreen(membership: m)),
  ));
  await tester.pumpAndSettle();
  return repo;
}

Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW'));

  testWidgets('小城外有 iCHEF：現金自動＝iCHEF 現金＋咖啡＋拉麵，改咖啡、清空都跟著變', (tester) async {
    final repo = await _open(tester, store: '小城外', ichef: 3000);
    expect(find.byKey(const Key('auto-cash')), findsOneWidget);
    expect(_field('現金'), findsNothing, reason: '現金不用手動填');

    await tester.enterText(_field('咖啡'), '800');
    await tester.enterText(_field('拉麵'), '450');
    await tester.pump();
    expect(find.descendant(of: find.byKey(const Key('auto-cash')), matching: find.text('4,250')), findsOneWidget);

    await tester.enterText(_field('咖啡'), '');
    await tester.enterText(_field('拉麵'), '');
    await tester.pump();
    expect(find.descendant(of: find.byKey(const Key('auto-cash')), matching: find.text('3,000')), findsOneWidget);

    await tester.enterText(_field('咖啡'), '600');
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(repo.saved?.cash, 3600, reason: '存的是 iCHEF 現金＋咖啡，不會在原本 3000 上再加');
    expect(repo.saved?.coffee, 600);
    expect(repo.saved?.creditCard, 5000, reason: '刷卡不受影響');
  });

  testWidgets('小城外還沒有 iCHEF：現金照舊手動填', (tester) async {
    await _open(tester, store: '小城外');
    expect(find.byKey(const Key('auto-cash')), findsNothing);
    expect(_field('現金'), findsOneWidget);
  });

  testWidgets('隱城：不自動算，現金照舊', (tester) async {
    await _open(tester, store: '隱城', ichef: 3000);
    expect(find.byKey(const Key('auto-cash')), findsNothing);
    expect(_field('現金'), findsOneWidget);
  });
}
