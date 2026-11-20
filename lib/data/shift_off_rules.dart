// 員工填指休的兩條規則（ops 0137，老闆 2026-11-20）：
//   同一天只能一位正職指休（先填先贏），每人每月最多 5 天。老闆、店長可以超過（App 先提醒）。
// 「正職」＝班表上的正職，而且排班條件沒有勾「排班時當兼職」。資料庫也擋，這裡是先在畫面上講清楚。

import 'models.dart';
import 'shift_planner.dart';

const shiftOffMonthMax = 5;

/// 同一天已經有正職指休的人（日 → 人員 id）。
/// [fromDb] 是資料庫算好的（ops 0137）；資料庫還沒更新時用畫面上的資料自己算
/// （員工讀不到別人的排班條件，這時「排班時當兼職」的人會被當成正職，只是提醒，資料庫才算數）。
Map<int, Set<String>> offTakenDays(
    {required Map<int, Set<String>>? fromDb, required List<ShiftPerson> people, required ShiftPlanSetup setup}) {
  if (fromDb != null) return fromDb;
  final full = {
    for (final p in people)
      if (p.isFull && !(setup.rules[p.id]?.planAsPart ?? false)) p.id
  };
  final m = <int, Set<String>>{};
  setup.requests.forEach((pid, days) {
    if (!full.contains(pid)) return;
    days.forEach((d, k) {
      if (k == 'off') m.putIfAbsent(d, () => {}).add(pid);
    });
  });
  return m;
}

/// 這個人要在這天填指休會碰到的規則：taken＝那天已經有其他正職指休的人；overLimit＝這個月已經 5 天了
({Set<String> taken, bool overLimit}) offCheck(
    {required Map<int, Set<String>> takenDays, required Map<int, String> mine, required String personId, required int day}) {
  final taken = {...?takenDays[day]}..remove(personId);
  final count = mine.entries.where((e) => e.key != day && e.value == 'off').length;
  return (taken: taken, overLimit: count >= shiftOffMonthMax);
}

/// 一位正職這個月的特休（ops 0138）：餘額＝起算數字＋調整＋到職滿期自動加 − 劃特休的天數
class SpecialLeave {
  final DateTime? start; // 從哪天開始自動算
  final double? balance; // 這個月月底為止剩幾天（還沒起算＝null）
  final int usedInMonth;
  final double grantedInMonth;
  final DateTime? nextGrantDate;
  final double? nextGrantDays;
  const SpecialLeave({this.start, this.balance, this.usedInMonth = 0, this.grantedInMonth = 0, this.nextGrantDate, this.nextGrantDays});

  static double? _n(Object? v) => v == null ? null : (v as num).toDouble();
  factory SpecialLeave.fromRow(Map<String, dynamic> r) => SpecialLeave(
        start: r['start_date'] == null ? null : DateTime.parse(r['start_date'] as String),
        balance: _n(r['balance']),
        usedInMonth: (r['used_in_month'] as num?)?.toInt() ?? 0,
        grantedInMonth: _n(r['granted_in_month']) ?? 0,
        nextGrantDate: r['next_grant_date'] == null ? null : DateTime.parse(r['next_grant_date'] as String),
        nextGrantDays: _n(r['next_grant_days']),
      );
}

/// 勞基法第 38 條（週年制）：到職滿這個期間加幾天，跟資料庫 app.lsa_special_grants 同一套
List<(DateTime, int)> lsaSpecialGrants(DateTime hire, {int years = 30}) => [
      (DateTime(hire.year, hire.month + 6, hire.day), 3),
      for (var y = 1; y <= years; y++)
        (DateTime(hire.year + y, hire.month, hire.day),
            y == 1 ? 7 : y == 2 ? 10 : y <= 4 ? 14 : y <= 9 ? 15 : (15 + y - 9).clamp(0, 30)),
    ];
