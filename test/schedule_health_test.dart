import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/schedule_health.dart';
import 'package:yincheng_ops/data/shift_planner.dart';

ShiftMonth month(Map<String, Map<int, String>> marks,
        {List<ShiftPerson>? people}) =>
    ShiftMonth(
      DateTime(2026, 12),
      people ??
          [
            ShiftPerson(id: 'a', name: '甲'),
            ShiftPerson(id: 'b', name: '乙'),
            ShiftPerson(id: 'c', name: '丙', kind: 'part'),
          ],
      marks,
      {},
      {},
      [],
    );

void main() {
  group('parseDayNumber', () {
    test('空白是 null、不算錯', () {
      expect(parseDayNumber('  '), (ok: true, value: null));
    });
    test('數字、全形、後面帶天都可以', () {
      expect(parseDayNumber('8').value, 8);
      expect(parseDayNumber('8.5').value, 8.5);
      expect(parseDayNumber('８').value, 8);
      expect(parseDayNumber('9天').value, 9);
    });
    test('打錯的字不能當成空白', () {
      expect(parseDayNumber('八').ok, false);
      expect(parseDayNumber('8天半').ok, false);
      expect(parseDayNumber('-1').ok, false);
    });
    test('只收整數的欄位', () {
      expect(parseDayNumber('5', integer: true).value, 5);
      expect(parseDayNumber('5.5', integer: true).ok, false);
    });
  });

  group('isMonthScheduled', () {
    const setup = ShiftPlanSetup(staffing: {
      1: StaffingNeed(2),
      2: StaffingNeed(2),
      3: StaffingNeed(2),
      4: StaffingNeed(2),
      5: StaffingNeed(2),
      6: StaffingNeed(2),
      7: StaffingNeed(2),
    });
    test('只點一天特休不算排好', () {
      expect(
          isMonthScheduled(
              month({
                'a': {3: '特休'}
              }),
              setup),
          false);
    });
    test('一格上班也不算排好', () {
      expect(
          isMonthScheduled(
              month({
                'a': {3: 'V'}
              }),
              setup),
          false);
    });
    test('上班人次到八成算排好', () {
      // 12 月要 62 人次，八成＝49.6 → 50
      final full = {
        'a': {for (var d = 1; d <= 31; d++) d: 'V'},
        'b': {for (var d = 1; d <= 19; d++) d: 'V'},
      };
      expect(isMonthScheduled(month(full), setup), true);
      full['b']!.remove(19);
      expect(isMonthScheduled(month(full), setup), false);
    });
    test('隱藏的人不算', () {
      final m = month({
        'a': {for (var d = 1; d <= 31; d++) d: 'V'},
        'b': {for (var d = 1; d <= 31; d++) d: 'V'},
      }, people: [
        ShiftPerson(id: 'a', name: '甲'),
        ShiftPerson(id: 'b', name: '乙', active: false),
      ]);
      expect(isMonthScheduled(m, setup), false);
    });
    test('讀不到設定時每天當 3 人', () {
      expect(requiredShifts(DateTime(2026, 12), null), 93);
    });
  });

  group('editIssues', () {
    test('排休假不檢查', () {
      final s = const ShiftPlanSetup(requests: {
        'a': {5: 'off'}
      });
      expect(
          editIssues(
              data: month({}), setup: s, personId: 'a', day: 5, mark: '休'),
          isEmpty);
    });
    test('填了指休的日子排上班＝一定不行', () {
      final s = const ShiftPlanSetup(requests: {
        'a': {5: 'off'}
      });
      final r = editIssues(
          data: month({}), setup: s, personId: 'a', day: 5, mark: 'V');
      expect(r.map((i) => (i.code, i.level)), contains(('off', 0)));
    });
    test('另一家店那天有班＝一定不行', () {
      final s = const ShiftPlanSetup(otherStoreDays: {
        'c': {7}
      });
      final r = editIssues(
          data: month({}),
          setup: s,
          personId: 'c',
          day: 7,
          mark: '18:00-00:30');
      expect(r.map((i) => (i.code, i.level)), contains(('busy', 0)));
      expect(
          editIssues(
              data: month({}), setup: s, personId: 'c', day: 8, mark: 'V'),
          isEmpty);
    });
    test('固定不排的星期、不能同一天、連上太多＝違反條件', () {
      final s = ShiftPlanSetup(
        rules: {
          'a': const ShiftRule(
              personId: 'a', noWeekdays: {1}, maxConsecutive: 3),
        },
        pairRules: const [PairRule(a: 'a', b: 'b', kind: 'apart')],
      );
      // 12/7 是週一
      expect(
          editIssues(
                  data: month({}), setup: s, personId: 'a', day: 7, mark: 'V')
              .map((i) => i.code),
          ['weekday']);
      expect(
          editIssues(
                  data: month({
                    'b': {9: 'V'}
                  }),
                  setup: s,
                  personId: 'a',
                  day: 9,
                  mark: 'V')
              .map((i) => i.code),
          ['pair']);
      final run = {
        'a': {10: 'V', 11: 'V', 12: 'V'}
      };
      expect(
          editIssues(
                  data: month(run), setup: s, personId: 'a', day: 13, mark: 'V')
              .map((i) => i.code),
          ['run']);
    });
    test('沒有問題就是空的', () {
      expect(
          editIssues(
              data: month({}),
              setup: const ShiftPlanSetup(),
              personId: 'a',
              day: 2,
              mark: 'V'),
          isEmpty);
    });
    test('超過最多天數只在這一格讓它超過時提醒', () {
      final s = ShiftPlanSetup(
          rules: {'c': const ShiftRule(personId: 'c', maxShifts: 2)});
      expect(
          editIssues(
              data: month({
                'c': {1: 'V'}
              }),
              setup: s,
              personId: 'c',
              day: 2,
              mark: 'V'),
          isEmpty);
      expect(
          editIssues(
                  data: month({
                    'c': {1: 'V', 2: 'V'}
                  }),
                  setup: s,
                  personId: 'c',
                  day: 3,
                  mark: 'V')
              .map((i) => i.code),
          ['max']);
      expect(
          editIssues(
              data: month({
                'c': {1: 'V', 2: 'V', 3: 'V'}
              }),
              setup: s,
              personId: 'c',
              day: 4,
              mark: 'V'),
          isEmpty);
    });
  });

  group('draftConflicts（照片套用前，0113）', () {
    test('指休那天、另一家店有班那天排上班會列出來；休、新人員不列', () {
      final s = ShiftPlanSetup(requests: const {
        'a': {3: 'off'}
      }, otherStoreDays: const {
        'c': {5}
      });
      final r = draftConflicts(
        month: DateTime(2026, 12),
        entries: const {
          '甲': {3: 'V', 4: 'V'},
          '丙': {5: '18:00-00:30', 6: 'V'},
          '乙': {3: '休'},
          '新人': {3: 'V'},
        },
        people: [ShiftPerson(id: 'a', name: '甲'), ShiftPerson(id: 'b', name: '乙'), ShiftPerson(id: 'c', name: '丙', kind: 'part')],
        setup: s,
      );
      expect(r, ['丙 12/5 另一家店已經有班', '甲 12/3 填了指休']);
    });
  });

  group('停用的班別（0113）', () {
    test('選單不列，時數照算', () {
      const o = ShiftOptions([
        ShiftMarkOption(kind: 'code', mark: 'B', timeRange: '17:00-00:30'),
        ShiftMarkOption(kind: 'code', mark: 'BX', timeRange: '18:00-00:30', hidden: true),
        ShiftMarkOption(kind: 'range', mark: '19:00-00:30'),
      ]);
      expect(o.codes.map((c) => c.mark), ['B']);
      expect(o.allCodes.map((c) => c.mark), ['B', 'BX']);
      expect(o.ranges, ['19:00-00:30']);
    });
  });
}
