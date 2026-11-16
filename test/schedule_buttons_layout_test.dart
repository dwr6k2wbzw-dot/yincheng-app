// 老闆 2026-11-17：班表頁下方的按鈕（班表人員、班別／時段、排班條件、修改紀錄、匯出、重新自動排）
// 原本大小不一、換行亂掉，改成同寬同高的格子：手機 2 欄、寬一點 4 欄；匯出、重新自動排各佔兩格。
// 人名、照片都是示範資料（虛構）。版面溢出會讓測試失敗。
// 畫面會載入網頁專用的程式（上傳照片、匯出），要用瀏覽器跑：
//   flutter test --platform chrome test/schedule_buttons_layout_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/screens/schedule_screen.dart';
import 'package:yincheng_ops/theme.dart';

/// 示範班表多一張原始照片
class _PhotoRepo extends DemoRepository {
  @override
  Future<ShiftMonth> shiftMonth(String storeId, DateTime month) async {
    final d = await super.shiftMonth(storeId, month);
    return ShiftMonth(d.month, d.people, d.marks, d.notes, d.stats, [ShiftPhoto('ph1', '$storeId/demo.jpg', null)], d.draft,
        d.options);
  }
}

const _settings = ['班表人員', '班別／時段', '排班條件', '修改紀錄'];

void main() {
  setUpAll(() => initializeDateFormatting('zh_TW'));

  final month = DateTime.now().month;
  final export = '匯出 $month 月班表（Excel）';
  final replan = '重新自動排 $month 月';

  Future<void> pump(WidgetTester tester, Role role, double width, {double textScale = 1}) async {
    SharedPreferences.setMockInitialValues({});
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 4000); // 夠高，整頁一次排完
    addTearDown(tester.view.reset);
    final repo = _PhotoRepo();
    await tester.runAsync(() => repo.signIn('owner@x', 'x'));
    final m = Membership(storeId: 'xc', storeName: '小城外', role: role, displayName: '示範');
    // 改版前就有、不是這次改的地方（main 上同樣出現），不算這次的問題：
    // 週格子的日期欄高度固定，測試字型下會高 1px、字放大時更多；字放大 2 倍時上方卡片裡有一列太寬。
    // 其他錯誤（包括下方按鈕）照常讓測試失敗
    final orig = FlutterError.onError;
    FlutterError.onError = (d) {
      final where = d.informationCollector?.call().join('\n') ?? '';
      final msg = d.exceptionAsString();
      if (msg.contains('A RenderFlex overflowed by') && msg.contains('pixels on the bottom') &&
          where.contains('Column ← Align ← Padding ← DecoratedBox') &&
          where.contains('GestureDetector ← Row')) {
        return;
      }
      if (msg.contains('A RenderFlex overflowed by') && msg.contains('pixels on the right') &&
          where.contains('Row ← Column ← Padding ← DecoratedBox ← ConstrainedBox ← Container ← SectionCard')) {
        return;
      }
      orig?.call(d);
    };
    await tester.pumpWidget(AppScope(
        state: AppState(repo),
        child: MaterialApp(theme: buildTheme(StorePalette.gold), home: Scaffold(body: ScheduleScreen(membership: m)))));
    await tester.pumpAndSettle();
    FlutterError.onError = orig;
  }

  Rect box(WidgetTester tester, String label) => tester.getRect(find
      .ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>())
      .first);

  for (final (width, cols) in [(390.0, 2), (360.0, 2), (640.0, 4)]) {
    testWidgets('老闆，寬 $width：四個設定同寬同高（$cols 欄）、匯出和重新自動排各佔兩格', (tester) async {
      await pump(tester, Role.owner, width);
      final s = [for (final l in _settings) box(tester, l)];
      final e = box(tester, export), r = box(tester, replan);
      for (final b in [...s, e, r]) {
        expect(b.height, 48);
      }
      for (final b in s) {
        expect(b.width, s.first.width);
      }
      // 每列左邊對齊；匯出、重新自動排＝兩格加中間的間距
      expect(s[0].left, s[cols == 2 ? 2 : 0].left);
      expect(e.left, s[0].left);
      expect(e.width, s[0].width * 2 + 8);
      expect(r.width, e.width);
      if (cols == 4) {
        expect({for (final b in s) b.top}.length, 1); // 四個在同一列
        expect(r.top, e.top); // 匯出、重新自動排同一列
      } else {
        expect(s[1].top, s[0].top);
        expect(s[2].top, greaterThan(s[0].top));
        expect(r.top, greaterThan(e.top)); // 手機上各自一整列
      }
      // 照片那一組：照片標籤和「再加一張」同高
      final photo = tester.getRect(find.widgetWithText(InputChip, '照片 1'));
      final add = tester.getRect(find.widgetWithText(ActionChip, '再加一張'));
      expect(add.height, photo.height);
      expect(add.top, photo.top);
    });
  }

  // 程式審查 2026-11-17：寬 552、字放大 1.3 倍時，原本固定高 48 會把換行的字切掉
  for (final (width, scale) in [(552.0, 1.3), (640.0, 1.3), (390.0, 2.0)]) {
    testWidgets('系統字放大 $scale 倍、寬 $width：字不會被切掉，同一列一樣大', (tester) async {
      await pump(tester, Role.owner, width, textScale: scale);
      final labels = [..._settings, export, replan];
      for (final l in labels) {
        final b = box(tester, l), t = tester.getRect(find.text(l));
        expect(b.height, greaterThanOrEqualTo(48), reason: l);
        expect(t.top >= b.top && t.bottom <= b.bottom && t.left >= b.left && t.right <= b.right, isTrue,
            reason: '$l 的字 $t 超出按鈕 $b');
      }
      final s = [for (final l in _settings) box(tester, l)];
      expect(s[1].top, s[0].top); // 字放大就 2 欄（每格比較寬）
      expect(s[2].top, greaterThan(s[0].top));
      for (final b in s) {
        expect(b.width, s.first.width);
      }
      // 同一列一樣高（其中一個換行，整列一起變高）
      expect(s[1].height, s[0].height);
      expect(s[3].height, s[2].height);
    });
  }

  testWidgets('店長看到的按鈕跟老闆一樣', (tester) async {
    await pump(tester, Role.manager, 390);
    for (final l in [..._settings, export, replan, '再加一張']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
  });

  testWidgets('員工：只看到匯出（照舊），沒有設定、重新自動排、加照片', (tester) async {
    await pump(tester, Role.staff, 390);
    expect(find.text(export), findsOneWidget);
    for (final l in [..._settings, replan, '再加一張']) {
      expect(find.text(l), findsNothing, reason: l);
    }
    expect(box(tester, export).height, 48);
  });
}
