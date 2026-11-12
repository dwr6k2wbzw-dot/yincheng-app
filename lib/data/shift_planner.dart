// 自動排班（老闆 2026-10-27，0073；2026-11-12 第二版，0098）
// 純 Dart（不用 Flutter），方便在 CI 用 `dart run tool/shift_plan_check.dart` 檢查。
//
// 第二版做法（老闆 2026-11-12 核定，ChatGPT 審過一輪）：
//   0. validateSchedule()：同一套檢查給「自動排、手動改格子、套用前」共用，回傳問題清單與字典序分數
//   1. 先排正職：每天先保證「正職至少幾人」，最難排的日子先排；再把每位正職補到該上的天數（補在最缺人的日子）
//   2. 再排兼職：最缺人、最少人能上的日子先排
//   3. 修補：缺正職→跟別天換班；缺人→換班；兼職沒到最少天數→跟天數多的人換
//   4. 一次算很多份（預設 40），用檢查器的分數挑最好的；排不滿就照實列出，不假裝排好
//   記號：有設「依星期的班別」就照星期，沒有就用第一個記號。
//   正職沒上班的日子：員工填指休的 → 指休，其他 → 休；兼職沒上班留空白。
//   員工填「指休」的日子、另一家店有班的日子一定不排；兼職有填「可以上」就只排那些天。
//   連續上班會接上個月月底、下個月月初已排的班一起算。

import 'dart:math';

int? _int(Object? v) => v == null ? null : int.tryParse('$v'.split('.').first);

/// 每個人的排班條件（shift_rules）
class ShiftRule {
  final String personId;
  final double? monthOff; // 正職每月休幾天（該月有填「應休」就用應休）
  final int? minShifts; // 每月最少上幾天
  final int? maxShifts; // 每月最多上幾天
  final int? maxConsecutive; // 最多連上幾天（沒填＝6）
  final Set<int> noWeekdays; // 固定不排（1＝週一…7＝週日）
  final List<String> marks; // 上班時排的記號／班別／時段（第一個優先）
  final String? note;
  final bool planAsPart; // 0074：班表上是正職，但排班時跟兼職一樣（不照應休、沒上班留空白）
  final Map<int, String> weekdayMarks; // 0098：依星期的班別／時段（1＝週一…7＝週日），沒設的星期用 marks 第一個
  const ShiftRule({
    required this.personId,
    this.planAsPart = false,
    this.monthOff,
    this.minShifts,
    this.maxShifts,
    this.maxConsecutive,
    this.noWeekdays = const {},
    this.marks = const [],
    this.weekdayMarks = const {},
    this.note,
  });

  factory ShiftRule.fromRow(Map<String, dynamic> r) => ShiftRule(
        personId: r['person_id'] as String,
        monthOff: r['month_off'] == null ? null : double.tryParse('${r['month_off']}'),
        minShifts: _int(r['min_shifts']),
        maxShifts: _int(r['max_shifts']),
        maxConsecutive: _int(r['max_consecutive']),
        noWeekdays: {for (final x in (r['no_weekdays'] as List?) ?? const []) if (_int(x) != null) _int(x)!},
        marks: [for (final x in (r['marks'] as List?) ?? const []) '$x'],
        note: r['note'] as String?,
        planAsPart: r['plan_as_part'] == true,
        weekdayMarks: {
          for (final e in ((r['weekday_marks'] as Map?) ?? const {}).entries)
            if (_int(e.key) != null && '${e.value}'.trim().isNotEmpty) _int(e.key)!: '${e.value}'.trim()
        },
      );

  Map<String, dynamic> toRow(String storeId) => {
        'person_id': personId,
        'store_id': storeId,
        'month_off': monthOff,
        'min_shifts': minShifts,
        'max_shifts': maxShifts,
        'max_consecutive': maxConsecutive,
        'no_weekdays': (noWeekdays.toList()..sort()),
        'marks': marks,
        'note': (note == null || note!.trim().isEmpty) ? null : note!.trim(),
        'plan_as_part': planAsPart,
        'weekday_marks': {for (final e in weekdayMarks.entries) '${e.key}': e.value},
      };

  bool get isEmpty =>
      monthOff == null &&
      minShifts == null &&
      maxShifts == null &&
      maxConsecutive == null &&
      noWeekdays.isEmpty &&
      marks.isEmpty &&
      weekdayMarks.isEmpty &&
      !planAsPart &&
      (note == null || note!.isEmpty);
}

/// 自訂規則（老闆店長設）：apart＝兩個人不能同一天上班；with＝a 上班的日子 b 也要上班
class PairRule {
  final String id;
  final String a;
  final String b;
  final String kind; // apart／with
  const PairRule({this.id = '', required this.a, required this.b, required this.kind});
  bool get isApart => kind == 'apart';
  factory PairRule.fromRow(Map<String, dynamic> r) =>
      PairRule(id: r['id'] as String, a: r['person_a'] as String, b: r['person_b'] as String, kind: r['kind'] as String);
}

/// 每天需要幾人（依星期）
class StaffingNeed {
  final int need;
  final int minFull; // 其中至少幾個正職
  const StaffingNeed(this.need, [this.minFull = 0]);
}

