// 2026-11-16 打卡用帳號＋4 位數密碼打卡（ops 0112）：公用帳號權限照舊，第一頁多一個密碼打卡。
// AppState 會載入網頁專用的 load_timing（dart:js_interop），所以只能在瀏覽器跑：
//   flutter test --platform chrome test/pin_punch_test.dart
@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/attendance_models.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/main.dart';
import 'package:yincheng_ops/screens/attendance_manage_screen.dart';
import 'package:yincheng_ops/screens/attendance_screen.dart';
import 'package:yincheng_ops/screens/home_shell.dart';
import 'package:yincheng_ops/screens/pin_punch_screen.dart';
import 'package:yincheng_ops/theme.dart';

Future<DemoRepository> _signedIn(WidgetTester tester, String email, [DemoRepository? r]) async {
  final repo = r ?? DemoRepository();
  await tester.runAsync(() => repo.signIn(email, 'x'));
  return repo;
}

/// 先開 App 再登入（跟真的登入一樣）：直接用已登入的狀態開 App，原本就會在 build 中讀店家清單而跳警告
Future<DemoRepository> _loginApp(WidgetTester tester, String email, [DemoRepository? r]) async {
  SharedPreferences.setMockInitialValues({});
  final repo = r ?? DemoRepository();
  await tester.pumpWidget(YinchengApp(state: AppState(repo)));
  await tester.pump();
  await tester.runAsync(() => repo.signIn(email, 'x'));
  await _settle(tester);
  return repo;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.widgetWithText(OutlinedButton, d));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 50));
}

/// 打卡頁晚一點才讀到（網路慢）
class _SlowKioskRepo extends DemoRepository {
  final gate = Completer<void>();
  final done = Completer<void>();
  @override
  Future<KioskMine?> kioskMine() async {
    await gate.future;
    final k = await super.kioskMine();
    if (!done.isCompleted) done.complete();
    return k;
  }
}

/// 一小時內錯太多次：伺服器鎖到整點（測畫面不會一分鐘就放開）
class _HourLockRepo extends DemoRepository {
  final until = DateTime.now().add(const Duration(minutes: 40));
  @override
  Future<PinPunchResult> pinPunch(String pin) async =>
      PinPunchResult(result: 'locked', lockedUntil: until, message: '這台打錯太多次，暫停到 12:00；急著打卡請找店長補登');
}

String _selectedTab(WidgetTester tester) {
  final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
  return (bar.destinations[bar.selectedIndex] as NavigationDestination).label;
}

Finder _dialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

final _emptyMonth = ShiftMonth(DateTime(2026, 11), const [], const {}, const {}, const {}, const []);

