// 哪些通知發到 LINE 群組（ops 0162，公版）：沒改不能存、存好按鈕變「已存好」、改回預設、存失敗不會當作存好。
// App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/line_notify_events_screen_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/screens/line_notify_events_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  Set<String> stored = {'handover_important'};
  bool fail = false;
  int saves = 0;
  @override
  Future<Set<String>> lineNotifyEvents(String storeId) async => {...stored};
  @override
  Future<void> saveLineNotifyEvents(String storeId, Set<String> events) async {
    saves++;
    if (fail) throw Exception('Failed to fetch');
    stored = {...events};
  }
}

Future<_Repo> _open(WidgetTester tester,
    {bool fail = false, Set<String>? stored}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _Repo()..fail = fail;
  if (stored != null) repo.stored = stored;
  final m = Membership(
      storeId: 's1', storeName: '示範小館', role: Role.owner, displayName: '示範');
  await tester.pumpWidget(AppScope(
      state: AppState(repo),
      child: MaterialApp(
          theme: buildTheme(StorePalette.gold),
          home: LineNotifyEventsScreen(membership: m))));
  await tester.pumpAndSettle();
  return repo;
}

FilledButton _button(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));
bool _checked(WidgetTester tester, String key) =>
    tester
        .widget<CheckboxListTile>(find.byKey(ValueKey('line-event-$key')))
        .value ??
    false;

void main() {
  testWidgets('一開始只勾重要交接，沒改不能存', (tester) async {
    await _open(tester);
    expect(_checked(tester, 'handover_important'), isTrue);
    expect(_checked(tester, 'reminder'), isFalse);
    expect(_button(tester).onPressed, isNull);
    expect(find.text('已存好'), findsOneWidget);
  });

  testWidgets('勾新提醒 → 存檔 → 存進去、按鈕變已存好', (tester) async {
    final repo = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('line-event-reminder')));
    await tester.pump();
    expect(find.text('存檔'), findsOneWidget);
    await tester.tap(find.text('存檔'));
    await tester.pumpAndSettle();
    expect(repo.stored, {'handover_important', 'reminder'});
    expect(find.text('已存好'), findsOneWidget);
  });

  testWidgets('改回預設只剩重要交接', (tester) async {
    await _open(tester, stored: {'reminder'});
    expect(_checked(tester, 'handover_important'), isFalse);
    await tester.tap(find.text('改回預設（只發重要交接）'));
    await tester.pump();
    expect(_checked(tester, 'handover_important'), isTrue);
    expect(_checked(tester, 'reminder'), isFalse);
  });

  testWidgets('存失敗：勾選沒存進去、按鈕還能再按（不當作存好）', (tester) async {
    final repo = await _open(tester, fail: true);
    await tester.tap(find.byKey(const ValueKey('line-event-schedule')));
    await tester.pump();
    await tester.tap(find.text('存檔'));
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
    expect(repo.stored, {'handover_important'});
    expect(find.text('存檔'), findsOneWidget);
    expect(_button(tester).onPressed, isNotNull);
  });
}
