// 班表頁健檢第一批（老闆 2026-11-16 核准）：純 Dart，給班表頁用、也給測試用。
//   * parseDayNumber：數字欄打錯不能當成空白存檔（C1）
//   * isMonthScheduled：「這個月排好了沒」改成看上班人次有沒有到需要的八成（A2；一格特休不算排好）
//   * editIssues：已公布的班表點格子改班，用跟自動排班同一套檢查器（B1）

import 'models.dart';
import 'shift_planner.dart';

/// 數字欄：空白＝null；「8」「8.5」「８」「8天」都可以；其他字＝錯（ok=false），不能當成空白存檔。
({bool ok, double? value}) parseDayNumber(String raw, {bool integer = false}) {
  var s = raw.trim().replaceAll(RegExp(r'\s'), '');
  const fw = '０１２３４５６７８９';
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(fw[i], '$i');
  }
  s = s.replaceAll('．', '.').replaceAll(RegExp(r'[天人號日]$'), '');
  if (s.isEmpty) return (ok: true, value: null);
  final v = double.tryParse(s);
  if (v == null || v < 0 || !v.isFinite) return (ok: false, value: null);
  if (integer && v != v.roundToDouble()) return (ok: false, value: null);
  return (ok: true, value: v);
}

/// 那天要幾個人：特別日子 → 依星期 → 沒設就 3（跟自動排班一樣）
int dayNeed(DateTime month, int day, ShiftPlanSetup? s) =>
    s?.specialDays[day] ??
    s?.staffing[DateTime(month.year, month.month, day).weekday]?.need ??
    3;

/// 整個月要幾人次
int requiredShifts(DateTime month, ShiftPlanSetup? s) {
  final days = DateTime(month.year, month.month + 1, 0).day;
  var n = 0;
  for (var d = 1; d <= days; d++) {
    n += dayNeed(month, d, s);
  }
  return n;
}

/// 已經排的上班人次（顯示中的人；休、指休、特休不算）
int workedShifts(ShiftMonth m) {
  var n = 0;
  for (final p in m.people.where((p) => p.active)) {
    n += (m.marks[p.id] ?? const <int, String>{})
        .values
        .where(ShiftMonth.isOn)
        .length;
  }
  return n;
}

/// 這個月排好了沒（老闆 2026-11-16：上班人次到當月需要的八成才算；先點一天特休不算）
bool isMonthScheduled(ShiftMonth m, ShiftPlanSetup? s) {
  final need = requiredShifts(m.month, s);
  final worked = workedShifts(m);
  if (need <= 0) return worked > 0;
  return worked * 10 >= need * 8;
}

/// 已公布的班表點格子改成 [mark]：用自動排班的檢查器看這一格會不會出問題。
/// 回傳跟這一格有關的問題：level 0＝一定不行（指休排上班、另一家店有班），level 1＝違反排班條件。
/// 跨月連班沒有算（班表頁沒有讀上下個月）。
List<PlanIssue> editIssues({
  required ShiftMonth data,
  required ShiftPlanSetup setup,
  required String personId,
  required int day,
  required String? mark,
}) {
  if (!ShiftMonth.isOn(mark)) return const [];
  final days = data.days;
  final people = <PlanPerson>[
    for (final p in data.people.where((p) => p.active || p.id == personId))
      () {
        final r = setup.rules[p.id];
        final full = p.isFull && !(r?.planAsPart ?? false);
        return PlanPerson(
          id: p.id,
          name: p.name,
          full: full,
          offTarget: data.stats[p.id]?.shouldOff ??
              r?.monthOff ??
              (days * 9 / 31).roundToDouble(),
          minShifts: r?.minShifts,
          maxShifts: r?.maxShifts,
          maxConsecutive: r?.maxConsecutive ?? 6,
          noWeekdays: r?.noWeekdays ?? const {},
          marks: const ['V'],
          busy: setup.otherStoreDays[p.id] ?? const {},
        );
      }(),
  ];
  final entries = {
    for (final p in people)
      p.id: Map<int, String>.from(data.marks[p.id] ?? const <int, String>{}),
  };
  final hadMax = _hasMax(people, data, entries, personId);
  entries.putIfAbsent(personId, () => {})[day] = mark!;
  final check = validateSchedule(
    year: data.month.year,
    month: data.month.month,
    people: people,
    needByDay: {
      for (var d = 1; d <= days; d++) d: dayNeed(data.month, d, setup)
    },
    minFullByDay: const {},
    entries: entries,
    requests: setup.requests,
    pairRules: setup.pairRules,
  );
  return [
    for (final i in check.issues)
      if (i.level <= 1 &&
          ((i.days.contains(day) &&
                  (i.personId == personId || i.code == 'pair')) ||
              (i.code == 'max' && i.personId == personId && !hadMax)))
        i,
  ];
}

/// 改之前是不是已經超過最多天數（已經超過的就不再提醒）
bool _hasMax(List<PlanPerson> people, ShiftMonth data,
        Map<String, Map<int, String>> entries, String personId) =>
    validateSchedule(
      year: data.month.year,
      month: data.month.month,
      people: people,
      needByDay: const {},
      minFullByDay: const {},
      entries: entries,
    ).issues.any((i) => i.code == 'max' && i.personId == personId);

/// 照片辨識草稿套用前：資料庫會擋的格子（那天填了指休、另一家店那天有班；0113）。
/// 整月套用只要有一格被擋就整批不寫，所以先在 App 列出全部，讓店長知道要改哪裡。
/// 照片上的新人員還沒有指休、也沒連到另一家店，不會被擋。
List<String> draftConflicts({
  required DateTime month,
  required Map<String, Map<int, String>> entries, // 人名 → 日 → 記號
  required List<ShiftPerson> people,
  required ShiftPlanSetup setup,
}) {
  final out = <String>[];
  final names = entries.keys.toList()..sort();
  for (final name in names) {
    final p = people.where((x) => x.name == name.trim()).firstOrNull;
    if (p == null) continue;
    final days = entries[name]!.keys.toList()..sort();
    for (final d in days) {
      if (!ShiftMonth.isOn(entries[name]![d])) continue;
      if (setup.requests[p.id]?[d] == 'off') out.add('${p.name} ${month.month}/$d 填了指休');
      if (setup.otherStoreDays[p.id]?.contains(d) ?? false) out.add('${p.name} ${month.month}/$d 另一家店已經有班');
    }
  }
  return out;
}