/// 一個月的排班設定：條件、人力、員工填的想休／可上
class ShiftPlanSetup {
  final Map<int, StaffingNeed> staffing; // 星期（1～7）→ 人力
  final Map<int, int> specialDays; // 日 → 這天要幾人（特別日子）
  final int deadline; // 每月幾號前填好下個月
  final Map<String, ShiftRule> rules; // 人 → 條件（員工只讀得到自己的）
  final Map<String, Map<int, String>> requests; // 人 → 日 → off／on
  final List<PairRule> pairRules; // 自訂規則（只有老闆店長讀得到）
  final int? preferRun; // 0098：盡量不要連上超過幾天（null＝不設；硬上限仍是每人的最多連上）
  final Map<String, Set<int>> otherStoreDays; // 0098：人 → 這個月在另一家店有班的日子（只有老闆店長拿得到）
  const ShiftPlanSetup({
    this.preferRun,
    this.otherStoreDays = const {},
    this.pairRules = const [],
    this.staffing = const {},
    this.specialDays = const {},
    this.deadline = 20,
    this.rules = const {},
    this.requests = const {},
  });

  /// 這個月的填寫截止日（上個月的 deadline 號）
  static DateTime deadlineFor(DateTime month, int deadline) => DateTime(month.year, month.month - 1, deadline);
}

/// 排班用的人
class PlanPerson {
  final String id;
  final String name;
  final bool full;
  final double offTarget; // 正職這個月要休幾天
  final int? minShifts;
  final int? maxShifts;
  final int maxConsecutive;
  final Set<int> noWeekdays;
  final List<String> marks; // 上班記號（至少一個）
  final Map<int, String> weekdayMarks; // 依星期的班別（1～7）
  final int? preferRun; // 盡量不要連上超過幾天
  final int prevRun; // 上個月月底已經連上幾天
  final int nextRun; // 下個月月初已排好連上幾天
  final Set<int> busy; // 這幾天在另一家店有班（一定不排）
  const PlanPerson({
    required this.id,
    required this.name,
    required this.full,
    this.offTarget = 0,
    this.minShifts,
    this.maxShifts,
    this.maxConsecutive = 6,
    this.noWeekdays = const {},
    required this.marks,
    this.weekdayMarks = const {},
    this.preferRun,
    this.prevRun = 0,
    this.nextRun = 0,
    this.busy = const {},
  });
}

/// 檢查出來的一個問題。level：0＝一定不行（擋套用）、1＝違反排班條件、2＝缺人、3＝提醒
class PlanIssue {
  final String code;
  final int level;
  final String text;
  final String? personId;
  final List<int> days;
  const PlanIssue(this.code, this.level, this.text, {this.personId, this.days = const []});
}

/// 檢查結果（自動排、手動改、套用前共用）
class PlanCheck {
  final List<PlanIssue> issues;
  final Map<int, int> staffed; // 日 → 上班人數
  final Map<int, int> fulls; // 日 → 正職人數
  final Map<String, int> workDays; // 人 → 上班天數
  final Map<String, int> restDays; // 人 → 休＋指休天數
  final Map<String, int> targets; // 正職 → 該上幾天
  final List<int> score; // 字典序，越小越好
  const PlanCheck(this.issues, this.staffed, this.fulls, this.workDays, this.restDays, this.targets, this.score);

  int count(int level) => issues.where((i) => i.level == level).length;

  /// 沒有「一定不行」的問題（可以套用；缺人、提醒要另外確認）
  bool get canApply => issues.every((i) => i.level != 0);

  /// 完全沒問題（提醒不算）
  bool get clean => issues.every((i) => i.level >= 3);

  /// 有問題的格子（'人|日'）→ 最嚴重的等級
  Map<String, int> get badCells {
    final m = <String, int>{};
    for (final i in issues) {
      if (i.personId == null || i.level > 1) continue;
      for (final d in i.days) {
        final k = '${i.personId}|$d';
        if (!m.containsKey(k) || m[k]! > i.level) m[k] = i.level;
      }
    }
    return m;
  }

  /// 缺人或缺正職的日子
  Set<int> get shortDays => {for (final i in issues) if (i.level == 2) ...i.days};
}

class PlanResult {
  final Map<String, Map<int, String>> entries; // 人 → 日 → 記號（只含列出的人）
  final Map<int, int> staffed; // 日 → 排到幾人
  final Map<int, int> need; // 日 → 需要幾人
  final Map<String, int> workDays; // 人 → 上班天數
  final List<String> warnings;
  final PlanCheck? check;
  final int tries; // 一共算了幾份
  const PlanResult(this.entries, this.staffed, this.need, this.workDays, this.warnings, {this.check, this.tries = 1});
}

const _away = {'休', '指休', '特休'};
bool _isWork(String? m) => m != null && m.isNotEmpty && !_away.contains(m);

/// 是不是上班的記號（休、指休、特休、空白以外都算）
bool isWorkMark(String? m) => _isWork(m);

const _wdName = '一二三四五六日';

int _fullTarget(PlanPerson p, int days, Map<int, String> row) =>
    max(0, days - p.offTarget.round() - row.values.where((m) => m == '特休').length);

/// 把連續的日子寫成 3～5、8、10～11
String _dayList(int month, List<int> ds) {
  final s = [...ds]..sort();
  final parts = <String>[];
  for (var i = 0; i < s.length;) {
    var j = i;
    while (j + 1 < s.length && s[j + 1] == s[j] + 1) {
      j++;
    }
    parts.add(i == j ? '${s[i]}' : '${s[i]}～${s[j]}');
    i = j + 1;
  }
  return '$month/${parts.join('、')}';
}

