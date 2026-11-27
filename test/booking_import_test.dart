import 'dart:convert';

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

  group('CSV', () {
    test('BOM、引號、逗號、換行、雙引號', () {
      final rows =
          parseCsv('﻿日期,姓名,備註\r\n2026-12-24,"王, 先生","說""要""靠窗\n兩行"\r\n');
      expect(rows.length, 2);
      expect(rows[1], ['2026-12-24', '王, 先生', '說"要"靠窗\n兩行']);
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
          readXlsxCells(buildImportTemplate(today: DateTime(2026, 11, 27))));
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
      final cells = readXlsxCells(bytes);
      expect(cells.first.take(3), ['日期', '時間', '人數']);
      expect([for (final row in cells.skip(1)) row[3]], ['c', 'a', 'b']);
      expect(cells[1][7], '未到');
      expect(cells[2].sublist(7, 9), ['已取消', '匯入']);
      expect(cells[3][8], '網路');
      expect(cells[1][8], '電話');
    });
    test('匯出檔名', () {
      expect(reservationsXlsxName('隱城', now: DateTime(2026, 11, 27)),
          '隱城_全部訂位_20261127.xlsx');
    });
  });
}
