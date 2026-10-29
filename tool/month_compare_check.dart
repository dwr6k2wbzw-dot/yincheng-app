// 上個月／近 3 個月平均的計算檢查（dart run tool/month_compare_check.dart）
import 'dart:io';
import '../lib/data/month_compare.dart';
import '../lib/data/models.dart';

var fails = 0;
void eq(String n, Object? got, Object? want) {
  final ok = got == want;
  if (!ok) fails++;
  print('${ok ? 'ok  ' : 'FAIL'} $n${ok ? '' : ': got $got, want $want'}');
}

MonthlySummary m(int mo, int g, double rev, {double drinks = 0}) =>
    MonthlySummary(month: DateTime(2026, mo), revenue: rev, guests: g, drinksRevenue: drinks, foodRevenue: 0);

void main() {
  final f = [m(9, 600, 600000), m(8, 700, 630000), m(7, 800, 880000)].map((s) => monthFigure(s, multi: false));
  final a = monthAverage(f);
  eq('月數', a.months, 3);
  eq('平均來客', a.guests, 700.0);
  eq('加權客單', a.avgTicket, 2110000 / 2100);
  // 小城外 7 月以前沒資料：只用有來客的月份
  final b = monthAverage([m(9, 500, 0, drinks: 400000), m(8, 0, 0), m(7, 0, 0)].map((s) => monthFigure(s, multi: true)));
  eq('只有 1 個月', b.months, 1);
  eq('小城外客單用調酒收入', b.avgTicket, 800.0);
  eq('全部沒資料', monthAverage([]).avgTicket, null);
  eq('變化', changeOf(110, 100)!.toStringAsFixed(3), '0.100');
  eq('變化缺值', changeOf(null, 100), null);
  print(fails == 0 ? '全部通過' : '$fails 項失敗');
  exit(fails == 0 ? 0 : 1);
}