/// 檢查一份班表。entries：人 → 日 → 記號（要檢查的整個月；沒列的人不檢查）。
PlanCheck validateSchedule({
  required int year,
  required int month,
  required List<PlanPerson> people,
  required Map<int, int> needByDay,
  required Map<int, int> minFullByDay,
  required Map<String, Map<int, String>> entries,
  Map<String, Map<int, String>> requests = const {},
  List<PairRule> pairRules = const [],
}) {
  final days = DateTime(year, month + 1, 0).day;
  int wd(int d) => DateTime(year, month, d).weekday;
  String dl(int d) => '$month/$d（${_wdName[wd(d) - 1]}）';
  final issues = <PlanIssue>[];
  final work = <String, Set<int>>{
    for (final p in people)
      p.id: {
        for (final e in (entries[p.id] ?? const <int, String>{}).entries)
          if (e.key >= 1 && e.key <= days && _isWork(e.value)) e.key
      }
  };
  final staffed = <int, int>{}, fulls = <int, int>{};
  for (var d = 1; d <= days; d++) {
    staffed[d] = people.where((p) => work[p.id]!.contains(d)).length;
    fulls[d] = people.where((p) => p.full && work[p.id]!.contains(d)).length;
  }
  var hard = 0, rule = 0, fullShort = 0, short = 0, dev = 0, over = 0, soft = 0;
  final targets = <String, int>{};
  final restDays = <String, int>{};

  for (final p in people) {
    final row = entries[p.id] ?? const <int, String>{};
    final w = work[p.id]!;
    final req = requests[p.id] ?? const <int, String>{};
    restDays[p.id] = row.entries.where((e) => e.key >= 1 && e.key <= days && (e.value == '休' || e.value == '指休')).length;

    final offBad = [for (final d in w) if (req[d] == 'off') d]..sort();
    if (offBad.isNotEmpty) {
      hard += offBad.length;
      issues.add(PlanIssue('off', 0, '${p.name} ${_dayList(month, offBad)} 填了指休卻排上班', personId: p.id, days: offBad));
    }
    final busyBad = [for (final d in w) if (p.busy.contains(d)) d]..sort();
    if (busyBad.isNotEmpty) {
      hard += busyBad.length;
      issues.add(PlanIssue('busy', 0, '${p.name} ${_dayList(month, busyBad)} 另一家店已經有班', personId: p.id, days: busyBad));
    }
    final wdBad = [for (final d in w) if (p.noWeekdays.contains(wd(d))) d]..sort();
    if (wdBad.isNotEmpty) {
      rule += wdBad.length;
      issues.add(PlanIssue('weekday', 1, '${p.name} ${_dayList(month, wdBad)} 是固定不排的星期', personId: p.id, days: wdBad));
    }
    if (!p.full && req.values.any((v) => v == 'on')) {
      final notOn = [for (final d in w) if (req[d] != 'on') d]..sort();
      if (notOn.isNotEmpty) {
        rule += notOn.length;
        issues.add(PlanIssue('notOn', 1, '${p.name} ${_dayList(month, notOn)} 沒填可以上', personId: p.id, days: notOn));
      }
    }
    // 連續上班（接上個月月底、下個月月初）
    for (var d = 1; d <= days; d++) {
      if (!w.contains(d) || w.contains(d - 1)) continue;
      var e = d;
      while (w.contains(e + 1)) {
        e++;
      }
      final len = e - d + 1 + (d == 1 ? p.prevRun : 0) + (e == days ? p.nextRun : 0);
      final ds = [for (var x = d; x <= e; x++) x];
      if (len > p.maxConsecutive) {
        rule += len - p.maxConsecutive;
        final cross = (d == 1 && p.prevRun > 0) ? '（含上個月月底 ${p.prevRun} 天）' : ((e == days && p.nextRun > 0) ? '（含下個月月初 ${p.nextRun} 天）' : '');
        issues.add(PlanIssue('run', 1, '${p.name} ${_dayList(month, ds)} 連上 $len 天$cross，最多 ${p.maxConsecutive} 天',
            personId: p.id, days: ds));
      } else if (p.preferRun != null && len > p.preferRun!) {
        soft += (len - p.preferRun!) * 3;
        issues.add(PlanIssue('pref', 3, '${p.name} ${_dayList(month, ds)} 連上 $len 天（盡量不超過 ${p.preferRun} 天）', personId: p.id));
      }
    }
    if (p.full) {
      final t = _fullTarget(p, days, row);
      targets[p.id] = t;
      if (p.maxShifts != null && w.length > p.maxShifts!) {
        rule += w.length - p.maxShifts!;
        issues.add(PlanIssue('max', 1, '${p.name} 排了 ${w.length} 天，超過最多 ${p.maxShifts} 天', personId: p.id));
      }
      if (w.length < t) {
        dev += t - w.length;
        issues.add(PlanIssue('target', 3, '${p.name} 排 ${w.length} 天，比該上的 $t 天少 ${t - w.length} 天（會多休）', personId: p.id));
      } else if (w.length > t) {
        dev += w.length - t;
        issues.add(PlanIssue('target', 3, '${p.name} 排 ${w.length} 天，比該上的 $t 天多 ${w.length - t} 天（休不到應休）', personId: p.id));
      }
    } else {
      if (p.maxShifts != null && w.length > p.maxShifts!) {
        rule += w.length - p.maxShifts!;
        issues.add(PlanIssue('max', 1, '${p.name} 排了 ${w.length} 天，超過最多 ${p.maxShifts} 天', personId: p.id));
      }
      if (p.minShifts != null && w.length < p.minShifts!) {
        dev += p.minShifts! - w.length;
        issues.add(PlanIssue('min', 3, '${p.name} 只排到 ${w.length} 天（最少要 ${p.minShifts} 天）', personId: p.id));
      }
    }
    // 班別跟「依星期的班別」不一樣（只算分數，不列出來）
    for (final d in w) {
      final want = p.weekdayMarks[wd(d)];
      if (want != null && row[d] != want) soft += 1;
    }
  }

  final names = {for (final p in people) p.id: p.name};
  for (final r in pairRules) {
    final a = names[r.a], b = names[r.b];
    if (a == null || b == null) continue;
    final bad = [
      for (var d = 1; d <= days; d++)
        if (r.isApart ? work[r.a]!.contains(d) && work[r.b]!.contains(d) : work[r.a]!.contains(d) && !work[r.b]!.contains(d)) d
    ];
    if (bad.isEmpty) continue;
    rule += bad.length;
    issues.add(PlanIssue('pair', 1,
        r.isApart ? '$a 跟 $b ${_dayList(month, bad)} 同一天上班（設定不能同一天）' : '$a ${_dayList(month, bad)} 上班但 $b 沒上（設定要一起上）',
        personId: r.a, days: bad));
  }

  for (var d = 1; d <= days; d++) {
    final need = needByDay[d] ?? 0;
    final mf = min(minFullByDay[d] ?? 0, need);
    final s = staffed[d]!;
    if (s < need) {
      short += need - s;
      final off = [for (final p in people) if (requests[p.id]?[d] == 'off') p.name];
      issues.add(PlanIssue('short', 2, '${dl(d)}少 ${need - s} 人${off.isEmpty ? '' : '（指休：${off.join('、')}）'}', days: [d]));
    } else if (s > need) {
      over += s - need;
      issues.add(PlanIssue('over', 3, need == 0 ? '${dl(d)}不用排人卻排了 $s 人' : '${dl(d)}多排 ${s - need} 人（要 $need 人）', days: [d]));
    }
    if (fulls[d]! < mf) {
      fullShort += mf - fulls[d]!;
      issues.add(PlanIssue('noFull', 2, '${dl(d)}正職只有 ${fulls[d]} 人（至少要 $mf 人）', days: [d]));
    }
  }

  // 兼職之間差太多（只算分數）
  final parts = [for (final p in people) if (!p.full && p.minShifts == null && p.maxShifts == null) work[p.id]!.length];
  if (parts.length > 1) soft += parts.reduce(max) - parts.reduce(min);

  issues.sort((a, b) => a.level.compareTo(b.level));
  return PlanCheck(issues, staffed, fulls, {for (final p in people) p.id: work[p.id]!.length}, restDays, targets,
      [hard, rule, fullShort, short, dev, over, soft]);
}

