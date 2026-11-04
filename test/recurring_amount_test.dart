import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';

void main() {
  // 0090（老闆 2026-11-04）：固定支出改金額只從那個月起生效，過去月份不變
  RecurringExpenseItem item(Map<String, num> from) => RecurringExpenseItem.fromRow({
        'id': 'r1',
        'name': '電費',
        'category': 'misc',
        'amount': 6000,
        'recurring_expense_amounts': [
          for (final e in from.entries) {'from_month': e.key, 'amount': e.value},
        ],
      });

  test('沒改過金額：每個月都是原本的金額', () {
    final it = item({});
    expect(it.amountFor(DateTime(2026, 1)), 6000);
    expect(it.amountFor(DateTime(2026, 11)), 6000);
  });

  test('11 月改成 7000：10 月以前照舊，11 月起用新金額', () {
    final it = item({'2026-11-01': 7000});
    expect(it.amountFor(DateTime(2026, 10)), 6000);
    expect(it.amountFor(DateTime(2026, 11, 20)), 7000);
    expect(it.amountFor(DateTime(2027, 3)), 7000);
  });

  test('改過好幾次：用那個月（含）以前最近一次', () {
    final it = item({'2026-12-01': 8000, '2026-09-01': 6500});
    expect(it.amountFor(DateTime(2026, 8)), 6000);
    expect(it.amountFor(DateTime(2026, 9)), 6500);
    expect(it.amountFor(DateTime(2026, 11)), 6500);
    expect(it.amountFor(DateTime(2026, 12)), 8000);
  });

  test('舊資料沒有改金額欄位也能讀', () {
    final it = RecurringExpenseItem.fromRow({'id': 'r', 'name': 'x', 'category': 'rent', 'amount': 100});
    expect(it.amountFor(DateTime(2026, 11)), 100);
  });
}
