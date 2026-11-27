// 許願單畫面（ops 0149，公版）：列出平台回覆、寫一則、表單錯誤寫在表單裡。示範資料都是虛構的。
// App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/platform_wishes_screen_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/platform_wish.dart';
import 'package:yincheng_ops/screens/platform_wishes_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  _Repo({this.empty = false});
  final bool empty;
  int loads = 0;
  final sent = <String>[];
  @override
  Future<List<PlatformWish>> platformWishes(String storeId) async {
    loads++;
    return empty ? <PlatformWish>[] : await super.platformWishes(storeId);
  }

  @override
  Future<String> createPlatformWish(String storeId, String title, String body) async {
    sent.add('$title|$body');
    return super.createPlatformWish(storeId, title, body);
  }
}

Future<_Repo> _open(WidgetTester tester, {bool empty = false}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _Repo(empty: empty);
  final m = Membership(storeId: 's1', storeName: '示範小館', role: Role.owner, displayName: '示範');
  await tester.pumpWidget(AppScope(
      state: AppState(repo),
      child: MaterialApp(theme: buildTheme(StorePalette.gold), home: PlatformWishesScreen(membership: m))));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('列出許願單和平台回覆', (tester) async {
    await _open(tester);
    expect(find.text('訂位頁可以讓客人選座位區'), findsOneWidget);
    expect(find.text('排進待辦'), findsOneWidget);
    expect(find.text('做好了'), findsOneWidget);
    expect(find.textContaining('排進下個月的待辦'), findsOneWidget);
    expect(find.textContaining('本月已寫'), findsOneWidget);
  });

  testWidgets('寫一則：沒寫想要什麼先擋、寫好送出後出現在最上面', (tester) async {
    final repo = await _open(tester);
    await tester.tap(find.text('寫許願單'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '標題'), '想要會員點數');
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle();
    expect(find.text('請寫你想要什麼'), findsOneWidget);
    expect(repo.sent, isEmpty);
    await tester.enterText(find.widgetWithText(TextField, '想要什麼'), '客人來五次送一杯');
    await tester.enterText(find.widgetWithText(TextField, '為什麼需要（可以不寫）'), '想要更多回頭客');
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle();
    expect(repo.sent, ['想要會員點數|客人來五次送一杯\n\n為什麼需要：想要更多回頭客']);
    expect(find.text('想要會員點數'), findsOneWidget);
    expect(find.text('平台收到了'), findsOneWidget);
  });

  testWidgets('沒有許願單的時候也能下拉更新（Codex P2）', (tester) async {
    final repo = await _open(tester, empty: true);
    expect(find.text('還沒有許願單'), findsOneWidget);
    expect(repo.loads, 1);
    await tester.fling(find.text('還沒有許願單'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(repo.loads, 2);
  });
}