bool _better(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
}

/// 排之前先檢查設定：互相衝突、人不夠的地方先講。level 0＝要先改好才能排，3＝提醒。
List<PlanIssue> precheckPlan({
  required int year,
  required int month,
  required List<PlanPerson> people,
  required Map<int, int> needByDay,
  required Map<int, int> minFullByDay,
  Map<String, Map<int, String>> fixed = const {},
  Map<String, Map<int, String>> requests = const {},
  List<PairRule> pairRules = const [],
}) {
  final days = DateTime(year, month + 1, 0).day;
  int wd(int d) => DateTime(year, month, d).weekday;
  final out = <PlanIssue>[];
  final ids = {for (final p in people) p.id};
  bool free(PlanPerson p, int d) {
    final f = fixed[p.id]?[d];
    if (f != null) return _isWork(f);
    if ((needByDay[d] ?? 0) <= 0) return false;
    if (p.noWeekdays.contains(wd(d)) || p.busy.contains(d)) return false;
    final r = requests[p.id]?[d];
    if (r == 'off') return false;
    if (!p.full && (requests[p.id] ?? const {}).values.any((v) => v == 'on') && r != 'on') return false;
    return true;
  }

  var supply = 0;
  for (final p in people) {
    final avail = [for (var d = 1; d <= days; d++) if (free(p, d)) d].length;
    if (p.minShifts != null && p.maxShifts != null && p.minShifts! > p.maxShifts!) {
      out.add(PlanIssue('conf', 0, '${p.name} 的最少 ${p.minShifts} 天比最多 ${p.maxShifts} 天還多，請先改排班條件', personId: p.id));
    }
    if (p.full) {
      final t = _fullTarget(p, days, fixed[p.id] ?? const {});
      if (p.maxShifts != null && t > p.maxShifts!) {
        out.add(PlanIssue('conf', 0,
            '${p.name}：休 ${p.offTarget.round()} 天＝要上 $t 天，但排班條件寫最多上 ${p.maxShifts} 天。請改應休或最多天數', personId: p.id));
      } else if (p.minShifts != null && t < p.minShifts!) {
        out.add(PlanIssue('conf', 0,
            '${p.name}：休 ${p.offTarget.round()} 天＝要上 $t 天，但排班條件寫最少上 ${p.minShifts} 天。請改應休或最少天數', personId: p.id));
      }
      if (avail < t) {
        out.add(PlanIssue('avail', 3, '${p.name} 這個月最多只有 $avail 天能排，排不到該上的 $t 天', personId: p.id));
      }
      supply += min(avail, min(t, p.maxShifts ?? t));
    } else {
      if (p.minShifts != null && avail < p.minShifts!) {
        out.add(PlanIssue('avail', 3, '${p.name} 這個月只有 $avail 天能排，排不到最少 ${p.minShifts} 天', personId: p.id));
      }
      supply += min(avail, p.maxShifts ?? avail);
    }
  }
  for (final r in pairRules) {
    if (!ids.contains(r.a) || !ids.contains(r.b)) {
      out.add(const PlanIssue('pairGone', 3, '有一條自訂規則的人已經不在名單上，這條不會生效'));
    }
  }
  var total = 0;
  final thin = <int>[], noFull = <int>[];
  for (var d = 1; d <= days; d++) {
    final need = needByDay[d] ?? 0;
    total += need;
    if (need <= 0) continue;
    if (people.where((p) => free(p, d)).length < need) thin.add(d);
    final mf = min(minFullByDay[d] ?? 0, need);
    if (people.where((p) => p.full && free(p, d)).length < mf) noFull.add(d);
  }
  if (thin.isNotEmpty) out.add(PlanIssue('thin', 3, '${_dayList(month, thin)} 能上班的人不夠，這幾天一定排不滿', days: thin));
  if (noFull.isNotEmpty) out.add(PlanIssue('thinFull', 3, '${_dayList(month, noFull)} 沒有正職能上班', days: noFull));
  if (supply < total) {
    out.add(PlanIssue('supply', 3, '整個月要 $total 人次，照現在的條件最多只排得到 $supply 人次（兼職沒設最多天數的不算上限）'));
  }
  out.sort((a, b) => a.level.compareTo(b.level));
  return out;
}

