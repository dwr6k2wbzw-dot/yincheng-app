// 用講的改排班設定（ops 0154）的畫面：說了之後列出改前改後、按確認才套用、改回去；入口只在公版出現。
// App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/shift_assistant_screen_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/booking_assist.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/screens/shift_assistant_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  int applied = 0;
  @override
  Future<void> applyShiftAssist(String storeId, String request, List<AssistChange> changes) async {
    applied++;
    await super.applyShiftAssist(storeId, request, changes);
  }
}

Future<_Repo> _open(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  final m = Membership(storeId: 'yc', storeName: '隱城', role: Role.manager, displayName: '示範店長');
  await tester.pumpWidget(AppScope(
      state: AppState(repo),
      child: MaterialApp(theme: buildTheme(StorePalette.gold), home: ShiftAssistantScreen(membership: m))));
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _say(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byTooltip('送出'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  test('入口只在公版：沒有 SELF_SIGNUP 的建置看不到', () {
    expect(shiftAssistantVisible, isFalse);
  });

  testWidgets('說了之後列出改前改後，按確認才套用，可以改回去', (tester) async {
    final repo = await _open(tester);
    expect(find.text('用講的改排班設定'), findsOneWidget);
    await _say(tester, '週五要 5 個人');
    expect(find.text('每週五要幾人'), findsOneWidget);
    expect(find.text('4 人（正職至少 1）'), findsOneWidget);
    expect(find.text('5 人（正職至少 1）'), findsOneWidget);
    expect(repo.applied, 0, reason: '還沒按確認，不能改');
    await tester.tap(find.text('確認套用'));
    await tester.pumpAndSettle();
    expect(repo.applied, 1);
    expect(find.text('已套用'), findsOneWidget);
    expect((await tester.runAsync(() => repo.shiftPlanSetup('yc', DateTime.now())))!.staffing[5]!.need, 5);

    await tester.tap(find.byTooltip('最近的修改'));
    await tester.pumpAndSettle();
    expect(find.text('「週五要 5 個人」'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '改回去').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '改回去'));
    await tester.pumpAndSettle();
    expect(find.text('已改回去'), findsOneWidget);
    expect((await tester.runAsync(() => repo.shiftPlanSetup('yc', DateTime.now())))!.staffing[5]!.need, 4);
  });
}
