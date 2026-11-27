// 員工填指休的兩條規則（ops 0137，老闆 2026-11-20；ops 0150 起每家店自己設）：
//   同一天最多幾位正職指休（先填先贏，預設 1 位），每人每月最多幾天（預設 5 天）；空白＝不限。
//   老闆、店長可以超過（App 先提醒）。
// 「正職」＝班表上的正職，而且排班條件沒有勾「排班時當兼職」。資料庫也擋，這裡是先在畫面上講清楚。

import '../config.dart';
import 'models.dart';
import 'shift_planner.dart';

/// 沒設定（或資料庫還沒更新）時的預設，跟兩家店原本的規則一樣
const shiftOffPerDayDefault = 1;
const shiftOffMonthMaxDefault = 5;

/// 排班條件頁的「員工指休規則」設定入口只在公版（建置時 SELF_SIGNUP=true）出現（老闆 2026-11-27：隱城／小城外這一份畫面完全不變）。
/// 兩家店的規則照樣從資料庫讀（值是 1 位／5 天），只是沒有地方改。
const offLimitsSettingVisible = AppConfig.selfSignup;

/// 排班設定那一列 → (同一天最多幾位, 每月最多幾天)；沒有那一列、或還沒有這兩欄＝預設；欄位空白＝不限（null）
({int? perDay, int? monthMax}) offLimitsFromRow(Map<String, dynamic>? r) => (
      perDay: r == null || !r.containsKey('off_per_day') ? shiftOffPerDayDefault : (r['off_per_day'] as num?)?.toInt(),
      monthMax: r == null || !r.containsKey('off_month_max') ? shiftOffMonthMaxDefault : (r['off_month_max'] as num?)?.toInt(),
    );

/// 給員工看的一句話：同一天只能一位正職指休（先填先贏），每月最多 5 天；要再多請找店長協調班表。
String offRuleText(int? perDay, int? monthMax) {
  final day = perDay == null ? null : perDay == 1 ? '同一天只能一位正職指休（先填先贏）' : '同一天最多 $perDay 位正職指休（先填先贏）';
  final month = monthMax == null ? null : '每月最多 $monthMax 天';
  if (day == null && month == null) return '指休沒有限制。';
  return '${[day, month].whereType<String>().join('，')}；要再多請找店長協調班表。';
}

/// 被擋時的訊息（員工）
String offBlockedText({required bool dayFull, int? perDay, int? monthMax}) => dayFull
    ? (perDay == 1 ? '已有人指休，請找店長協調班表' : '這天指休的人已經滿了（最多 $perDay 位），請找店長協調班表')
    : '一個月最多指休 $monthMax 天，要再多請找店長協調班表';

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

/// 這個人要在這天填指休會碰到的規則：taken＝那天已經有其他正職指休的人；
/// dayFull＝那天的人數已經到上限；overLimit＝這個月的天數已經到上限（上限 null＝不限）
({Set<String> taken, bool dayFull, bool overLimit}) offCheck(
    {required Map<int, Set<String>> takenDays,
    required Map<int, String> mine,
    required String personId,
    required int day,
    int? perDay = shiftOffPerDayDefault,
    int? monthMax = shiftOffMonthMaxDefault}) {
  final taken = {...?takenDays[day]}..remove(personId);
  final count = mine.entries.where((e) => e.key != day && e.value == 'off').length;
  return (
    taken: taken,
    dayFull: perDay != null && taken.length >= perDay,
    overLimit: monthMax != null && count >= monthMax,
  );
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
