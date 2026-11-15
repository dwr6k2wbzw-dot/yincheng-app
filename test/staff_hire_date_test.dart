// 2026-11-15 老闆：員工資料頁「離職日」改成「到職日」（算薪的應計薪名單靠到職日）。
// 到職日存在班表人員資料（shift_people.hire_date，老闆、店長能改）；離職日照樣保留，只在停用或已填離職日的人顯示。
// 人名都是示範資料（虛構）。CI 跑的是 attendance_test.dart 的「到職日、離職日」那組；這個畫面會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/staff_hire_date_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/attendance_models.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/screens/attendance_manage_screen.dart';
import 'package:yincheng_ops/theme.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW'));

  Future<DemoRepository> signedIn(WidgetTester tester, String email) async {
    SharedPreferences.setMockInitialValues({});
    final repo = DemoRepository();
    await tester.runAsync(() => repo.signIn(email, 'x'));
    return repo;
  }

  Future<StaffEntry> entry(WidgetTester tester, DemoRepository repo, String id) async =>
      (await tester.runAsync(() => repo.staffDirectory('yc')))!.firstWhere((s) => s.personId == id);

  Future<void> open(WidgetTester tester, DemoRepository repo, Role role, StaffEntry e) async {
    final m = Membership(storeId: 'yc', storeName: '隱城', role: role, displayName: '示範');
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppScope(
        state: AppState(repo),
        child: MaterialApp(
            theme: buildTheme(StorePalette.gold),
            home: Builder(
                builder: (c) => Scaffold(
                    body: Center(
                        child: TextButton(
                            onPressed: () => Navigator.of(c)
                                .push(MaterialPageRoute(builder: (_) => StaffEditScreen(membership: m, entry: e))),
                            child: const Text('開啟'))))))));
    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();
  }

  Future<void> pickDay(WidgetTester tester, String row, int day) async {
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$day').last);
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
  }

  for (final (role, email) in [(Role.owner, 'owner@x'), (Role.manager, 'manager@x')]) {
    testWidgets('${role.name}：在職的人顯示「到職日：未填」、沒有離職日；選日期存檔後重開還在', (tester) async {
      final repo = await signedIn(tester, email);
      await open(tester, repo, role, await entry(tester, repo, 'f1'));
      expect(find.text('到職日：未填'), findsOneWidget);
      expect(find.textContaining('離職日'), findsNothing);

      await pickDay(tester, '到職日：未填', 3);
      final picked = find.textContaining('到職日：');
      final label = tester.widget<Text>(picked).data!;
      expect(label, isNot('到職日：未填'));
      expect(label, endsWith('/3'));

      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();
      final saved = await entry(tester, repo, 'f1');
      expect(saved.hireDate?.day, 3);
      expect(saved.leaveDate, isNull, reason: '存到職日不會動到離職日');

      await open(tester, repo, role, saved);
      expect(find.text(label), findsOneWidget);
    });
  }

  testWidgets('清掉到職日再存，資料也跟著清掉', (tester) async {
    final repo = await signedIn(tester, 'owner@x');
    await tester.runAsync(() => repo.saveHireDate('yc', 'f2', DateTime(2025, 4, 1)));
    await open(tester, repo, Role.owner, await entry(tester, repo, 'f2'));
    expect(find.text('到職日：2025/4/1'), findsOneWidget);
    await tester.tap(find.byTooltip('清除'));
    await tester.pumpAndSettle();
    expect(find.text('到職日：未填'), findsOneWidget);
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect((await entry(tester, repo, 'f2')).hireDate, isNull);
  });

  testWidgets('已停用（離職）的人：到職日、離職日都看得到，離職日改了照樣存', (tester) async {
    final repo = await signedIn(tester, 'owner@x');
    final left = await entry(tester, repo, 'x0');
    expect((left.active, left.leaveDate), (false, DateTime(2026, 10, 31)));
    await open(tester, repo, Role.owner, left);
    expect(find.text('到職日：未填'), findsOneWidget);
    expect(find.text('離職日：2026/10/31'), findsOneWidget);

    await pickDay(tester, '離職日：2026/10/31', 30);
    expect(find.text('離職日：2026/10/30'), findsOneWidget);
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect((await entry(tester, repo, 'x0')).leaveDate, DateTime(2026, 10, 30));
  });

  test('員工不能改到職日', () async {
    SharedPreferences.setMockInitialValues({});
    final staff = DemoRepository();
    await staff.signIn('staff@x', 'x');
    await expectLater(staff.saveHireDate('yc', 'f0', DateTime(2025, 1, 1)), throwsA(anything));
  });
}