/// 自動排班。fixed：保留不動的格子（人 → 日 → 記號）。tries：算幾份挑最好的。
PlanResult planShifts({
  required int year,
  required int month,
  required List<PlanPerson> people,
  required Map<int, int> needByDay,
  required Map<int, int> minFullByDay,
  Map<String, Map<int, String>> fixed = const {},
  Map<String, Map<int, String>> requests = const {},
  List<PairRule> pairRules = const [],
  int seed = 0,
  int tries = 40,
}) {
  Map<String, Map<int, String>>? best;
  PlanCheck? bestCheck;
  final n = max(1, tries);
  for (var i = 0; i < n; i++) {
    final e = _planOnce(
        year: year,
        month: month,
        people: people,
        needByDay: needByDay,
        minFullByDay: minFullByDay,
        fixed: fixed,
        requests: requests,
        pairRules: pairRules,
        seed: seed * 7919 + i);
    final c = validateSchedule(
        year: year,
        month: month,
        people: people,
        needByDay: needByDay,
        minFullByDay: minFullByDay,
        entries: e,
        requests: requests,
        pairRules: pairRules);
    if (bestCheck == null || _better(c.score, bestCheck.score)) {
      best = e;
      bestCheck = c;
    }
    // 完全沒問題就不用再算；只剩「好不好看」的差別時，多算幾份就夠了（手機上才不會等太久）
    if (c.score.every((x) => x == 0)) break;
    if (i >= 11 && bestCheck.score.take(6).every((x) => x == 0)) break;
  }
  final days = DateTime(year, month + 1, 0).day;
  return PlanResult(best!, bestCheck!.staffed, {for (var d = 1; d <= days; d++) d: needByDay[d] ?? 0}, bestCheck.workDays,
      [for (final i in bestCheck.issues) if (i.code != 'pref') i.text],
      check: bestCheck, tries: n);
}

