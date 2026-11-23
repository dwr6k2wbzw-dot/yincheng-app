import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/pl_statement.dart';
import 'package:yincheng_ops/services/pl_account_xlsx.dart';

// 會計科目格式的損益表（ops 0142）。這個 repo 是公開的：數字、科目名稱都是假的。
List<PlAccount> accounts(List<(String, String, String?)> names) => [
      for (final (i, n) in names.indexed) PlAccount(id: n.$1, name: n.$1, category: n.$2, autoKind: n.$3, sortOrder: i + 1),
    ];

final demoAccounts = accounts([
  ('薪資支出', 'payroll', 'payroll_base'),
  ('保險費-勞健保+退休金', 'payroll', null),
  ('租金支出-甲', 'rent', 'rent_base'),
  ('租金支出-乙', 'rent', null),
  ('其他費用-雜項', 'misc', 'purchase_misc'),
  ('修繕費', 'misc', null),
  ('手續費', 'misc', 'card_fee'),
  ('記帳費', 'misc', null),
]);

ExpenseItem item(String name, double amount, String account, [String? note]) =>
    ExpenseItem(id: name, name: name, category: 'misc', amount: amount, accountId: account, note: note);

final month = DateTime(2030, 3);

AccountStatement demo({bool multi = false}) => accountStatementOf(
      accounts: demoAccounts,
      storeLabel: '示範店(一店)',
      storeName: '示範店',
      month: month,
      summary: MonthlySummary(
          month: month, revenue: 100000, guests: 0, drinksRevenue: 70000, foodRevenue: 20000, projectAmount: 0,
          coffeeRevenue: multi ? 6000 : 0, ramenRevenue: multi ? 4000 : 0,
          purchaseCost: 30000, drinkCost: 20000, foodCost: 10000, miscCost: 1000),
      multiLineRevenue: multi,
      payrollBase: 20000,
      rentBase: 3000,
      cardFee: 1234.5,
      cardFeeLabel: '刷卡手續費（2%）',
      items: [
        item('勞保', 1000, '保險費-勞健保+退休金', '扣某人 100+50'),
        item('健保', 500, '保險費-勞健保+退休金'),
        item('派對樂手', 2000, '其他費用-雜項', '雜項1000+樂手2000'),
        item('手續費差額', 15.5, '手續費'),
      ],
      recurring: [
        RecurringExpenseItem(id: 'r1', name: '記帳費', category: 'misc', amount: 800, accountId: '記帳費'),
        RecurringExpenseItem(
            id: 'r2', name: '租金乙', category: 'rent', amount: 0, accountId: '租金支出-乙', amountsFrom: {DateTime(2030, 3): 5000}),
      ],
    );

String rows(AccountStatement p) => [
      for (final a in p.expenses) '${a.name}=${a.amount.round()}${a.note.isEmpty ? '' : '「${a.note}」'}',
    ].join('\n');

