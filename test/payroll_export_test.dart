// 匯出薪資表（老闆 2026-11-18）：欄位照薪資單的項目展開、合計、看不到的列不匯出。人名、金額都是虛構的。
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/payroll.dart';
import 'package:yincheng_ops/services/payroll_export.dart';

void main() {
  const monthly = PayrollRow(
      personId: 'a', name: '王月薪', payType: 'monthly', baseAmount: 40000, otHours: 2, otRate: 200, bonus: 1000,
      extras: PayExtras(laborIns: 900, healthIns: 600, cashPaid: 5000, items: [PayItem(income: false, label: '借支', amount: 300)]),
      note: '月底結算', gross: 40000 + 400 + 1000 - 900 - 600 - 300);
  const hourly = PayrollRow(
      personId: 'b', name: '李時薪', payType: 'hourly', baseAmount: 200, hours: 30.5,
      extras: PayExtras(items: [PayItem(income: true, label: '交通補助', amount: 500)]), gross: 6100 + 500);
  const hidden = PayrollRow(personId: 'c', name: '店長', payType: 'monthly', hidden: true);
  const exempt = PayrollRow(personId: 'd', name: '老闆', payType: 'monthly', exempt: true);
  const missing = PayrollRow(personId: 'e', name: '新人', payType: 'hourly', missingRate: true);
  final p = PayrollExport(
      storeName: '虛構店', companyName: '虛構餐飲有限公司', month: DateTime(2031, 3, 1),
      rows: const [monthly, hourly, hidden, exempt, missing], revenue: 500000, costRate: 0.1);

  test('欄位照薪資單的項目展開（自訂項目各一欄）', () {
    final c = p.columns();
    expect(c.income, ['本薪', '加班費', '獎金', '交通補助']);
    expect(c.deduction, ['代扣勞保費', '代扣健保費', '借支']);
  });

  test('看不到的、不計薪的不匯出；沒有薪資的列出來', () {
    expect(p.people.map((r) => r.personId), ['a', 'b', 'e']);
    expect(p.hasHidden, isTrue);
  });

  test('每個人的金額跟薪資單一樣', () {
    expect(p.amountsOf(monthly).income, {'本薪': 40000, '加班費': 400, '獎金': 1000});
    expect(p.amountsOf(monthly).deduction, {'代扣勞保費': 900, '代扣健保費': 600, '借支': 300});
    expect(p.amountsOf(hourly).income, {'本薪': 6100, '交通補助': 500});
    expect(p.amountsOf(hourly).deduction, isEmpty);
    expect(p.slipOf(monthly).transfer, 39600 - 5000);
  });

  test('產生的 Excel：表頭、每個人、合計', () {
    final x = Excel.decodeBytes(buildPayrollXlsx(p));
    final rows = x.tables['薪資表']!.rows.map((r) => r.map((c) => c?.value?.toString() ?? '').toList()).toList();
    final head = rows.indexWhere((r) => r.isNotEmpty && r.first == '姓名');
    expect(head, greaterThan(0));
    final h = rows[head];
    String cell(List<String> r, String col) => r[h.indexOf(col)];
    final wang = rows.firstWhere((r) => r.first == '王月薪'), li = rows.firstWhere((r) => r.first == '李時薪');
    expect(double.parse(cell(wang, '收入合計')), 41400);
    expect(double.parse(cell(wang, '支出合計')), 1800);
    expect(double.parse(cell(wang, '實領金額')), 39600);
    expect(double.parse(cell(wang, '領現金額')), 5000);
    expect(double.parse(cell(wang, '實際入帳金額')), 34600);
    expect(cell(wang, '備註'), '月底結算');
    expect(double.parse(cell(li, '實際入帳金額')), 6600);
    expect(rows.firstWhere((r) => r.first == '新人').last, '還沒有薪資資料，沒有算');
    final total = rows.firstWhere((r) => r.first.startsWith('合計'));
    expect(total.first, '合計（3 人）');
    expect(double.parse(cell(total, '實領金額')), 39600 + 6600);
    expect(double.parse(cell(total, '實際入帳金額')), 34600 + 6600);
    expect(rows.any((r) => r.first == '店長' || r.first == '老闆'), isFalse);
    expect(rows.any((r) => r.isNotEmpty && r.first.contains('不含你自己')), isTrue);
  });

  test('收入、支出同名的項目分開算（Codex P2）', () {
    const same = PayrollRow(
        personId: 'f', name: '周同名', payType: 'monthly', baseAmount: 30000, bonus: 1000,
        extras: PayExtras(items: [PayItem(income: false, label: '獎金', amount: 200)]), gross: 30000 + 1000 - 200);
    final q = PayrollExport(storeName: '虛構店', month: DateTime(2031, 3, 1), rows: const [same]);
    expect(q.amountsOf(same).income['獎金'], 1000);
    expect(q.amountsOf(same).deduction['獎金'], 200);
    final x = Excel.decodeBytes(buildPayrollXlsx(q));
    final rows = x.tables['薪資表']!.rows.map((r) => r.map((c) => c?.value?.toString() ?? '').toList()).toList();
    final h = rows.firstWhere((r) => r.isNotEmpty && r.first == '姓名');
    final first = h.indexOf('獎金'), second = h.lastIndexOf('獎金');
    expect(second, greaterThan(first));
    for (final r in [rows.firstWhere((r) => r.first == '周同名'), rows.firstWhere((r) => r.first.startsWith('合計'))]) {
      expect(double.parse(r[first]), 1000);
      expect(double.parse(r[second]), 200);
      expect(double.parse(r[h.indexOf('收入合計')]), 31000);
      expect(double.parse(r[h.indexOf('支出合計')]), 200);
    }
  });
}
