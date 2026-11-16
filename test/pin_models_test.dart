// 2026-11-16 打卡用帳號＋4 位數密碼打卡（ops 0112）：App 端讀資料庫回傳的欄位、CSV 來源。
// 密碼對錯、鎖定、同店不重複、只有打卡用帳號能打、店長不能設自己的：完整驗證在私人 repo 的 tests/27_kiosk_account.sql（資料庫端）。
// 畫面（鍵盤、員工資料設定）在 pin_punch_test.dart，要在瀏覽器跑。要在台北、UTC、紐約三個時區都過。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/attendance_models.dart';
import 'package:yincheng_ops/services/attendance_csv.dart';

void main() {
  test('PinPunchResult：成功、密碼不對、鎖住', () {
    final ok = PinPunchResult.fromRow({
      'result': 'ok',
      'person_name': '阿明',
      'punch_type': 'in',
      'punched_at': '2026-11-16T12:30:00+00:00',
      'business_date': '2026-11-16',
      'status': 'pending',
      'flags': ['no_shift'],
      'remaining': 5,
      'locked_until': null,
      'message': '',
    });
    expect(ok.ok, isTrue);
    expect(ok.pending, isTrue);
    expect(ok.personName, '阿明');
    expect(ok.flags, ['no_shift']);
    expect(ok.punchedAt!.toUtc(), DateTime.utc(2026, 11, 16, 12, 30));

    final wrong = PinPunchResult.fromRow({'result': 'wrong', 'remaining': 3, 'message': '密碼不對'});
    expect(wrong.ok, isFalse);
    expect(wrong.locked, isFalse);
    expect(wrong.remaining, 3);
    expect(wrong.flags, isEmpty);

    final locked = PinPunchResult.fromRow({'result': 'locked', 'locked_until': '2026-11-16T12:31:00+00:00'});
    expect(locked.locked, isTrue);
    expect(locked.lockedUntil!.toUtc(), DateTime.utc(2026, 11, 16, 12, 31));
    expect(locked.message, '');
  });

  test('KioskMine：哪家店；打卡沒開時 error 有原因', () {
    final k = KioskMine.fromRow({'kiosk_id': 'k1', 'store_id': 's1', 'store_name': '小城外', 'kiosk_name': '公用', 'error': '小城外打卡尚未開啟'});
    expect(k.storeName, '小城外');
    expect(k.error, '小城外打卡尚未開啟');
    expect(KioskMine.fromRow({'kiosk_id': 'k1', 'store_id': 's1'}).error, isNull);
  });

  test('PinStatus、PinSetResult：只有設了沒，沒有密碼本身', () {
    final p = PinStatus.fromRow(
        {'person_id': 'p1', 'name': '小魚', 'active': true, 'has_pin': true, 'set_at': '2026-11-16T01:00:00Z', 'can_set': false, 'mine': true});
    expect(p.hasPin, isTrue);
    expect(p.canSet, isFalse);
    expect(p.mine, isTrue);
    final empty = PinStatus.fromRow({'person_id': 'p2'});
    expect(empty.hasPin, isFalse);
    expect(empty.canSet, isFalse);

    expect(PinSetResult.fromRow({'result': 'ok', 'pin': '4821'}).pin, '4821');
    final taken = PinSetResult.fromRow({'result': 'taken', 'message': '這組密碼不能用，請換一組'});
    expect(taken.ok, isFalse);
    expect(taken.pin, isNull);
  });

  test('KioskInfo：有綁帳號＝打卡用帳號', () {
    final base = {'id': 'k1', 'name': '公用', 'active': true, 'created_at': '2026-11-16T00:00:00Z'};
    expect(KioskInfo.fromRow(base).isAccount, isFalse);
    final acc = KioskInfo.fromRow({...base, 'account_user_id': 'u1', 'account_name': '隱城公用'});
    expect(acc.isAccount, isTrue);
    expect(acc.accountName, '隱城公用');
  });

  test('CSV：密碼打卡的來源寫「密碼」', () {
    AttendanceExportRow row(String source) => AttendanceExportRow(
        businessDate: DateTime(2026, 11, 16),
        personName: '阿明',
        punchType: 'in',
        punchedAt: DateTime.utc(2026, 11, 16, 12),
        storeName: '隱城',
        source: source,
        status: 'ok',
        flags: '',
        counted: true,
        punchId: 'x');
    final lines = buildAttendanceCsv([row('pin'), row('qr'), row('amendment')]).split('\r\n');
    expect(lines[1].split(',')[5], '密碼');
    expect(lines[2].split(',')[5], 'QR');
    expect(lines[3].split(',')[5], '補登');
  });
}
