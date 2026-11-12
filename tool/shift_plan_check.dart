// 自動排班演算法檢查（CI：pr-check.yml `dart run tool/shift_plan_check.dart`）
// 用接近兩家店真實狀況的假資料（人名用代號），確認條件都有照做。
// 第二版（2026-11-12）：加檢查器、排前檢查、跨月連班、跨店、依星期班別的回歸測試，
// 以及兩家店的設定 × 4 個月 × 多組亂數：選出來的班表不能缺正職、不能缺人、不能違反條件。
import 'dart:io';
import 'dart:math';

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

  // ---- 小城外：班別依星期（0098），兼職時段 ----
  const wk = {1: 'B', 2: 'B', 3: 'B', 4: 'B', 5: 'BH', 6: 'BH', 7: 'B'};
  final xc = [
    PlanPerson(id: 'g', name: 'g', full: true, offTarget: 9, marks: const ['B'], weekdayMarks: {...wk, 6: 'RBK', 7: 'RBK'}),
    PlanPerson(id: 'w', name: 'w', full: true, offTarget: 9, marks: const ['B', 'BH'], weekdayMarks: wk),
    PlanPerson(id: 'l', name: 'l', full: true, offTarget: 9, marks: const ['B', 'BH']), // 沒設依星期 → 用第一個記號
    PlanPerson(id: 't', name: 't', full: false, minShifts: 3, maxShifts: 10, marks: const ['18:00-00:30']),
    PlanPerson(id: 'v', name: 'v', full: false, marks: const ['19:00-00:30']), // 不限天數（人力才補得滿）
  ];
  final xneed = {for (var d = 1; d <= days; d++) d: switch (wd(d)) { 1 || 2 => 2, 5 || 6 => 4, _ => 3 }};
  final r = planShifts(year: y, month: mo, people: xc, needByDay: xneed, minFullByDay: {for (var d = 1; d <= days; d++) d: 1});
  check('[小城外] 班別照星期（週五六 BH、其他 B；g 週六日 RBK）',
      [for (var d = 1; d <= days; d++) d].every((d) =>
          (!isWork(r.entries['w']![d]) || r.entries['w']![d] == wk[wd(d)]) &&
          (!isWork(r.entries['g']![d]) || r.entries['g']![d] == (wd(d) >= 6 ? 'RBK' : wk[wd(d)]))));
  check('[小城外] 沒設依星期的人用第一個記號', r.entries['l']!.values.where(isWork).every((m) => m == 'B'));
  check('[小城外] 兼職排時段', r.entries['t']!.values.every((m) => m == '18:00-00:30'));
  check('[小城外] 兼職至少 3 天', r.workDays['t']! >= 3);
  check('[小城外] 人力補足', [for (var d = 1; d <= days; d++) d].every((d) => r.staffed[d]! >= xneed[d]!),
      '${[for (var d = 1; d <= days; d++) if (r.staffed[d]! < xneed[d]!) d]}');

  regressions();
  realSetups();

  stdout.writeln(_fail == 0 ? '✓ 自動排班檢查全部通過' : '✗ $_fail 項沒過');
  exit(_fail == 0 ? 0 : 1);
}

int maxRunOf(Map<int, String> row, int days, {int prev = 0}) {
  var run = prev, worst = 0;
  for (var d = 1; d <= days; d++) {
    run = isWork(row[d]) ? run + 1 : 0;
    if (run > worst) worst = run;
  }
  return worst;
}

