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
  bool platformCode = false; // 0161：模擬老闆貼了平台機器人給的代碼
  StoreLineResult? testResult;
  @override
  Future<bool> linkLineOwnerVia(String storeId, String code) async {
    if (platformCode) {
      await linkLineOwner(code);
      return false;
    }
    return super.linkLineOwnerVia(storeId, code);
  }
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

  // ---------------- 0161：私訊也走這個官方帳號 ----------------
  Future<void> connect(WidgetTester tester) async {
    await tester.enterText(_field('Channel secret'), _secret);
    await tester.enterText(_field('Channel access token'), _token);
    await tester.tap(find.text('驗證並接上'));
    await tester.pumpAndSettle();
    // 接上的提示先收掉，不然後面的提示排在它後面、還看不到
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
    await tester.pumpAndSettle();
  }

  Future<void> bindDm(WidgetTester tester, String code) async {
    await tester.tap(find.text('綁定我的私訊'));
    await tester.pumpAndSettle();
    expect(find.textContaining('私訊打「綁定」'), findsOneWidget);
    expect(find.textContaining('示範小館通知'), findsWidgets, reason: '要說私訊哪個帳號');
    await tester.enterText(_field('代碼'), code);
    await tester.tap(find.widgetWithText(FilledButton, '綁定'));
    await tester.pumpAndSettle();
  }

  testWidgets('私訊（0161）：還沒接上不顯示；接上後可以用這個帳號綁定、解除', (tester) async {
    await _open(tester);
    expect(find.textContaining('私訊：'), findsNothing);
    await connect(tester);
    expect(find.text('私訊：還沒用這個帳號綁定'), findsOneWidget);
    await bindDm(tester, '123456');
    expect(find.text('私訊：已用這個帳號綁定'), findsOneWidget);
    expect(find.textContaining('訂位異常會私訊你'), findsOneWidget);
    await tester.tap(find.text('解除我的私訊綁定'));
    await tester.pumpAndSettle();
    expect(find.text('私訊：還沒用這個帳號綁定'), findsOneWidget);
  });

  testWidgets('私訊（0161）：代碼不對寫錯誤、不算綁上', (tester) async {
    await _open(tester);
    await connect(tester);
    await bindDm(tester, '12');
    expect(find.textContaining('代碼不對或已過期'), findsOneWidget);
    expect(find.text('私訊：還沒用這個帳號綁定'), findsOneWidget);
  });

  testWidgets('私訊（0161）：貼了平台機器人的代碼 → 講清楚綁到平台、這個帳號還沒綁', (tester) async {
    final repo = await _open(tester);
    await connect(tester);
    repo.platformCode = true;
    await bindDm(tester, '654321');
    expect(find.textContaining('平台的 LINE 機器人給的'), findsOneWidget);
    expect(find.text('私訊：還沒用這個帳號綁定'), findsOneWidget);
  });

  testWidgets('私訊（0161）：解除官方帳號時私訊綁定一起拿掉', (tester) async {
    final repo = await _open(tester);
    await connect(tester);
    await bindDm(tester, '123456');
    expect(await repo.lineOwnerLinkedVia('s1'), isTrue);
    await tester.tap(find.text('解除這個帳號'));
    await tester.pumpAndSettle();
    expect(find.textContaining('私訊也會一起解除'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '解除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('私訊：'), findsNothing);
    expect(await repo.lineOwnerLinkedVia('s1'), isFalse);
  });
}
