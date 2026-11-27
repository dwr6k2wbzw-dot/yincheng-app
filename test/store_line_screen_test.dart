// LINE 官方帳號畫面（ops 0160，公版）：一步一步的說明、格式錯誤寫在表單上、斷線不卡住、接上後顯示狀態與 Webhook 網址、
// secret 不對時提醒還差一步、解除。金鑰都是假的。App 會載入網頁專用的程式，要用瀏覽器跑：
//   flutter test --platform chrome test/store_line_screen_test.dart
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/app_state.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/store_line.dart';
import 'package:yincheng_ops/screens/store_line_screen.dart';
import 'package:yincheng_ops/theme.dart';

const _secret = '0123456789abcdef0123456789abcdef';
final _token = 'tok-${'t' * 60}WXYZ';

class _Repo extends DemoRepository {
  bool offline = false;
  StoreLineResult? testResult;
  @override
  Future<StoreLineResult> testStoreLine(String storeId) async =>
      testResult ?? await super.testStoreLine(storeId);
  @override
  Future<StoreLineResult> saveStoreLine(
      String storeId, String secret, String token) async {
    if (offline) throw Exception('Failed to fetch');
    return super.saveStoreLine(storeId, secret, token);
  }
}

Future<_Repo> _open(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  final m = Membership(
      storeId: 's1', storeName: '示範小館', role: Role.owner, displayName: '示範');
  await tester.pumpWidget(AppScope(
      state: AppState(repo),
      child: MaterialApp(
          theme: buildTheme(StorePalette.gold),
          home: StoreLineScreen(membership: m))));
  await tester.pumpAndSettle();
  return repo;
}

Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  testWidgets('還沒接上：說明一步一步展開、格式不對寫在表單上', (tester) async {
    await _open(tester);
    expect(find.text('還沒接上自己的 LINE 官方帳號'), findsOneWidget);
    expect(find.text('申請 LINE 官方帳號'), findsOneWidget);
    expect(find.text('拉進群組、綁定'), findsOneWidget);
    await tester.tap(find.text('驗證並接上'));
    await tester.pumpAndSettle();
    expect(find.text('請貼上 Channel secret'), findsOneWidget);
    await tester.enterText(_field('Channel secret'), 'abc');
    await tester.tap(find.text('驗證並接上'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Channel secret 格式不對'), findsOneWidget);
  });

  testWidgets('斷線：按鈕放開、原因寫在表單上；再試接上後顯示狀態和 Webhook 網址', (tester) async {
    final repo = await _open(tester);
    await tester.enterText(_field('Channel secret'), _secret);
    await tester.enterText(_field('Channel access token'), _token);
    repo.offline = true;
    await tester.tap(find.text('驗證並接上'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '不能一直卡在處理中');
    expect(find.text('驗證並接上'), findsOneWidget);
    repo.offline = false;
    await tester.tap(find.text('驗證並接上'));
    await tester.pumpAndSettle();
    expect(find.text('已接上：示範小館通知'), findsOneWidget);
    expect(find.text('•••• WXYZ'), findsOneWidget);
    expect(find.textContaining('/functions/v1/line-notify?k='), findsOneWidget);
    expect(find.text('產生群組綁定代碼'), findsOneWidget);
  });

  testWidgets('secret 不對：存了但提醒還差一步，狀態標紅', (tester) async {
    await _open(tester);
    await tester.enterText(_field('Channel secret'), '0' * 32);
    await tester.enterText(_field('Channel access token'), _token);
    await tester.tap(find.text('驗證並接上'));
    await tester.pumpAndSettle();
    expect(find.text('還差一步'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Channel secret 不對'), findsWidgets);
    expect(find.text('還沒驗證成功'), findsOneWidget);
  });

  testWidgets('驗證一次：token 可以用但 Webhook 測試沒過，不說正常、提醒還差一步（Codex P2）',
      (tester) async {
    final repo = await _open(tester);
    await tester.enterText(_field('Channel secret'), _secret);
    await tester.enterText(_field('Channel access token'), _token);
    await tester.tap(find.text('驗證並接上'));
    await tester.pumpAndSettle();
    repo.testResult = const StoreLineResult.ok(
        verified: false,
        webhookSet: false,
        warning: 'LINE 的 Webhook 測試沒有通過：請確認 Use webhook 有打開');
    await tester.tap(find.text('驗證一次'));
    await tester.pumpAndSettle();
    expect(find.text('LINE 連線正常'), findsNothing);
    expect(find.text('還差一步'), findsOneWidget);
    expect(find.textContaining('Use webhook 有打開'), findsWidgets);
    expect(find.textContaining('/functions/v1/line-notify?k='), findsWidgets,
        reason: '要給 Webhook 網址讓老闆貼');
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    // 等前面「接上了！」的提示消失（提示會排隊）
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    repo.testResult = const StoreLineResult.ok();
    await tester.tap(find.text('驗證一次'));
    await tester.pumpAndSettle();
    expect(find.text('LINE 連線正常'), findsOneWidget);
    expect(find.text('還差一步'), findsNothing);
  });

  testWidgets('解除：回到還沒接上', (tester) async {
    await _open(tester);
    await tester.enterText(_field('Channel secret'), _secret);
    await tester.enterText(_field('Channel access token'), _token);
    await tester.tap(find.text('驗證並接上'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解除這個帳號'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '解除'));
    await tester.pumpAndSettle();
    expect(find.text('還沒接上自己的 LINE 官方帳號'), findsOneWidget);
  });
}