/// 第二版的回歸測試（ChatGPT 審查 2026-11-12 列的項目）
void regressions() {
  const y = 2026, mo = 12;
  const days = 31;
  int wd(int d) => DateTime(y, mo, d).weekday;
  final need3 = {for (var d = 1; d <= days; d++) d: 3};
  final mf1 = {for (var d = 1; d <= days; d++) d: 1};
  PlanCheck chk(List<PlanPerson> ps, Map<String, Map<int, String>> e,
          {Map<int, int>? need, Map<int, int>? mf, Map<String, Map<int, String>> req = const {}, List<PairRule> rules = const []}) =>
      validateSchedule(year: y, month: mo, people: ps, needByDay: need ?? need3, minFullByDay: mf ?? mf1, entries: e, requests: req, pairRules: rules);

  // --- 檢查器 ---
  final a = PlanPerson(id: 'a', name: 'a', full: true, offTarget: 10, marks: const ['V'], prevRun: 3, maxShifts: 20);
  final b = PlanPerson(id: 'b', name: 'b', full: false, marks: const ['V'], busy: const {5}, noWeekdays: const {1});
  final c = PlanPerson(id: 'c', name: 'c', full: false, marks: const ['V'], maxShifts: 2);
  var k = chk([a, b, c], {
    'a': {1: 'V', 2: 'V', 3: 'V', 4: 'V', 10: 'V'},
    'b': {5: 'V', 7: 'V'},
    'c': {8: 'V', 9: 'V', 11: 'V'},
  }, req: {
    'a': {10: 'off'}
  });
  bool has(String code, [int? level]) => k.issues.any((i) => i.code == code && (level == null || i.level == level));
  check('[檢查器] 指休排上班 → 一定不行', has('off', 0) && !k.canApply);
  check('[檢查器] 另一家店有班那天排上班 → 一定不行', has('busy', 0));
  check('[檢查器] 跨月連上（上月底 3 天＋月初 4 天）', has('run', 1), k.issues.map((i) => i.text).join('｜'));
  check('[檢查器] 固定不排的星期', has('weekday', 1));
  check('[檢查器] 超過最多天數', has('max', 1));
  check('[檢查器] 缺人的日子就算缺人也要列缺正職', k.issues.any((i) => i.code == 'noFull' && i.days.contains(20)) && k.issues.any((i) => i.code == 'short' && i.days.contains(20)));
  check('[檢查器] 有問題的格子會標出來', k.badCells.containsKey('a|10') && k.badCells.containsKey('b|5'));
  k = chk([a, b], {'a': {1: 'V'}, 'b': {2: 'V', 3: 'V'}}, need: {for (var d = 1; d <= days; d++) d: d == 1 ? 0 : 1}, mf: const {});
  check('[檢查器] 不用排人的日子排了人會提醒', k.issues.any((i) => i.code == 'over' && i.days.contains(1)));
  k = chk([a, c], {'a': {8: 'V'}, 'c': {8: 'V', 9: 'V'}}, rules: const [PairRule(a: 'c', b: 'a', kind: 'with')]);
  check('[檢查器] 要一起上卻沒一起', k.issues.any((i) => i.code == 'pair' && i.days.length == 1 && i.days.first == 9));
  final clean = planShifts(year: y, month: mo, people: [
    for (final n in ['f1', 'f2', 'f3']) PlanPerson(id: n, name: n, full: true, offTarget: 10, marks: const ['V']),
    for (final n in ['q1', 'q2', 'q3']) PlanPerson(id: n, name: n, full: false, marks: const ['V']),
  ], needByDay: need3, minFullByDay: mf1);
  check('[檢查器] 排得出來的月份沒有任何問題', clean.check!.clean && clean.check!.score.take(6).every((x) => x == 0), clean.warnings.join('｜'));

  // --- 排前檢查 ---
  final pre = precheckPlan(year: y, month: mo, needByDay: need3, minFullByDay: mf1, people: [
    PlanPerson(id: 'boss', name: 'boss', full: true, offTarget: 18, maxShifts: 12, marks: const ['V']),
    PlanPerson(id: 'x', name: 'x', full: false, minShifts: 5, maxShifts: 3, marks: const ['V']),
  ]);
  check('[排前] 應休 18 天＝要上 13 天，跟最多 12 天衝突 → 要先改', pre.any((i) => i.level == 0 && i.personId == 'boss'));
  check('[排前] 最少比最多還多 → 要先改', pre.any((i) => i.level == 0 && i.personId == 'x'));
  check('[排前] 人不夠會先講', pre.any((i) => i.code == 'thin' || i.code == 'supply'));

  // --- 排班 ---
  for (var seed = 0; seed < 10; seed++) {
    final tag = '[回歸 seed $seed]';
    // 不用排人的日子（need=0）不能有人；正職補天數也不能補到那天
    final need = {for (var d = 1; d <= days; d++) d: wd(d) == 1 ? 0 : 2};
    var r = planShifts(year: y, month: mo, seed: seed, needByDay: need, minFullByDay: mf1, people: [
      PlanPerson(id: 'f1', name: 'f1', full: true, offTarget: 6, marks: const ['V']),
      PlanPerson(id: 'f2', name: 'f2', full: true, offTarget: 6, marks: const ['V']),
      PlanPerson(id: 'p', name: 'p', full: false, minShifts: 30, marks: const ['V']),
    ]);
    check('$tag 不用排人的日子沒有人', [for (var d = 1; d <= days; d++) if (need[d] == 0) d].every((d) => r.staffed[d] == 0));
    check('$tag 兼職最少天數排不到時不硬塞（不超編）', [for (var d = 1; d <= days; d++) d].every((d) => r.staffed[d]! <= max(need[d]!, 2)));
    // 跨月連班＋另一家店有班＋盡量不超過 5 天
    r = planShifts(year: y, month: mo, seed: seed, needByDay: need3, minFullByDay: mf1, requests: {
      'f1': {24: 'off', 25: 'off'}
    }, people: [
      PlanPerson(id: 'f1', name: 'f1', full: true, offTarget: 9, marks: const ['V'], prevRun: 5, preferRun: 5),
      PlanPerson(id: 'f2', name: 'f2', full: true, offTarget: 9, marks: const ['V'], prevRun: 3, preferRun: 5),
      PlanPerson(id: 'f3', name: 'f3', full: true, offTarget: 9, marks: const ['V'], nextRun: 4, preferRun: 5),
      PlanPerson(id: 's', name: 's', full: false, marks: const ['V'], busy: const {5, 6, 12, 13, 19, 20, 26, 27}),
      PlanPerson(id: 'q', name: 'q', full: false, marks: const ['V']),
    ]);
    final e = r.entries;
    check('$tag 接上個月月底不超過 6 天', maxRunOf(e['f1']!, days, prev: 5) <= 6 && maxRunOf(e['f2']!, days, prev: 3) <= 6,
        'f1 ${maxRunOf(e['f1']!, days, prev: 5)}、f2 ${maxRunOf(e['f2']!, days, prev: 3)}');
    var tail = 0;
    for (var d = days; d >= 1 && isWork(e['f3']![d]); d--) {
      tail++;
    }
    check('$tag 接下個月月初不超過 6 天', tail + (tail > 0 ? 4 : 0) <= 6, '月底連上 $tail 天');
    check('$tag 另一家店有班的日子不排', const [5, 6, 12, 13, 19, 20, 26, 27].every((d) => !isWork(e['s']![d])));
    check('$tag 每天都有正職、沒有缺人', r.check!.score[2] == 0 && r.check!.score[3] == 0, r.warnings.join('｜'));
    check('$tag 沒有違反條件', r.check!.score[0] == 0 && r.check!.score[1] == 0, r.warnings.join('｜'));
    // 「a 上班時 b 也要上」：b 排在名單後面、或兩個人互相要求，都要排得出來
    r = planShifts(year: y, month: mo, seed: seed, needByDay: need3, minFullByDay: mf1, pairRules: const [
      PairRule(a: 'p1', b: 'p9', kind: 'with'),
      PairRule(a: 'm1', b: 'm2', kind: 'with'),
      PairRule(a: 'm2', b: 'm1', kind: 'with'),
    ], people: [
      PlanPerson(id: 'f1', name: 'f1', full: true, offTarget: 10, marks: const ['V']),
      PlanPerson(id: 'f2', name: 'f2', full: true, offTarget: 10, marks: const ['V']),
      PlanPerson(id: 'p1', name: 'p1', full: false, minShifts: 4, marks: const ['V']),
      PlanPerson(id: 'm1', name: 'm1', full: false, minShifts: 3, marks: const ['V']),
      PlanPerson(id: 'm2', name: 'm2', full: false, marks: const ['V']),
      PlanPerson(id: 'p9', name: 'p9', full: false, marks: const ['V']),
    ]);
    final w = r.entries;
    check('$tag 要一起上的人（對方排在後面）排得到班', r.workDays['p1']! >= 4 && [for (var d = 1; d <= days; d++) d].every((d) => !isWork(w['p1']![d]) || isWork(w['p9']![d])),
        'p1 ${r.workDays['p1']} 天');
    check('$tag 互相要求一起上的兩個人排得到班、而且同進同出',
        r.workDays['m1']! >= 3 && [for (var d = 1; d <= days; d++) d].every((d) => isWork(w['m1']![d]) == isWork(w['m2']![d])), 'm1 ${r.workDays['m1']} 天');
    check('$tag 沒有超編', r.check!.score[5] == 0, r.warnings.join('｜'));
  }

  // --- 照過去的班表整理習慣 ---
  final s = suggestRule([
    (DateTime(2026, 10), {2: '19:00-01:30', 3: '19:00-01:30', 9: '19:00-01:30', 10: '18:00-01:30', 4: '休'}),
    (DateTime(2026, 11), {6: '19:00-01:30', 7: '18:00-01:30', 13: '19:00-01:30'}),
  ], full: false);
  check('[習慣] 沒上過的星期、天數範圍、各星期的時段', s.noWeekdays.length == 5 && !s.noWeekdays.contains(5) && !s.noWeekdays.contains(6) && s.minShifts == 3 && s.maxShifts == 4 && s.weekdayMarks[5] == '19:00-01:30' && s.weekdayMarks[6] == '18:00-01:30',
      '${s.noWeekdays} ${s.minShifts}～${s.maxShifts} ${s.weekdayMarks}');
  final sf = suggestRule([(DateTime(2026, 11), {for (var d = 1; d <= 20; d++) d: DateTime(2026, 11, d).weekday >= 5 && DateTime(2026, 11, d).weekday <= 6 ? 'BH' : 'B'})], full: true);
  check('[習慣] 正職只建議班別', sf.noWeekdays.isEmpty && sf.minShifts == null && sf.weekdayMarks[5] == 'BH' && sf.weekdayMarks[1] == 'B');
}