Map<String, Map<int, String>> _planOnce({
  required int year,
  required int month,
  required List<PlanPerson> people,
  required Map<int, int> needByDay,
  required Map<int, int> minFullByDay,
  required Map<String, Map<int, String>> fixed,
  required Map<String, Map<int, String>> requests,
  required List<PairRule> pairRules,
  required int seed,
}) {
  final rnd = Random(seed);
  final days = DateTime(year, month + 1, 0).day;
  final wds = [0, for (var d = 1; d <= days; d++) DateTime(year, month, d).weekday];
  int wd(int d) => wds[d];
  final byId = {for (final p in people) p.id: p};
  final work = {for (final p in people) p.id: <int>{}};
  final out = {for (final p in people) p.id: <int, String>{}};
  for (final p in people) {
    for (final e in (fixed[p.id] ?? const <int, String>{}).entries) {
      if (e.key < 1 || e.key > days) continue;
      out[p.id]![e.key] = e.value;
      if (_isWork(e.value)) work[p.id]!.add(e.key);
    }
  }
  final hasOn = {for (final p in people) p.id: (requests[p.id] ?? const {}).values.any((v) => v == 'on')};
  int needOf(int d) => needByDay[d] ?? 0;
  int mfOf(int d) => min(minFullByDay[d] ?? 0, needOf(d));
  // 每天的人數、正職人數（跟 work 同步，改 work 一律用 addW／remW）
  final cnt = List<int>.filled(days + 2, 0), fcnt = List<int>.filled(days + 2, 0);
  for (final p in people) {
    for (final d in work[p.id]!) {
      cnt[d]++;
      if (p.full) fcnt[d]++;
    }
  }
  void addW(String id, int d) {
    if (work[id]!.add(d)) {
      cnt[d]++;
      if (byId[id]!.full) fcnt[d]++;
    }
  }

  void remW(String id, int d) {
    if (work[id]!.remove(d)) {
      cnt[d]--;
      if (byId[id]!.full) fcnt[d]--;
    }
  }

  int staffedOn(int d) => cnt[d];
  int fullsOn(int d) => fcnt[d];
  int room(int d) => needOf(d) - staffedOn(d);

  /// p 在 d 上班的話，這一段連上幾天（接上個月、下個月）
  int runWith(PlanPerson p, int d) {
    final w = work[p.id]!;
    var a = d, b = d;
    while (w.contains(a - 1)) {
      a--;
    }
    while (w.contains(b + 1)) {
      b++;
    }
    return b - a + 1 + (a == 1 ? p.prevRun : 0) + (b == days ? p.nextRun : 0);
  }

  // 每個人最多排幾天（正職＝該上的天數；保留的特休在排之前就固定了，所以先算好）
  final capOf = <String, int?>{
    for (final p in people)
      p.id: !p.full
          ? p.maxShifts
          : (p.maxShifts == null ? _fullTarget(p, days, out[p.id]!) : min(_fullTarget(p, days, out[p.id]!), p.maxShifts!))
  };
  int? cap(PlanPerson p) => capOf[p.id];

  bool capOk(PlanPerson p) {
    final c = cap(p);
    return c == null || work[p.id]!.length < c;
  }

  /// 不看天數上限、不看「要跟誰一起上」：這個人這天能不能排
  bool baseOk(PlanPerson p, int d) {
    if (out[p.id]!.containsKey(d) || work[p.id]!.contains(d)) return false;
    if (needOf(d) <= 0) return false; // 這天不用排人
    if (p.noWeekdays.contains(wd(d)) || p.busy.contains(d)) return false;
    final r = requests[p.id]?[d];
    if (r == 'off') return false;
    if (!p.full && hasOn[p.id]! && r != 'on') return false;
    for (final x in pairRules) {
      if (!x.isApart) continue;
      final other = x.a == p.id ? x.b : (x.b == p.id ? x.a : null);
      if (other != null && (work[other]?.contains(d) ?? false)) return false;
    }
    return runWith(p, d) <= p.maxConsecutive;
  }

  /// 把 p 排在 d 要一起排的人（「a 上班時 b 也要上」）；排不了回 null
  List<PlanPerson>? groupFor(PlanPerson p, int d, {bool ignoreCap = false}) {
    if (!baseOk(p, d) || (!ignoreCap && !capOk(p))) return null;
    final g = <PlanPerson>[p];
    for (var i = 0; i < g.length; i++) {
      for (final x in pairRules) {
        if (x.isApart || x.a != g[i].id) continue;
        if (work[x.b]?.contains(d) ?? false) continue;
        if (g.any((m) => m.id == x.b)) continue;
        final pb = byId[x.b];
        if (pb == null) continue; // 那個人不在名單上，這條不生效
        if (!baseOk(pb, d) || !capOk(pb)) return null;
        g.add(pb);
      }
    }
    for (final x in pairRules) {
      if (x.isApart && g.any((m) => m.id == x.a) && g.any((m) => m.id == x.b)) return null;
    }
    return g;
  }

  void put(List<PlanPerson> g, int d) {
    for (final m in g) {
      addW(m.id, d);
    }
  }

  /// 能不能把 p 從 e 那天拿掉（保留的格子不動；有人規定要跟 p 一起上、那天也有上 → 不能拿）
  bool removable(PlanPerson p, int e) =>
      !out[p.id]!.containsKey(e) && !pairRules.any((x) => !x.isApart && x.b == p.id && (work[x.a]?.contains(e) ?? false));

  double runPenalty(PlanPerson p, int d) {
    if (p.preferRun == null) return 0;
    final r = runWith(p, d);
    return r > p.preferRun! ? 0.6 * (r - p.preferRun!) : 0;
  }

  final fullsList = [for (final p in people) if (p.full) p];

  // ---- 1a. 先保證每天的正職下限：最少正職能上的日子先排 ----
  final dead = <int>{};
  while (true) {
    int? pick;
    List<(PlanPerson, List<PlanPerson>)> pickC = const [];
    double pickKey = 0;
    for (var d = 1; d <= days; d++) {
      if (dead.contains(d) || fullsOn(d) >= mfOf(d)) continue;
      final c = <(PlanPerson, List<PlanPerson>)>[];
      for (final p in fullsList) {
        final g = groupFor(p, d);
        if (g != null && g.length <= max(1, room(d))) c.add((p, g));
      }
      if (c.isEmpty) {
        dead.add(d);
        continue;
      }
      final key = c.length + rnd.nextDouble() * 0.9;
      if (pick == null || key < pickKey) {
        pick = d;
        pickC = c;
        pickKey = key;
      }
    }
    if (pick == null) break;
    final d = pick;
    (PlanPerson, List<PlanPerson>)? bestC;
    double bestS = -1e9;
    for (final c in pickC) {
      final p = c.$1;
      final left = (cap(p) ?? days) - work[p.id]!.length;
      final s = left / max(1, cap(p) ?? days) - runPenalty(p, d) + rnd.nextDouble() * 0.25;
      if (s > bestS) {
        bestS = s;
        bestC = c;
      }
    }
    put(bestC!.$2, d);
  }

  // ---- 1b. 每位正職補到該上的天數：補在最缺人的日子 ----
  for (var guard = 0; guard < days * fullsList.length + 5; guard++) {
    PlanPerson? who;
    double worst = 0;
    for (final p in fullsList) {
      final c = cap(p)!;
      final lack = c - work[p.id]!.length;
      if (lack <= 0) continue;
      final k = lack / max(1, c) + rnd.nextDouble() * 0.05;
      if (who == null || k > worst) {
        who = p;
        worst = k;
      }
    }
    if (who == null) break;
    final p = who;
    int? bd;
    List<PlanPerson>? bg;
    double bs = -1e9;
    for (var d = 1; d <= days; d++) {
      final g = groupFor(p, d);
      if (g == null) continue;
      // 還缺人的日子優先；都不缺了才排到人已經夠的日子（正職要上滿該上的天數）
      final s = (room(d) - g.length + 1) * 2.0 - runPenalty(p, d) + rnd.nextDouble() * 0.9;
      if (s > bs) {
        bs = s;
        bd = d;
        bg = g;
      }
    }
    if (bd == null) {
      // 這個人排不進去了：把上限當成已到，換下一位
      fullsList.remove(p);
      continue;
    }
    put(bg!, bd);
  }

  // ---- 2. 兼職：最缺人、最少人能上的日子先排 ----
  final partGoal = <String, double>{};
  {
    var open = 0;
    for (var d = 1; d <= days; d++) {
      open += max(0, room(d));
    }
    final free = <PlanPerson>[];
    for (final p in people) {
      if (p.full) continue;
      if (p.minShifts != null || p.maxShifts != null) {
        final mn = p.minShifts ?? 0;
        final mx = p.maxShifts ?? max(mn, 4);
        partGoal[p.id] = (mn + mx) / 2;
        open -= partGoal[p.id]!.round() - work[p.id]!.length;
      } else {
        free.add(p);
      }
    }
    for (final p in free) {
      partGoal[p.id] = max(1.0, open / free.length + work[p.id]!.length);
    }
  }
  double want(PlanPerson p, int d) {
    final w = work[p.id]!.length;
    var s = 0.0;
    if (p.full) {
      s = 2.0 + ((cap(p) ?? days) - w);
    } else {
      final goal = partGoal[p.id] ?? 4;
      s = (goal - w) / max(1.0, goal);
      if (p.minShifts != null && w < p.minShifts!) s += 0.6;
    }
    if (requests[p.id]?[d] == 'on') s += 0.5;
    return s - runPenalty(p, d) + rnd.nextDouble() * 0.3;
  }

  bool fillOne(int d) {
    (PlanPerson, List<PlanPerson>)? b;
    double bs = -1e9;
    for (final p in people) {
      final g = groupFor(p, d);
      if (g == null || g.length > room(d)) continue;
      final s = want(p, d);
      if (s > bs) {
        bs = s;
        b = (p, g);
      }
    }
    if (b == null) return false;
    put(b.$2, d);
    return true;
  }

  final stuck = <int>{};
  while (true) {
    int? pick;
    double pickKey = 0;
    for (var d = 1; d <= days; d++) {
      if (stuck.contains(d) || room(d) <= 0) continue;
      var c = 0;
      for (final p in people) {
        final g = groupFor(p, d);
        if (g != null && g.length <= room(d)) c++;
      }
      if (c == 0) {
        stuck.add(d);
        continue;
      }
      final key = (c - room(d)) + rnd.nextDouble() * 0.9;
      if (pick == null || key < pickKey) {
        pick = d;
        pickKey = key;
      }
    }
    if (pick == null) break;
    if (!fillOne(pick)) stuck.add(pick);
  }

  // ---- 3a. 缺正職的日子：把正職從正職比較多的日子換過來，原本那天找人頂 ----
  for (var round = 0; round < 2; round++) {
    for (var d = 1; d <= days; d++) {
      var guard = 0;
      while (fullsOn(d) < mfOf(d) && guard++ < 6) {
        var done = false;
        final order = [for (final p in people) if (p.full) p]..shuffle(rnd);
        for (final p in order) {
          if (done) break;
          if (work[p.id]!.contains(d) || out[p.id]!.containsKey(d)) continue;
          final es = [for (final e in work[p.id]!) if (removable(p, e) && fullsOn(e) > mfOf(e)) e]..shuffle(rnd);
          for (final e in es) {
            remW(p.id, e);
            final g = groupFor(p, d, ignoreCap: true);
            if (g == null || g.length != 1) {
              addW(p.id, e);
              continue;
            }
            addW(p.id, d);
            // d 那天人太多 → 挪一位兼職去頂 e；e 還缺就再找人補
            if (room(d) < 0) {
              final qs = [for (final q in people) if (!q.full && work[q.id]!.contains(d) && removable(q, d)) q]..shuffle(rnd);
              PlanPerson? moved;
              for (final q in qs) {
                remW(q.id, d);
                final gq = groupFor(q, e, ignoreCap: true);
                if (gq != null && gq.length == 1) {
                  addW(q.id, e);
                  moved = q;
                  break;
                }
                addW(q.id, d);
              }
              if (moved == null && qs.isNotEmpty) remW(qs.first.id, d);
            }
            while (room(e) > 0 && fillOne(e)) {}
            done = true;
            break;
          }
        }
        if (!done) break;
      }
    }
  }

  // ---- 3b. 還缺人的日子：能上的人天數滿了 → 把他別天的班交給別人，換到這天 ----
  for (var round = 0; round < 3; round++) {
    for (var d = 1; d <= days; d++) {
      var guard = 0;
      while (room(d) > 0 && guard++ < 12) {
        if (fillOne(d)) continue;
        var done = false;
        final order = [...people]..shuffle(rnd);
        for (final p in order) {
          if (done) break;
          if (work[p.id]!.contains(d) || out[p.id]!.containsKey(d)) continue;
          final es = [for (final e in work[p.id]!) if (removable(p, e)) e]..shuffle(rnd);
          for (final e in es) {
            if (p.full && fullsOn(e) <= mfOf(e)) continue; // 不把那天唯一的正職挪走
            remW(p.id, e);
            final g = groupFor(p, d, ignoreCap: true);
            if (g == null || g.length != 1) {
              addW(p.id, e);
              continue;
            }
            // e 那天少一個人了 → 要有人頂（不能是 p 自己）
            if (room(e) > 0) {
              List<PlanPerson>? sub;
              for (final x in people) {
                if (x.id == p.id) continue;
                final gx = groupFor(x, e);
                if (gx != null && gx.length == 1) {
                  sub = gx;
                  break;
                }
              }
              if (sub == null) {
                addW(p.id, e);
                continue;
              }
              put(sub, e);
            }
            addW(p.id, d);
            done = true;
            break;
          }
        }
        if (!done) break;
      }
    }
  }

  // ---- 3c. 兼職沒到最少天數：跟同一天、天數比較多的兼職換 ----
  for (final p in people) {
    if (p.full || p.minShifts == null) continue;
    var guard = 0;
    while (work[p.id]!.length < p.minShifts! && guard++ < days) {
      var done = false;
      final ds = [for (var d = 1; d <= days; d++) d]..shuffle(rnd);
      for (final d in ds) {
        if (done) break;
        if (work[p.id]!.contains(d)) continue;
        final qs = [
          for (final q in people)
            if (!q.full && q.id != p.id && work[q.id]!.contains(d) && removable(q, d) && work[q.id]!.length > (q.minShifts ?? 0) + 1) q
        ]..sort((a, b) => work[b.id]!.length.compareTo(work[a.id]!.length));
        for (final q in qs) {
          remW(q.id, d);
          final g = groupFor(p, d);
          if (g != null && g.length == 1) {
            addW(p.id, d);
            done = true;
            break;
          }
          addW(q.id, d);
        }
      }
      if (!done) break;
    }
  }

  // ---- 記號 ----
  for (var d = 1; d <= days; d++) {
    for (final p in people) {
      if (out[p.id]!.containsKey(d)) continue;
      if (work[p.id]!.contains(d)) {
        out[p.id]![d] = p.weekdayMarks[wd(d)] ?? (p.marks.isEmpty ? 'V' : p.marks.first);
      } else if (p.full) {
        out[p.id]![d] = requests[p.id]?[d] == 'off' ? '指休' : '休';
      }
    }
  }
  return out;
}

