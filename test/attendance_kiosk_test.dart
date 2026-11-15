// 2026-11-15 班表第一階段：打卡機畫面（老闆）。
// AppState 會載入網頁專用的 load_timing（dart:js_interop），所以只能在瀏覽器跑：
//   flutter test --platform chrome test/attendance_kiosk_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/screens/kiosk_screen.dart';
import 'package:yincheng_ops/theme.dart';

const _k = '0f8fad5b-d9cb-469f-a165-70867728950e';

void main() {
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
    });
  });

}
