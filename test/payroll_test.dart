// 2026-11-15 班表第二階段：自動算薪資、薪資單。
// 真實 10 月 12 人的金額、總計、成本率，以及店長看不到自己、員工只看自己的權限，都在私人 repo 的 tests/26_payroll.sql（資料庫端）驗；
// 這裡只用虛構的人名和金額，驗 App 端的試算公式（要和資料庫同一套）、薪資單內容、示範資料。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/payroll.dart';
import 'package:yincheng_ops/data/repository.dart';
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

    test('扣項（ops 0124）：三種計薪方式都從實發扣掉', () {
      expect(payrollTotal(payType: 'daily', base: 1500, days: 12, bonus: 300, deduction: 500), 17800);
      expect(payrollTotal(payType: 'hourly', base: 190, hours: 80.5, insurance: 250, deduction: 45), 15000);
      expect(payrollTotal(payType: 'monthly', base: 40000, bonus: 2000, insurance: 1500, otHours: 6, otRate: 200, deduction: 1700), 40000);
      // 沒填＝0，跟原本的結果一樣
      expect(payrollTotal(payType: 'monthly', base: 40000, bonus: 2000, insurance: 1500, otHours: 6, otRate: 200), 41700);
    });

    test('薪資單多一行「扣項」，每一行加起來等於實發', () {
      final s = PayrollSlip(
          month: DateTime(2031, 1), storeName: '虛構店', personName: '虛構', payType: 'hourly', baseAmount: 190, hours: 80.5,
          insurance: 250, deduction: 45, gross: 15000);
      final lines = s.lines();
      expect(lines.where((l) => l.label == '扣項').single.amount, -45);
      expect(lines.fold<double>(0, (a, l) => a + l.amount), 15000);
      // 沒有扣項就不多那一行
      expect(PayrollSlip(month: DateTime(2031, 1), storeName: '虛構店', personName: '虛構', payType: 'hourly', baseAmount: 190, hours: 1, gross: 190)
          .lines().any((l) => l.label == '扣項'), isFalse);
    });

    test('數字欄位：格式不對（1..5、abc、負數）跟空白分開；0 和正數才算對', () {
      String? e(String t) => payrollNumberError(t, decimals: 2);
      for (final t in ['1..5', 'abc', '-3', '-0.5', '.', '..', '4.5.', '1,500', 'NaN', 'Infinity', '1e999']) {
        expect(e(t), '格式不對：只能填 0 或正數（例如 4、4.5、1500）', reason: t);
      }
      for (final t in ['', '  ', '0', '4', '4.5', '.5', '5.', '1500', ' 73.5 ']) {
        expect(e(t), isNull, reason: t);
      }
    });

    test('數字欄位小數位數照資料庫：天數 1 位、金額 2 位（多的會被資料庫四捨五入）；上限照欄位檢查', () {
      // 天數 numeric(4,1)：1.25 天存進去會變 1.3 天，日薪 2,000 會從試算 2,500 變 2,600
      expect(payrollNumberError('1.25', decimals: 1, max: 31), '最多 1 位小數（例如 1.5）');
      for (final t in ['1.2', '1.20', '1.0', '12', '31', '31.0']) {
        expect(payrollNumberError(t, decimals: 1, max: 31), isNull, reason: t);
      }
      expect(payrollNumberError('32', decimals: 1, max: 31), '不能超過 31');
      expect(payrollNumberError('31.5', decimals: 1, max: 31), '不能超過 31');
      // 金額 numeric(10,2)
      for (final t in ['100.555', '0.001', '1500.125']) {
        expect(payrollNumberError(t, decimals: 2), '最多 2 位小數（例如 1500.25）', reason: t);
      }
      for (final t in ['100.55', '100.550', '100.5', '0.01']) {
        expect(payrollNumberError(t, decimals: 2), isNull, reason: t);
      }
    });

    test('時數只能 0.5 的倍數', () {
      for (final v in [0.0, 4.0, 4.5, 82.5, 160.0]) {
        expect(isHalfHour(v), isTrue, reason: '$v');
      }
      for (final v in [4.25, 16.3, 0.1, 82.75]) {
        expect(isHalfHour(v), isFalse, reason: '$v');
      }
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

    test('每一項先四捨五入到元；和實發對不上時多一行「進位調整」，加總一定＝實發', () {
      expect(slip.lines().any((l) => l.label == '進位調整'), isFalse); // 整數的不會多一行
      // 時薪 183 × 10.25＝1875.75 → 1876；獎金 100.5 → 101；合計 1976.25 → 實發 1976
      expect(payrollTotal(payType: 'hourly', base: 183, hours: 10.25, bonus: 100.5), 1976);
      final odd = PayrollSlip(
          month: DateTime(2026, 9, 1), storeName: 's', personName: 'p', payType: 'hourly', baseAmount: 183, hours: 10.25,
          bonus: 100.5, gross: 1976);
      final lines = odd.lines();
      expect(lines.map((l) => l.amount), [1876, 101, -1]);
      expect(lines.last.label, '進位調整');
      expect(lines.fold<double>(0, (a, l) => a + l.amount), odd.gross);
      for (final l in lines) {
        expect(l.amount, l.amount.roundToDouble(), reason: '${l.label} 要是整數元');
      }
      final html = payslipHtml([odd]);
      expect(html, contains('進位調整'));
      expect(html, contains('1,976'));
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

    test('草稿在標題旁標「草稿／尚未發布」；金額欄標新臺幣（元）；已發布的不標草稿', () {
      final draft = payslipHtml([slip]);
      expect(draft, contains('<span class="draft">草稿／尚未發布</span></h1>'));
      expect(draft, contains('<title>【草稿】'));
      expect(draft, contains('金額・新臺幣（元）'));
      final pub = payslipHtml([
        PayrollSlip(
            month: slip.month, storeName: '示範店', personName: '阿明', payType: 'hourly', baseAmount: 200, hours: 10,
            gross: 2000, publishedAt: DateTime(2026, 10, 5))
      ]);
      expect(pub, isNot(contains('草稿')));
      expect(pub, contains('金額・新臺幣（元）'));
    });

    test('管理頁的清單轉成薪資單：照清單的發布狀態標草稿（清單沒有發布時間，頁尾只寫已發布）', () {
      const row = PayrollRow(personId: 'p1', name: '阿明', payType: 'hourly', baseAmount: 200, hours: 10, gross: 2000);
      const pubRow = PayrollRow(
          personId: 'p1', name: '阿明', status: 'published', payType: 'hourly', baseAmount: 200, hours: 10, gross: 2000);
      final m = DateTime(2026, 9, 1);
      final draft = PayrollSlip.fromPayrollRow(row, m, '示範店'), pub = PayrollSlip.fromPayrollRow(pubRow, m, '示範店');
      expect(draft.published, isFalse);
      expect(pub.published, isTrue);
      expect(payslipHtml([draft]), contains('草稿／尚未發布'));
      expect(payslipHtml([draft]), contains('<title>【草稿】'));
      final html = payslipHtml([pub]);
      expect(html, isNot(contains('草稿')));
      expect(html, contains('<p class="foot">已發布・'));
      // 多人一起印：有一張草稿就整份標草稿；全部已發布就不標
      expect(payslipHtml([pub, draft]), contains('<title>【草稿】薪資單'));
      expect(payslipHtml([pub, pub]), contains('<title>薪資單'));
    });

    test('一次印多人：一人一頁', () {
      final html = payslipHtml([slip, slip]);
      expect('<section class="slip">'.allMatches(html).length, 2);
    });
  });

  group('示範資料', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('老闆：建立 → 改一個人 → 缺人不能發布 → 設不計薪 → 發布後不能改 → 重新開啟', () async {
      final repo = DemoRepository();
      await repo.signIn('owner@x', 'x');
      final m = DateTime(2026, 9, 1);
      expect((await repo.payrollReport('yc', m)).status, isNull);
      final n = await repo.preparePayroll('yc', m);
      expect(n, greaterThan(0));
      final rows = await repo.payrollMonth('yc', m);
      final hourly = rows.firstWhere((r) => r.payType == 'hourly' && r.gross != null);
      // 時數只能 0.5 的倍數
      await expectLater(repo.savePayrollEntry('yc', hourly.personId, m, hours: 10.25), throwsA(anything));
      final g = await repo.savePayrollEntry('yc', hourly.personId, m, hours: 10, bonus: 100, insurance: 50);
      expect(g, 200 * 10 + 100 - 50);
      // 應計薪名單缺一位沒有薪率的人：總計不算、畫面列出名字、不能發布
      var report = await repo.payrollReport('yc', m);
      expect(report.missingNames, hasLength(1));
      expect(report.total, isNull);
      final missing = (await repo.payrollMonth('yc', m)).singleWhere((r) => r.missingRate);
      expect(missing.name, report.missingNames.single);
      await expectLater(repo.publishPayroll('yc', m), throwsA(anything));
      // 老闆把他設成不計薪 → 名單補齊、可以發布
      await repo.setPayrollExempt('yc', missing.personId, true);
      report = await repo.payrollReport('yc', m);
      expect(report.missingNames, isEmpty);
      expect((await repo.payrollMonth('yc', m)).singleWhere((r) => r.personId == missing.personId).exempt, isTrue);
      expect(report.total,
          (await repo.payrollMonth('yc', m)).where((r) => !r.exempt).fold<double>(0, (a, r) => a + r.gross!));
      await repo.publishPayroll('yc', m);
      // 已發布的月份用發布當時的名單：之後名單有變（取消不計薪）也不會讓總計變空白
      final publishedTotal = (await repo.payrollReport('yc', m)).total;
      await repo.setPayrollExempt('yc', missing.personId, false);
      report = await repo.payrollReport('yc', m);
      expect(report.missingNames, isEmpty);
      expect(report.total, publishedTotal);
      expect((await repo.payrollMonth('yc', m)).any((r) => r.personId == missing.personId), isFalse);
      await expectLater(repo.savePayrollEntry('yc', hourly.personId, m, hours: 11), throwsA(anything));
      await repo.reopenPayroll('yc', m, '補獎金');
      expect((await repo.payrollReport('yc', m)).published, isFalse);
    });

    test('先設不計薪的人，帶入時不建立他的薪資列，總額不含他', () async {
      final repo = DemoRepository();
      await repo.signIn('owner@x', 'x');
      final m = DateTime(2026, 8, 1);
      final people = (await repo.shiftMonth('yc', m)).people;
      final skip = people[1].id;
      await repo.setPayrollExempt('yc', skip, true);
      expect(await repo.preparePayroll('yc', m), people.length - 1);
      final rows = await repo.payrollMonth('yc', m);
      expect(rows.any((r) => r.personId == skip), isFalse);
      expect(rows.where((r) => r.personId != 'demo-no-rate').length, people.length - 1);
    });

    test('店長（示範）：看不到自己那一列、沒有總計與成本率；不能改自己、不能設不計薪', () async {
      final repo = DemoRepository();
      await repo.signIn('manager@x', 'x');
      expect((await repo.myMemberships()).first.role.name, 'manager');
      final m = DateTime(2026, 7, 1);
      await repo.preparePayroll('yc', m);
      final rows = await repo.payrollMonth('yc', m);
      final self = rows.first;
      expect(self.hidden, isTrue);
      expect(self.gross, isNull);
      final report = await repo.payrollReport('yc', m);
      expect(report.total, isNull);
      expect(report.costRate, isNull);
      expect(report.visibleTotal, rows.where((r) => !r.hidden && r.gross != null).fold<double>(0, (a, r) => a + r.gross!));
      await expectLater(repo.savePayrollEntry('yc', self.personId, m, bonus: 1), throwsA(anything));
      await expectLater(repo.setPayrollExempt('yc', 'demo-no-rate', true), throwsA(anything));
    });

    test('員工：不能看薪資清單；綁定沒確認就沒有薪資單', () async {
      final staff = DemoRepository();
      await staff.signIn('staff@x', 'x');
      await expectLater(staff.payrollMonth('yc', DateTime(2026, 9, 1)), throwsA(anything));
      await expectLater(staff.setPayrollExempt('yc', 'someone', true), throwsA(anything));
      expect(await staff.myPayslips('yc'), isNotEmpty);

      final pending = DemoRepository();
      await pending.signIn('unverified-staff@x', 'x');
      expect(await pending.myPayslips('yc'), isEmpty);
    });
  });

  group('畫面上「薪率」改叫「薪資」（2026-11-15 老闆）', () {
    test('資料庫守衛的訊息還寫「薪率」，顯示時換成「薪資」', () {
      expect(friendlyError(Exception('message: 薪率只能往後加：生效日要晚於已有的生效日（已生效的不能改）, code: P0001')),
          '薪資只能往後加：生效日要晚於已有的生效日（已生效的不能改）');
      expect(friendlyError(Exception('message: 已生效的薪率不能刪除, code: P0001')), '已生效的薪資不能刪除');
      expect(friendlyError(Exception('message: 還有人沒有薪率或還沒帶入，不能發布：示範甲, code: 22023')),
          '還有人沒有薪資或還沒帶入，不能發布：示範甲');
    });
  });
}
