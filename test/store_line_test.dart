// 店家自己的 LINE 官方帳號（ops 0160）：格式檢查跟資料庫同一套、狀態解析、Webhook 網址。金鑰都是假的。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/store_line.dart';

void main() {
  test('Channel secret：32 個英數字（小寫 16 進位）', () {
    expect(storeLineSecretProblem('0123456789abcdef0123456789abcdef'), isNull);
    expect(
        storeLineSecretProblem(' 0123456789abcdef0123456789abcdef '), isNull);
    expect(storeLineSecretProblem(''), contains('請貼上'));
    expect(storeLineSecretProblem('0123456789ABCDEF0123456789ABCDEF'),
        contains('格式不對'));
    expect(storeLineSecretProblem('0123'), contains('格式不對'));
  });

  test('Channel access token：40～600 字、不能有空白', () {
    expect(storeLineTokenProblem('t' * 172), isNull);
    expect(storeLineTokenProblem(''), contains('請貼上'));
    expect(storeLineTokenProblem('short'), contains('格式不對'));
    expect(storeLineTokenProblem('${'a' * 30} ${'b' * 30}'), contains('格式不對'));
    expect(storeLineTokenProblem('a' * 601), contains('格式不對'));
  });

  test('狀態：接上、群組透過哪個帳號、Webhook 網址接在這個環境的網址後面', () {
    final s = StoreLineStatus.fromJson({
      'connected': true,
      'bot_name': '小店通知',
      'basic_id': '@abc1234',
      'secret_last4': 'cdef',
      'token_last4': 'WXYZ',
      'verified_at': '2026-11-28T01:02:03+00:00',
      'last_error': null,
      'webhook_path': '/functions/v1/line-notify?k=${'a' * 32}',
      'group_bound': true,
      'group_via': 'store',
    });
    expect(s.connected, isTrue);
    expect(s.groupViaStore, isTrue);
    expect(s.webhookUrl('https://x.supabase.co/'),
        'https://x.supabase.co/functions/v1/line-notify?k=${'a' * 32}');
    final none = StoreLineStatus.fromJson(
        {'connected': false, 'group_bound': true, 'group_via': 'platform'});
    expect(none.connected, isFalse);
    expect(none.groupViaStore, isFalse);
    expect(none.webhookUrl('https://x.supabase.co'), isNull);
  });

  test(
      '一步一步的說明照順序：申請 → Messaging API → secret → token → 貼上 → Use webhook → 綁群組',
      () {
    expect(storeLineSteps.length, 7);
    expect(storeLineSteps.first.$1, contains('申請'));
    expect(storeLineSteps.last.$1, contains('綁定'));
  });

  test('示範資料：接上、token 不能用、secret 不對、驗證、解除', () async {
    final r = DemoRepository();
    expect((await r.storeLineStatus('s1')).connected, isFalse);
    final bad = await r.saveStoreLine(
        's1', '0123456789abcdef0123456789abcdef', 'bad-${'t' * 60}');
    expect(bad.ok, isFalse);
    expect((await r.storeLineStatus('s1')).connected, isFalse);
    final ok = await r.saveStoreLine(
        's1', '0123456789abcdef0123456789abcdef', 'tok-${'t' * 60}WXYZ');
    expect(ok.ok && ok.verified, isTrue);
    final st = await r.storeLineStatus('s1');
    expect(st.connected, isTrue);
    expect(st.tokenLast4, 'WXYZ');
    expect((await r.testStoreLine('s1')).ok, isTrue);
    final wrong = await r.saveStoreLine('s1', '0' * 32, 'tok-${'t' * 60}');
    expect(wrong.ok && !wrong.verified, isTrue);
    expect(wrong.warning, contains('Channel secret 不對'));
    await r.clearStoreLine('s1');
    expect((await r.storeLineStatus('s1')).connected, isFalse);
  });
}
