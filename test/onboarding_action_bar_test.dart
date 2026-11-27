import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/screens/onboarding_action_bar.dart';

// 開店精靈底部的按鈕列（Codex P2）：窄手機、字放大時不能擠出畫面
void main() {
  Future<void> pump(WidgetTester t, {required double width, double textScale = 1}) async {
    t.view.physicalSize = Size(width * 3, 700 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 700), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: OnboardingActionBar(
            label: '建立線上訂位',
            onPrimary: () {},
            showBack: true,
            onBack: () {},
            showSkip: true,
            onSkip: () {},
          ),
        ),
      ),
    ));
  }

  testWidgets('320 寬＋字放大 1.3 倍：不擠出畫面，主要按鈕滿寬在上、上一步和先略過在下面', (t) async {
    await pump(t, width: 320, textScale: 1.3);
    expect(t.takeException(), isNull);
    final primary = t.getRect(find.byType(FilledButton));
    final back = t.getRect(find.text('上一步'));
    final skip = t.getRect(find.text('先略過'));
    expect(primary.width, greaterThan(270));
    expect(back.top, greaterThan(primary.bottom - 1));
    expect(skip.top, greaterThan(primary.bottom - 1));
    for (final r in [primary, back, skip]) {
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(320));
    }
  });

  testWidgets('390 寬＋字放大 1.3 倍也改成上下兩列、不擠出畫面', (t) async {
    await pump(t, width: 390, textScale: 1.3);
    expect(t.takeException(), isNull);
    expect(t.getRect(find.text('上一步')).top, greaterThan(t.getRect(find.byType(FilledButton)).bottom - 1));
  });

  testWidgets('320 寬、字正常大小也不擠出畫面', (t) async {
    await pump(t, width: 320);
    expect(t.takeException(), isNull);
    expect(t.getRect(find.byType(FilledButton)).right, lessThanOrEqualTo(320));
  });

  for (final w in [375.0, 390.0]) {
  testWidgets('一般手機寬度（${w.toInt()}）排成一列、不擠出畫面', (t) async {
    await pump(t, width: w);
    expect(t.takeException(), isNull);
    final primary = t.getRect(find.byType(FilledButton));
    final back = t.getRect(find.text('上一步'));
    expect((primary.center.dy - back.center.dy).abs(), lessThan(4));
    expect(primary.right, lessThanOrEqualTo(w));
  });
  }
}
