// 2026-11-15 班表第二階段：自動算薪資、薪資單。
// 真實 10 月 12 人的金額、總計、成本率，以及店長看不到自己、員工只看自己的權限，都在私人 repo 的 tests/26_payroll.sql（資料庫端）驗；
// 這裡只用虛構的人名和金額，驗 App 端的試算公式（要和資料庫同一套）、薪資單內容、示範資料。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/payroll.dart';
import 'package:yincheng_ops/services/payslip_html.dart';

void main() {
  group('試算公式（和資料庫 app.payroll_total 一樣）', () {
    test('日薪：日薪 × 天數＋獎金，不扣勞健保', () {
      expect(payrollTotal(payType: 'daily', base: 1500, days: 12, bonus: 300, insurance: 999), 18300);
    });

    test('時薪：時數 × 時薪＋獎金−勞健保', () {
      expect(payrollTotal(payType: 'hourly', base: 190, hours: 80.5, bonus: 0, insurance: 250), 15045);
    });

    test('月薪＋固定加班時薪', () {
      expect(payrollTotal(payType: 'monthly', base: 40000, bonus: 2000, insurance: 1500, otHours: 6, otRate: 200), 41700);
    });

    test('月薪＋依勞基法加班（÷240，前 2 小時 ×1.34、之後 ×1.67）', () {
      // 36000/240=150；150×(1.34×4＋1.67×1)=150×7.03=1054.5 → 1055
      expect(payrollTotal(payType: 'monthly', base: 36000, otMode: 'lsa', otHours: 4, otHours2: 1), 37055);
    });

    test('沒有薪率＝算不出來', () {
      expect(payrollTotal(payType: 'hourly', base: null, hours: 10), isNull);
    });

    test('四捨五入到元：.5 進位（和 Postgres numeric 一樣，負數離 0 遠）', () {
      expect(roundYuan(100.5), 101);
      expect(roundYuan(100.49), 100);
      expect(roundYuan(-100.5), -101);
      expect(roundYuan(0.1 + 0.2 + 0.2), 1);
    });

    test('固定加班時薪低於勞基法 → 標示', () {
      const r = PayrollRow(personId: 'x', name: '虛構', payType: 'monthly', baseAmount: 48000, otRate: 200, lsaRate: 268);
      expect(r.otBelowLaw, isTrue);
      const ok = PayrollRow(personId: 'x', name: '虛構', payType: 'monthly', baseAmount: 30000, otRate: 200, lsaRate: 167.5);
      expect(ok.otBelowLaw, isFalse);
      expect(lsaOtRate(30000), closeTo(167.5, 1e-9));
    });
  });

  group('薪資單', () {
    final slip = PayrollSlip(
        month: DateTime(2026, 9, 1),
        storeName: '示範店',
        personName: '王<小明>',
        payType: 'monthly',
        baseAmount: 36000,
        otHours: 3,
        otRate: 200,
        bonus: 1000,
        insurance: 1100,
        note: '含 A&B 活動',
        gross: 36500);

    test('每一行：底薪、加班費、獎金、勞健保（扣）合起來＝實發', () {
      final lines = slip.lines();
      expect(lines.map((l) => l.label), ['底薪', '加班費', '獎金', '勞健保自付額']);
      expect(lines.fold<double>(0, (a, l) => a + l.amount), slip.gross);
    });

    test('時薪、日薪的說明寫出單價 × 數量', () {
      final h = PayrollSlip(month: DateTime(2026, 9, 1), storeName: 's', personName: 'p', payType: 'hourly', baseAmount: 200, hours: 82.5);
      expect(h.lines().first.detail, '200 × 82.5 小時');
      final d = PayrollSlip(month: DateTime(2026, 9, 1), storeName: 's', personName: 'p', payType: 'daily', baseAmount: 1800, days: 3);
      expect(d.lines().single.amount, 5400);
    });

    test('網頁版：名字、備註會跳脫（不會被當成 HTML），金額有千分位', () {
      final html = payslipHtml([slip]);
      expect(html, contains('王&lt;小明&gt;'));
      expect(html, isNot(contains('王<小明>')));
      expect(html, contains('含 A&amp;B 活動'));
      expect(html, contains('36,500'));
      expect(html, contains('−1,100'));
      expect(html, contains('2026 年 9 月薪資單'));
    });

    test('一次印多人：一人一頁', () {
      final html = payslipHtml([slip, slip]);
      expect('<section class="slip">'.allMatches(html).length, 2);
    });
  });

  group('示範資料', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('老闆：建立 → 改一個人 → 發布後不能改 → 重新開啟', () async {
      final repo = DemoRepository();
      await repo.signIn('owner@x', 'x');
      final m = DateTime(2026, 9, 1);
      expect((await repo.payrollReport('yc', m)).status, isNull);
      final n = await repo.preparePayroll('yc', m);
      expect(n, greaterThan(0));
      final rows = await repo.payrollMonth('yc', m);
      final hourly = rows.firstWhere((r) => r.payType == 'hourly');
      final g = await repo.savePayrollEntry('yc', hourly.personId, m, hours: 10, bonus: 100, insurance: 50);
      expect(g, 200 * 10 + 100 - 50);
      final report = await repo.payrollReport('yc', m);
      expect(report.total, (await repo.payrollMonth('yc', m)).fold<double>(0, (a, r) => a + r.gross!));
      await repo.publishPayroll('yc', m);
      await expectLater(repo.savePayrollEntry('yc', hourly.personId, m, hours: 11), throwsA(anything));
      await repo.reopenPayroll('yc', m, '補獎金');
      expect((await repo.payrollReport('yc', m)).published, isFalse);
    });

    test('員工：不能看薪資清單；綁定沒確認就沒有薪資單', () async {
      final staff = DemoRepository();
      await staff.signIn('staff@x', 'x');
      await expectLater(staff.payrollMonth('yc', DateTime(2026, 9, 1)), throwsA(anything));
      expect(await staff.myPayslips('yc'), isNotEmpty);

      final pending = DemoRepository();
      await pending.signIn('unverified-staff@x', 'x');
      expect(await pending.myPayslips('yc'), isEmpty);
    });
  });
}
