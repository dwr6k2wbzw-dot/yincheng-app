// 老闆 2026-11-14：小城外 App 手動輸入的咖啡、拉麵，要自動加進現金（iCHEF 現金＋咖啡＋拉麵）
// 數字都是測試用的假資料
// 表單要用 AppScope，而 AppState 會載入網頁專用的 load_timing（dart:js_interop），所以只能在瀏覽器跑：
//   flutter test --platform chrome test/revenue_cash_auto_test.dart
@TestOn('browser')
library;

import 'dart:async';

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
  double? ichef;
  bool ichefFails = false; // 模擬讀 iCHEF 現金失敗（斷線、權限…）
  double? dbIchef; // 模擬資料庫存檔時用的 iCHEF 現金（存檔前 iCHEF 剛更新）
  RevenueEntry? saved; // App 送出的
  RevenueEntry? stored; // 資料庫實際存的
  bool empty = false; // 這天還沒有紀錄（新增）
  bool readFails = false; // 模擬讀回失敗
  Completer<void>? ichefGate; // 模擬讀 iCHEF 很慢：完成前不回應
  int inserts = 0;
  final day = DateTime(2026, 1, 5);

  @override
  Future<DateTime> businessDate(String storeId) async => day;
  @override
  Future<RevenueEntry?> revenueEntryFor(String storeId, DateTime bizDate) async {
    if (readFails) throw Exception('read timeout');
    return stored ??
        (empty
            ? null
            : RevenueEntry(
                id: 'r1', bizDate: day, cash: 3000, creditCard: 5000, guests: 6, drinks: 8000, food: 0, source: 'app'));
  }

  @override
  Future<double?> ichefCash(String storeId, DateTime bizDate) async {
    final gate = ichefGate;
    if (gate != null) await gate.future;
    if (ichefFails) throw Exception('network down');
    return ichef;
  }

  @override
  Future<void> saveRevenueEntry(String storeId, RevenueEntry e) async {
    // 同一天只能有一筆（資料庫唯一索引）
    if (e.id == null && (stored != null || !empty)) throw Exception('duplicate key value violates unique constraint');
    if (e.id == null) inserts++;
    saved = e;
    final id = e.id ?? 'new1';
    final base = dbIchef;
    stored = base == null
        ? RevenueEntry(
            id: id,
            bizDate: e.bizDate,
            cash: e.cash,
            creditCard: e.creditCard,
            guests: e.guests,
            drinks: e.drinks,
            food: e.food,
            coffee: e.coffee,
            ramen: e.ramen,
            source: e.source)
        : RevenueEntry(
            id: id,
            bizDate: e.bizDate,
            cash: base + e.coffee + e.ramen,
            creditCard: e.creditCard,
            guests: e.guests,
            drinks: e.drinks,
            food: e.food,
            coffee: e.coffee,
            ramen: e.ramen,
            source: e.source);
  }
}

Future<_Repo> _open(WidgetTester tester,
    {required String store, double? ichef, bool fails = false, bool empty = false}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo(ichef)
    ..ichefFails = fails
    ..empty = empty;
  final m = Membership(storeId: 's', storeName: store, role: Role.staff, displayName: '測試');
  await tester.pumpWidget(AppScope(
    state: AppState(repo),
    child: MaterialApp(theme: buildTheme(StorePalette.gold), home: RevenueFormScreen(membership: m)),
  ));
  await tester.pumpAndSettle();
  return repo;
}

