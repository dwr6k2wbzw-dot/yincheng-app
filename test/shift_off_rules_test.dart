import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/shift_off_rules.dart';
import 'package:yincheng_ops/data/shift_planner.dart';

void main() {
  ShiftPerson person(String id, String kind) => ShiftPerson.fromRow({'id': id, 'name': id, 'kind': kind, 'sort_order': 0, 'active': true});

  test('資料庫有回就用資料庫的', () {
    final m = offTakenDays(fromDb: {5: {'a'}}, people: const [], setup: const ShiftPlanSetup());
    expect(m, {5: {'a'}});
  });

  test('資料庫還沒更新：只算正職、不算排班時當兼職和兼職', () {
    final people = [person('a', 'full'), person('b', 'full'), person('c', 'part')];
    final setup = ShiftPlanSetup(
      rules: {'b': ShiftRule(personId: 'b', planAsPart: true)},
      requests: {'a': {5: 'off', 6: 'on'}, 'b': {7: 'off'}, 'c': {8: 'off'}},
    );
    expect(offTakenDays(fromDb: null, people: people, setup: setup), {5: {'a'}});
  });

  test('同一天已經有別人指休；自己填的不算', () {
    final taken = {5: {'a'}};
    expect(offCheck(takenDays: taken, mine: const {}, personId: 'b', day: 5).taken, {'a'});
    expect(offCheck(takenDays: taken, mine: const {5: 'off'}, personId: 'a', day: 5).taken, isEmpty);
  });

  test('每月最多 5 天：第 6 天才擋，改同一天不算', () {
    final five = {for (var d = 1; d <= 5; d++) d: 'off'};
    expect(offCheck(takenDays: const {}, mine: five, personId: 'a', day: 10).overLimit, isTrue);
    expect(offCheck(takenDays: const {}, mine: five, personId: 'a', day: 3).overLimit, isFalse);
    expect(offCheck(takenDays: const {}, mine: {...five}..remove(5), personId: 'a', day: 10).overLimit, isFalse);
    expect(offCheck(takenDays: const {}, mine: {...five, 9: 'on'}, personId: 'a', day: 9).overLimit, isTrue);
  });

  test('勞基法特休：半年 3、1 年 7、2 年 10、3～4 年 14、5～9 年 15、10 年 16、24 年起 30', () {
    final g = lsaSpecialGrants(DateTime(2025, 7, 18));
    expect(g.first, (DateTime(2026, 1, 18), 3));
    expect(g[1], (DateTime(2026, 7, 18), 7));
    expect([for (final x in g.skip(2).take(9)) x.$2], [10, 14, 14, 15, 15, 15, 15, 15, 16]);
    expect(g[24].$2, 30);
    expect(g[30].$2, 30);
  });

  test('店長劃的特休：排班先固定成特休，不算在應休裡', () {
    const p = PlanPerson(id: 'a', name: '甲', full: true, offTarget: 8, marks: ['V']);
    final r = planShifts(
        year: 2026, month: 12, people: [p], needByDay: {for (var d = 1; d <= 31; d++) d: 1}, minFullByDay: const {},
        requests: {'a': {5: 'special', 6: 'off'}});
    final row = r.entries['a']!;
    expect(row[5], '特休');
    expect(row[6], '指休');
    expect(row.values.where((m) => m == '休' || m == '指休').length, 8); // 應休 8 天照樣休滿
    expect(row.values.where(isWorkMark).length, 31 - 8 - 1);
  });
}
