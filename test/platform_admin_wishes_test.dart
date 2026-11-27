// 客戶許願（平台）（ops 0159，公版）：平台管理者看所有店的許願、改狀態、寫回覆；別人剛回過要重新整理。
// 示範資料都是虛構的。App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/platform_admin_wishes_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/platform_wish.dart';
import 'package:yincheng_ops/screens/platform_admin_wishes_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  _Repo({this.staleOnce = false});
  bool staleOnce;
  int loads = 0;
  final sent = <String>[];
  @override
  Future<List<PlatformAdminWish>> platformAdminWishes() async {
    loads++;
    return super.platformAdminWishes();
  }

  @override
  Future<void> platformAdminReply(
      PlatformAdminWish w, PlatformWishStatus status, String reply) async {
    sent.add('${w.wish.id}|${platformWishStatusCode(status)}|$reply');
    if (staleOnce) {
      staleOnce = false;
      throw Exception('message: WISH_STALE：別人剛回覆過這則許願單，請重新整理,');
    }
    return super.platformAdminReply(w, status, reply);
  }
}

Future<_Repo> _open(WidgetTester tester,
    {bool staleOnce = false, String email = 'platform@demo'}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _Repo(staleOnce: staleOnce);
  await tester.runAsync(() => repo.signIn(email, 'demo'));
  await tester.pumpWidget(AppScope(
      state: AppState(repo),
      child: MaterialApp(
          theme: buildTheme(StorePalette.gold),
          home: const PlatformAdminWishesScreen())));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  test('狀態代碼、名稱、數字', () {
    expect(platformWishStatusCode(PlatformWishStatus.received), 'new');
    expect(platformAdminStatusLabel(PlatformWishStatus.planned), '規劃中');
    final c =
        platformWishCountsOf(const [MapEntry('new', 3), MapEntry('done', 1)]);
    expect(c[PlatformWishStatus.received], 3);
    expect(c[PlatformWishStatus.declined], 0);
    expect(validateAdminReply('x' * 1001), '回覆最多 1000 個字');
    expect(validateAdminReply('好'), isNull);
    expect(isWishStale(Exception('message: WISH_STALE：x,')), isTrue);
  });

  testWidgets('預設看「新的」，分頁有數字，可以切到全部', (tester) async {
    await _open(tester);
    expect(find.text('新的 3'), findsOneWidget);
    expect(find.text('規劃中 1'), findsOneWidget);
    expect(find.text('全部 6'), findsOneWidget);
    expect(find.text('會員集點換飲料'), findsOneWidget);
    expect(find.text('晨光咖啡'), findsOneWidget);
    expect(find.text('盤點可以掃條碼'), findsNothing);
    await tester.tap(find.text('全部 6'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('盤點可以掃條碼'), 200);
    expect(find.text('盤點可以掃條碼'), findsOneWidget);
  });

  testWidgets('回覆：選狀態、寫回覆、送出後移到「規劃中」', (tester) async {
    final repo = await _open(tester);
    await tester.tap(find.text('會員集點換飲料'));
    await tester.pumpAndSettle();
    expect(find.text('店家會看到：平台收到了'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '規劃中').last);
    await tester.pumpAndSettle();
    expect(find.text('店家會看到：排進待辦'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '下個月做');
    await tester.tap(find.text('送出回覆'));
    await tester.pumpAndSettle();
    expect(repo.sent, ['pa-1|planned|下個月做']);
    expect(find.text('已回覆，店家會收到通知'), findsOneWidget);
    expect(find.text('新的 2'), findsOneWidget);
    expect(find.text('規劃中 2'), findsOneWidget);
    expect(find.text('會員集點換飲料'), findsNothing);
  });

  testWidgets('什麼都沒改按送出：表單裡提示，不送', (tester) async {
    final repo = await _open(tester);
    await tester.tap(find.text('會員集點換飲料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出回覆'));
    await tester.pumpAndSettle();
    expect(find.text('狀態和回覆都沒有改'), findsOneWidget);
    expect(repo.sent, isEmpty);
  });

  testWidgets('別人剛回覆過：關掉、提示、重新整理', (tester) async {
    final repo = await _open(tester, staleOnce: true);
    expect(repo.loads, 1);
    await tester.tap(find.text('會員集點換飲料'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '不做').last);
    await tester.tap(find.text('送出回覆'));
    await tester.pumpAndSettle();
    expect(find.text('別人剛回覆過，已重新整理'), findsOneWidget);
    expect(find.text('送出回覆'), findsNothing);
    expect(repo.loads, 2);
  });

  testWidgets('不是平台管理者：顯示沒有權限的錯誤', (tester) async {
    await _open(tester, email: 'owner@demo');
    expect(find.textContaining('只有平台管理者'), findsOneWidget);
  });
}
