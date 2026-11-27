// AI 設定畫面（ops 0157，公版）：斷線等例外不會讓按鈕一直卡在處理中（Codex P2），原因寫在畫面上。
// 金鑰都是假的。App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/store_ai_screen_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/store_ai.dart';
import 'package:yincheng_ops/screens/store_ai_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  bool fail = true;
  StoreAiSetting? setting;
  @override
  Future<StoreAiSetting?> storeAiSetting(String storeId) async => setting;
  @override
  Future<StoreAiResult> saveStoreAi(String storeId, StoreAiProvider provider,
      String model, String key) async {
    if (fail) throw Exception('Failed to fetch');
    return super.saveStoreAi(storeId, provider, model, key);
  }

  @override
  Future<StoreAiResult> testStoreAi(String storeId) async {
    if (fail) throw Exception('Failed to fetch');
    return const StoreAiResult.ok();
  }

  @override
  Future<void> clearStoreAi(String storeId) async {
    if (fail) throw Exception('Failed to fetch');
  }
}

Future<_Repo> _open(WidgetTester tester, {StoreAiSetting? setting}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _Repo()..setting = setting;
  final m = Membership(
      storeId: 's1', storeName: '示範小館', role: Role.owner, displayName: '示範');
  await tester.pumpWidget(AppScope(
      state: AppState(repo),
      child: MaterialApp(
          theme: buildTheme(StorePalette.gold),
          home: StoreAiScreen(membership: m))));
  await tester.pumpAndSettle();
  return repo;
}

FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.ancestor(of: find.text('測試並儲存'), matching: find.byType(FilledButton)));

void main() {
  testWidgets('儲存時斷線：按鈕放開、原因寫在表單上，可以再試', (tester) async {
    final repo = await _open(tester);
    await tester.enterText(
        find.byType(TextField).last, 'sk-proj-0000000000000000000000ABCD');
    await tester.tap(find.text('測試並儲存'));
    await tester.pumpAndSettle();
    expect(_saveButton(tester).onPressed, isNotNull, reason: '不能一直卡在處理中');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 再試一次就成功
    repo.fail = false;
    await tester.tap(find.text('測試並儲存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已經改用你自己的'), findsOneWidget);
  });

  testWidgets('測試連線、改回平台時斷線：按鈕放開、顯示原因', (tester) async {
    await _open(tester,
        setting: StoreAiSetting(
            provider: StoreAiProvider.openai,
            model: 'gpt-5-mini',
            keyLast4: 'ABCD',
            verifiedAt: DateTime(2026, 11, 27)));
    await tester.tap(find.text('測試連線'));
    await tester.pumpAndSettle();
    final testBtn = find.ancestor(
        of: find.text('測試連線'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    expect(
        tester.widget<ButtonStyleButton>(testBtn.first).onPressed, isNotNull);
    expect(_saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('改回平台的 AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪掉金鑰'));
    await tester.pumpAndSettle();
    expect(tester.widget<ButtonStyleButton>(testBtn.first).onPressed, isNotNull,
        reason: '清除失敗也要放開');
    expect(_saveButton(tester).onPressed, isNotNull);
  });
}
