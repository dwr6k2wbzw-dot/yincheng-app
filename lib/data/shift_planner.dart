// 自動排班（老闆 2026-10-27，0073）
// 純 Dart（不用 Flutter），方便在 CI 用 `dart run tool/shift_plan_check.dart` 檢查。
//
// 做法：
//   1. 照日期順序，每天補到「需要的人數」（先補正職下限），挑「落後進度最多」的人
//      （正職：該上的天數按日子平均分；兼職：最少～最多天數的中間值）
//   2. 正職還沒上到該上的天數、兼職還沒到最少天數 → 補在人力最吃緊的日子
//   3. 還不夠人的日子：找還有空的人補，都排滿了就跟別天換班
//   3. 上班記號：用排班條件的記號（第一個優先；同一天別人用過的換下一個，例如 B、BH 輪流）
//      正職沒上班的日子：員工填想休的 → 指休，其他 → 休；兼職沒上班留空白
//   員工填「想休」的日子一定不排（老闆選：盡量照排，人不夠時提醒）；兼職有填「可以上」就只排那些天。

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
  const ShiftRule({
    required this.personId,
    this.monthOff,
    this.minShifts,
    this.maxShifts,
    this.maxConsecutive,
    this.noWeekdays = const {},
    this.marks = const [],
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
      };

  bool get isEmpty =>
      monthOff == null &&
      minShifts == null &&
      maxShifts == null &&
      maxConsecutive == null &&
      noWeekdays.isEmpty &&
      marks.isEmpty &&
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
  const ShiftPlanSetup({
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
  });
}

class PlanResult {
  final Map<String, Map<int, String>> entries; // 人 → 日 → 記號（只含列出的人）
  final Map<int, int> staffed; // 日 → 排到幾人
  final Map<int, int> need; // 日 → 需要幾人
  final Map<String, int> workDays; // 人 → 上班天數
  final List<String> warnings;
  const PlanResult(this.entries, this.staffed, this.need, this.workDays, this.warnings);
}

const _away = {'休', '指休', '特休'};
bool _isWork(String? m) => m != null && m.isNotEmpty && !_away.contains(m);

