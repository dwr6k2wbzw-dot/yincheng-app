import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/booking_import.dart';
import 'package:yincheng_ops/data/reservation_models.dart';
import 'package:yincheng_ops/services/reservation_xlsx.dart';

void main() {
  group('整理日期時間', () {
    test('日期各種寫法都換成 yyyy-MM-dd', () {
      expect(normDate('2026/12/24'), '2026-12-24');
      expect(normDate('2026-1-5'), '2026-01-05');
      expect(normDate('2026.12.24'), '2026-12-24');
      expect(normDate('2026年12月24日'), '2026-12-24');
      expect(normDate('2026-12-24 19:30'), '2026-12-24');
      expect(normDate('12/24'), '12/24', reason: '看不懂的照原樣交給資料庫');
      expect(normDate('2026-12-24T19:30:00'), '2026-12-24');
    });
    test('日之後多了字不能被截掉（照原樣交給資料庫）', () {
      expect(normDate('2026-12-240'), '2026-12-240');
      expect(normDate('2026/12/24號'), '2026/12/24號');
      expect(normDate('2026-12-24 備註'), '2026-12-24 備註');
      expect(normDate('2026-12-2419:30'), '2026-12-2419:30');
    });
    test('Excel 的日期序號、時間小數（公式格存的計算結果）', () {
      expect(normDate('46010'), '2025-12-19');
      expect(normDate('12345'), '12345', reason: '不像日期的數字照原樣');
      expect(normTime('0.8125'), '19:30');
      expect(normTime('.5'), '12:00');
    });
    test('時間各種寫法都換成 HH:mm', () {
      expect(normTime('19:30'), '19:30');
      expect(normTime('7:30'), '07:30');
      expect(normTime('19:30:00'), '19:30');
      expect(normTime('19：30'), '19:30');
      expect(normTime('7:30 PM'), '19:30');
      expect(normTime('晚上 7:30'), '19:30');
      expect(normTime('12:15 AM'), '00:15');
      expect(normTime('1930'), '19:30');
      expect(normTime('25:00'), '25:00', reason: '不合理的照原樣');
    });
    test('人數、語言', () {
      expect(normParty('4'), '4');
      expect(normParty('4 位'), '4');
      expect(normParty('4人'), '4');
      expect(normParty('4.0'), '4');
      expect(normParty('2.5'), '2.5');
      expect(normLang('英文'), 'en');
      expect(normLang('日本語'), 'ja');
      expect(normLang(' 中文 '), 'zh');
      expect(normLang(''), '');
      expect(normLang('法文'), '法文');
    });
  });

  group('讀表格', () {
    test('表頭可以在第幾列、欄位順序可以不同、空白列跳過、列號照檔案', () {
      final t = readImportTable([
        ['舊系統匯出 2026/11'],
        [],
        ['姓名', '訂位日期', '時段', '大人', '手機', 'E-mail', '需求'],
        [
          '王 先生',
          '2026/12/24',
          '7:30 PM',
          '4位',
          '0912-345-678',
          'w@x.com',
          '靠窗'
        ],
        ['', '', '', '', '', '', ''],
        ['Lee', '2026-12-25', '20:00', '2', '', '', ''],
      ]);
      expect(t.problem, isNull);
      expect(t.rows.length, 2);
      final a = t.rows.first;
      expect([
        a.line,
        a.date,
        a.time,
        a.party,
        a.name,
        a.phone,
        a.email,
        a.note
      ], [
        4,
        '2026-12-24',
        '19:30',
        '4',
        '王 先生',
        '0912-345-678',
        'w@x.com',
        '靠窗'
      ]);
      expect(t.rows.last.line, 6);
      expect(a.toJson().containsKey('lang'), isFalse, reason: '沒填語言不送（資料庫當中文）');
    });
    test('找不到日期、姓名 → 說清楚', () {
      expect(
          readImportTable([
            ['a', 'b'],
            ['1', '2']
          ]).problem,
          contains('找不到「日期」和「姓名」'));
    });
    test('缺時間或人數那一欄', () {
      expect(
          readImportTable([
            ['日期', '姓名', '人數'],
            ['2026-12-24', '王', '2']
          ]).problem,
          '找不到「時間」這一欄');
    });
    test('只有表頭', () {
      expect(
          readImportTable([
            ['日期', '時間', '人數', '姓名']
          ]).problem,
          '表頭下面沒有任何訂位');
    });
  });

  group('狀態欄', () {
    test('有效的匯入；已取消、未到、已到店略過；看不懂的列成問題；列號照檔案', () {
      final t = readImportTable([
        ['日期', '時間', '人數', '姓名', '狀態'],
        ['2026-12-24', '19:00', '2', '甲', ''],
        ['2026-12-24', '19:00', '2', '乙', '已確認'],
        ['2026-12-24', '19:00', '2', '丙', 'Booked'],
        ['2026-12-24', '19:00', '2', '丁', '已取消'],
        ['2026-12-24', '19:00', '2', '戊', 'no_show'],
        ['2026-12-24', '19:00', '2', '己', 'Arrived'],
        ['2026-12-24', '19:00', '2', '庚', '改期中'],
      ]);
      expect(t.problem, isNull);
      expect([for (final r in t.rows) r.name], ['甲', '乙', '丙']);
      expect([for (final e in t.skipped) '${e.line} ${e.text}'], ['5 狀態是已取消', '6 狀態是no_show', '7 狀態是Arrived']);
      expect(t.errors.single.line, 8);
      expect(t.errors.single.text, startsWith('看不懂的狀態「改期中」'));
    });
    test('全部都是已取消：不是「沒有任何訂位」，而是全部略過', () {
      final t = readImportTable([
        ['日期', '時間', '人數', '姓名', 'Status'],
        ['2026-12-24', '19:00', '2', '甲', 'cancelled'],
      ]);
      expect(t.problem, isNull);
      expect(t.rows, isEmpty);
      expect(t.skipped.single.line, 2);
    });
    test('自己 App 匯出的檔案匯回來：已取消、未到、已到店都略過，只留已確認', () {
      Reservation r(String id, String status) => Reservation(
          id: id, date: DateTime(2026, 12, 24), time: '19:00', party: 2, name: id, phone: '',
          status: status, source: 'app', createdAt: DateTime(2026, 11, 1));
      final x = readXlsxCells(buildReservationsXlsx('隱城', [
        r('甲', 'confirmed'),
        r('乙', 'cancelled'),
        r('丙', 'no_show'),
        r('丁', 'arrived'),
      ]));
      final t = readImportTable(x.cells);
      expect([for (final r in t.rows) r.name], ['甲']);
      expect([for (final e in t.skipped) e.text], ['狀態是已取消', '狀態是未到', '狀態是已到店']);
      expect(t.errors, isEmpty);
    });
    test('預覽結果加上讀檔時分出來的列，照列號排', () {
      const db = ImportResult(ready: 1, skipped: [ImportIssue(9, '這個時間已經有這位客人的訂位')], errors: [ImportIssue(4, '沒有日期')]);
      final m = db.withLocal([const ImportIssue(3, '狀態是已取消')], [const ImportIssue(12, '看不懂的狀態')]);
      expect([for (final e in m.skipped) e.line], [3, 9]);
      expect([for (final e in m.errors) e.line], [4, 12]);
      expect(m.ready, 1);
    });
  });

  group('CSV', () {
    test('BOM、引號、逗號、換行、雙引號', () {
      final rows =
          parseCsv('﻿日期,姓名,備註\r\n2026-12-24,"王, 先生","說""要""靠窗\n兩行"\r\n');
      expect(rows.length, 2);
      expect(rows[1], ['2026-12-24', '王, 先生', '說"要"靠窗\n兩行']);
    });
    test('不是 UTF-8（Big5）：不讀成亂碼，請人另存', () {
      // 「中文」的 Big5
      expect(() => decodeCsvBytes(Uint8List.fromList([0xA4, 0xA4, 0xA4, 0xE5])),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('不是 UTF-8 編碼（可能是 Big5）'))));
      expect(decodeCsvBytes(Uint8List.fromList(utf8.encode('日期,姓名'))), '日期,姓名');
    });
    test('引號開了沒收尾：不能把後面的列吞掉，說大約在第幾列', () {
      expect(
          () => parseCsv('日期,時間,人數,姓名,備註\n2026-12-24,19:00,2,王,ok\n2026-12-25,19:00,2,李,"靠窗\n2026-12-26,19:00,2,陳,\n2026-12-27,19:00,2,林,\n'),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', 'CSV 有一格的引號沒有收尾（大約在第 3 列），請檢查後再選一次')));
      // 有收尾的多行格照常
      expect(parseCsv('a,b\n"x\ny",z\n').length, 2);
    });
    test('分號分隔', () {
      expect(parseCsv('日期;姓名\n2026-12-24;王')[1], ['2026-12-24', '王']);
    });
    test('UTF-8 檔案讀回來接到 readImportTable', () {
      final text =
          utf8.decode(utf8.encode('日期,時間,人數,姓名\n2026/12/24,19:00,2,王\n'));
      final t = readImportTable(parseCsv(text));
      expect(t.rows.single.date, '2026-12-24');
    });
  });

  test('資料庫回的第幾個換成檔案裡的列號', () {
    final rows = [
      const ImportRow(line: 4, name: 'a'),
      const ImportRow(line: 9, name: 'b')
    ];
    final r = ImportResult.fromJson({
      'batch': null,
      'ready': 0,
      'errors': [
        {'row': 2, 'message': '沒有日期'}
      ],
      'skipped': [
        {'row': 1, 'reason': '這個時間已經有這位客人的訂位'}
      ],
    }, rows);
    expect(r.errors.single.line, 9);
    expect(r.errors.single.text, '沒有日期');
    expect(r.skipped.single.line, 4);
    expect(
        ImportResult.fromJson(
                {'batch': 'b1', 'inserted': 2, 'repeat': true}, rows)
            .repeat,
        isTrue);
  });

  group('Excel', () {
    test('範本讀回來：表頭、兩列範例都看得懂', () {
      final t = readImportTable(
          readXlsxCells(buildImportTemplate(today: DateTime(2026, 11, 27))).cells);
      expect(t.problem, isNull);
      expect(t.rows.length, 2);
      expect([t.rows[0].date, t.rows[0].time, t.rows[0].party, t.rows[0].lang],
          ['2026-12-04', '19:00', '4', 'zh']);
      expect([t.rows[1].date, t.rows[1].phone, t.rows[1].lang],
          ['2026-12-11', '', 'en']);
    });
    test('匯出全部訂位：表頭、排序、來源、狀態中文', () {
      Reservation r(String id, DateTime d, String t,
              {String source = 'app',
              String status = 'confirmed',
              String? batch}) =>
          Reservation(
              id: id,
              date: d,
              time: t,
              party: 2,
              name: id,
              phone: '',
              status: status,
              source: source,
              createdAt: DateTime(2026, 11, 1, 10),
              importBatchId: batch);
      final bytes = buildReservationsXlsx('隱城', [
        r('b', DateTime(2026, 12, 2), '19:00', source: 'web'),
        r('a', DateTime(2026, 12, 1), '20:00', status: 'cancelled', batch: 'x'),
        r('c', DateTime(2026, 12, 1), '18:00', status: 'no_show'),
      ]);
      final cells = readXlsxCells(bytes).cells;
      expect(cells.first.take(3), ['日期', '時間', '人數']);
      expect([for (final row in cells.skip(1)) row[3]], ['c', 'a', 'b']);
      expect(cells[1][7], '未到');
      expect(cells[2].sublist(7, 9), ['已取消', '匯入']);
      expect(cells[3][8], '網路');
      expect(cells[1][8], '電話');
    });
    test('公式格：有存計算結果就用結果；沒有就說是哪一格，不默默變空白', () {
      Uint8List build() {
        final e = Excel.createExcel();
        final sh = e['Sheet1'];
        for (final (i, h) in ['日期', '時間', '人數', '姓名'].indexed) {
          sh.updateCell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0), TextCellValue(h));
        }
        sh.updateCell(CellIndex.indexByString('A2'), const FormulaCellValue('TODAY()+7'));
        sh.updateCell(CellIndex.indexByString('B2'), const FormulaCellValue('"19:"&"30"'));
        sh.updateCell(CellIndex.indexByString('C2'), const FormulaCellValue('1+1'));
        sh.updateCell(CellIndex.indexByString('D2'), TextCellValue('王'));
        return Uint8List.fromList(e.save()!);
      }

      // 套件存檔時公式格沒有結果（<v></v>）＝像沒算過的檔案
      final noCache = readXlsxCells(build());
      expect(noCache.problem, '第 2 列 A 欄是公式，請先複製後「貼上值」再匯入');

      // 模擬 Excel 存過的檔案：每一格都有存結果（日期是序號、文字公式 t="str"）
      final zip = ZipDecoder().decodeBytes(build());
      final out = Archive();
      for (final f in zip.files) {
        var bytes = f.content as List<int>;
        if (f.name.startsWith('xl/worksheets/')) {
          var x = utf8.decode(bytes);
          x = x
              .replaceAll('<f>TODAY()+7</f><v></v>', '<f>TODAY()+7</f><v>46010</v>')
              .replaceAllMapped(RegExp(r'<c r="B2"([^>]*)><f>([^<]*)</f><v></v>'), (m) => '<c r="B2"${m[1]} t="str"><f>${m[2]}</f><v>19:30</v>')
              .replaceAll('<f>1+1</f><v></v>', '<f>1+1</f><v>2</v>');
          bytes = utf8.encode(x);
        }
        out.addFile(ArchiveFile(f.name, bytes.length, bytes));
      }
      final cached = readXlsxCells(Uint8List.fromList(ZipEncoder().encode(out)!));
      expect(cached.problem, isNull);
      final t = readImportTable(cached.cells);
      expect([t.rows.single.date, t.rows.single.time, t.rows.single.party, t.rows.single.name], ['2025-12-19', '19:30', '2', '王']);
    });
    test('欄位代號', () {
      expect([columnLetter(0), columnLetter(25), columnLetter(26), columnLetter(27)], ['A', 'Z', 'AA', 'AB']);
    });
    test('匯出檔名', () {
      expect(reservationsXlsxName('隱城', now: DateTime(2026, 11, 27)),
          '隱城_全部訂位_20261127.xlsx');
    });
  });
}
