// 自動排班演算法檢查（CI：pr-check.yml `dart run tool/shift_plan_check.dart`）
// 用接近兩家店 10 月真實狀況的假資料，確認條件都有照做。
import 'dart:io';

import 'package:yincheng_ops/data/shift_planner.dart';

var _fail = 0;
void check(String name, bool ok, [String detail = '']) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'} $name${ok || detail.isEmpty ? '' : '：$detail'}');
  if (!ok) _fail++;
}

bool isWork(String? m) => m != null && m.isNotEmpty && !{'休', '指休', '特休'}.contains(m);

void main() {
  const y = 2026, mo = 12;
  final days = DateTime(y, mo + 1, 0).day;
  int wd(int d) => DateTime(y, mo, d).weekday;

  // ---- 隱城：5 正職＋4 兼職，平日 3 人、週五六 4 人 ----
  final people = [
    for (final n in ['A', 'B', 'C', 'D', 'E'])
      PlanPerson(id: n, name: n, full: true, offTarget: 10, marks: const ['V'], noWeekdays: n == 'A' ? {1} : const {}),
    PlanPerson(id: 'p1', name: 'p1', full: false, minShifts: 4, maxShifts: 8, marks: const ['V']),
    PlanPerson(id: 'p2', name: 'p2', full: false, maxShifts: 6, marks: const ['O']),
    PlanPerson(id: 'p3', name: 'p3', full: false, marks: const ['V'], maxConsecutive: 2),
    PlanPerson(id: 'p4', name: 'p4', full: false, maxShifts: 10, marks: const ['V']),
  ];
  final need = {for (var d = 1; d <= days; d++) d: (wd(d) == 5 || wd(d) == 6) ? 4 : 3};
  need[24] = 6; // 特別日子
  final minFull = {for (var d = 1; d <= days; d++) d: 1};
  final requests = {
    'B': {5: 'off', 6: 'off', 7: 'off'},
    'C': {24: 'off'},
    'p4': {3: 'on', 10: 'on', 17: 'on', 24: 'on'},
  };
  final fixed = {
    'D': {1: '特休', 2: 'V'},
  };
  for (var seed = 0; seed < 20; seed++) {
    final r = planShifts(
        year: y, month: mo, people: people, needByDay: need, minFullByDay: minFull, fixed: fixed, requests: requests, seed: seed);
    final e = r.entries;
    final tag = '[seed $seed]';
    check('$tag 想休的日子都沒排上班', [5, 6, 7].every((d) => !isWork(e['B']![d])) && !isWork(e['C']![24]));
    check('$tag 正職想休的那天是指休', e['B']![5] == '指休');
    check('$tag A 每週一都不排', [for (var d = 1; d <= days; d++) if (wd(d) == 1) d].every((d) => !isWork(e['A']![d])));
    check('$tag 保留的格子不動', e['D']![1] == '特休' && e['D']![2] == 'V');
    check('$tag 兼職有填可以上，只排那些天', e['p4']!.keys.every((d) => requests['p4']!.containsKey(d)));
    check('$tag 兼職沒上班是空白', e['p1']!.values.every(isWork));
    check('$tag 兼職不超過最多天數', r.workDays['p1']! <= 8 && r.workDays['p2']! <= 6);
    check('$tag 兼職記號照條件', e['p2']!.values.every((m) => m == 'O'));
    for (final p in people) {
      var run = 0, worst = 0;
      for (var d = 1; d <= days; d++) {
        run = isWork(e[p.id]![d]) ? run + 1 : 0;
        if (run > worst) worst = run;
      }
      check('$tag ${p.name} 連上不超過 ${p.maxConsecutive} 天', worst <= p.maxConsecutive, '連上 $worst 天');
    }
    final fullOff = ['A', 'B', 'C', 'E'].map((n) => e[n]!.values.where((m) => m == '休' || m == '指休').length);
    check('$tag 正職休假天數＝應休（10 天）', fullOff.every((n) => n == 10), '$fullOff');
    check('$tag D 有排特休，休假少一天以外照應休', e['D']!.values.where((m) => m == '休' || m == '指休').length == 10);
    final shortDays = [for (var d = 1; d <= days; d++) if (r.staffed[d]! < need[d]!) d];
    check('$tag 人力都補足（24 號特別日子以外）', shortDays.every((d) => d == 24), '$shortDays');
    check('$tag 人不夠會提醒', shortDays.isEmpty || r.warnings.any((w) => w.contains('少')));
    check('$tag 每天至少 1 個正職', [for (var d = 1; d <= days; d++) d].every((d) => ['A', 'B', 'C', 'D', 'E'].any((n) => isWork(e[n]![d]))));
  }

  // ---- 自訂規則：A、B 不能同一天；p1 上班時 C 也要上 ----
  final rules = [const PairRule(a: 'A', b: 'B', kind: 'apart'), const PairRule(a: 'p1', b: 'C', kind: 'with')];
  for (var seed = 0; seed < 20; seed++) {
    final r = planShifts(
        year: y, month: mo, people: people, needByDay: need, minFullByDay: minFull, requests: requests, pairRules: rules, seed: seed);
    final e = r.entries;
    final tag = '[規則 seed $seed]';
    final both = [for (var d = 1; d <= days; d++) if (isWork(e['A']![d]) && isWork(e['B']![d])) d];
    check('$tag A 跟 B 沒有同一天上班', both.isEmpty, '$both');
    final alone = [for (var d = 1; d <= days; d++) if (isWork(e['p1']![d]) && !isWork(e['C']![d])) d];
    check('$tag p1 上班那天 C 都有上', alone.isEmpty, '$alone');
    final shortDays = [for (var d = 1; d <= days; d++) if (r.staffed[d]! < need[d]!) d];
    check('$tag 人力都補足（24 號以外）', shortDays.every((d) => d == 24), '$shortDays');
  }

  // ---- 小城外：班別輪流（B、BH），兼職時段 ----
  final xc = [
    PlanPerson(id: 'g', name: 'g', full: true, offTarget: 9, marks: const ['RBK', 'B']),
    PlanPerson(id: 'w', name: 'w', full: true, offTarget: 9, marks: const ['B', 'BH']),
    PlanPerson(id: 'l', name: 'l', full: true, offTarget: 9, marks: const ['B', 'BH']),
    PlanPerson(id: 't', name: 't', full: false, minShifts: 3, maxShifts: 10, marks: const ['18:00-00:30']),
    PlanPerson(id: 'v', name: 'v', full: false, marks: const ['19:00-00:30']), // 不限天數（人力才補得滿）
  ];
  final xneed = {for (var d = 1; d <= days; d++) d: switch (wd(d)) { 1 || 2 => 2, 5 || 6 => 4, _ => 3 }};
  final r = planShifts(year: y, month: mo, people: xc, needByDay: xneed, minFullByDay: {for (var d = 1; d <= days; d++) d: 1});
  final both = [for (var d = 1; d <= days; d++) if (r.entries['w']![d] != null && r.entries['l']![d] != null && isWork(r.entries['w']![d]) && isWork(r.entries['l']![d])) d];
  check('[小城外] 同一天兩個人都上 B 系時會分成 B、BH', both.every((d) => r.entries['w']![d] != r.entries['l']![d]));
  check('[小城外] 兼職排時段', r.entries['t']!.values.every((m) => m == '18:00-00:30'));
  check('[小城外] 兼職至少 3 天', r.workDays['t']! >= 3);
  check('[小城外] 人力補足', [for (var d = 1; d <= days; d++) d].every((d) => r.staffed[d]! >= xneed[d]!),
      '${[for (var d = 1; d <= days; d++) if (r.staffed[d]! < xneed[d]!) d]}');

  stdout.writeln(_fail == 0 ? '✓ 自動排班檢查全部通過' : '✗ $_fail 項沒過');
  exit(_fail == 0 ? 0 : 1);
}
