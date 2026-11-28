// 盤點品項搬家（ops 0167）的畫面：入口只在公版、只有老闆店長；匯入畫面的預覽、匯入、整批復原。示範資料都是虛構的。
// App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/product_import_screen_test.dart
// 公版那一份的入口：加 --dart-define=SELF_SIGNUP=true 再跑一次。
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/config.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/screens/product_import_screen.dart';
import 'package:yincheng_ops/screens/stock_counts_screen.dart';
import 'package:yincheng_ops/theme.dart';

Future<void> _pump(WidgetTester tester, Widget home) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(
      state: AppState(DemoRepository()),
      child: MaterialApp(theme: buildTheme(StorePalette.gold), home: home)));
  await tester.pumpAndSettle();
}

Membership _m(Role r) =>
    Membership(storeId: 'yc', storeName: '隱城', role: r, displayName: '示範');

void main() {
  testWidgets('品項管理的入口：隱城／小城外這一份沒有；公版只有老闆、店長有', (tester) async {
    for (final r in Role.values) {
      await _pump(tester, ProductsScreen(membership: _m(r)));
      final shown = find.byTooltip('匯入、匯出品項').evaluate().isNotEmpty;
      final expected =
          AppConfig.selfSignup && (r == Role.owner || r == Role.manager);
      expect(shown, expected, reason: '$r');
    }
  });

  testWidgets('匯入畫面：步驟、範本、匯入紀錄、匯出；店長看到成本價只有老闆能匯入', (tester) async {
    await _pump(tester, ProductImportScreen(membership: _m(Role.manager)));
    expect(find.text('匯入、匯出品項'), findsOneWidget);
    expect(find.text('下載範本'), findsOneWidget);
    expect(find.text('選擇檔案'), findsOneWidget);
    expect(find.text('還沒有匯入過'), findsOneWidget);
    expect(find.textContaining('成本價只有老闆能匯入'), findsOneWidget);
    expect(find.textContaining('不含成本價'), findsOneWidget);

    await _pump(tester, ProductImportScreen(membership: _m(Role.owner)));
    expect(find.textContaining('成本價只有老闆能匯入'), findsNothing);
    expect(find.textContaining('含成本價'), findsOneWidget);
  });
}
