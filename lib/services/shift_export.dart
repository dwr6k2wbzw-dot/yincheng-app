import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';

/// 匯出班表 Excel（老闆 2026-11-04：小城外班表加「匯出班表」）。
/// 版面照紙本班表：一人一列、一天一欄，最後是統計；底下是每天人力、備註、班別說明。
/// 數字跟 App 班表頁同一算法（ShiftMonth）。存檔用 pl_export.saveFile。
String shiftFileName(String storeName, DateTime month) => '$storeName班表_${DateFormat('yyyy-MM').format(month)}.xlsx';

Uint8List buildShiftXlsx({
  required String storeName,
  required ShiftMonth data,
  required List<String> marks, // 班別說明要列的記號（同畫面圖例）
  required Map<String, double> codeHours,
  required Map<String, String> codeTimes,
}) {
  final month = data.month;
  final days = data.days;
  final excel = Excel.createExcel();
  const sheetName = '班表';
  excel.rename('Sheet1', sheetName);
  final sh = excel[sheetName];

  final people = [
    ...data.people.where((p) => p.active && p.isFull),
    ...data.people.where((p) => p.active && !p.isFull),
  ];
  const statHeads = ['總時數', '上班天數', '月休', '未休補休', '累計特休'];
  final statCol = days + 1; // 第一欄姓名、1～days 是日期

  sh.setColumnWidth(0, 12);
  for (var d = 1; d <= days; d++) {
    sh.setColumnWidth(d, 6.5);
  }
  for (var i = 0; i < statHeads.length; i++) {
    sh.setColumnWidth(statCol + i, 9);
  }

  final line = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('FFBFBFBF'));
  CellStyle cell({String? bg, bool bold = false, bool left = false, int? size, bool wrap = false, String? font}) => CellStyle(
        backgroundColorHex: bg == null ? ExcelColor.none : ExcelColor.fromHexString(bg),
        fontColorHex: font == null ? ExcelColor.black : ExcelColor.fromHexString(font),
        bold: bold,
        fontSize: size ?? 10,
        horizontalAlign: left ? HorizontalAlign.Left : HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: wrap ? TextWrapping.WrapText : null,
        leftBorder: line,
        rightBorder: line,
        topBorder: line,
        bottomBorder: line,
      );
  void put(int c, int r, CellValue v, CellStyle s) =>
      sh.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r), v, cellStyle: s);
  CellValue num(double v) => v == v.roundToDouble() ? IntCellValue(v.round()) : DoubleCellValue(v);
  bool weekend(int d) => DateTime(month.year, month.month, d).weekday >= DateTime.saturday;
  const head = 'FFEFEFEF', weekendHead = 'FFE3E3E3';

  // 標題
  sh.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      TextCellValue('$storeName　${DateFormat('yyyy 年 M 月').format(month)} 班表'),
      cellStyle: CellStyle(bold: true, fontSize: 14));
  sh.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
      TextCellValue('匯出時間：${DateFormat('yyyy/M/d HH:mm').format(DateTime.now())}（App 匯出）'),
      cellStyle: CellStyle(fontSize: 9, fontColorHex: ExcelColor.fromHexString('FF808080')));

  // 表頭：日期＋星期
  const wd = ['一', '二', '三', '四', '五', '六', '日'];
  var r = 3;
  put(0, r, TextCellValue('姓名'), cell(bg: head, bold: true));
  put(0, r + 1, TextCellValue(''), cell(bg: head));
  for (var d = 1; d <= days; d++) {
    final bg = weekend(d) ? weekendHead : head;
    put(d, r, IntCellValue(d), cell(bg: bg, bold: true));
    put(d, r + 1, TextCellValue(wd[DateTime(month.year, month.month, d).weekday - 1]), cell(bg: bg));
  }
  for (var i = 0; i < statHeads.length; i++) {
    put(statCol + i, r, TextCellValue(statHeads[i]), cell(bg: head, bold: true, wrap: true));
    put(statCol + i, r + 1, TextCellValue(''), cell(bg: head));
  }
  r += 2;

  // 每個人一列
  for (final p in people) {
    final st = data.stats[p.id] ?? const ShiftStats();
    put(0, r, TextCellValue(p.isFull ? p.name : '${p.name}（兼）'), cell(bold: true, left: true));
    var tall = false;
    for (var d = 1; d <= days; d++) {
      final m = data.mark(p.id, d);
      final range = ShiftMonth.isRange(m);
      tall |= range;
      put(d, r, TextCellValue(m == null ? '' : (range ? m.replaceFirst('-', '\n') : m)),
          cell(bg: markFill(m), wrap: range, size: range ? 8 : 10));
    }
    final stats = <CellValue>[
      num(data.hours(p.id, codeHours)),
      IntCellValue(data.workDays(p.id)),
      p.isFull ? IntCellValue(data.offDays(p.id)) : TextCellValue('—'),
      p.isFull && st.compUnused != null ? num(st.compUnused!) : TextCellValue('—'),
      p.isFull && st.specialTotal != null ? num(st.specialTotal!) : TextCellValue('—'),
    ];
    for (var i = 0; i < stats.length; i++) {
      put(statCol + i, r, stats[i], cell());
    }
    if (tall) sh.setRowHeight(r, 26);
    r++;
  }

  // 每天人力、備註
  put(0, r, TextCellValue('人力'), cell(bg: head, bold: true, left: true));
  for (var d = 1; d <= days; d++) {
    put(d, r, IntCellValue(data.staffing(d)), cell(bg: head));
  }
  r++;
  if (data.notes.isNotEmpty) {
    put(0, r, TextCellValue('備註'), cell(bold: true, left: true));
    for (var d = 1; d <= days; d++) {
      put(d, r, TextCellValue(data.notes[d] ?? ''), cell(wrap: true, size: 8));
    }
    sh.setRowHeight(r, 40);
    r++;
  }

  // 班別說明
  r++;
  sh.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), TextCellValue('班別說明'),
      cellStyle: CellStyle(bold: true));
  r++;
  for (final m in marks) {
    final t = codeTimes[m];
    final h = codeHours[m];
    put(0, r, TextCellValue(m), cell(bg: markFill(m), bold: true));
    sh.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r),
        TextCellValue([
          if (t != null) t.replaceFirst('-', '～'),
          if (h != null && h > 0) '${NumberFormat('0.#').format(h)} 小時',
          if (t == null && (h == null || h == 0)) _markLabel[m] ?? '',
        ].join('　')),
        cellStyle: CellStyle(fontSize: 10));
    r++;
  }
  sh.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1),
      TextCellValue('總時數＝整個月；月休＝休＋指休（特休另計）；兼職時段照實際時間算（過午夜算隔天）。'),
      cellStyle: CellStyle(fontSize: 9, fontColorHex: ExcelColor.fromHexString('FF808080')));

  excel.setDefaultSheet(sheetName);
  final bytes = excel.encode();
  if (bytes == null) throw Exception('班表產生失敗');
  return Uint8List.fromList(bytes);
}

const _markLabel = {'休': '休假', '指休': '指定休', '特休': '特休', 'V': '上班', 'O': 'O'};

/// 格子底色（白底版，對應 App 班表的顏色）
String? markFill(String? m) => switch (m) {
      null || '' => null,
      '休' => 'FFF6DDB4',
      '指休' => 'FFF7C6BD',
      '特休' => 'FFE8A39B',
      'R' => 'FFF2F2F2',
      'R1' => 'FFD9D9D9',
      'RBK' => 'FFE8C8DE',
      'B' || 'BP' || 'BP+' || 'BH' || 'BH-' => 'FFC9D8F3',
      'BHP' || 'BHP-' => 'FFFBEAB0',
      _ when ShiftMonth.isRange(m) => 'FFEFE6D2',
      _ when RegExp(r'^[A-Z][A-Z0-9]{0,3}[+-]?$').hasMatch(m) && m != 'V' && m != 'O' => 'FFDCE6F6',
      _ => null,
    };