/// 從過去的班表整理出一個人的習慣，給「照過去的班表帶入」用（店長確認後才存成排班條件）。
class RuleSuggestion {
  final Set<int> noWeekdays; // 過去從來沒上過的星期
  final int? minShifts;
  final int? maxShifts;
  final Map<int, String> weekdayMarks; // 每個星期最常排的班別／時段
  final int worked; // 這段期間一共上了幾天
  const RuleSuggestion(this.noWeekdays, this.minShifts, this.maxShifts, this.weekdayMarks, this.worked);
}

/// months：每個月一份（月初日期, 日 → 記號）。full＝正職（只建議班別，不建議星期與天數）。
RuleSuggestion suggestRule(List<(DateTime, Map<int, String>)> months, {required bool full}) {
  final byWd = <int, Map<String, int>>{};
  final counts = <int>[];
  var worked = 0;
  final marks = <String>{};
  for (final (m, row) in months) {
    var c = 0;
    for (final e in row.entries) {
      if (!_isWork(e.value)) continue;
      c++;
      marks.add(e.value);
      final w = DateTime(m.year, m.month, e.key).weekday;
      (byWd[w] ??= {})[e.value] = (byWd[w]![e.value] ?? 0) + 1;
    }
    counts.add(c);
    worked += c;
  }
  final wm = <int, String>{};
  if (marks.length > 1) {
    for (final e in byWd.entries) {
      final top = e.value.entries.reduce((a, b) => b.value > a.value ? b : a);
      wm[e.key] = top.key;
    }
  }
  if (full || worked < 3) return RuleSuggestion(const {}, null, null, wm, worked);
  return RuleSuggestion({for (var w = 1; w <= 7; w++) if (!byWd.containsKey(w)) w}, counts.reduce(min), counts.reduce(max), wm, worked);
}