void main() {
  test('照科目加總、順序固定、沒金額的科目也列、備註接在科目那一行', () {
    final p = demo();
    expect(p.title, '示範店(一店)_3月份損益表');
    expect([for (final l in p.revenue) '${l.label}=${l.amount.round()}'], ['調酒收入=70000', '餐食收入=20000', '其他收入=10000']);
    expect([for (final l in p.purchase) '${l.label}=${l.amount.round()}'], ['酒水=20000', '餐食=10000']);
    expect((p.share(p.purchaseTotal) * 10000).round(), 3000);
    expect(rows(p), '''薪資支出=20000
保險費-勞健保+退休金=1500「扣某人 100+50」
租金支出-甲=3000
租金支出-乙=5000
其他費用-雜項=3000「雜項1000+樂手2000」
修繕費=0
手續費=1250
記帳費=800''');
    expect(p.expenseTotal, 20000 + 1500 + 3000 + 5000 + 3000 + 1234.5 + 15.5 + 800);
    expect(p.profit, 100000 - 30000 - p.expenseTotal);
    expect([for (final d in p.expenses[1].details) '${d.label}=${d.amount.round()}'], ['勞保=1000', '健保=500']);
    expect([for (final d in p.expenses[4].details) d.label], ['雜項類進貨', '派對樂手']);
    expect([for (final d in p.expenses[6].details) d.label], ['刷卡手續費（2%）', '手續費差額']);
    expect(p.expenses[0].details, isEmpty); // 只有一筆不列明細
  });

  test('營收分四項的店：調酒＝酒水＋餐食＋專案，另列咖啡、拉麵', () {
    final p = demo(multi: true);
    expect([for (final l in p.revenue) '${l.label}=${l.amount.round()}'], ['調酒收入=90000', '咖啡收入=6000', '拉麵收入=4000']);
  });

  test('每月固定還沒開始的月份（金額 0）只有一筆時不列明細', () {
    final p = accountStatementOf(
      accounts: demoAccounts, storeLabel: 'x', storeName: 'x', month: DateTime(2030, 2),
      summary: MonthlySummary(month: DateTime(2030, 2), revenue: 0, guests: 0, drinksRevenue: 0, foodRevenue: 0),
      multiLineRevenue: false, payrollBase: null, rentBase: null, cardFee: 0,
      items: const [],
      recurring: [
        RecurringExpenseItem(
            id: 'r2', name: '租金乙', category: 'rent', amount: 0, accountId: '租金支出-乙', amountsFrom: {DateTime(2030, 3): 5000}),
      ],
    );
    expect(p.expenses.firstWhere((a) => a.name == '租金支出-乙').amount, 0);
    expect(p.expenseTotal, 0);
  });

  test('沒選科目的不會不見：放在最後「未選科目」', () {
    final rows = groupByAccount(demoAccounts, [
      const PlEntry(label: '營業稅', amount: 900),
      const PlEntry(accountId: '修繕費', label: '修冰箱', amount: 100),
    ]);
    expect(rows.last.name, '（未選科目）');
    expect(rows.last.amount, 900);
    expect(rows.length, demoAccounts.length + 1);
  });

  test('停用的科目沒有金額就不列', () {
    final acc = [
      const PlAccount(id: 'a', name: 'A', category: 'misc', sortOrder: 1),
      const PlAccount(id: 'b', name: 'B', category: 'misc', sortOrder: 2, active: false),
    ];
    expect(groupByAccount(acc, const []).map((r) => r.name), ['A']);
    expect(groupByAccount(acc, const [PlEntry(accountId: 'b', label: 'x', amount: 1)]).map((r) => r.name), ['A', 'B']);
  });

  test('Excel：順序、%、明細、本期淨利', () {
    final x = Excel.decodeBytes(buildAccountPlXlsx(demo()));
    final sh = x.tables['損益表']!;
    String v(int r, int c) => sh.rows[r].length > c ? (sh.rows[r][c]?.value?.toString() ?? '') : '';
    final labels = [for (var r = 0; r < sh.maxRows; r++) v(r, 0)];
    expect(labels[0], '示範店(一店)_3月份損益表');
    expect(labels.sublist(1, 3), ['摘要', '營業收入']);
    expect(labels.indexOf('進貨成本') > labels.indexOf('營業收入合計'), isTrue);
    expect(labels.indexOf('營業費用') > labels.indexOf('進貨成本合計'), isTrue);
    expect(labels.indexOf('本期淨利') > labels.indexOf('營業費用類合計'), isTrue);
    final ins = labels.indexOf('保險費-勞健保+退休金');
    expect(labels.sublist(ins + 1, ins + 3), ['　勞保', '　健保']);
    expect(v(ins, 1), '1500');
    expect(v(ins, 3), '扣某人 100+50');
    expect(double.parse(v(labels.indexOf('進貨成本合計'), 2)), closeTo(0.30, 0.0001));
    expect(v(labels.indexOf('修繕費'), 1), ''); // 沒金額的科目也列，金額空白
    expect(v(labels.indexOf('修繕費'), 2), '0');
    expect(v(labels.indexOf('本期淨利'), 1), '35450');
  });
}
