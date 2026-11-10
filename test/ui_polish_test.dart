// 2026-11-10 介面整理：這幾個是「畫面上的錯」，改回去就會壞，所以留測試
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/theme.dart';
import 'package:yincheng_ops/widgets/content_width_limit.dart';

Widget _app(Widget child) => MaterialApp(theme: buildTheme(StorePalette.gold), home: Scaffold(body: child));

void main() {
  group('輸入框', () {
    testWidgets('有內容時，標籤留在框裡面（原本浮到上緣、一半跑出框外）', (tester) async {
      await tester.pumpWidget(_app(Padding(
        padding: const EdgeInsets.all(40),
        child: TextField(
          controller: TextEditingController(text: '8000'),
          decoration: const InputDecoration(labelText: '現金'),
        ),
      )));
      await tester.pumpAndSettle();
      final field = tester.getRect(find.byType(TextField));
      final label = tester.getRect(find.text('現金'));
      expect(label.top, greaterThanOrEqualTo(field.top), reason: '標籤上緣不能高過輸入框');
      expect(label.bottom, lessThan(tester.getRect(find.text('8000')).top + 1), reason: '標籤在內容上面');
    });
  });

  group('按鈕外形', () {
    final theme = buildTheme(StorePalette.gold);
    const want = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)));
    test('主要按鈕、外框按鈕、文字按鈕、分段切換都是同一種圓角（不是膠囊形）', () {
      expect(theme.filledButtonTheme.style!.shape!.resolve({}), want);
      expect(theme.outlinedButtonTheme.style!.shape!.resolve({}), want);
      expect(theme.textButtonTheme.style!.shape!.resolve({}), want);
      expect(theme.segmentedButtonTheme.style!.shape!.resolve({}), want);
    });
    test('分段切換：選到的那一格用主色字', () {
      final fg = theme.segmentedButtonTheme.style!.foregroundColor!;
      expect(fg.resolve({WidgetState.selected}), StorePalette.gold.primary);
      expect(fg.resolve({}), StorePalette.gold.text);
    });
  });

  group('電腦寬度 ContentWidthLimit', () {
    Future<Size> pumpAt(WidgetTester tester, Size screen) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late Size seen;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(StorePalette.gold),
        builder: (context, child) => ContentWidthLimit(child: child!),
        home: Builder(builder: (context) {
          seen = MediaQuery.of(context).size;
          return const Scaffold(body: SizedBox.expand(key: Key('body')));
        }),
      ));
      return seen;
    }

    testWidgets('電腦上置中、最寬 640，裡面看到的畫面寬度也是 640', (tester) async {
      final seen = await pumpAt(tester, const Size(1280, 800));
      final body = tester.getRect(find.byKey(const Key('body')));
      expect(body.width, 640);
      expect(body.left, 320);
      expect(seen.width, 640);
    });
    testWidgets('手機寬度不受影響', (tester) async {
      final seen = await pumpAt(tester, const Size(390, 844));
      expect(tester.getRect(find.byKey(const Key('body'))).width, 390);
      expect(seen.width, 390);
    });
  });
}
