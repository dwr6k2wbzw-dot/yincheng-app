// 打卡設定進度（ops 0164，公版）：資料庫回的 JSON 解析、每一步做完了沒、一定要做的有幾項。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/attendance_setup.dart';
import 'package:yincheng_ops/data/demo_repository.dart';

void main() {
  test('全新的店：什麼都沒做', () {
    final s = AttendanceSetupStatus.fromJson({
      'can_owner': true,
      'enabled': false,
      'kiosk': null,
      'kiosk_invite_until': null,
      'people': 0,
      'unbound': [],
      'no_pin': [],
      'shift_codes': false,
      'has_time': false,
      'untimed': [],
      'last_pin_punch': null,
    });
    expect(s.canOwner, isTrue);
    for (final step in SetupStep.values) {
      expect(s.done(step), isFalse, reason: '$step');
    }
    // 班表上沒有人時，對應帳號、密碼都不算做完（不然會誤以為好了）
    expect(s.requiredDone, 0);
    expect(s.ready, isFalse);
  });

  test('解析人名清單、邀請碼期限、最近一次密碼打卡', () {
    final s = AttendanceSetupStatus.fromJson({
      'can_owner': false,
      'enabled': true,
      'kiosk': {'id': 'k1', 'name': '店裡平板'},
      'kiosk_invite_until': '2026-12-12T03:00:00+00:00',
      'people': 3,
      'unbound': [
        {'id': 'p1', 'name': '王阿A'},
      ],
      'no_pin': [
        {'id': 'p2', 'name': '小B'},
        {'id': 'p3', 'name': '小C'},
      ],
      'shift_codes': false,
      'has_time': true,
      'untimed': ['O'],
      'last_pin_punch': '2026-11-28T10:00:00.123+00:00',
    });
    expect(s.kioskName, '店裡平板');
    expect(s.kioskInviteUntil, DateTime.utc(2026, 12, 12, 3));
    expect(s.unbound.single.name, '王阿A');
    expect([for (final p in s.noPin) p.id], ['p2', 'p3']);
    expect(s.done(SetupStep.enable), isTrue);
    expect(s.done(SetupStep.kiosk), isTrue);
    expect(s.done(SetupStep.accounts), isFalse);
    expect(s.done(SetupStep.pins), isFalse);
    // V 有時間、但班表上排了沒時間的 O：還不算好
    expect(s.done(SetupStep.times), isFalse);
    expect(s.done(SetupStep.test), isTrue);
    expect(s.requiredDone, 3);
  });

  test('員工對應帳號是建議：沒做也算全部完成', () {
    final s = AttendanceSetupStatus.fromJson({
      'can_owner': true,
      'enabled': true,
      'kiosk': {'id': 'k1', 'name': '平板'},
      'people': 2,
      'unbound': [
        {'id': 'p1', 'name': '阿A'},
      ],
      'no_pin': [],
      'shift_codes': true,
      'has_time': true,
      'untimed': [],
      'last_pin_punch': '2026-11-28T10:00:00Z',
    });
    expect(AttendanceSetupStatus.required.contains(SetupStep.accounts), isFalse);
    expect(s.done(SetupStep.accounts), isFalse);
    expect(s.ready, isTrue);
  });

  test('欄位缺少或格式怪：不會壞掉，當作沒做', () {
    final s = AttendanceSetupStatus.fromJson(const {});
    expect(s.enabled, isFalse);
    expect(s.kioskName, isNull);
    expect(s.people, 0);
    expect(s.lastPinPunch, isNull);
    expect(s.ready, isFalse);
  });

  test('示範：老闆打開打卡、產生平板邀請碼', () async {
    final repo = DemoRepository();
    final before = await repo.attendanceSetupStatus('yc');
    expect(before.enabled, isTrue);
    expect(before.kioskName, isNull);
    expect(before.kioskInviteUntil, isNull);
    expect(before.noPin, isNotEmpty);
    expect(before.hasTime, isTrue);
    final code = await repo.attendanceKioskInvite('yc');
    expect(code, isNotEmpty);
    expect((await repo.attendanceSetupStatus('yc')).kioskInviteUntil, isNotNull);
    await repo.attendanceSetupEnable('xc');
    expect((await repo.attendanceSetupStatus('xc')).enabled, isTrue);
  });
}
