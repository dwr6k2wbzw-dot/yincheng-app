// 訂位頁的樣子（公版階段 2 第 3 步）：讀資料、即時預覽、開關語言、檢查、存檔。示範資料都是虛構的。
// 畫面會載入網頁專用的程式（選圖、開新視窗），要用瀏覽器跑：
//   flutter test --platform chrome test/booking_page_screen_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/booking_profile.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/screens/booking_page_screen.dart';
import 'package:yincheng_ops/theme.dart';

class _Repo extends DemoRepository {
  BookingProfile? saved;
  @override
  Future<void> saveBookingProfile(String storeId, BookingProfile p) async {
    saved = p;
    await super.saveBookingProfile(storeId, p);
  }
}

Future<_Repo> _open(WidgetTester tester, {List<Membership> sisters = const []}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 844 * 3); // 手機尺寸，版面溢出會讓測試失敗
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  final settings = (await tester.runAsync(() => repo.reservationSettings('yc')))!;
  final m = Membership(storeId: 'yc', storeName: '隱城', role: Role.owner, displayName: '示範');
  await tester.pumpWidget(AppScope(
      state: AppState(repo),
      child: MaterialApp(
          theme: buildTheme(StorePalette.gold),
          home: BookingPageScreen(membership: m, settings: settings, sisterChoices: sisters))));
  await tester.pumpAndSettle();
  return repo;
}

Finder _field(String label) => find.ancestor(of: find.text(label), matching: find.byType(TextField)).first;

/// 清單是邊捲邊建的：先捲到看得到
Future<void> _show(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus(); // 不然捲動後游標所在的欄位會把畫面拉回去
  await tester.pumpAndSettle();
  await _show(tester, find.text('儲存'));
  await tester.tap(find.text('儲存'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('讀出原本的內容：預覽顯示大標；介紹只在欄位裡（訂位頁本身不顯示介紹）', (tester) async {
    await _open(tester);
    expect(find.text('示範酒吧'), findsWidgets);
    expect(find.descendant(of: find.byType(AspectRatio), matching: find.text('老宅二樓的小酒吧')), findsNothing);
    expect(find.text('預覽'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
    await _show(tester, find.text('一句話介紹（姊妹店卡片上用）'));
    expect(find.text('老宅二樓的小酒吧'), findsOneWidget);
  });

  testWidgets('改大標，預覽馬上跟著變；切到英文看英文', (tester) async {
    await _open(tester);
    await _show(tester, find.text('大標'));
    await tester.enterText(_field('大標'), '大稻埕的夜晚');
    await tester.pump();
    await tester.scrollUntilVisible(find.text('預覽'), -300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AspectRatio), matching: find.text('大稻埕的夜晚')), findsOneWidget); // 預覽
    await _show(tester, find.byType(SegmentedButton<String>));
    await tester.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('English')));
    await tester.pumpAndSettle();
    expect(find.text('Demo Bar'), findsWidgets);
    expect(find.text('地址（這個語言）'), findsOneWidget);
  });

  testWidgets('低消金額亂填：表單上直接說，不會存', (tester) async {
    final repo = await _open(tester);
    await _show(tester, find.text('低消金額（每人；空白＝不顯示低消）'));
    await tester.enterText(_field('低消金額（每人；空白＝不顯示低消）'), '0');
    await _save(tester);
    expect(find.text('低消金額要是 1～100000 的整數，或留白'), findsOneWidget);
    expect(repo.saved, isNull);
  });

  testWidgets('關掉英文再存：只存中文、文字和取景都帶過去', (tester) async {
    final repo = await _open(tester);
    await _show(tester, find.text('語言'));
    await tester.tap(find.descendant(of: find.byType(Wrap), matching: find.text('English')).first);
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<String>), findsNothing); // 只剩中文就不用切換
    await _show(tester, find.text('大標'));
    await tester.enterText(_field('大標'), '新店名');
    await _save(tester);
    final s = repo.saved!;
    expect(s.langs, ['zh']);
    expect(s.title, {'zh': '新店名'});
    expect(s.heroPos, '22% 45%');
    expect(s.toRow()['address_i18n'], <String, String>{});
    expect(find.text('已儲存訂位頁，客人重新整理就看得到'), findsOneWidget);
  });

  testWidgets('拿掉封面照：預覽沒有圖、取景拉桿不見、存成沒有封面照', (tester) async {
    final repo = await _open(tester);
    await _show(tester, find.text('封面照取景（拖拉看上面的預覽）'));
    await tester.ensureVisible(find.byTooltip('拿掉').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('拿掉').last);
    await tester.pumpAndSettle();
    expect(find.text('封面照取景（拖拉看上面的預覽）'), findsNothing);
    await _save(tester);
    expect(repo.saved!.heroUrl, isNull);
    expect(repo.saved!.heroPos, isNull);
    expect(repo.saved!.logoUrl, 'logo-xcw.png');
  });

  testWidgets('資訊卡：新增一列沒填中文標題卻填了內容，要求補標題', (tester) async {
    final repo = await _open(tester);
    await _show(tester, find.text('新增一列'));
    await tester.tap(find.text('新增一列'));
    await tester.pumpAndSettle();
    await _show(tester, find.widgetWithText(TextField, '內容').last);
    await tester.enterText(find.widgetWithText(TextField, '內容').last, '只有內容');
    await _save(tester);
    expect(find.text('資訊卡第 2 列要有中文標題'), findsOneWidget);
    expect(repo.saved, isNull);
  });

  testWidgets('有別的店才出現姊妹店選單', (tester) async {
    await _open(tester);
    await _show(tester, find.text('儲存'));
    expect(find.text('姊妹店'), findsNothing);
    await _open(tester, sisters: [Membership(storeId: 'xc', storeName: '小城外', role: Role.owner, displayName: '示範')]);
    await _show(tester, find.text('儲存'));
    expect(find.text('姊妹店'), findsOneWidget);
  });
}
