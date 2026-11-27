import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../data/booking_import.dart';
import '../data/reservation_models.dart';

/// 訂位搬家（ops 0148）：範本、讀 Excel、匯出全部訂位。
const reservationXlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

String _two(int n) => n.toString().padLeft(2, '0');

/// 匯入範本：第一頁「訂位」第一列是表頭、下面兩列範例（日期是下週、下下週，刪掉換成自己的）；第二頁「說明」
Uint8List buildImportTemplate({DateTime? today}) {
  final t = today ?? DateTime.now();
  final d1 = DateFormat('yyyy-MM-dd').format(t.add(const Duration(days: 7)));
  final d2 = DateFormat('yyyy-MM-dd').format(t.add(const Duration(days: 14)));
  final excel = Excel.createExcel();
  excel.rename('Sheet1', '訂位');
  final sh = excel['訂位'];
  final head = CellStyle(
      bold: true, backgroundColorHex: ExcelColor.fromHexString('#E8E2D6'));
  const widths = [14.0, 9.0, 7.0, 16.0, 16.0, 26.0, 28.0, 8.0];
  for (var c = 0; c < importColumns.length; c++) {
    sh.setColumnWidth(c, widths[c]);
    sh.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(importColumns[c]),
        cellStyle: head);
  }
  final samples = [
    [
      d1,
      '19:00',
      '4',
      '王 先生',
      '0912-345-678',
      'wang@example.com',
      '靠窗、慶生',
      '中文'
    ],
    [d2, '20:30', '2', 'Emily Chen', '', 'emily@example.com', '', '英文'],
  ];
  for (var r = 0; r < samples.length; r++) {
    for (var c = 0; c < samples[r].length; c++) {
      sh.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
          TextCellValue(samples[r][c]));
    }
  }
  final help = excel['說明'];
  help.setColumnWidth(0, 90);
  const lines = [
    '怎麼填（第一頁「訂位」，一列一組客人；兩列範例填完請刪掉）',
    '日期：2026-12-24 或 2026/12/24。只能匯入今天以後、一年內的訂位（過去的不用搬）。',
    '時間：19:30 或 7:30 PM。',
    '人數：1～9999。',
    '姓名：必填，最多 40 個字（例：王 先生、林小姐）。',
    '電話、Email：可以空白；有填要是正確格式。',
    '備註：最多 200 個字。',
    '語言：中文／英文／日文，空白＝中文。',
    '',
    '匯入的訂位跟電話訂位一樣：不算每天線上名額、不寄確認信和提醒信。',
    '同一天同時間、同一位客人已經有訂位的會自動略過，重複匯入不會變兩筆。',
    '匯入後在 App「匯入、匯出訂位」可以整批復原。',
  ];
  for (var i = 0; i < lines.length; i++) {
    help.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i),
        TextCellValue(lines[i]),
        cellStyle: i == 0 ? CellStyle(bold: true) : null);
  }
  excel.setDefaultSheet('訂位');
  return Uint8List.fromList(excel.save()!);
}

/// 一格的文字：日期格 → 2026-12-24、時間格 → 19:30、數字去掉 .0
String cellText(CellValue? v) => switch (v) {
      null => '',
      TextCellValue() => v.value.toString().trim(),
      IntCellValue() => '${v.value}',
      DoubleCellValue() => v.value == v.value.roundToDouble()
          ? '${v.value.round()}'
          : '${v.value}',
      DateCellValue() => '${v.year}-${_two(v.month)}-${_two(v.day)}',
      DateTimeCellValue() => (v.hour == 0 && v.minute == 0 && v.second == 0)
          ? '${v.year}-${_two(v.month)}-${_two(v.day)}'
          : (v.year <= 1900
              ? '${_two(v.hour)}:${_two(v.minute)}'
              : '${v.year}-${_two(v.month)}-${_two(v.day)} ${_two(v.hour)}:${_two(v.minute)}'),
      TimeCellValue() => '${_two(v.hour)}:${_two(v.minute)}',
      BoolCellValue() => '${v.value}',
      FormulaCellValue() => '',
    };

/// 讀 .xlsx：有「日期」那一欄的第一個工作表（範本是「訂位」）；沒有就讀第一個
List<List<String>> readXlsxCells(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  List<List<String>> cellsOf(Sheet s) => [
        for (final row in s.rows) [for (final c in row) cellText(c?.value)]
      ];
  List<List<String>>? first;
  for (final name in excel.tables.keys) {
    final cells = cellsOf(excel.tables[name]!);
    first ??= cells;
    if (readImportTable(cells).problem == null) return cells;
  }
  return first ?? const [];
}

String _status(String s) => switch (s) {
      'confirmed' => '已確認',
      'arrived' => '已到店',
      'no_show' => '未到',
      'cancelled' => '已取消',
      _ => s,
    };

String _source(Reservation r) => r.importBatchId != null
    ? '匯入'
    : r.walkIn
        ? '現場'
        : r.source == 'web'
            ? '網路'
            : '電話';

String _lang(String l) => switch (l) { 'en' => '英文', 'ja' => '日文', _ => '中文' };

/// 匯出全部訂位（日期、時間排序；建立時間台北時間）
Uint8List buildReservationsXlsx(String storeName, List<Reservation> rows) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', '訂位');
  final sh = excel['訂位'];
  const cols = [
    '日期',
    '時間',
    '人數',
    '姓名',
    '電話',
    'Email',
    '備註',
    '狀態',
    '來源',
    '語言',
    '建立時間'
  ];
  const widths = [12.0, 8.0, 6.0, 16.0, 16.0, 26.0, 30.0, 8.0, 8.0, 6.0, 18.0];
  final head = CellStyle(
      bold: true, backgroundColorHex: ExcelColor.fromHexString('#E8E2D6'));
  for (var c = 0; c < cols.length; c++) {
    sh.setColumnWidth(c, widths[c]);
    sh.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(cols[c]),
        cellStyle: head);
  }
  final sorted = [...rows]..sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.time.compareTo(b.time);
    });
  final day = DateFormat('yyyy-MM-dd'), at = DateFormat('yyyy-MM-dd HH:mm');
  for (var i = 0; i < sorted.length; i++) {
    final r = sorted[i];
    final values = <CellValue>[
      TextCellValue(day.format(r.date)),
      TextCellValue(r.time),
      IntCellValue(r.party),
      TextCellValue(r.name),
      TextCellValue(r.phone),
      TextCellValue(r.email ?? ''),
      TextCellValue(r.note ?? ''),
      TextCellValue(_status(r.status)),
      TextCellValue(_source(r)),
      TextCellValue(_lang(r.lang)),
      TextCellValue(at.format(r.createdAt)),
    ];
    for (var c = 0; c < values.length; c++) {
      sh.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: i + 1),
          values[c]);
    }
  }
  return Uint8List.fromList(excel.save()!);
}

String reservationsXlsxName(String store, {DateTime? now}) =>
    '${store}_全部訂位_${DateFormat('yyyyMMdd').format(now ?? DateTime.now())}.xlsx';
