// 損益設定畫面（ops 0169，公版）：新店選業態套範本、改科目、手續費率與抬頭。資料都是示範的。
// App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/pl_settings_screen_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/screens/pl_settings_screen.dart';
import 'package:yincheng_ops/theme.dart';

Future<DemoRepository> _open(WidgetTester tester, String storeId) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = DemoRepository();
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
}
