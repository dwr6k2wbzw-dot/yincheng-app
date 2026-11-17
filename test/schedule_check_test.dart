import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/payroll.dart';
import 'package:yincheng_ops/data/repository.dart';
import 'package:yincheng_ops/services/attendance_csv.dart';

/// ops 0127：打卡跟班表比對、加班申請、核准的加班帶入薪資
void main() {
  group('ScheduleCheckRow', () {
    final row = ScheduleCheckRow.fromRow({
      'business_date': '2026-11-14',
      'person_id': 'p1',
      'person_name': '小安',
      'mark': 'V',
      'plan_start': '2026-11-14T11:00:00Z', // 台北 19:00
      'plan_end': '2026-11-14T17:30:00Z', // 台北 01:30
      'first_in': '2026-11-14T10:50:00Z',
      'last_out': '2026-11-14T18:45:00Z',
      'issues': ['late_out'],
      'early_in_min': null,
      'late_in_min': null,
      'early_out_min': null,
      'late_out_min': 75,
      'punch_pending': false,
      'ot_approved': null,
      'ot_pending': false,
    });

    test('讀得到異常和分鐘數', () {
      expect(row.issues, ['late_out']);
      expect(row.issueText('late_out'), '晚走 1 小時 15 分');
      expect(row.lateWithoutOvertime, isTrue);
    });

    test('建議的加班時數往下取到 0.5 小時，最少 0.5', () {
      expect(row.suggestedOvertimeHours, 1.0);
      expect(
        const ScheduleCheckRow(
          businessDate: _d,
          personId: 'x',
          personName: 'x',
          issues: ['late_out'],
          lateOutMin: 31,
        ).suggestedOvertimeHours,
        0.5,
      );
      expect(
        const ScheduleCheckRow(
          businessDate: _d,
          personId: 'x',
          personName: 'x',
          issues: ['late_out'],
          lateOutMin: 100,
        ).suggestedOvertimeHours,
        1.5,
      );
    });

    test('有核准或待審的加班就不算「沒申請」', () {
      expect(
        const ScheduleCheckRow(
          businessDate: _d,
          personId: 'x',
          personName: 'x',
          issues: ['late_out'],
          otApproved: 1,
        ).lateWithoutOvertime,
        isFalse,
      );
      expect(
        const ScheduleCheckRow(
          businessDate: _d,
          personId: 'x',
          personName: 'x',
          issues: ['late_out'],
          otPending: true,
        ).lateWithoutOvertime,
        isFalse,
      );
    });

    test('沒有分鐘數的異常只顯示名稱', () {
      const r = ScheduleCheckRow(
        businessDate: _d,
        personId: 'x',
        personName: 'x',
        issues: ['no_punch'],
      );
      expect(r.issueText('no_punch'), '有排班沒打卡');
    });
  });

  test('時間長度', () {
    expect(durationLabel(40), '40 分');
    expect(durationLabel(60), '1 小時');
    expect(durationLabel(150), '2 小時 30 分');
    expect(hoursLabel(2), '2');
    expect(hoursLabel(2.5), '2.5');
  });

  test('V 的時間：那個星期另設的優先，沒有就用平常的', () {
    const times = [
      ShiftMarkTime(mark: 'V', timeRange: '18:00-00:30'),
      ShiftMarkTime(mark: 'V', weekday: 5, timeRange: '19:00-01:30'),
    ];
    expect(markTimeOn(times, 'V', DateTime(2026, 11, 13)), '19:00-01:30'); // 週五
    expect(markTimeOn(times, 'V', DateTime(2026, 11, 12)), '18:00-00:30'); // 週四
    expect(markTimeOn(times, 'O', DateTime(2026, 11, 12)), isNull);
  });

  test('加班申請的狀態文字', () {
    final o = OvertimeRequest.fromRow({
      'id': 'o1',
      'person_id': 'p1',
      'person_name': '小安',
      'business_date': '2026-11-14',
      'hours': 3,
      'reason': '包場',
      'after_the_fact': true,
      'status': 'approved',
      'approved_hours': 2.5,
      'requested_by_name': '小安',
      'requested_at': '2026-11-15T03:00:00Z',
      'mine': false,
      'can_decide': false,
    });
    expect(o.statusLabel, '已核准 2.5 小時');
    expect(o.afterTheFact, isTrue);
    expect(o.pending, isFalse);
  });

  test('匯出報表：表頭、異常文字、核准加班', () {
    final csv = buildScheduleCheckCsv([
      const ScheduleCheckRow(
        businessDate: _d,
        personId: 'x',
        personName: '小安',
        mark: 'V',
        issues: ['late_out'],
        lateOutMin: 75,
        otApproved: 1,
      ),
    ]);
    final lines = const LineSplitter().convert(csv);
    expect(lines.first, startsWith('營業日,姓名,班表'));
    expect(lines[1], contains('晚走 1 小時 15 分'));
    expect(lines[1], contains(',1,'));
    expect(scheduleCheckCsvBytes(const []).sublist(0, 3), [0xEF, 0xBB, 0xBF]);
  });

  test('薪資列讀得到核准的加班帶入', () {
    final r = PayrollRow.fromRow({
      'person_id': 'p1',
      'name': '小安',
      'pay_type': 'monthly',
      'ot_hours': 2,
      'ot_hours2': 0.5,
      'auto_ot_hours': 2,
      'auto_ot_hours2': 0.5,
      'ot_manual': false,
    });
    expect(r.autoOtHours, 2);
    expect(r.autoOtHours2, 0.5);
    expect(r.otManual, isFalse);
    expect(
      PayrollRow.fromRow({'person_id': 'p1', 'name': '小安'}).autoOtHours,
      isNull,
    );
  });
}

const _d = _Date();

/// const 用的固定日期
class _Date implements DateTime {
  const _Date();
  @override
  dynamic noSuchMethod(Invocation i) => DateTime(2026, 11, 14).noSuchMethod(i);
}
