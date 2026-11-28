// 打卡設定畫面（ops 0164，公版）：進度、每一步的狀態、老闆產生平板邀請碼、店長看得到但不能做老闆的步驟、
// 讀不到時可以重試。App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/attendance_setup_screen_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/attendance_setup.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/screens/attendance_setup_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  AttendanceSetupStatus? fixed;
  bool offline = false;
  int enabled = 0;
  @override
  Future<AttendanceSetupStatus> attendanceSetupStatus(String storeId) async {
    if (offline) throw Exception('Failed to fetch');
    return fixed ?? await super.attendanceSetupStatus(storeId);
  }

  @override
  Future<void> attendanceSetupEnable(String storeId) async {
    enabled++;
    fixed = null;
  }
}

const _fresh = AttendanceSetupStatus(
  canOwner: true,
  enabled: false,
  people: 2,
  unbound: [SetupPerson('p1', '王阿A')],
  noPin: [SetupPerson('p1', '王阿A'), SetupPerson('p2', '小B')],
  shiftCodes: false,
  hasTime: false,
);

Future<_Repo> _open(WidgetTester tester, {AttendanceSetupStatus? s, Role role = Role.owner, bool offline = false}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _Repo()
    ..fixed = s
    ..offline = offline;
  final m = Membership(storeId: 'yc', storeName: '示範小館', role: role, displayName: '示範');
  await tester.pumpWidget(AppScope(
      state: AppState(repo),
      child: MaterialApp(theme: buildTheme(StorePalette.gold), home: AttendanceSetupScreen(membership: m))));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('全新的店：還差 5 項，每一步都列出來，老闆可以打開打卡', (tester) async {
    final repo = await _open(tester, s: _fresh);
    expect(find.text('還差 5 項就能開始打卡'), findsOneWidget);
    expect(find.text('0／5'), findsOneWidget);
    for (final t in ['打開打卡', '打卡用帳號（店裡的平板）', '員工對應 App 帳號（建議）', '打卡密碼', '班的時間', '試打一次卡']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('王阿A'), findsNWidgets(2)); // 沒對應、沒密碼各一次
    expect(find.text('還沒設「V」（上班）是幾點到幾點。'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '打開打卡'));
    await tester.pumpAndSettle();
    expect(repo.enabled, 1);
    expect(find.text('已經打開'), findsOneWidget); // 重新讀了一次（示範資料：隱城已打開）
  });

  testWidgets('老闆產生平板邀請碼：顯示代碼與在平板上要做的步驟，關掉後顯示期限', (tester) async {
    await _open(tester);
    await tester.tap(find.text('產生平板用的邀請碼'));
    await tester.pumpAndSettle();
    expect(find.text('平板用的邀請碼'), findsOneWidget);
    expect(find.text('KIOSK-28DEM'), findsOneWidget);
    expect(find.textContaining('我有邀請碼'), findsOneWidget);
    await tester.tap(find.text('好了'));
    await tester.pumpAndSettle();
    expect(find.text('重新產生邀請碼'), findsOneWidget);
    expect(find.textContaining('前在平板上輸入有效'), findsOneWidget);
  });

  testWidgets('店長：看得到進度，打開打卡、平板帳號要請老闆', (tester) async {
    await _open(tester, s: const AttendanceSetupStatus(
      canOwner: false,
      enabled: false,
      people: 1,
      shiftCodes: true,
      hasTime: false,
    ), role: Role.manager);
    expect(find.text('要請老闆打開。'), findsOneWidget);
    expect(find.text('打卡用帳號只有老闆能設定。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '打開打卡'), findsNothing);
    // 用班別代碼的店：班的時間到班表的「班別／時段」設
    expect(find.textContaining('班別／時段'), findsOneWidget);
  });

  testWidgets('全部做好：打卡設定好了', (tester) async {
    await _open(tester, s: AttendanceSetupStatus(
      canOwner: true,
      enabled: true,
      kioskName: '店裡平板',
      people: 2,
      shiftCodes: false,
      hasTime: true,
      lastPinPunch: DateTime.utc(2026, 11, 28, 10),
    ));
    expect(find.text('打卡設定好了'), findsOneWidget);
    expect(find.text('5／5'), findsOneWidget);
    expect(find.text('平板帳號：店裡平板'), findsOneWidget);
    expect(find.text('最近一次密碼打卡：11/28 18:00'), findsOneWidget);
  });

  testWidgets('讀不到：顯示錯誤、可以重試', (tester) async {
    final repo = await _open(tester, offline: true);
    expect(find.text('重試'), findsOneWidget);
    repo.offline = false;
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();
    expect(find.text('打卡開始使用'), findsOneWidget);
    expect(find.text('打開打卡'), findsOneWidget);
  });

  testWidgets('已經有進度、之後重新整理失敗：照樣顯示上次的進度，上面標出沒更新到並可重試', (tester) async {
    final repo = await _open(tester, s: _fresh);
    repo.offline = true; // 打開打卡成功，但之後重新讀進度失敗
    await tester.tap(find.widgetWithText(FilledButton, '打開打卡'));
    await tester.pumpAndSettle();
    expect(repo.enabled, 1);
    expect(find.byKey(const Key('setup_stale_banner')), findsOneWidget);
    expect(find.textContaining('沒有更新到最新的進度'), findsOneWidget);
    expect(find.text('還差 5 項就能開始打卡'), findsOneWidget); // 上一次的進度還在
    repo.offline = false;
    await tester.tap(find.widgetWithText(TextButton, '重試'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setup_stale_banner')), findsNothing);
    expect(find.text('已經打開'), findsOneWidget);
  });
}
