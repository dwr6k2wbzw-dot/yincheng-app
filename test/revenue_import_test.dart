// 營收搬家（ops 0168）：看懂檔案、範本、匯出、示範版的檢查。數字都是測試用的假資料。
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/booking_import.dart' show ImportIssue;
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/revenue_import.dart';
import 'package:yincheng_ops/services/reservation_xlsx.dart';
import 'package:yincheng_ops/services/revenue_xlsx.dart';

void main() {
  group('整理數字', () {
    test('金額各種寫法', () {
      expect(normMoney('12,345'), '12345');
      expect(normMoney('NT\$ 12,345'), '12345');
      expect(normMoney('\$12,345.0'), '12345');
      expect(normMoney('12345 元'), '12345');
      expect(normMoney('１２３４５'), '12345', reason: '全形數字');
      expect(normMoney('12.5'), '12.5');
      expect(normMoney('-'), '', reason: '報表常用「-」代表 0');
      expect(normMoney(''), '');
      expect(normMoney('一萬'), '一萬', reason: '看不懂的照原樣交給資料庫');
    });
    test('來客數', () {
      expect(normGuests('12'), '12');
      expect(normGuests('12 位'), '12');
      expect(normGuests('12人'), '12');
      expect(normGuests('12.0'), '12');
      expect(normGuests('12.5'), '12.5', reason: '資料庫會說要整數');
      expect(normGuests('1,200'), '1200');
    });
  });

  group('讀表格', () {
    test('範本的表頭：一天一列，送資料庫的欄位名稱', () {
      final t = readRevenueTable([
        ['日期', '來客數', '現金', '刷卡', 'AE', '訂金', '酒水', '餐食', '專案', '備註'],
        [
          '2025/10/01',
          '32',
          '9,800',
          '14200',
          '',
          '0',
          '17200',
          '6800',
          '',
          '颱風'
        ],
        ['', '', '', '', '', '', '', '', '', ''],
        [
          '2025-10-02',
          '18人',
          '6400',
          '7600',
          '',
          '2000',
          '11600',
          '4400',
          '',
          ''
        ],
      ]);
      expect(t.problem, isNull);
      expect(t.rows.length, 2);
      expect(t.rows[0].line, 2);
      expect(t.rows[1].line, 4, reason: '空白列跳過，列號照檔案');
      expect(t.rows[0].toJson(), {
        'date': '2025-10-01',
        'guests': '32',
        'cash': '9800',
        'credit_card': '14200',
        'amex': '',
        'deposit': '0',
        'drinks_revenue': '17200',
        'food_revenue': '6800',
        'project_amount': '',
        'note': '颱風',
      });
      expect(t.rows[1].v('guests'), '18');
      expect(t.rows[0].received, 24000);
    });

    test('舊系統的表頭：前面有標題列、別的寫法、合計列略過', () {
      final t = readRevenueTable([
        ['2025 年 10 月營業日報'],
        ['營業日', '來客', '現金收入', '信用卡', '飲料', '餐點', '咖啡'],
        ['2025-10-01', '10', '1000', '2000', '2500', '500', '0'],
        ['合計', '10', '1000', '2000', '2500', '500', '0'],
      ]);
      expect(t.problem, isNull);
      expect(t.rows.length, 1);
      expect(
          t.rows[0].values.keys,
          containsAll([
            'guests',
            'cash',
            'credit_card',
            'drinks_revenue',
            'food_revenue',
            'coffee_revenue'
          ]));
      expect(t.skipped.single.line, 4);
      expect(t.skipped.single.text, '合計列');
    });

    test('認不得的欄位底下有資料 → 不默默丟掉，要改欄名或標成不要', () {
      // Codex：「刷卡金額」沒對上，刷卡的錢就會少算
      final t = readRevenueTable([
        ['日期', '現金', '刷卡金額'],
        ['2025-10-01', '1000', '2000'],
      ]);
      expect(t.rows, isEmpty);
      expect(t.problem, contains('「刷卡金額」（第 C 欄）'));
      // 重複的欄名（第二個「現金」）也算認不得
      expect(
          readRevenueTable([
            ['日期', '現金', '現金'],
            ['2025-10-01', '1000', '500'],
          ]).problem,
          contains('「現金」（第 C 欄）'));
      // 沒有欄名但底下有數字
      expect(
          readRevenueTable([
            ['日期', '現金', ''],
            ['2025-10-01', '1000', '500'],
          ]).problem,
          contains('第 C 欄（沒有欄名）'));
      // 欄名前加 # 或「略過」＝不要；認不得但整欄空白的不擋
      final ok = readRevenueTable([
        ['日期', '現金', '#合計', '略過 備用', '店長簽名'],
        ['2025-10-01', '1000', '1000', 'x', ''],
      ]);
      expect(ok.problem, isNull);
      expect(ok.rows.single.values, {'cash': '1000'});
      expect(columnLetter(0), 'A');
      expect(columnLetter(25), 'Z');
      expect(columnLetter(26), 'AA');
    });

    test('找不到日期、或只有日期沒有營收欄位 → 看不懂', () {
      expect(
          readRevenueTable([
            ['名字', '金額'],
            ['a', '1'],
          ]).problem,
          contains('找不到「日期」'));
      expect(
          readRevenueTable([
            ['日期', '備註'],
            ['2025-10-01', 'x'],
          ]).problem,
          contains('找不到「日期」'));
      expect(
          readRevenueTable([
            ['日期', '現金'],
          ]).problem,
          '表頭下面沒有任何一天的營收');
    });

    test('資料庫回的列號換成檔案裡的列號；0＝整個檔案', () {
      final rows = [
        const RevenueImportRow(line: 3, date: '2025-10-01'),
        const RevenueImportRow(line: 7, date: '2025-10-02'),
      ];
      final r = RevenueImportResult.fromJson({
        'batch': null,
        'ready': 0,
        'errors': [
          {'row': 2, 'message': '現金看不懂（請填數字）'},
          {'row': 0, 'message': '一次最多 2 年'},
        ],
        'skipped': [
          {'row': 1, 'reason': '這天已經有營收資料（不會蓋掉）'}
        ],
        'warnings': [],
        'date_from': '2025-10-01',
        'date_to': '2025-10-02',
      }, rows);
      expect([for (final e in r.errors) e.line], [7, 0]);
      expect(r.skipped.single.line, 3);
      expect(r.dateFrom, DateTime(2025, 10, 1));
      final merged = r.withLocal([const ImportIssue(5, '合計列')]);
      expect([for (final e in merged.skipped) e.line], [3, 5]);
    });
  });

  group('範本', () {
    for (final multi in [false, true]) {
      test('下載的範本讀回來就是兩天（${multi ? '有' : '沒有'}分咖啡拉麵）', () {
        final x = readXlsxCells(
            buildRevenueTemplate(multi: multi, today: DateTime(2026, 11, 28)),
            accept: (c) => readRevenueTable(c).problem == null);
        expect(x.problem, isNull);
        final t = readRevenueTable(x.cells);
        expect(t.problem, isNull);
        expect([for (final r in t.rows) r.date], ['2026-10-01', '2026-10-02']);
        expect(t.columns.contains('coffee_revenue'), multi);
        // 範例的營業收入分類＝收款合計（不會跳提醒）
        for (final r in t.rows) {
          final lines = [
            'drinks_revenue',
            'food_revenue',
            'project_amount',
            'coffee_revenue',
            'ramen_revenue'
          ].fold<double>(0, (a, k) => a + (double.tryParse(r.v(k)) ?? 0));
          expect(lines, r.received);
        }
      });
    }
  });

  group('匯出', () {
    final rows = [
      RevenueEntry(
          id: '1',
          bizDate: DateTime(2025, 9, 30),
          cash: 1000,
          creditCard: 500,
          guests: 3,
          drinks: 1500),
      RevenueEntry(
          id: '2',
          bizDate: DateTime(2025, 10, 2),
          cash: 2000,
          deposit: 1000,
          guests: 5,
          drinks: 2000,
          food: 1000,
          source: 'import'),
      RevenueEntry(
          id: '3',
          bizDate: DateTime(2025, 10, 1),
          cash: 0,
          guests: 0,
          fileImportId: 'b1'),
      RevenueEntry(
          id: '4',
          bizDate: DateTime(2025, 10, 3),
          cash: 400,
          guests: 2,
          drinks: 400,
          fileImportId: 'b1'),
    ];

    test('月份彙總：營業天數不算全部 0 的日子', () {
      final m = revenueByMonth(rows);
      expect([for (final x in m) x.month],
          [DateTime(2025, 9), DateTime(2025, 10)]);
      expect(m[1].days, 2);
      expect(m[1].guests, 7);
      expect(m[1].received, 3400);
      expect(m[1].drinks, 2400);
    });

    test('Excel：每日營收舊到新、來源；月份彙總一頁', () {
      final excel = Excel.decodeBytes(buildRevenueXlsx(rows, multi: false));
      final daily = excel.tables['每日營收']!.rows;
      expect(cellText(daily[0][0]!.value), '日期');
      expect([for (final r in daily.skip(1)) cellText(r[0]!.value)],
          ['2025-09-30', '2025-10-01', '2025-10-02', '2025-10-03']);
      final last = daily[0].length - 1;
      expect(cellText(daily[0][last]!.value), '來源');
      expect([for (final r in daily.skip(1)) cellText(r[last]!.value)],
          ['App 登記', '搬家匯入', '日報表', '搬家匯入']);
      expect(daily[0].any((c) => cellText(c?.value) == '咖啡'), isFalse,
          reason: '沒分咖啡拉麵的店不列那兩欄');
      final month = excel.tables['月份彙總']!.rows;
      expect(cellText(month[2][0]!.value), '2025-10');
      expect(cellText(month[2][3]!.value), '3400');
    });

    test('有分咖啡拉麵的店多兩欄', () {
      final excel = Excel.decodeBytes(buildRevenueXlsx(rows, multi: true));
      final head = [
        for (final c in excel.tables['每日營收']!.rows[0]) cellText(c?.value)
      ];
      expect(head, containsAll(['咖啡', '拉麵']));
    });
  });

  group('示範版（照資料庫的規則）', () {
    final repo = DemoRepository();
    final today = DateTime.now().subtract(const Duration(hours: 6));
    String d(int daysAgo) {
      final x = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: daysAgo));
      return '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    }

    test('預覽：錯誤整批擋下、公休與重複略過、對不上只提醒', () async {
      final rows = [
        const RevenueImportRow(
            line: 2,
            date: '2020-02-01',
            values: {'cash': '1000', 'drinks_revenue': '800'}),
        const RevenueImportRow(
            line: 3, date: '2020-02-02', values: {'cash': '0', 'guests': '0'}),
        const RevenueImportRow(line: 4, date: '2020-02-01', values: {'cash': '500'}),
      ];
      final p = await repo.previewRevenueImport('yc', rows);
      expect(p.errors, isEmpty);
      expect(p.ready, 1);
      expect([for (final e in p.skipped) e.line], [3, 4]);
      expect(p.warnings.single.line, 2);

      final bad = await repo.previewRevenueImport('yc', [
        RevenueImportRow(line: 2, date: d(-3), values: {'cash': '1'}),
        const RevenueImportRow(line: 3, date: '2020-02-03', values: {'cash': '一萬'}),
        const RevenueImportRow(
            line: 4, date: '2020-02-04', values: {'coffee_revenue': '100'}),
      ]);
      expect([
        for (final e in bad.errors) e.text
      ], [
        '日期還沒到（只能匯入今天以前的營收）',
        '現金看不懂（請填數字）',
        '這家店的營收沒有分咖啡、拉麵，請把那兩欄留空',
      ]);
      expect(bad.ready, 0);
    });

    test('匯入、重送同一批、整批復原', () async {
      final rows = [
        const RevenueImportRow(
            line: 2,
            date: '2020-03-01',
            values: {'cash': '1000', 'guests': '4'}),
        const RevenueImportRow(
            line: 3, date: '2020-03-02', values: {'credit_card': '2000'}),
      ];
      final r = await repo.importRevenue('yc', rows, 'a.csv', 'req-1');
      expect(r.inserted, 2);
      final again = await repo.importRevenue('yc', rows, 'a.csv', 'req-1');
      expect(again.repeat, isTrue);
      expect(again.batchId, r.batchId);
      final all = await repo.allRevenueEntries('yc');
      expect(all.where((e) => e.fileImportId == r.batchId).length, 2);
      // 換一個代號再匯一次：兩天都已經有了
      final dup = await repo.previewRevenueImport('yc', rows);
      expect(dup.ready, 0);
      expect(dup.skipped.length, 2);
      final (deleted, kept) = await repo.undoRevenueImport(r.batchId!);
      expect((deleted, kept), (2, 0));
      expect(
          (await repo.allRevenueEntries('yc'))
              .where((e) => e.fileImportId == r.batchId),
          isEmpty);
      expect(() => repo.undoRevenueImport(r.batchId!), throwsException);
      final batches = await repo.revenueImports('yc');
      expect(batches.first.undoneCount, 2);
    });

    test('超過 2 年整個檔案擋下', () async {
      final p = await repo.previewRevenueImport('yc', [
        const RevenueImportRow(line: 2, date: '2020-01-01', values: {'cash': '1'}),
        const RevenueImportRow(line: 3, date: '2022-01-10', values: {'cash': '1'}),
      ]);
      expect(p.errors.single.line, 0);
      expect(p.errors.single.text, contains('一次最多 2 年'));
    });
  });
}
