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
        RecurringExpenseItem(id: 'r3', name: '獎金', category: 'payroll', amount: 700, accountId: '薪資支出'),
      ],
    );

String rows(AccountStatement p) => [
      for (final a in p.misc) '${a.name}=${a.amount.round()}${a.note.isEmpty ? '' : '「${a.note}」'}',
    ].join('\n');

void main() {
  test('五大項：雜項照科目分組，租金、人事逐筆', () {
    final p = demo();
    expect(p.title, '示範店(一店)_3月份損益表');
    expect([for (final l in p.revenue) '${l.label}=${l.amount.round()}'], ['調酒收入=70000', '餐食收入=20000', '其他收入=10000']);
    expect([for (final l in p.purchase) '${l.label}=${l.amount.round()}'], ['酒水=20000', '餐食=10000']);
    expect(rows(p), """保險費-勞健保+退休金=1500「扣某人 100+50」
其他費用-雜項=3000「雜項1000+樂手2000」
手續費=1250
記帳費=800""");
    expect([for (final d in p.misc[0].details) '${d.label}=${d.amount.round()}'], ['勞保=1000', '健保=500']);
    expect([for (final d in p.misc[1].details) d.label], ['進貨雜項', '派對樂手']);
    expect([for (final d in p.misc[2].details) d.label], ['刷卡手續費', '手續費差額']);
    expect(p.misc[3].details, isEmpty); // 只有一筆不列明細
    expect([for (final l in p.rent) '${l.label}=${l.amount.round()}'], ['甲=3000', '租金乙=5000']); // 基底名稱照科目、拿掉「租金支出-」
    expect([for (final l in p.payroll) '${l.label}=${l.amount.round()}'], ['薪資支出=20000', '獎金=700']);
    expect(p.miscTotal, 1500 + 3000 + 1250 + 800);
    expect(p.rentTotal, 8000);
    expect(p.payrollTotal, 20700);
    expect(p.profit, 100000 - 30000 - 6550 - 8000 - 20700);
  });

  test('基底名稱：拿掉「租金支出-」和括號', () {
    expect(baseLabel([const PlAccount(id: 'a', name: '租金支出-世代(營業提成)', category: 'rent', autoKind: 'rent_base')],
        'rent_base', '租金'), '世代營業提成');
    expect(baseLabel(const [], 'rent_base', '租金'), '租金');
  });

  test('營收分四項的店：調酒＝酒水＋餐食＋專案，另列咖啡、拉麵', () {
    final p = demo(multi: true);
    expect([for (final l in p.revenue) '${l.label}=${l.amount.round()}'], ['調酒收入=90000', '咖啡收入=6000', '拉麵收入=4000']);
  });

  test('沒選科目的不會不見：放在最後「未選科目」；沒金額的科目不列', () {
    final rows = groupByAccount(demoAccounts, [
      const PlEntry(label: '營業稅', amount: 900),
      const PlEntry(accountId: '修繕費', label: '修冰箱', amount: 100),
    ]);
    expect(rows.map((r) => r.name), ['修繕費', '未選科目']);
    expect(rows.last.amount, 900);
  });

  test('Excel：五大項、% 只在合計和本期淨利、沒有說明欄', () {
    final x = Excel.decodeBytes(buildAccountPlXlsx(demo()));
    final sh = x.tables['損益表']!;
    String v(int r, int c) => sh.rows[r].length > c ? (sh.rows[r][c]?.value?.toString() ?? '') : '';
    final labels = [for (var r = 0; r < sh.maxRows; r++) v(r, 0)];
    expect(labels[0], '示範店(一店)_3月份損益表');
    final order = ['營業收入', '營業收入合計', '進貨', '進貨合計', '雜項', '雜項合計', '租金', '租金合計', '人事', '人事合計', '本期淨利'];
    final idx = [for (final o in order) labels.indexOf(o)];
    expect(idx.every((i) => i > 0), isTrue);
    for (var i = 1; i < idx.length; i++) {
      expect(idx[i] > idx[i - 1], isTrue, reason: order[i]);
    }
    final ins = labels.indexOf('保險費-勞健保+退休金');
    expect(labels.sublist(ins + 1, ins + 3), ['　勞保', '　健保']);
    expect(v(ins, 2), ''); // 明細不顯示 %
    expect(double.parse(v(labels.indexOf('進貨合計'), 2)), closeTo(0.30, 0.0001));
    expect(double.parse(v(labels.indexOf('本期淨利'), 2)), closeTo(0.3475, 0.0001));
    expect(v(labels.indexOf('本期淨利'), 1), '34750');
    expect(sh.maxColumns, 3); // 沒有說明欄
    expect(labels.any((l) => l.contains('（') || l.contains('說明')), isFalse);
  });
}
