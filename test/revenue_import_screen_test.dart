// 營收搬家（ops 0168）：匯入、匯出營收的畫面；營收頁的入口只在公版。數字都是測試用的假資料。
// 營收頁要用 AppScope，而 AppState 會載入網頁專用的 load_timing（dart:js_interop），所以只能在瀏覽器跑：
//   flutter test --platform chrome test/revenue_import_screen_test.dart
// 看懂檔案、範本、匯出、示範版的檢查在 test/revenue_import_test.dart（CI 一般 flutter test 會跑）
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/revenue_import.dart';
import 'package:yincheng_ops/screens/revenue_import_screen.dart';
import 'package:yincheng_ops/screens/revenue_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  bool undone = false;
  @override
  Future<List<RevenueImportBatch>> revenueImports(String storeId) async => [
        RevenueImportBatch(
          id: 'b1',
          createdAt: DateTime(2026, 11, 20, 14, 5),
          fileName: '舊系統_2025.xlsx',
          total: 120,
          inserted: 118,
          skipped: 2,
          dateFrom: DateTime(2025, 1, 1),
          dateTo: DateTime(2025, 4, 30),
          undoneAt: undone ? DateTime(2026, 11, 21) : null,
          undoneCount: undone ? 116 : null,
          undoneKept: undone ? 2 : null,
        ),
      ];

  @override
  Future<(int, int)> undoRevenueImport(String batchId) async {
    undone = true;
    return (116, 2);
  }
}

Future<_Repo> _pump(WidgetTester tester, Widget home, {_Repo? repo}) async {
  await initializeDateFormatting('zh_TW');
  final r = repo ?? _Repo();
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(
      state: AppState(r),
      child: MaterialApp(theme: buildTheme(StorePalette.gold), home: home)));
  await tester.pumpAndSettle();
  return r;
}

void main() {
  final owner = Membership(
      storeId: 'yc', storeName: '隱城', role: Role.owner, displayName: '示範');

  testWidgets('匯入紀錄、整批復原（留下改過的天數）、匯出', (tester) async {
    final repo = await _pump(tester, RevenueImportScreen(membership: owner));
    expect(find.text('把過去的營收搬過來'), findsOneWidget);
    expect(find.text('下載範本'), findsOneWidget);
    expect(find.text('選擇檔案'), findsOneWidget);
    expect(find.text('2025/1/1～2025/4/30'), findsOneWidget);
    expect(find.text('匯入 118 天・略過 2 列'), findsOneWidget);

    await tester.tap(find.text('整批復原'));
    await tester.pumpAndSettle();
    expect(find.text('整批復原？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '整批復原'));
    await tester.pumpAndSettle();
    expect(repo.undone, isTrue);
    expect(find.text('已刪掉 116 天，2 天改過或鎖帳所以留著'), findsOneWidget);
    expect(find.text('已復原・刪掉 116 天・留下 2 天'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '整批復原'), findsNothing,
        reason: '每一批只能復原一次');

    expect(find.text('匯出每日營收'), findsOneWidget);
  });

  testWidgets('隱城／小城外這一份：營收頁沒有匯入、匯出的入口（只有公版有）', (tester) async {
    await _pump(tester, Scaffold(body: RevenueScreen(membership: owner)));
    expect(find.byKey(const Key('revenue-import')), findsNothing);
    expect(find.text('匯入、匯出'), findsNothing);
  });
}
