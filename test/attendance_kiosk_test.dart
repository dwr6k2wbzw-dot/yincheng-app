// 2026-11-15 班表第一階段：打卡機畫面（老闆）。
// AppState 會載入網頁專用的 load_timing（dart:js_interop），所以只能在瀏覽器跑：
//   flutter test --platform chrome test/attendance_kiosk_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/repository.dart';
import 'package:yincheng_ops/main.dart';
import 'package:yincheng_ops/screens/attendance_manage_screen.dart';
import 'package:yincheng_ops/screens/attendance_screen.dart';
import 'package:yincheng_ops/screens/home_shell.dart';
import 'package:yincheng_ops/screens/kiosk_screen.dart';
import 'package:yincheng_ops/screens/login_screen.dart';
import 'package:yincheng_ops/theme.dart';

const _k = '0f8fad5b-d9cb-469f-a165-70867728950e';

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW'));
  reviewTests();
  group('打卡機畫面', () {
    Widget app(DemoRepository repo) =>
        AppScope(state: AppState(repo), child: MaterialApp(theme: buildTheme(StorePalette.gold), home: const KioskScreen()));

    testWidgets('沒設定過：提示到出勤管理設定', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(app(DemoRepository()));
      await tester.pumpAndSettle();
      expect(find.text('這台還沒設成打卡機'), findsOneWidget);
    });

    testWidgets('設定過：顯示店名、QR 碼、倒數；離開時停止計時', (tester) async {
      SharedPreferences.setMockInitialValues({kioskIdPref: _k, kioskSecretPref: 'demo-secret'});
      await tester.pumpWidget(app(DemoRepository()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('隱城'), findsOneWidget);
      expect(find.textContaining('秒後換碼'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));
  });

  // 程式審查 2026-11-15：打卡機不能留老闆／店長的登入
  group('打卡機不留管理者登入', () {
    testWidgets('已登入的人直接開打卡畫面 → 先登出', (tester) async {
      SharedPreferences.setMockInitialValues({kioskIdPref: _k, kioskSecretPref: 'demo-secret'});
      final repo = DemoRepository();
      await tester.runAsync(() => repo.signIn('owner@x', 'x'));
      await tester.pumpWidget(
          AppScope(state: AppState(repo), child: MaterialApp(theme: buildTheme(StorePalette.gold), home: const KioskScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.isSignedIn, isFalse);
      expect(find.textContaining('秒後換碼'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('老闆設定打卡機 → 登出、清掉頁面；按返回、離開都回不到後台', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 2000);
      addTearDown(tester.view.reset);
      final repo = DemoRepository();
      await tester.runAsync(() => repo.signIn('owner@x', 'x'));
      final m = Membership(storeId: 'yc', storeName: '隱城', role: Role.owner, displayName: '示範');
      // 跟 App 一樣的路由（'/'＝AuthGate、'/kiosk'＝打卡機），從出勤管理開始
      await tester.pumpWidget(AppScope(
          state: AppState(repo),
          child: MaterialApp(
            theme: buildTheme(StorePalette.gold),
            onGenerateInitialRoutes: (_) => [
              MaterialPageRoute<void>(
                  builder: (_) => AttendanceManageScreen(
                      membership: m,
                      data: ShiftMonth(DateTime(2026, 11), const [], const {}, const {}, const {}, const []),
                      codeTimes: const {})),
            ],
            onGenerateRoute: appRoute,
          )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打卡機'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('把這台設成打卡機'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('設定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.isSignedIn, isFalse, reason: '設定完要登出');
      expect(find.byType(KioskScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(AttendanceManageScreen), findsNothing);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      expect(nav.canPop(), isFalse, reason: '頁面堆疊只剩打卡機，按返回沒有上一頁');

      // 瀏覽器／手機的返回鍵
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(AttendanceManageScreen), findsNothing);

      // 離開打卡機 → 登入頁（不是後台）
      await tester.tap(find.byTooltip('離開打卡機（回登入頁）'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('重新整理：網址還是 #/kiosk → 打卡機畫面、仍是登出', (tester) async {
      SharedPreferences.setMockInitialValues({kioskIdPref: _k, kioskSecretPref: 'demo-secret'});
      final repo = DemoRepository(); // 重新整理後沒有登入
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/kiosk';
      addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
      await tester.pumpWidget(YinchengApp(state: AppState(repo)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(KioskScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(repo.isSignedIn, isFalse);
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('密鑰錯／嘗試太多次：顯示原因、不自動重試', (tester) async {
      SharedPreferences.setMockInitialValues({kioskIdPref: _k, kioskSecretPref: 'wrong'});
      final repo = _FailingKioskRepo();
      await tester.pumpWidget(
          AppScope(state: AppState(repo), child: MaterialApp(theme: buildTheme(StorePalette.gold), home: const KioskScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('嘗試太多次，請 10 分鐘後再試'), findsOneWidget);
      expect(find.text('重試'), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
      expect(repo.calls, 1, reason: '不自動重試，免得一直累積失敗次數');
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}

// 程式審查 2026-11-15 第二輪
final _emptyMonth = ShiftMonth(DateTime(2026, 11), const [], const {}, const {}, const {}, const []);

Widget _wrap(DemoRepository repo, Widget child) => AppScope(
    state: AppState(repo), child: MaterialApp(theme: buildTheme(StorePalette.gold), home: Scaffold(body: SingleChildScrollView(child: child))));

void reviewTests() {
  group('第二輪審查', () {
    testWidgets('小城外沒開打卡：老闆照樣進得了員工資料、確認綁定', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 2000);
      addTearDown(tester.view.reset);
      final repo = DemoRepository();
      await tester.runAsync(() => repo.signIn('owner@x', 'x'));
      final m = Membership(storeId: 'xc', storeName: '小城外', role: Role.owner, displayName: '示範');
      await tester.pumpWidget(_wrap(repo, AttendanceCard(membership: m, data: _emptyMonth, codeTimes: const {})));
      await tester.pumpAndSettle();
      expect(find.text('打卡（試行）'), findsNothing, reason: '沒開打卡就不顯示打卡卡片');
      expect(find.text('掃碼打卡'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, '員工資料'));
      await tester.pumpAndSettle();
      expect(find.text('員工資料・小城外'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing, reason: '只有員工資料，沒有打卡相關分頁');
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('小城外沒開打卡：一般員工（綁定已確認）什麼都不顯示；等確認的看得到提示', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final m = Membership(storeId: 'xc', storeName: '小城外', role: Role.staff, displayName: '示範');
      final staff = DemoRepository();
      await tester.runAsync(() => staff.signIn('staff@x', 'x'));
      await tester.pumpWidget(_wrap(staff, AttendanceCard(membership: m, data: _emptyMonth, codeTimes: const {})));
      await tester.pumpAndSettle();
      expect(find.text('員工資料'), findsNothing);
      final pending = DemoRepository();
      await tester.runAsync(() => pending.signIn('unverified-staff@x', 'x'));
      await tester.pumpWidget(_wrap(pending, AttendanceCard(key: UniqueKey(), membership: m, data: _emptyMonth, codeTimes: const {})));
      await tester.pumpAndSettle();
      expect(find.textContaining('還在等老闆確認'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '員工資料'), findsNothing, reason: '員工沒有員工資料入口');
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('原始紀錄審核成功後，出勤分頁的合計跟著更新', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 2000);
      addTearDown(tester.view.reset);
final repo = DemoRepository();
      await tester.runAsync(() => repo.signIn('owner@x', 'x'));
      final m = Membership(storeId: 'yc', storeName: '隱城', role: Role.owner, displayName: '示範');
      await tester.pumpWidget(AppScope(
          state: AppState(repo),
          child: MaterialApp(
              theme: buildTheme(StorePalette.gold),
              home: AttendanceManageScreen(membership: m, data: _emptyMonth, codeTimes: const {}))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('出勤'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('近 7 天'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 段待確認不計入'), findsOneWidget);
      final before = tester.widget<Text>(find.textContaining('計入工時合計')).textSpan!.toPlainText();

      await tester.tap(find.text('原始紀錄'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('小魚・上班'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '確認'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '有看到人');
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('出勤'));
      await tester.pumpAndSettle();
      expect(find.text('這段期間沒有出勤'), findsNothing, reason: '切回來還是「近 7 天」，不跳回今天');
      expect(find.textContaining('待確認不計入'), findsNothing);
      final after = tester.widget<Text>(find.textContaining('計入工時合計')).textSpan!.toPlainText();
      expect(after, isNot(before));
      expect(after, contains('計入工時合計 9 小時 28 分'), reason: '330 + 238 分鐘');
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}

class _FailingKioskRepo extends DemoRepository {
  int calls = 0;
  @override
  Future<KioskCode> kioskCode(String kioskId, String secret) async {
    calls++;
    throw const KioskCodeError('嘗試太多次，請 10 分鐘後再試');
  }
}

