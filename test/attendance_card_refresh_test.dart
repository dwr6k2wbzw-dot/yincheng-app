// 打卡設定（ops 0163）從 ⋯ 選單存好之後，班表頁留在 IndexedStack 裡的打卡卡片要重新讀（Codex P2）。
// App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/attendance_card_refresh_test.dart
@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/repository.dart';
import 'package:yincheng_ops/screens/attendance_screen.dart';
import 'package:yincheng_ops/screens/attendance_settings_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  int loads = 0;
  int saves = 0;
  Completer<void>? hold; // 有值＝存檔卡在這裡，模擬網路慢
  @override
  Future<void> saveAttendanceSettings(
      String storeId, Map<String, Object?> changes) async {
    saves++;
    final h = hold;
    if (h != null) await h.future;
    return super.saveAttendanceSettings(storeId, changes);
  }

  @override
  Future<AttendanceMe?> attendanceMe(String storeId) async {
    loads++;
    return super.attendanceMe(storeId);
  }
}

/// 儲存鈕在清單最下面，先捲到看得到再按
Future<void> _tapSave(WidgetTester tester) async {
  final list = find
      .descendant(
          of: find.byType(AttendanceSettingsScreen),
          matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(find.text('儲存'), 200, scrollable: list);
  await tester.tap(find.text('儲存'));
}

void main() {
  testWidgets('存好打卡設定 → 同一家店的打卡卡片重新讀，別家店不動', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.runAsync(() => repo.signIn('owner@demo', 'demo'));
    final m = Membership(
        storeId: 's1', storeName: '晨光咖啡', role: Role.owner, displayName: '林老闆');
    await tester.pumpWidget(AppScope(
      state: AppState(repo),
      child: MaterialApp(
        theme: buildTheme(StorePalette.gold),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AttendanceCard(
              membership: m,
              data: ShiftMonth(DateTime(2026, 12), const [], const {}, const {},
                  const {}, const []),
              codeTimes: const {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(repo.loads, 1);

    notifyAttendanceSettingsSaved('other-store');
    await tester.pumpAndSettle();
    expect(repo.loads, 1, reason: '別家店存設定，這張卡片不用重讀');

    notifyAttendanceSettingsSaved('s1');
    await tester.pumpAndSettle();
    expect(repo.loads, 2, reason: '同一家店存好設定，卡片要重新讀開關狀態');

    notifyAttendanceSettingsSaved('s1');
    await tester.pumpAndSettle();
    expect(repo.loads, 3, reason: '同一家店連存兩次也要各重讀一次');

    await tester.pumpWidget(const SizedBox());
    notifyAttendanceSettingsSaved('s1');
    await tester.pumpAndSettle();
    expect(repo.loads, 3, reason: '卡片拿掉之後不再聽通知');
  });

  Widget shell(AppState state, Membership m) => AppScope(
        state: state,
        child: MaterialApp(
          theme: buildTheme(StorePalette.gold),
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(actions: [
                // 跟 HomeShell ⋯ 選單一樣：直接 push 打卡設定頁
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AttendanceSettingsScreen(membership: m))),
                  child: const Text('打開設定'),
                ),
              ]),
              body: SingleChildScrollView(
                child: AttendanceCard(
                  membership: m,
                  data: ShiftMonth(DateTime(2026, 12), const [], const {},
                      const {}, const {}, const []),
                  codeTimes: const {},
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('從 ⋯ 選單那條路進打卡設定、存好返回 → 卡片重新讀', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.runAsync(() => repo.signIn('owner@demo', 'demo'));
    final m = Membership(
        storeId: 's1', storeName: '晨光咖啡', role: Role.owner, displayName: '林老闆');
    await tester.pumpWidget(shell(AppState(repo), m));
    await tester.pumpAndSettle();
    final before = repo.loads;

    await tester.tap(find.text('打開設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開放打卡'));
    await tester.pumpAndSettle();
    final dialog = find.text('關掉');
    if (dialog.evaluate().isNotEmpty) {
      await tester.tap(dialog);
      await tester.pumpAndSettle();
    }
    await _tapSave(tester);
    await tester.pumpAndSettle();
    final dialog2 = find.text('關掉');
    if (dialog2.evaluate().isNotEmpty) {
      await tester.tap(dialog2);
      await tester.pumpAndSettle();
    }
    expect(repo.saves, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repo.loads, greaterThan(before), reason: '從選單進去存好，回到班表頁卡片要重新讀開關狀態');
  });

  testWidgets('存檔途中按返回離開 → 不會出錯，卡片照樣收到通知', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.runAsync(() => repo.signIn('owner@demo', 'demo'));
    final m = Membership(
        storeId: 's1', storeName: '晨光咖啡', role: Role.owner, displayName: '林老闆');
    await tester.pumpWidget(shell(AppState(repo), m));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打開設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開放打卡'));
    await tester.pumpAndSettle();
    repo.hold = Completer<void>();
    await _tapSave(tester);
    await tester.pump();
    final dialog = find.text('關掉');
    if (dialog.evaluate().isNotEmpty) {
      await tester.tap(dialog);
      await tester.pump();
    }
    expect(repo.saves, 1);
    final loadsBefore = repo.loads;
    // 還在存，老闆先按返回
    await tester.pageBack();
    await tester.pumpAndSettle();
    repo.hold!.complete();
    // 頁面已經關掉、畫面沒有動畫，pumpAndSettle 不會往前推時間；手動推過示範資料的 300ms 等待
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: '離開後存檔才完成，不能對已關掉的頁面 setState');
    expect(repo.loads, greaterThan(loadsBefore), reason: '存好的通知照發，卡片要重新讀');
  });
}
