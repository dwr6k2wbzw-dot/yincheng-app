import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/purchase_items_math.dart';
import 'package:yincheng_ops/data/stock_math.dart';

void main() {
  test('複製成日報表那一列：日期、類別、摘要、金額用 Tab 分開', () {
    expect(dailyReportRow(DateTime(2026, 11, 3), '雜項', ' 小北 3M手套 ', 290), '11/3\t雜項\t小北 3M手套\t290');
    expect(dailyReportRow(DateTime(2026, 11, 12), '酒水', '示範酒商', -580.5), '11/12\t酒水\t示範酒商\t-580.50');
  });

  test('打數量：小數四捨五入到 0.1，不合理的不收', () {
    expect(parseQty('3'), 3);
    expect(parseQty(' 3.44 '), 3.4);
    expect(parseQty('0.96'), 1.0);
    expect(parseQty(''), isNull);
    expect(parseQty('abc'), isNull);
    expect(parseQty('10000'), isNull);
  });

  group('重點品項該盤了沒', () {
    final today = bizToday();
    DateTime ago(int n) => DateTime(today.year, today.month, today.day - n);
    Product p(String? cycle) => Product('p', '琴酒', '酒水', '瓶', countCycle: cycle);
    test('每天盤：今天（營業日）盤過就不用，昨天盤的要', () {
      expect(isCountDue(p('daily'), LastCount(1, ago(0))), isFalse);
      expect(isCountDue(p('daily'), LastCount(1, ago(1))), isTrue);
      expect(isCountDue(p('daily'), null), isTrue);
    });
    test('每週盤：滿 7 天才要', () {
      expect(isCountDue(p('weekly'), LastCount(1, ago(6))), isFalse);
      expect(isCountDue(p('weekly'), LastCount(1, ago(7))), isTrue);
    });
    test('不追蹤的品項不會列進該盤的清單', () {
      expect(isCountDue(p(null), null), isFalse);
      expect(isCountDue(p(null), LastCount(1, ago(30))), isFalse);
    });
    test('幾天前盤的、誰盤的', () {
      expect(countAge(null), '還沒盤過');
      expect(countAge(LastCount(1, ago(0), by: '小明')), '今天盤・小明');
      expect(countAge(LastCount(1, ago(1))), '昨天盤');
      expect(countAge(LastCount(1, ago(6), by: '小明'), who: false), '6 天前盤');
    });
  });

  test('進貨報價分區：照合併後的類別，雜項不列', () {
    final g = quoteGroupOf([
      CostCategory.full('yc_drink', '酒水', null, costGroup: 'drink', inMiscRate: false),
      CostCategory.full('yc_food', '餐食', null, costGroup: 'food', inMiscRate: false),
      CostCategory.full('yc_misc', '雜項', null, costGroup: 'other', inMiscRate: true),
      CostCategory.full('bar_misc', '酒水副材料-雜項', null, costGroup: 'drink', inMiscRate: true, selectable: false, displayAs: 'yc_misc'),
      CostCategory.full('xc_ramen_food', '布布拉麵-餐食', null, costGroup: 'ramen', inMiscRate: false, selectable: false, displayAs: 'yc_food'),
    ]);
    expect([g('yc_drink'), g('yc_food'), g('yc_misc'), g('bar_misc'), g('xc_ramen_food'), g('沒有這個')],
        ['drink', 'food', null, null, 'food', null]);
  });

  test('待確認：只差日期的才能一次確認', () {
    PurchaseMatch m(List<String> reasons, {String kind = 'pair', bool waiting = false}) => PurchaseMatch(
        kind: kind, appId: 'a', appDate: DateTime(2026, 11, 3), amount: 1, paidBy: 'vendor', appName: 'x', appCategory: '酒水',
        reasons: reasons, waiting: waiting);
    expect(m(['日期不同']).dateOnly, isTrue);
    expect(m(['日期不同', '名稱對不上']).dateOnly, isFalse);
    expect(m(['日期不同'], waiting: true).dateOnly, isFalse);
    expect(m(['日報表沒有這一筆'], kind: 'unmatched').dateOnly, isFalse);
  });
}
