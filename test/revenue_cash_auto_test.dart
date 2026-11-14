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
  Completer<void>? readGate; // 模擬讀紀錄很慢
  Completer<void>? saveGate; // 模擬存檔很慢
  final saves = <RevenueEntry>[]; // 每次送出的，依序
  final day = DateTime(2026, 1, 5); // A 日
  final dayB = DateTime(2026, 1, 6); // B 日：已有自己的紀錄 b1
  late RevenueEntry rowB = RevenueEntry(
      id: 'b1', bizDate: dayB, cash: 2000, creditCard: 0, guests: 3, drinks: 3000, food: 0, source: 'app');

  @override
  Future<DateTime> businessDate(String storeId) async => day;
  @override
  Future<RevenueEntry?> revenueEntryFor(String storeId, DateTime bizDate) async {
    final gate = readGate;
    if (gate != null) await gate.future;
    if (readFails) throw Exception('read timeout');
    if (DateUtils.isSameDay(bizDate, dayB)) return rowB;
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
    final gate = saveGate;
    if (gate != null) await gate.future;
    saves.add(e);
    if (DateUtils.isSameDay(e.bizDate, dayB)) {
      saved = e;
      rowB = e;
      return;
    }
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

/// 打開日期選擇，選 B 日（1/6）
Future<void> _pickDayB(WidgetTester tester) async {
  await tester.tap(find.text('營業日'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('6')));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// 每筆送出的 id 都要屬於它自己那天（A 日：r1／new1，B 日：b1），不能拿 A 日的 id 寫 B 日的欄位
void _expectNoCrossDay(_Repo repo) {
  for (final e in repo.saves) {
    final isB = DateUtils.isSameDay(e.bizDate, repo.dayB);
    expect(e.id == 'b1' || (isB && e.id == null), isB, reason: '送出 id=${e.id}、營業日=${e.bizDate}：跨日混寫');
  }
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

  testWidgets('A 日新增後讀回失敗，重存時讀回很慢：不能切到 B 日，回應回來後只更新 A 日那筆', (tester) async {
    final repo = await _open(tester, store: '小城外', ichef: 3000, empty: true);
    await tester.enterText(_field('咖啡'), '500');
    await tester.enterText(_field('酒水'), '3000');
    await tester.enterText(_field('來客數'), '2');
    repo.readFails = true;
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(repo.inserts, 1);

    // 重存：先讀回剛新增那筆，這次讀回很慢
    repo
      ..readFails = false
      ..readGate = Completer<void>();
    await tester.enterText(_field('咖啡'), '600');
    await tester.tap(find.text('儲存'));
    await tester.pump();
    // 等候中想切到 B 日：不能開日期選擇
    await tester.tap(find.text('營業日'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DatePickerDialog), findsNothing, reason: '儲存／讀回中換日，A 日的回應會套到 B 日畫面');

    repo.readGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.inserts, 1);
    expect(repo.saves.last.id, 'new1');
    expect(DateUtils.isSameDay(repo.saves.last.bizDate, repo.day), isTrue);
    expect(repo.saves.last.coffee, 600, reason: '用 A 日畫面上的數字');
    expect(repo.rowB.cash, 2000, reason: 'B 日那筆沒被動到');
    _expectNoCrossDay(repo);
  });

  testWidgets('存檔很慢：等候中不能換日，也不能離開；存完列表照常重新載入', (tester) async {
    final (repo, results) = await _openFromList(tester, _Repo(3000));
    repo.saveGate = Completer<void>();
    await tester.enterText(_field('咖啡'), '600');
    await tester.tap(find.text('更新'));
    await tester.pump();
    await tester.tap(find.text('營業日'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DatePickerDialog), findsNothing);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RevenueFormScreen), findsOneWidget, reason: '還不知道有沒有寫進去，不能先離開');
    expect(find.text('正在儲存，請稍候'), findsOneWidget);
    expect(results, isEmpty);

    repo.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(RevenueFormScreen), findsNothing);
    expect(results, [true]);
    expect(repo.saves.single.id, 'r1');
    _expectNoCrossDay(repo);
  });

  testWidgets('重試 iCHEF 中不能換日', (tester) async {
    final repo = await _open(tester, store: '小城外', ichef: 3000, fails: true);
    repo
      ..ichefFails = false
      ..ichefGate = Completer<void>();
    await tester.tap(find.text('重試'));
    await tester.pump();
    await tester.tap(find.text('營業日'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DatePickerDialog), findsNothing);
    repo.ichefGate!.complete();
    await tester.pumpAndSettle();
    expect(_autoCashText('3,000'), findsOneWidget);
  });

  testWidgets('切到 B 日：B 日用自己的紀錄更新，A 日那筆不受影響', (tester) async {
    final repo = await _open(tester, store: '小城外', ichef: 2700);
    await _pickDayB(tester);
    expect(tester.widget<TextField>(_field('酒水')).controller!.text, '3000', reason: '帶入 B 日自己的紀錄');
    await tester.enterText(_field('拉麵'), '300');
    await tester.enterText(_field('酒水'), '2700'); // 假資料：現金 2700＋300＝酒水 2700＋拉麵 300
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(repo.saves.single.id, 'b1');
    expect(repo.saves.single.cash, 3000);
    expect(repo.stored, isNull, reason: 'A 日那筆沒被動到');
    _expectNoCrossDay(repo);
  });

  testWidgets('打開表單還在讀資料就離開：之後回來的回應不會出錯', (tester) async {
    final repo = _Repo(3000)..readGate = Completer<void>();
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RevenueFormScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RevenueFormScreen), findsNothing);
    repo.readGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(results, [null]);
    expect(repo.saves, isEmpty);
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
