import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/attendance_models.dart';
import 'package:yincheng_ops/data/booking_import.dart' show parseCsv;
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/staff_import.dart';
import 'package:yincheng_ops/services/staff_xlsx.dart';

void main() {
  group('讀名冊檔案', () {
    test('範本的表頭：每一欄都讀得到、日期金額整理好', () {
      final t = readStaffImportTable([
        ['員工名冊'],
        staffImportColumns,
        [
          '小明',
          '王小明',
          '正職',
          '2026/3/1',
          '0912345678',
          '王媽媽',
          '0922333444',
          '月薪',
          'NT\$ 32,000',
          '',
          '33,300'
        ],
        ['', '', '', '', '', '', '', '', '', '', ''],
        [
          '阿華',
          '',
          '兼職',
          '2026年11月1日',
          '',
          '',
          '',
          '時薪',
          '196.0',
          '2026-11-15',
          ''
        ],
      ]);
      expect(t.problem, isNull);
      expect(t.rows.length, 2);
      final a = t.rows[0], b = t.rows[1];
      expect(a.line, 3);
      expect(a.name, '小明');
      expect(a.fullName, '王小明');
      expect(a.hireDate, '2026-03-01');
      expect(a.amount, '32000');
      expect(a.insuredSalary, '33300');
      expect(a.effectiveFrom, '');
      expect(a.hasPay, isTrue);
      expect(b.line, 5, reason: '空白列跳過，列號照檔案');
      expect(b.hireDate, '2026-11-01');
      expect(b.amount, '196');
      expect(b.effectiveFrom, '2026-11-15');
    });

    test('沒有暱稱欄：用姓名當暱稱、全名留空', () {
      final t = readStaffImportTable([
        ['姓名', '電話', '職別'],
        ['王小明', '0912345678', '兼職'],
      ]);
      expect(t.problem, isNull);
      expect(t.rows.single.name, '王小明');
      expect(t.rows.single.fullName, '');
      expect(t.rows.single.kind, '兼職');
      expect(t.rows.single.hasPay, isFalse);
    });

    test('表頭寫法：正職/兼職（半形斜線）、大小寫、空白都認得', () {
      final t = readStaffImportTable([
        ['Nickname', 'Full Name', '正職/兼職', 'Hire Date', '計薪 方式', '起薪'],
        ['Kiki', 'Chen Kiki', 'part', '2026-01-02', 'hourly', '200'],
      ]);
      final r = t.rows.single;
      expect(r.name, 'Kiki');
      expect(r.fullName, 'Chen Kiki');
      expect(r.kind, 'part');
      expect(r.hireDate, '2026-01-02');
      expect(r.payType, 'hourly');
      expect(r.amount, '200');
    });

    test('找不到暱稱或姓名欄、表頭下面沒有人', () {
      expect(
          readStaffImportTable([
            ['日期', '金額'],
            ['2026-01-01', '100']
          ]).problem,
          contains('找不到'));
      expect(
          readStaffImportTable([
            ['暱稱', '全名']
          ]).problem,
          contains('沒有任何員工'));
    });

    test('看不懂的金額照原樣交給資料庫（不偷偷改成別的數字）', () {
      final r = readStaffImportTable([
        ['暱稱', '起薪金額'],
        ['小明', '三萬'],
        ['小華', '190.5'],
      ]).rows;
      expect(r[0].amount, '三萬');
      expect(r[1].amount, '190.5');
    });

    test('送給資料庫的欄位名稱；清空起薪只留名冊', () {
      const r = StaffImportRow(
          line: 2,
          name: '小明',
          payType: '月薪',
          amount: '30000',
          hireDate: '2026-01-01');
      final j = r.toJson();
      expect(j.keys.toSet(), {
        'name',
        'full_name',
        'kind',
        'hire_date',
        'phone',
        'emergency_contact',
        'emergency_phone',
        'pay_type',
        'amount',
        'effective_from',
        'insured_salary',
      });
      expect(j.keys.any((k) => k.contains('national') || k.contains('bank')),
          isFalse,
          reason: '身分證、銀行帳號不送');
      final w = r.withoutPay();
      expect(w.hasPay, isFalse);
      expect(w.hireDate, '2026-01-01');
      expect(w.line, 2);
    });

    test('CSV（Excel 存的）也讀得懂', () {
      final t =
          readStaffImportTable(parseCsv('﻿暱稱,全名,到職日\r\n小明,王小明,2026/1/2\r\n'));
      expect(t.rows.single.fullName, '王小明');
      expect(t.rows.single.hireDate, '2026-01-02');
    });
  });

  group('資料庫回的結果', () {
    test('row 換成檔案裡的列號', () {
      final rows = [
        const StaffImportRow(line: 3, name: 'A'),
        const StaffImportRow(line: 7, name: 'B'),
      ];
      final r = StaffImportResult.fromJson({
        'batch': null,
        'inserted': 0,
        'ready': 1,
        'ready_pay': 1,
        'errors': [
          {'row': 2, 'message': '電話格式不對'}
        ],
        'skipped': [
          {'row': 1, 'reason': '班表上已經有這個名字'}
        ],
      }, rows);
      expect(r.ready, 1);
      expect(r.readyPay, 1);
      expect(r.errors.single.line, 7);
      expect(r.errors.single.text, '電話格式不對');
      expect(r.skipped.single.line, 3);
      expect(r.repeat, isFalse);
    });

    test('重送：回同一批', () {
      final r = StaffImportResult.fromJson({
        'batch': 'b1',
        'inserted': 2,
        'with_pay': 1,
        'skipped': [],
        'errors': [],
        'repeat': true
      }, const []);
      expect(r.batchId, 'b1');
      expect(r.withPay, 1);
      expect(r.repeat, isTrue);
    });

    test('匯入紀錄、整批復原', () {
      final b = StaffImportBatch.fromRow({
        'id': 'b1',
        'created_at': '2032-07-01T10:00:00Z',
        'file_name': 'a.xlsx',
        'total_rows': 3,
        'inserted': 2,
        'with_pay': 1,
        'skipped': 1,
        'undone_at': '2032-07-02T10:00:00Z',
        'undone_count': 1,
        'undone_kept': 1,
      });
      expect(b.inserted, 2);
      expect(b.undoneKept, 1);
      final u = StaffImportUndo.fromJson({
        'deactivated': 1,
        'kept': 1,
        'kept_names': ['阿花']
      });
      expect(u.deactivated, 1);
      expect(u.keptNames, ['阿花']);
    });
  });

  group('Excel 範本與匯出', () {
    test('範本讀回來是兩位範例，說明頁寫了身分證、銀行帳號不匯入', () {
      final bytes = buildStaffImportTemplate(today: DateTime(2032, 7, 1));
      final x = readStaffXlsx(bytes);
      expect(x.problem, isNull);
      final t = readStaffImportTable(x.cells);
      expect(t.rows.map((r) => r.name), ['小明', '阿華']);
      expect(t.rows[0].hireDate, '2032-01-02');
      final help = Excel.decodeBytes(bytes)
          .tables['說明']!
          .rows
          .map((r) => r.first?.value.toString() ?? '')
          .join('\n');
      expect(help, contains('身分證、銀行帳號不放進匯入'));
    });

    test('匯出：欄位跟範本一樣、看不到薪資的人不寫起薪、不含身分證和帳號', () {
      final people = [
        ShiftPerson(
            id: 'a',
            name: '小明',
            fullName: '王小明',
            sortOrder: 1,
            hireDate: DateTime(2026, 3, 1)),
        ShiftPerson(id: 'b', name: '阿華', kind: 'part', sortOrder: 2),
        ShiftPerson(id: 'c', name: '老張', sortOrder: 0, active: false),
      ];
      final dir = [
        StaffEntry(
            personId: 'a',
            name: '王小明',
            kind: 'full',
            active: true,
            phone: '0912345678',
            nationalId: 'A123456789',
            bankAccount: '0001112223334',
            ratePayType: 'monthly',
            rateAmount: 32000,
            rateEffectiveFrom: DateTime(2026, 3, 1),
            insuredSalary: 33300,
            canSeePay: true),
        const StaffEntry(
            personId: 'b',
            name: '阿華',
            kind: 'part',
            active: true,
            ratePayType: 'hourly',
            rateAmount: 196,
            canSeePay: false),
      ];
      final bytes = buildStaffRosterXlsx(people, dir);
      final cells = readStaffXlsx(bytes).cells;
      expect(cells.first, [...staffImportColumns, '狀態']);
      final all = cells.expand((r) => r).join('|');
      expect(all.contains('A123456789'), isFalse);
      expect(all.contains('0001112223334'), isFalse);
      expect(cells[1].sublist(0, 4), ['小明', '王小明', '正職', '2026-03-01']);
      expect(cells[1].sublist(7, 11), ['月薪', '32000', '2026-03-01', '33300']);
      expect(cells[2][0], '阿華');
      expect(cells[2].sublist(7, 11).every((v) => v.isEmpty), isTrue,
          reason: '看不到薪資：起薪留空');
      expect(cells[3][0], '老張', reason: '停用的排最後');
      expect(cells[3].last, '停用');
      // 匯出的檔案可以直接拿去匯入
      final t = readStaffImportTable(cells);
      expect(t.problem, isNull);
      expect(t.rows.length, 3);
      expect(t.rows.first.amount, '32000');
    });
  });
}
