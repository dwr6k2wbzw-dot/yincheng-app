import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/attendance_settings.dart';
import 'package:yincheng_ops/data/demo_repository.dart';

void main() {
  group('打卡設定（0163）', () {
    test('讀資料庫回的一列；沒值照以前的規則', () {
      final s = AttendanceSettings.fromJson({
        'enabled': true,
        'grace_min': 45,
        'check_from': '2026-12-01',
        'amend_owner_after': null,
        'manager_payroll': false,
        'can_edit': true,
      });
      expect(
        (s.enabled, s.graceMin, s.checkFrom, s.amendOwnerAfter, s.managerPayroll, s.canEdit),
        (true, 45, DateTime(2026, 12, 1), null, false, true),
      );
      final d = AttendanceSettings.fromJson({});
      expect((d.enabled, d.graceMin, d.checkFrom, d.managerPayroll, d.canEdit), (false, 30, null, true, false));
      expect(
        (AttendanceSettings.fallback.graceMin, AttendanceSettings.fallback.amendOwnerAfter),
        (30, 3),
        reason: '讀不到時跟 0163 以前一樣：寬限 30、第 4 次起要老闆',
      );
    });

    test('只送有改的項目；清掉日期、改成不限都送 null', () {
      final before = AttendanceSettings(enabled: true, graceMin: 30, checkFrom: DateTime(2026, 12, 1));
      expect(before.changesFrom(before), isEmpty);
      final after = before.copyWith(
        graceMin: 40,
        checkFrom: () => null,
        amendOwnerAfter: () => null,
      );
      expect(after.changesFrom(before), {'grace_min': 40, 'check_from': null, 'amend_owner_after': null});
      final moved = before.copyWith(checkFrom: () => DateTime(2027, 1, 5, 13), enabled: false, managerPayroll: false);
      expect(moved.changesFrom(before), {'enabled': false, 'check_from': '2027-01-05', 'manager_payroll': false});
      expect(before.copyWith(checkFrom: () => DateTime(2026, 12, 1, 23)).changesFrom(before), isEmpty, reason: '同一天不算改');
    });

    test('補登規則的說明', () {
      expect(AttendanceSettings.fallback.amendRuleLabel, '同一個人一個月第 4 次補登起只有老闆能核准');
      expect(const AttendanceSettings(enabled: true, graceMin: 30, amendOwnerAfter: 0).amendRuleLabel, '每一筆補登都要老闆核准');
      expect(const AttendanceSettings(enabled: true, graceMin: 30, amendOwnerAfter: null).amendRuleLabel, '補登店長都能核准');
    });

    test('打錯的數字：寬限 5～180、補登 0～31', () {
      expect(attendanceGraceProblem('30'), isNull);
      expect(attendanceGraceProblem(' 5 '), isNull);
      expect(attendanceGraceProblem('180'), isNull);
      expect(attendanceGraceProblem('4'), isNotNull);
      expect(attendanceGraceProblem('181'), isNotNull);
      expect(attendanceGraceProblem('半小時'), isNotNull);
      expect(attendanceAmendProblem('0'), isNull);
      expect(attendanceAmendProblem('31'), isNull);
      expect(attendanceAmendProblem('32'), isNotNull);
      expect(attendanceAmendProblem('-1'), isNotNull);
      expect(attendanceAmendProblem(''), isNotNull);
    });

    test('示範資料：老闆改了讀得回來、開打卡跟著變；店長、正職改不了', () async {
      final owner = DemoRepository();
      await owner.signIn('owner@x', 'x');
      final s = await owner.attendanceSettings('xc');
      expect((s.enabled, s.graceMin, s.canEdit), (false, 30, true));
      await owner.saveAttendanceSettings('xc', {'enabled': true, 'grace_min': 20, 'amend_owner_after': null});
      final s2 = await owner.attendanceSettings('xc');
      expect((s2.enabled, s2.graceMin, s2.amendOwnerAfter), (true, 20, null));
      expect((await owner.attendanceMe('xc'))?.enabled, isTrue);

      final manager = DemoRepository();
      await manager.signIn('manager@x', 'x');
      expect((await manager.attendanceSettings('yc')).canEdit, isFalse);
      await expectLater(manager.saveAttendanceSettings('yc', {'grace_min': 60}), throwsA(anything));
      final staff = DemoRepository();
      await staff.signIn('staff@x', 'x');
      await expectLater(staff.saveAttendanceSettings('yc', {'enabled': false}), throwsA(anything));
    });

    test('讀不到設定時照以前的規則', () async {
      expect((await attendanceSettingsOrFallback(_Broken(), 'yc')).graceMin, 30);
    });
  });
}

class _Broken extends DemoRepository {
  @override
  Future<AttendanceSettings> attendanceSettings(String storeId) async => throw Exception('db');
}