/// 從列表打開表單：記下表單關掉時回傳的值（true＝列表要重新載入）
Future<(_Repo, List<bool?>)> _openFromList(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <bool?>[];
  final m = Membership(storeId: 's', storeName: '小城外', role: Role.staff, displayName: '測試');
  await tester.pumpWidget(AppScope(
    state: AppState(repo),
    child: MaterialApp(
      theme: buildTheme(StorePalette.gold),
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                results.add(await Navigator.push<bool>(c, MaterialPageRoute(builder: (_) => RevenueFormScreen(membership: m)))),
            child: const Text('打開'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('打開'));
  await tester.pumpAndSettle();
  return (repo, results);
}

Finder _saveButton() => find.widgetWithText(FilledButton, '更新');
Finder _field(String label) => find.widgetWithText(TextField, label);
Finder _autoCashText(String v) => find.descendant(of: find.byKey(const Key('auto-cash')), matching: find.text(v));

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

  testWidgets('讀 iCHEF 現金失敗：顯示錯誤、不能儲存；重試成功後改成自動算', (tester) async {
    final repo = await _open(tester, store: '小城外', ichef: 3000, fails: true);
    expect(find.byKey(const Key('ichef-error')), findsOneWidget, reason: '失敗不能當成「沒有 iCHEF」');
    expect(find.byKey(const Key('auto-cash')), findsNothing);
    final save = find.widgetWithText(FilledButton, '更新');
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: '讀不到就暫停儲存');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repo.saved, isNull);

    repo.ichefFails = false;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ichef-error')), findsNothing);
    expect(_autoCashText('3,000'), findsOneWidget);
    await tester.enterText(_field('咖啡'), '500');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repo.saved?.cash, 3500);
  });

  testWidgets('重試還是失敗：錯誤留著、仍不能儲存', (tester) async {
    final repo = await _open(tester, store: '小城外', ichef: 3000, fails: true);
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ichef-error')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '更新')).onPressed, isNull);
    expect(repo.saved, isNull);
  });

  testWidgets('存檔後讀回：資料庫用較新的 iCHEF 現金算出不同數字 → 留在這頁顯示實際存的', (tester) async {
    final repo = await _open(tester, store: '小城外', ichef: 3000);
    repo.dbIchef = 3200; // 打開表單後 iCHEF 重送了
    repo.ichef = 3200;
    await tester.enterText(_field('咖啡'), '600');
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(repo.saved?.cash, 3600);
    expect(find.byType(RevenueFormScreen), findsOneWidget, reason: '數字不同不能直接關掉當作成功');
    expect(find.byKey(const Key('saved-check')), findsOneWidget);
    expect(find.textContaining('現金 \$3,800'), findsOneWidget);
    expect(_autoCashText('3,800'), findsOneWidget, reason: '畫面換成資料庫實際存的');
  });

  testWidgets('重試讀取中不能儲存；慢慢讀到後才恢復', (tester) async {
    final repo = await _open(tester, store: '小城外', ichef: 3000, fails: true);
    repo
      ..ichefFails = false
      ..ichefGate = Completer<void>();
    await tester.tap(find.text('重試'));
    await tester.pump();
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull, reason: '重試還沒回來，不能用手動現金存');
    expect(find.byKey(const Key('ichef-error')), findsOneWidget, reason: '讀取中維持「讀不到」，不會當成沒有 iCHEF');
    await tester.tap(_saveButton());
    await tester.pump();
    expect(repo.saved, isNull);

    repo.ichefGate!.complete();
    await tester.pumpAndSettle();
    expect(_autoCashText('3,000'), findsOneWidget);
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();
    expect(repo.saved?.cash, 3000);
  });

  testWidgets('重試讀取中，慢慢回來還是失敗：仍不能儲存', (tester) async {
    final repo = await _open(tester, store: '小城外', ichef: 3000, fails: true);
    repo.ichefGate = Completer<void>();
    await tester.tap(find.text('重試'));
    await tester.pump();
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull);
    repo.ichefGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ichef-error')), findsOneWidget);
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull);
    expect(repo.saved, isNull);
  });

  testWidgets('存檔後數字不同留在這頁：按返回離開，列表要重新載入', (tester) async {
    final (repo, results) = await _openFromList(tester, _Repo(3000)..dbIchef = 3200);
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saved-check')), findsOneWidget);
    expect(repo.stored?.cash, 3200);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(RevenueFormScreen), findsNothing);
    expect(results, [true], reason: '已經寫入，列表不能停在舊數字');
  });

  testWidgets('存檔成功但讀回失敗：按返回離開，列表要重新載入', (tester) async {
    final (repo, results) = await _openFromList(tester, _Repo(3000));
    repo.readFails = true;
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('讀不回存檔結果'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('沒存就按返回：照舊不重新載入', (tester) async {
    final (_, results) = await _openFromList(tester, _Repo(3000));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(results, [null]);
  });

  testWidgets('新增成功但讀回失敗：再按儲存先讀回那筆改成更新，不重複新增', (tester) async {
    final repo = await _open(tester, store: '小城外', ichef: 3000, empty: true);
    expect(find.text('登記營收'), findsOneWidget);
    // 假資料：iCHEF 現金 3000＋咖啡 500＝收款 3500＝酒水 3000＋咖啡 500
    await tester.enterText(_field('咖啡'), '500');
    await tester.enterText(_field('酒水'), '3000');
    await tester.enterText(_field('來客數'), '2');
    repo.readFails = true;
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(repo.inserts, 1);
    expect(find.textContaining('讀不回存檔結果'), findsOneWidget);

    // 讀回還是失敗：不存（不然會再新增一筆撞同日唯一索引）
    repo.saved = null;
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(repo.saved, isNull);
    expect(find.textContaining('避免重複新增'), findsOneWidget);

    // 恢復後：先讀回取得那筆的 id，改成更新
    repo.readFails = false;
    await tester.enterText(_field('咖啡'), '600');
    await tester.enterText(_field('酒水'), '3000');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(repo.inserts, 1, reason: '沒有第二次新增');
    expect(repo.saved?.id, 'new1');
    expect(repo.saved?.coffee, 600, reason: '用畫面上新填的數字，不被讀回的舊值蓋掉');
    expect(repo.stored?.cash, 3600);
  });

  testWidgets('存檔後讀回一致：照常關閉', (tester) async {
    final repo = await _open(tester, store: '小城外', ichef: 3000);
    await tester.enterText(_field('拉麵'), '450');
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(repo.stored?.cash, 3450);
    expect(find.byKey(const Key('saved-check')), findsNothing);
    expect(find.byType(RevenueFormScreen), findsNothing);
  });

  testWidgets('隱城：不自動算，現金照舊', (tester) async {
    await _open(tester, store: '隱城', ichef: 3000);
    expect(find.byKey(const Key('auto-cash')), findsNothing);
    expect(_field('現金'), findsOneWidget);
  });
}