/// 自動排班。fixed：保留不動的格子（人 → 日 → 記號）。
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
}) {
  final rnd = Random(seed);
  final days = DateTime(year, month + 1, 0).day;
  int wd(int d) => DateTime(year, month, d).weekday;
  final work = {for (final p in people) p.id: <int>{}};
  final out = {for (final p in people) p.id: <int, String>{}};
  for (final p in people) {
    for (final e in (fixed[p.id] ?? const <int, String>{}).entries) {
      if (e.key < 1 || e.key > days) continue;
      out[p.id]![e.key] = e.value;
      if (_isWork(e.value)) work[p.id]!.add(e.key);
    }
  }
  final hasOn = {
    for (final p in people) p.id: (requests[p.id] ?? const {}).values.any((v) => v == 'on'),
  };

  bool can(PlanPerson p, int d) {
    if (out[p.id]!.containsKey(d)) return false; // 已經有格子（保留的或排好的）
    if (p.noWeekdays.contains(wd(d))) return false;
    final r = requests[p.id]?[d];
    if (r == 'off') return false;
    if (!p.full && hasOn[p.id]! && r != 'on') return false;
    // 自訂規則：不能同一天的人那天已經上班 → 不排；要跟誰一起上 → 那個人那天沒上就不排
    for (final r in pairRules) {
      if (r.isApart) {
        final other = r.a == p.id ? r.b : (r.b == p.id ? r.a : null);
        if (other != null && (work[other]?.contains(d) ?? false)) return false;
      } else if (r.a == p.id && !(work[r.b]?.contains(d) ?? false)) {
        return false;
      }
    }
    final w = work[p.id]!;
    var run = 1;
    for (var x = d - 1; w.contains(x); x--) {
      run++;
    }
    for (var x = d + 1; w.contains(x); x++) {
      run++;
    }
    return run <= p.maxConsecutive;
  }

  int leaveDays(PlanPerson p) => out[p.id]!.values.where((m) => m == '特休').length;
  // 正職該上幾天；兼職最多幾天（null＝不限）
  int? target(PlanPerson p) =>
      p.full ? max(0, days - p.offTarget.round() - leaveDays(p)) : p.maxShifts;
  bool capOk(PlanPerson p) {
    final t = target(p);
    return t == null || work[p.id]!.length < t;
  }

  double score(PlanPerson p, int d) {
    final w = work[p.id]!.length;
    final remaining = days - d + 1;
    double s;
    if (p.full) {
      final t = target(p)!;
      s = 1.0 + (t * d / days - w); // 落後進度越多越優先
      if (t - w >= remaining) s += 5; // 剩下的日子全都要上
    } else {
      final mn = p.minShifts ?? 0;
      final mx = p.maxShifts ?? max(mn, 4);
      final goal = (mn + mx) / 2;
      s = 0.3 + (goal * d / days - w) * 0.8;
      if (mn - w >= remaining) s += 5;
    }
    if (requests[p.id]?[d] == 'on') s += 1.0;
    return s + rnd.nextDouble() * 0.15;
  }

  int staffedOn(int d) => people.where((p) => work[p.id]!.contains(d)).length;

  // 第一輪：照日期順序，每天補到需要的人數
  for (var d = 1; d <= days; d++) {
    var cnt = staffedOn(d);
    var fulls = people.where((p) => p.full && work[p.id]!.contains(d)).length;
    final need = needByDay[d] ?? 0;
    final minFull = minFullByDay[d] ?? 0;
    // 照進度：不讓同一個人在月初就把天數用完（月底才不會沒人）
    bool paceOk(PlanPerson p) {
      final t = target(p);
      return t == null || work[p.id]!.length < t * d / days + 1.5;
    }

    final cands = [for (final p in people) if (can(p, d) && capOk(p) && paceOk(p)) (p, score(p, d))]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    // 一個一個加（加了之後再檢查下一個，自訂規則才會生效）；跑兩次讓「要跟誰一起上」的人有機會排到
    for (final (p, _) in cands) {
      if (fulls >= minFull || cnt >= need) break;
      if (p.full && !work[p.id]!.contains(d) && can(p, d)) {
        work[p.id]!.add(d);
        fulls++;
        cnt++;
      }
    }
    for (var pass = 0; pass < 2; pass++) {
      for (final (p, _) in cands) {
        if (cnt >= need) break;
        if (!work[p.id]!.contains(d) && can(p, d)) {
          work[p.id]!.add(d);
          cnt++;
        }
      }
    }
  }

  // 第二輪：正職還沒上到該上的天數、兼職還沒到最少天數 → 補在人力最吃緊的日子
  for (final p in people) {
    final want = p.full ? target(p)! : (p.minShifts ?? 0);
    while (work[p.id]!.length < want) {
      final ds = [for (var d = 1; d <= days; d++) if (!work[p.id]!.contains(d) && can(p, d)) (d, rnd.nextDouble())];
      if (ds.isEmpty) break;
      ds.sort((a, b) {
        final ra = staffedOn(a.$1) - (needByDay[a.$1] ?? 0), rb = staffedOn(b.$1) - (needByDay[b.$1] ?? 0);
        if (ra != rb) return ra.compareTo(rb);
        final na = needByDay[a.$1] ?? 0, nb = needByDay[b.$1] ?? 0;
        if (na != nb) return nb.compareTo(na);
        return a.$2.compareTo(b.$2);
      });
      work[p.id]!.add(ds.first.$1);
    }
  }

  // 第三輪：還不夠人的日子，找還有空的人補；都排滿了就跟別天換班
  //   （把某人從人多的那天、或有人能頂替的那天挪過來；保留的格子不動）
  bool fixDay(int d) {
    final c = [for (final p in people) if (!work[p.id]!.contains(d) && can(p, d) && capOk(p)) (p, score(p, d))]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    if (c.isNotEmpty) {
      work[c.first.$1.id]!.add(d);
      return true;
    }
    final order = [...people]..shuffle(rnd);
    for (final p in order) {
      final w = work[p.id]!;
      if (w.contains(d) || !can(p, d)) continue;
      final es = [for (final e in w) if (!out[p.id]!.containsKey(e)) (e, rnd.nextDouble())]
        ..sort((a, b) {
          final sa = staffedOn(a.$1) - (needByDay[a.$1] ?? 0), sb = staffedOn(b.$1) - (needByDay[b.$1] ?? 0);
          return sa != sb ? sb.compareTo(sa) : a.$2.compareTo(b.$2);
        });
      for (final (e, _) in es) {
        // 有人規定要跟 p 一起上、那天也有上 → p 不能從那天挪走
        if (pairRules.any((r) => !r.isApart && r.b == p.id && (work[r.a]?.contains(e) ?? false))) continue;
        w.remove(e);
        if (!can(p, d)) {
          w.add(e);
          continue;
        }
        if (staffedOn(e) >= (needByDay[e] ?? 0)) {
          w.add(d);
          return true;
        }
        final q = [for (final x in people) if (x.id != p.id && !work[x.id]!.contains(e) && can(x, e) && capOk(x)) (x, score(x, e))]
          ..sort((a, b) => b.$2.compareTo(a.$2));
        if (q.isNotEmpty) {
          work[q.first.$1.id]!.add(e);
          w.add(d);
          return true;
        }
        w.add(e);
      }
    }
    return false;
  }

  for (var round = 0; round < 3; round++) {
    for (var d = 1; d <= days; d++) {
      var guard = 0;
      while (staffedOn(d) < (needByDay[d] ?? 0) && guard++ < 20 && fixDay(d)) {}
    }
  }

  // 記號
  final warnings = <String>[];
  final staffed = <int, int>{};
  for (var d = 1; d <= days; d++) {
    final used = <String, int>{};
    for (final p in people) {
      final m = out[p.id]![d];
      if (m != null && _isWork(m)) used[m] = (used[m] ?? 0) + 1;
    }
    for (final p in people) {
      if (out[p.id]!.containsKey(d) || !work[p.id]!.contains(d)) continue;
      final m = p.marks.firstWhere((x) => (used[x] ?? 0) == 0, orElse: () => p.marks.first);
      used[m] = (used[m] ?? 0) + 1;
      out[p.id]![d] = m;
    }
    for (final p in people) {
      if (out[p.id]!.containsKey(d) || !p.full) continue;
      out[p.id]![d] = requests[p.id]?[d] == 'off' ? '指休' : '休';
    }
    staffed[d] = staffedOn(d);
    final need = needByDay[d] ?? 0;
    if (staffed[d]! < need) {
      final off = [for (final p in people) if (requests[p.id]?[d] == 'off') p.name];
      warnings.add('$month/$d（${'一二三四五六日'[wd(d) - 1]}）少 ${need - staffed[d]!} 人'
          '${off.isEmpty ? '' : '（想休：${off.join('、')}）'}');
    }
    final minFull = minFullByDay[d] ?? 0;
    final fulls = people.where((p) => p.full && work[p.id]!.contains(d)).length;
    if (fulls < minFull && staffed[d]! >= need) {
      warnings.add('$month/$d 正職只有 $fulls 人（至少要 $minFull 人）');
    }
  }
  final names = {for (final p in people) p.id: p.name};
  for (final r in pairRules) {
    final a = names[r.a], b = names[r.b];
    if (a == null || b == null) continue;
    final bad = [
      for (var d = 1; d <= days; d++)
        if (r.isApart
            ? work[r.a]!.contains(d) && work[r.b]!.contains(d)
            : work[r.a]!.contains(d) && !work[r.b]!.contains(d))
          d
    ];
    if (bad.isNotEmpty) {
      warnings.add(r.isApart
          ? '$a 跟 $b 有 ${bad.length} 天同一天上班（$month/${bad.join('、')}，是原本排好的格子）'
          : '$a 有 ${bad.length} 天沒跟 $b 一起上（$month/${bad.join('、')}）');
    }
  }
  for (final p in people) {
    final w = work[p.id]!.length;
    if (p.full && w < target(p)!) {
      warnings.add('${p.name} 只排到 $w 天，比該上的少 ${target(p)! - w} 天（會多休）');
    }
    if (!p.full && p.minShifts != null && w < p.minShifts!) {
      warnings.add('${p.name} 只排到 $w 天（最少要 ${p.minShifts} 天）');
    }
  }
  return PlanResult(out, staffed, {for (var d = 1; d <= days; d++) d: needByDay[d] ?? 0},
      {for (final p in people) p.id: work[p.id]!.length}, warnings);
}
