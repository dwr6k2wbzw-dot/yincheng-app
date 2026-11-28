// 打卡設定（ops 0163）從 ⋯ 選單存好之後，班表頁留在 IndexedStack 裡的打卡卡片要重新讀（Codex P2）。
// App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/attendance_card_refresh_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/repository.dart';
import 'package:yincheng_ops/screens/attendance_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  int loads = 0;
  @override
  Future<AttendanceMe?> attendanceMe(String storeId) async {
    loads++;
    return super.attendanceMe(storeId);
  }
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
}
