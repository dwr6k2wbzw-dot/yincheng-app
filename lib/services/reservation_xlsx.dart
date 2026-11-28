import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

/// 一格的文字：日期格 → 2026-12-24、時間格 → 19:30、數字去掉 .0。
/// 公式格不在這裡處理（讀檔時另外查 Excel 存下來的計算結果，見 [readXlsxCells]）
String cellText(CellValue? v) => switch (v) {
      null => '',
      TextCellValue() => v.value.toString().trim(),
      IntCellValue() => '${v.value}',
      DoubleCellValue() => _num(v.value),
      DateCellValue() => '${v.year}-${_two(v.month)}-${_two(v.day)}',
      DateTimeCellValue() => (v.hour == 0 && v.minute == 0 && v.second == 0)
          ? '${v.year}-${_two(v.month)}-${_two(v.day)}'
          : (v.year <= 1900 ? '${_two(v.hour)}:${_two(v.minute)}' : '${v.year}-${_two(v.month)}-${_two(v.day)} ${_two(v.hour)}:${_two(v.minute)}'),
      TimeCellValue() => '${_two(v.hour)}:${_two(v.minute)}',
      BoolCellValue() => '${v.value}',
      FormulaCellValue() => '',
    };

String _num(double d) => d == d.roundToDouble() ? '${d.round()}' : '$d';

/// 欄位代號：0 → A、25 → Z、26 → AA
String columnLetter(int c) {
  var n = c + 1, out = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    out = String.fromCharCode(65 + r) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

/// 讀 .xlsx 的結果：每一格的文字；有看不懂的公式格時 problem 說是哪一格
class XlsxCells {
  final List<List<String>> cells;
  final String? problem;
  const XlsxCells(this.cells, [this.problem]);
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// 公式格在檔案裡存的計算結果（Excel、Google 試算表存檔時都會存）：工作表名稱 → {A1 → 結果}。
/// 試算表套件讀公式格時只給公式、丟掉結果，所以直接看檔案內容。讀不到就回空的（那些格會被當成問題）。
Map<String, Map<String, String>> _formulaCache(Uint8List bytes) {
  final out = <String, Map<String, String>>{};
  try {
    final zip = ZipDecoder().decodeBytes(bytes);
    String? text(String name) {
      final f = zip.findFile(name);
      return f == null ? null : utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    final wb = text('xl/workbook.xml'), rels = text('xl/_rels/workbook.xml.rels');
    if (wb == null || rels == null) return out;
    final target = <String, String>{
      for (final m in RegExp(r'<Relationship\b[^>]*>').allMatches(rels))
        if (RegExp(r'Id="([^"]+)"').firstMatch(m[0]!) case final id?)
          if (RegExp(r'Target="([^"]+)"').firstMatch(m[0]!) case final t?) id[1]!: t[1]!,
    };
    for (final m in RegExp(r'<sheet\b[^>]*>').allMatches(wb)) {
      final name = RegExp(r'name="([^"]*)"').firstMatch(m[0]!)?[1];
      final rid = RegExp(r'r:id="([^"]+)"').firstMatch(m[0]!)?[1];
      var path = target[rid];
      if (name == null || path == null) continue;
      path = path.startsWith('/') ? path.substring(1) : 'xl/$path';
      final xml = text(path);
      if (xml == null) continue;
      final cache = <String, String>{};
      for (final c in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true).allMatches(xml)) {
        final body = c[2] ?? '';
        if (!body.contains('<f')) continue;
        final ref = RegExp(r'r="([A-Z]+\d+)"').firstMatch(c[1]!)?[1];
        final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?[1];
        final type = RegExp(r't="([a-z]+)"').firstMatch(c[1]!)?[1];
        // 沒有結果、結果是錯誤（#REF! 之類）、或數字格存了空的結果（沒算過）＝沒有結果
        if (ref == null || v == null || type == 'e' || (v.isEmpty && type != 'str' && type != 'inlineStr')) continue;
        final raw = _unescape(v);
        cache[ref] = switch (type) {
          'str' || 'inlineStr' => raw.trim(),
          'b' => raw == '1' ? 'true' : 'false',
          _ => double.tryParse(raw) == null ? raw.trim() : _num(double.parse(raw)),
        };
      }
      out[_unescape(name)] = cache;
    }
  } catch (_) {
    // 檔案結構跟預期不同：當作沒有結果
  }
  return out;
}

/// 讀 .xlsx：有「日期」那一欄的第一個工作表（範本是「訂位」）；沒有就讀第一個。
/// accept：哪個工作表算讀得懂（員工名冊用自己的判斷；預設是訂位）。
/// 公式格用檔案裡存的計算結果；沒有結果的公式格不默默當成空白，回 problem 請人先「貼上值」。
XlsxCells readXlsxCells(Uint8List bytes, {bool Function(List<List<String>> cells)? accept}) {
  final excel = Excel.decodeBytes(bytes);
  Map<String, Map<String, String>>? cache;
  XlsxCells read(String name) {
    final rows = <List<String>>[];
    String? problem;
    final sheetRows = excel.tables[name]!.rows;
    for (var r = 0; r < sheetRows.length; r++) {
      final out = <String>[];
      for (var c = 0; c < sheetRows[r].length; c++) {
        final v = sheetRows[r][c]?.value;
        if (v is FormulaCellValue) {
          cache ??= _formulaCache(bytes);
          final hit = cache![name]?['${columnLetter(c)}${r + 1}'];
          if (hit == null) problem ??= '第 ${r + 1} 列 ${columnLetter(c)} 欄是公式，請先複製後「貼上值」再匯入';
          out.add(hit ?? '');
        } else {
          out.add(cellText(v));
        }
      }
      rows.add(out);
    }
    return XlsxCells(rows, problem);
  }

  XlsxCells? first;
  for (final name in excel.tables.keys) {
    final x = read(name);
    first ??= x;
    if (accept != null ? accept(x.cells) : readImportTable(x.cells).problem == null) return x;
  }
  return first ?? const XlsxCells([]);
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