/// 兩家店的設定（2026-11-12 資料庫的實際設定，人名換成代號）× 4 個月 × 多組亂數。
/// 上線門檻：選出來的班表不能缺正職、不能缺人、不能違反條件；正職休假＝應休。
void realSetups() {
  const months = [(2026, 11), (2026, 12), (2027, 1), (2027, 2)];
  final seeds = int.tryParse(Platform.environment['PLAN_SEEDS'] ?? '') ?? 25; // 上線前本機跑 100
  for (final (y, mo) in months) {
    final days = DateTime(y, mo + 1, 0).day;
    int wd(int d) => DateTime(y, mo, d).weekday;
    // 甲店：每天 3 人（週五六 4 人）、正職至少 1 人；老闆應休讓他上 12 天；兩位正職「排班時當兼職」；9 位兼職都沒設條件
    final a = [
      PlanPerson(id: 'A1', name: 'A1', full: true, offTarget: days - 12, maxShifts: 12, marks: const ['V'], preferRun: null),
      PlanPerson(id: 'A2', name: 'A2', full: true, offTarget: 10, marks: const ['V'], prevRun: 3),
      PlanPerson(id: 'A3', name: 'A3', full: true, offTarget: 10, marks: const ['V'], prevRun: 1),
      PlanPerson(id: 'A4', name: 'A4', full: false, marks: const ['V'], prevRun: 1),
      PlanPerson(id: 'A5', name: 'A5', full: false, marks: const ['V']),
      for (var i = 1; i <= 9; i++)
        PlanPerson(id: 'a$i', name: 'a$i', full: false, marks: const ['V'], busy: i <= 3 ? {for (var d = 1; d <= days; d++) if (wd(d) == 4 + i) d} : const {}),
    ];
    final aNeed = {for (var d = 1; d <= days; d++) d: (wd(d) == 5 || wd(d) == 6) ? 4 : 3};
    // 乙店：週一二 2 人、三四日 3 人、五六 4 人；正職至少 1 人；盡量不連上超過 5 天；班別依星期；兼職照過去的星期
    const wk = {1: 'B', 2: 'B', 3: 'B', 4: 'B', 5: 'BH', 6: 'BH', 7: 'B'};
    PlanPerson part(String id, Set<int> on, {int? mn, int? mx, Set<int> busy = const {}}) => PlanPerson(
        id: id, name: id, full: false, marks: const ['19:00-00:30'], noWeekdays: {for (var w = 1; w <= 7; w++) if (!on.contains(w)) w},
        minShifts: mn, maxShifts: mx, preferRun: 5, busy: busy,
        weekdayMarks: {for (final w in on) w: (w == 5 || w == 6) ? '18:00-01:30' : '19:00-00:30'});
    final b = [
      PlanPerson(id: 'B1', name: 'B1', full: true, offTarget: 10, marks: const ['B'], weekdayMarks: {...wk, 6: 'RBK', 7: 'RBK'}, prevRun: 5, preferRun: 5),
      PlanPerson(id: 'B2', name: 'B2', full: true, offTarget: 10, marks: const ['B'], weekdayMarks: wk, preferRun: 5),
      PlanPerson(id: 'B3', name: 'B3', full: true, offTarget: 10, marks: const ['B'], weekdayMarks: wk, prevRun: 4, preferRun: 5),
      part('b1', {5, 6, 7}, mx: 12, busy: {for (var d = 1; d <= days; d++) if (wd(d) == 5 && d % 2 == 0) d}),
      part('b2', {1, 2, 3, 4, 5, 6, 7}, mx: 12),
      part('b3', {3, 4}, mx: 6),
      part('b4', {4, 5, 6, 7}, mx: 8),
      part('b5', {6, 7}, mx: 5),
      part('b6', {3, 4, 5, 6}, mx: 14),
    ];
    final bNeed = {for (var d = 1; d <= days; d++) d: switch (wd(d)) { 1 || 2 => 2, 5 || 6 => 4, _ => 3 }};
    final bReq = {
      'B1': {10: 'off', 11: 'off', 25: 'off'}
    };
    for (final (store, people, need, req) in [('甲店', a, aNeed, const <String, Map<int, String>>{}), ('乙店', b, bNeed, bReq)]) {
      final mf = {for (var d = 1; d <= days; d++) d: 1};
      final pre = precheckPlan(year: y, month: mo, people: people, needByDay: need, minFullByDay: mf, requests: req);
      check('[$store $y/$mo] 排前檢查沒有要先改的', pre.every((i) => i.level != 0), pre.map((i) => i.text).join('｜'));
      var noFull = 0, short = 0, bad = 0, off = 0, over = 0, runBad = 0, markBad = 0, pref = 0;
      String detail = '';
      for (var seed = 0; seed < seeds; seed++) {
        final r = planShifts(year: y, month: mo, people: people, needByDay: need, minFullByDay: mf, requests: req, seed: seed);
        final sc = r.check!.score;
        if (sc[2] > 0) noFull++;
        if (sc[3] > 0) short++;
        if (sc[0] > 0 || sc[1] > 0) bad++;
        if (sc[5] > 0) over++;
        if ((sc[2] > 0 || sc[3] > 0 || sc[0] > 0 || sc[1] > 0 || sc[4] > 0) && detail.isEmpty) detail = 'seed $seed：${r.warnings.take(4).join('｜')}';
        for (final p in people) {
          final row = r.entries[p.id]!;
          if (p.full && row.values.where((m) => m == '休' || m == '指休').length != p.offTarget.round()) off++;
          if (maxRunOf(row, days, prev: p.prevRun) > p.maxConsecutive) runBad++;
          for (var d = 1; d <= days; d++) {
            if (isWork(row[d]) && p.weekdayMarks[wd(d)] != null && row[d] != p.weekdayMarks[wd(d)]) markBad++;
          }
        }
        pref += r.check!.issues.where((i) => i.code == 'pref').length;
      }
      check('[$store $y/$mo] $seeds 組：每天都有正職', noFull == 0, '$noFull 組缺正職；$detail');
      check('[$store $y/$mo] $seeds 組：沒有缺人', short == 0, '$short 組缺人；$detail');
      check('[$store $y/$mo] $seeds 組：沒有違反條件', bad == 0, '$bad 組；$detail');
      check('[$store $y/$mo] $seeds 組：沒有超編', over == 0, '$over 組');
      check('[$store $y/$mo] $seeds 組：正職休假＝應休', off == 0, '$off 人次不符；$detail');
      check('[$store $y/$mo] $seeds 組：含上月底連上不超過上限', runBad == 0, '$runBad 人次');
      check('[$store $y/$mo] $seeds 組：班別都照星期', markBad == 0, '$markBad 格');
      stdout.writeln('     （$store $y/$mo 連上超過偏好天數的段數：平均每份 ${(pref / seeds).toStringAsFixed(1)} 段）');
    }
  }
}
