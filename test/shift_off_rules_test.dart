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

  test('ops 0150 同一天上限 2 位：一位時不擋、兩位才擋；不限＝永遠不擋', () {
    expect(offCheck(takenDays: {5: {'a'}}, mine: const {}, personId: 'c', day: 5, perDay: 2).dayFull, isFalse);
    expect(offCheck(takenDays: {5: {'a', 'b'}}, mine: const {}, personId: 'c', day: 5, perDay: 2).dayFull, isTrue);
    expect(offCheck(takenDays: {5: {'a', 'b', 'd'}}, mine: const {}, personId: 'c', day: 5, perDay: null).dayFull, isFalse);
    // 預設照舊（一位就滿）
    expect(offCheck(takenDays: {5: {'a'}}, mine: const {}, personId: 'c', day: 5).dayFull, isTrue);
  });

  test('ops 0150 每月上限 3 天、不限', () {
    final three = {1: 'off', 2: 'off', 3: 'off'};
    expect(offCheck(takenDays: const {}, mine: three, personId: 'a', day: 10, monthMax: 3).overLimit, isTrue);
    expect(offCheck(takenDays: const {}, mine: {1: 'off', 2: 'off'}, personId: 'a', day: 10, monthMax: 3).overLimit, isFalse);
    expect(offCheck(takenDays: const {}, mine: {for (var d = 1; d <= 20; d++) d: 'off'}, personId: 'a', day: 25, monthMax: null).overLimit,
        isFalse);
  });

  test('ops 0150 排班設定讀上限：沒有那一列、資料庫還沒更新＝預設 1／5；欄位空白＝不限', () {
    expect(offLimitsFromRow(null), (perDay: 1, monthMax: 5));
    expect(offLimitsFromRow({'request_deadline': 20}), (perDay: 1, monthMax: 5));
    expect(offLimitsFromRow({'off_per_day': 2, 'off_month_max': 3}), (perDay: 2, monthMax: 3));
    expect(offLimitsFromRow({'off_per_day': null, 'off_month_max': null}), (perDay: null, monthMax: null));
  });

  test('ops 0150 說明文字跟著設定變', () {
    expect(offRuleText(1, 5), '同一天只能一位正職指休（先填先贏），每月最多 5 天；要再多請找店長協調班表。');
    expect(offRuleText(2, null), '同一天最多 2 位正職指休（先填先贏）；要再多請找店長協調班表。');
    expect(offRuleText(null, 3), '每月最多 3 天；要再多請找店長協調班表。');
    expect(offRuleText(null, null), '指休沒有限制。');
    expect(offBlockedText(dayFull: true, perDay: 1), '已有人指休，請找店長協調班表');
    expect(offBlockedText(dayFull: true, perDay: 2), '這天指休的人已經滿了（最多 2 位），請找店長協調班表');
    expect(offBlockedText(dayFull: false, monthMax: 3), '一個月最多指休 3 天，要再多請找店長協調班表');
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

  test('排班時當兼職的正職：店長劃的特休照樣排成特休（Codex P2）', () {
    const p = PlanPerson(id: 'k', name: '凱', full: false, marks: ['V'], maxShifts: 10);
    final r = planShifts(
        year: 2026, month: 12, people: [p], needByDay: {for (var d = 1; d <= 31; d++) d: 1}, minFullByDay: const {},
        requests: {'k': {5: 'special'}});
    expect(r.entries['k']![5], '特休');
  });

  test('排之前的檢查也把店長劃的特休算進去（Codex P2）', () {
    const p = PlanPerson(id: 'a', name: '甲', full: true, offTarget: 8, marks: ['V'], maxShifts: 22);
    final issues = precheckPlan(
        year: 2026, month: 12, people: [p], needByDay: {for (var d = 1; d <= 31; d++) d: 1}, minFullByDay: const {},
        requests: {'a': {5: 'special'}});
    expect(issues.where((i) => i.level == 0), isEmpty);
  });

  test('原本是休、指休的格子，店長劃特休後改成特休；排上班的留著給檢查擋（Codex P2）', () {
    final f = withSpecialLeave({'a': {5: '休', 6: '指休', 7: 'V'}}, {'a': {5: 'special', 6: 'special', 7: 'special', 8: 'special'}});
    expect(f['a'], {5: '特休', 6: '特休', 7: 'V', 8: '特休'});
  });
}
