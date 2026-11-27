// 用講的改訂位設定（ops 0147）：建議怎麼顯示、確認才套用、不用就不改、改回去。示範資料都是虛構的。
// App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/booking_assistant_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/booking_assist.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/screens/booking_assistant_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  int applied = 0;
  @override
  Future<void> applyBookingAssist(
      String storeId, String request, List<AssistChange> changes) async {
    applied++;
    await super.applyBookingAssist(storeId, request, changes);
  }
}

Future<_Repo> _open(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  final m = Membership(
      storeId: 'yc', storeName: '隱城', role: Role.owner, displayName: '示範');
  await tester.pumpWidget(AppScope(
      state: AppState(repo),
      child: MaterialApp(
          theme: buildTheme(StorePalette.gold),
          home: BookingAssistantScreen(membership: m))));
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
  group('AssistChange 顯示', () {
    test('文字、低消、語言、某一天', () {
      const t = AssistChange({
        'op': 'text',
        'field': 'intro',
        'lang': 'en',
        'before': null,
        'after': 'Hi'
      });
      expect(t.label, '介紹（English）');
      expect(t.beforeText, '（沒有）');
      expect(t.afterText, 'Hi');
      const m = AssistChange({'op': 'min_spend', 'before': 800, 'after': null});
      expect(m.beforeText, '800 元');
      expect(m.afterText, '（不顯示）');
      const l = AssistChange({
        'op': 'langs',
        'before': ['zh'],
        'after': ['zh', 'ja']
      });
      expect(l.afterText, '中文、日本語');
      const d = AssistChange({
        'op': 'day',
        'date': '2032-07-03',
        'before': null,
        'after': {'closed': true, 'note': '包場'}
      });
      expect(d.label, '7/3（週六）');
      expect(d.beforeText, '照平常開放');
      expect(d.afterText, '整天不開放（包場）');
    });
  });

  testWidgets('一開始有例子可以點；說了之後列出改前改後，按確認才套用', (tester) async {
    final repo = await _open(tester);
    expect(find.text('想改什麼，直接說'), findsOneWidget);
    await _say(tester, '低消改成每人 700');
    expect(find.text('600 元'), findsOneWidget); // 改前
    expect(find.text('700 元'), findsOneWidget); // 改後
    expect(repo.applied, 0, reason: '還沒按確認，不能改');
    await tester.tap(find.text('確認套用'));
    await tester.pumpAndSettle();
    expect(repo.applied, 1);
    expect(find.text('已套用'), findsOneWidget);
    expect((await tester.runAsync(() => repo.bookingProfile('yc')))!.minSpend,
        700);
  });

  testWidgets('按「不用」就不改；問新的問題時，沒決定的舊建議也不能再按', (tester) async {
    final repo = await _open(tester);
    await _say(tester, '低消改成每人 700');
    await tester.tap(find.text('不用'));
    await tester.pumpAndSettle();
    expect(find.text('沒有套用'), findsOneWidget);
    await _say(tester, '加開日文');
    await _say(tester, '低消改 900');
    expect(find.text('確認套用'), findsOneWidget, reason: '只有最新的那一則還能套用');
    expect(repo.applied, 0);
  });

  testWidgets('改回去：最近的修改裡整筆改回去', (tester) async {
    final repo = await _open(tester);
    await _say(tester, '這週六包場，不開放線上訂位');
    expect(find.text('照平常開放'), findsOneWidget);
    expect(find.text('整天不開放（包場）'), findsOneWidget);
    await tester.tap(find.text('確認套用'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('最近的修改'));
    await tester.pumpAndSettle();
    expect(find.text('「這週六包場，不開放線上訂位」'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '改回去').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '改回去'));
    await tester.pumpAndSettle();
    expect(find.text('已改回去'), findsOneWidget);
    final now = DateTime.now();
    final days = await tester.runAsync(
        () => repo.specialDays('yc', now, now.add(const Duration(days: 8))));
    expect(days, isEmpty);
  });

  testWidgets('示範版聽不懂時只回說明、沒有建議', (tester) async {
    await _open(tester);
    await _say(tester, '幫我把時段改成 18:00 開始');
    expect(find.textContaining('示範版只認得幾種說法'), findsOneWidget);
    expect(find.text('確認套用'), findsNothing);
  });
}