Widget _wrap(DemoRepository repo, Widget child) =>
    AppScope(state: AppState(repo), child: MaterialApp(theme: buildTheme(StorePalette.gold), home: child));

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW'));

  group('公用帳號登入', () {
    testWidgets('隱城：第一頁是打卡鍵盤，原本兼職的交接、庫存、班表都在', (tester) async {
      final repo = await _loginApp(tester, 'kiosk@x');
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(PinPunchScreen), findsOneWidget);
      expect(find.text('隱城・打卡'), findsOneWidget);
      final labels = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label).toList();
      expect(labels.first, '打卡');
      expect(labels, containsAll(['交接', '庫存']));
      expect(labels, isNot(contains('營收')), reason: '權限照兼職，不會變多');
      expect(repo.isSignedIn, isTrue);
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('小城外打卡沒開：打卡頁顯示「小城外打卡尚未開啟」，其他分頁照常', (tester) async {
      await _loginApp(tester, 'kiosk-xc@x');
      expect(find.text('小城外打卡尚未開啟'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '1'), findsNothing, reason: '沒開就不顯示鍵盤');
      final labels = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label).toList();
      expect(labels, ['打卡', '交接', '庫存', ...labels.skip(3)]);
      await tester.tap(find.text('交接'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('打卡頁晚讀到才插在最前面：已經選的分頁不會跳成別頁', (tester) async {
      final repo = _SlowKioskRepo();
      await _loginApp(tester, 'kiosk@x', repo);
      expect(find.byType(PinPunchScreen, skipOffstage: false), findsNothing);
      await tester.tap(find.text('庫存'));
      await _settle(tester);
      expect(_selectedTab(tester), '庫存');
      // 登入是在真的非同步裡做的，讀打卡頁也在那邊：讓它真的跑完
      await tester.runAsync(() async {
        repo.gate.complete();
        await repo.done.future;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await _settle(tester);
      expect(find.byType(PinPunchScreen, skipOffstage: false), findsOneWidget, reason: '打卡分頁出現了（在後面，沒切過去）');
      final labels = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label).toList();
      expect(labels.first, '打卡');
      expect(_selectedTab(tester), '庫存', reason: '還是停在剛剛選的庫存，不會因為前面多一頁就跳到別頁');
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('一般帳號沒有打卡分頁', (tester) async {
      await _loginApp(tester, 'owner@x');
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(PinPunchScreen), findsNothing);
      final labels = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label);
      expect(labels, isNot(contains('打卡')));
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));
  });

  group('密碼打卡鍵盤', () {
    Future<DemoRepository> open(WidgetTester tester, [DemoRepository? r]) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = await _signedIn(tester, 'kiosk@x', r);
      final kiosk = await repo.kioskMine();
      await tester.pumpWidget(_wrap(repo, Scaffold(body: PinPunchScreen(kiosk: kiosk!))));
      await tester.pump();
      return repo;
    }

    testWidgets('密碼對：大字顯示姓名、上班、時間，4 秒後回到鍵盤；再打一次是下班', (tester) async {
      await open(tester);
      await _type(tester, '1234');
      expect(find.text('阿明'), findsOneWidget);
      expect(find.text('上班'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d\d:\d\d$')), findsOneWidget);
      expect(find.text('1234'), findsNothing, reason: '畫面上不顯示密碼');
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('阿明'), findsOneWidget, reason: '還沒到 4 秒');
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('隱城・打卡'), findsOneWidget);
      await _type(tester, '1234');
      expect(find.text('下班'), findsOneWidget);
      // 點一下馬上回鍵盤
      await tester.tap(find.text('阿明'));
      await tester.pump();
      expect(find.text('隱城・打卡'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('密碼不對：顯示剩幾次和「請找店長設定」，連錯 5 次鎖 1 分鐘、鍵盤不能按', (tester) async {
      final repo = await open(tester);
      await _type(tester, '0000');
      expect(find.textContaining('還可以試 4 次'), findsOneWidget);
      expect(find.textContaining('請找店長設定打卡密碼'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await _type(tester, '0000');
      }
      expect(find.textContaining('密碼連錯 5 次'), findsOneWidget);
      final one = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '1'));
      expect(one.onPressed, isNull, reason: '鎖住時鍵盤不能按');
      // 鎖住期間連對的密碼也打不了（資料庫一樣擋）
      expect((await repo.pinPunch('1234')).locked, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('一小時內錯太多次：鎖超過 1 分鐘，顯示伺服器的「找店長補登」，1 分鐘後鍵盤還是鎖著', (tester) async {
      await open(tester, _HourLockRepo());
      await _type(tester, '0000');
      expect(find.textContaining('急著打卡請找店長補登'), findsOneWidget);
      expect(find.textContaining('秒後再試'), findsNothing, reason: '不是 1 分鐘的鎖，不能顯示秒數倒數');
      await tester.pump(const Duration(seconds: 61));
      final one = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '1'));
      expect(one.onPressed, isNull, reason: '過 1 分鐘還在鎖：照伺服器的截止時間');
      expect(find.textContaining('急著打卡請找店長補登'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('刪除、清除：不到 4 位不送出', (tester) async {
      await open(tester);
      await _type(tester, '12');
      await tester.tap(find.bySemanticsLabel('刪除一位'));
      await tester.pump();
      await tester.tap(find.text('清除'));
      await tester.pump();
      await _type(tester, '5678');
      expect(find.text('小魚'), findsOneWidget, reason: '清掉之前按的，才打 5678');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('打卡密碼設定', () {
    Future<void> openStaff(WidgetTester tester, String email, Role role) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = await _signedIn(tester, email);
      final m = Membership(storeId: 'yc', storeName: '隱城', role: role, displayName: '示範');
      await tester.pumpWidget(_wrap(repo, AttendanceManageScreen(membership: m, data: _emptyMonth, codeTimes: const {}, staffOnly: true)));
      await _settle(tester);
    }

    testWidgets('老闆：員工資料看得到設了沒、看不到密碼；重複的被擋，隨機產生只顯示一次', (tester) async {
      await openStaff(tester, 'owner@x', Role.owner);
      expect(find.textContaining('打卡密碼已設定'), findsNWidgets(2)); // 阿明、小魚
      expect(find.textContaining('打卡密碼未設定'), findsWidgets);
      expect(find.textContaining('1234'), findsNothing);
      await tester.tap(find.text('小安'));
      await _settle(tester);
      expect(find.text('打卡密碼：未設定'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '設定'));
      await _settle(tester);
      await tester.enterText(_dialog(find.byType(TextField)), '1234');
      await tester.tap(_dialog(find.widgetWithText(FilledButton, '儲存')));
      await _settle(tester);
      expect(find.text('這組密碼不能用，請換一組'), findsOneWidget, reason: '跟阿明重複');
      await tester.enterText(_dialog(find.byType(TextField)), '12');
      await tester.tap(_dialog(find.widgetWithText(FilledButton, '儲存')));
      await _settle(tester);
      expect(find.text('打卡密碼要是 4 位數字'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '隨機產生'));
      await _settle(tester);
      expect(find.textContaining('只顯示這一次'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d{4}$')), findsOneWidget);
      await tester.tap(find.text('記下了'));
      await _settle(tester);
      expect(find.text('打卡密碼：已設定'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d{4}$')), findsNothing, reason: '關掉就看不到了');
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('店長：可以設別人的，不能設自己的', (tester) async {
      await openStaff(tester, 'manager@x', Role.manager);
      await tester.tap(find.text('阿明')); // 示範店長自己那列
      await _settle(tester);
      expect(find.text('店長的打卡密碼請老闆設定'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '重設'), findsNothing);
      await tester.pageBack();
      await _settle(tester);
      await tester.tap(find.text('小魚'));
      await _settle(tester);
      expect(find.widgetWithText(OutlinedButton, '重設'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '重設'));
      await _settle(tester);
      expect(find.text('清除密碼'), findsOneWidget, reason: '店長可以清除別人的');
      await tester.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(seconds: 90)));

    testWidgets('員工：打卡卡片沒有掃碼打卡，有「打卡密碼」可以改自己的（只能隨機產生）', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = await _signedIn(tester, 'staff@x');
      final m = Membership(storeId: 'yc', storeName: '隱城', role: Role.staff, displayName: '示範');
      await tester.pumpWidget(_wrap(repo, Scaffold(body: SingleChildScrollView(
          child: AttendanceCard(membership: m, data: _emptyMonth, codeTimes: const {})))));
      await _settle(tester);
      expect(find.text('掃碼打卡'), findsNothing);
      expect(find.textContaining('手機相機掃'), findsNothing);
      await tester.tap(find.text('打卡密碼'));
      await _settle(tester);
      expect(find.text('重設打卡密碼・阿明'), findsOneWidget);
      expect(find.text('清除密碼'), findsNothing, reason: '員工只能改，不能清除');
      expect(_dialog(find.byType(TextField)), findsNothing, reason: '自己改不能自己挑（不然試得出別人的密碼）');
      expect(_dialog(find.text('儲存')), findsNothing);
      await tester.tap(_dialog(find.widgetWithText(FilledButton, '隨機產生')));
      await _settle(tester);
      expect(find.text('新的打卡密碼・阿明'), findsOneWidget);
      final pin = tester.widgetList<Text>(_dialog(find.byType(Text))).map((t) => t.data ?? '').firstWhere((t) => RegExp(r'^[0-9]{4}$').hasMatch(t));
      expect(find.textContaining('只顯示這一次'), findsOneWidget);
      await tester.tap(find.text('記下了'));
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      await expectLater(repo.pinSet('f0', '2468'), throwsA(anything), reason: '資料庫也擋員工自己挑');
      await expectLater(repo.pinPunch(pin), throwsA(anything), reason: '員工帳號不能用密碼打卡（只有打卡用帳號可以）');
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
