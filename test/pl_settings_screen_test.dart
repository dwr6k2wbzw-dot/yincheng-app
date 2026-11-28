// 損益設定畫面（ops 0169，公版）：新店選業態套範本、改科目、手續費率與抬頭。資料都是示範的。
// App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/pl_settings_screen_test.dart
@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/screens/pl_settings_screen.dart';
import 'package:yincheng_ops/theme.dart';

/// 存每月固定支出時先卡住，數被叫了幾次（模擬慢網路連按）。
class _SlowRepo extends DemoRepository {
  int recurringSaves = 0;
  final gate = Completer<void>();
  @override
  Future<void> saveRecurringExpenseItem(
      String storeId, RecurringExpenseItem item,
      {bool isNew = false}) async {
    recurringSaves++;
    await gate.future;
    return super.saveRecurringExpenseItem(storeId, item, isNew: isNew);
  }

  int accountSaves = 0;
  final accountGate = Completer<void>();
  @override
  Future<void> savePlAccount(String storeId, PlAccount account,
      {bool isNew = false}) async {
    accountSaves++;
    await accountGate.future;
    return super.savePlAccount(storeId, account, isNew: isNew);
  }
}

Future<DemoRepository> _open(WidgetTester tester, String storeId,
    [DemoRepository? given]) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = given ?? DemoRepository();
  final m = Membership(
      storeId: storeId, storeName: '示範小館', role: Role.owner, displayName: '示範');
  await tester.pumpWidget(AppScope(
      state: AppState(repo),
      child: MaterialApp(
          theme: buildTheme(StorePalette.gold),
          home: PlSettingsScreen(membership: m))));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('新店：選咖啡廳、看清單、套用後列出科目', (tester) async {
    final repo = await _open(tester, 'demo-new');
    expect(find.text('還沒有會計科目'), findsOneWidget);
    expect(find.text('酒吧'), findsOneWidget);
    await tester.tap(find.text('咖啡廳'));
    await tester.pumpAndSettle();
    expect(find.text('咖啡廳的科目'), findsOneWidget);
    expect(find.text('外送平台抽成'), findsOneWidget);
    await tester.tap(find.text('套用「咖啡廳」'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('會計科目'), findsOneWidget);
    expect(find.text('還沒有會計科目'), findsNothing);
    expect((await repo.plAccounts('demo-new')).length, 16);
  });

  testWidgets('已經有科目的店：不顯示範本；改名存檔', (tester) async {
    final repo = await _open(tester, 'yc');
    expect(find.text('還沒有會計科目'), findsNothing);
    expect(find.text('修繕費'), findsOneWidget);
    await tester.tap(find.text('修繕費'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '修繕費'), '修繕維護費');
    await tester.tap(find.text('儲存').last);
    await tester.pumpAndSettle();
    expect(find.text('修繕維護費'), findsOneWidget);
    expect((await repo.plAccounts('yc')).any((a) => a.name == '修繕維護費'), isTrue);
    // 面板關掉後輸入框等動畫跑完才釋放（畫面裡延後 0.6 秒），讓它跑完再結束
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('手續費率填錯在畫面上說明；填對存起來', (tester) async {
    final repo = await _open(tester, 'demo-new');
    final rate = find.widgetWithText(TextField, '刷卡手續費率');
    await tester.enterText(rate, 'abc');
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('手續費率請填 0～100'), findsOneWidget);
    await tester.enterText(rate, '1.91');
    await tester.enterText(find.widgetWithText(TextField, '損益表抬頭'), '一店');
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();
    expect(await repo.cardFeeRate('demo-new'), closeTo(0.0191, 1e-9));
    expect(await repo.plTitle('demo-new'), '一店');
  });

  testWidgets('新增每月固定支出：送出中連按不會重複新增', (tester) async {
    final repo = _SlowRepo();
    await _open(tester, 'demo-new', repo);
    final before = (await repo.recurringExpenseItems('demo-new')).length;
    await tester.ensureVisible(find.text('新增').last);
    await tester.tap(find.text('新增').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名稱（例：記帳費）'), '記帳費');
    await tester.enterText(find.widgetWithText(TextField, '每月金額'), '3000');
    final save = find.widgetWithText(FilledButton, '儲存').last;
    await tester.tap(save);
    await tester.pump();
    // 送出中：按鈕變「儲存中…」而且按不了
    final busy = find.widgetWithText(FilledButton, '儲存中…');
    expect(busy, findsOneWidget);
    expect(tester.widget<FilledButton>(busy).onPressed, isNull);
    await tester.tap(busy, warnIfMissed: false);
    await tester.pump();
    expect(repo.recurringSaves, 1);
    repo.gate.complete();
    await tester.pumpAndSettle();
    expect(repo.recurringSaves, 1);
    expect((await repo.recurringExpenseItems('demo-new')).length, before + 1);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('每月固定支出儲存中：按返回、點外面都關不掉；硬拉下來關掉，存好後清單照樣更新', (tester) async {
    final repo = _SlowRepo();
    await _open(tester, 'demo-new', repo);
    await tester.ensureVisible(find.text('新增').last);
    await tester.tap(find.text('新增').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名稱（例：記帳費）'), '記帳費');
    await tester.enterText(find.widgetWithText(TextField, '每月金額'), '3000');
    await tester.tap(find.widgetWithText(FilledButton, '儲存').last);
    await tester.pump();
    expect(find.text('儲存中…'), findsOneWidget);
    // 按返回
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('儲存中…'), findsOneWidget);
    // 點面板外面
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('儲存中…'), findsOneWidget);
    // 硬拉下來關掉
    await tester.drag(find.text('新增每月固定支出'), const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(find.text('儲存中…'), findsNothing);
    expect(find.text('記帳費'), findsNothing);
    repo.gate.complete();
    await tester.pumpAndSettle();
    expect(repo.recurringSaves, 1);
    // 父畫面重新讀了：新的那筆出現在清單上，不會以為沒存又新增一次
    expect(find.text('記帳費'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('科目儲存中：按返回關不掉；硬拉下來關掉，存好後清單照樣更新', (tester) async {
    final repo = _SlowRepo();
    await _open(tester, 'yc', repo);
    await tester.tap(find.text('修繕費'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '修繕費'), '修繕維護費');
    await tester.tap(find.widgetWithText(FilledButton, '儲存').last);
    await tester.pump();
    expect(find.text('儲存中…'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('儲存中…'), findsOneWidget);
    await tester.drag(find.text('修改科目'), const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(find.text('儲存中…'), findsNothing);
    expect(find.text('修繕維護費'), findsNothing);
    repo.accountGate.complete();
    await tester.pumpAndSettle();
    expect(repo.accountSaves, 1);
    expect(find.text('修繕維護費'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
