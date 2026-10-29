import 'models.dart';

/// 總覽「上個月」「近 3 個月平均」的來客數與客單價（老闆 2026-10-29）。
///
/// 數字跟總覽本月卡片同一口徑（每月營收彙總，含活動）：
/// - 客單＝客單分子 ÷ 來客；小城外分子用調酒收入（酒水＋餐食＋專案，與小城外 Excel 相同），其他店用營業額。
/// - 近 3 個月＝選的月份往前 3 個完整月份（10 月 → 7、8、9 月），不含本月。
///   平均來客＝有資料月份的來客合計 ÷ 月數；平均客單＝分子合計 ÷ 來客合計（依來客加權，不是三個客單直接平均）。
///   沒有來客的月份（例如小城外 7 月以前沒匯入）不算進月數。
class MonthFigure {
  const MonthFigure(this.month, this.guests, this.base);
  final DateTime month;
  final int guests;
  final double base;
  double? get avgTicket => guests > 0 ? base / guests : null;
}

class MonthAverage {
  const MonthAverage(this.months, this.guests, this.avgTicket);
  final int months; // 有資料的月份數
  final double? guests; // 平均每月來客
  final double? avgTicket;
}

MonthFigure monthFigure(MonthlySummary s, {required bool multi}) =>
    MonthFigure(s.month, s.guests, multi ? s.drinksRevenue + s.foodRevenue + s.projectAmount : s.revenue);

MonthAverage monthAverage(Iterable<MonthFigure> figures) {
  var n = 0, guests = 0;
  var base = 0.0;
  for (final f in figures) {
    if (f.guests <= 0) continue;
    n++;
    guests += f.guests;
    base += f.base;
  }
  if (n == 0) return const MonthAverage(0, null, null);
  return MonthAverage(n, guests / n, base / guests);
}

/// a 比 b 的變化（a／b − 1）；任一邊沒有值時為 null
double? changeOf(double? a, double? b) => a == null || b == null || b == 0 ? null : a / b - 1;
