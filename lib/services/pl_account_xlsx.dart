import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../data/pl_statement.dart';

/// 會計科目格式的損益表（ops 0142，老闆 2026-11-23 附圖）：
/// 摘要｜金額｜占營收｜備註；營業收入／進貨成本／營業費用／本期淨利，順序固定。
Uint8List buildAccountPlXlsx(AccountStatement p) {
  final excel = Excel.createExcel();
  final sheetName = p.sheetName;
  excel.rename('Sheet1', sheetName);
  final sh = excel[sheetName];
  sh.setColumnWidth(0, 26);
  sh.setColumnWidth(1, 14);
  sh.setColumnWidth(2, 9);
  sh.setColumnWidth(3, 30);

  const money = NumFormat.standard_3; // #,##0
  const percent = NumFormat.standard_10; // 0.00%
  final gray = ExcelColor.fromHexString('#D9D9D9');
  final yellow = ExcelColor.fromHexString('#FFFF00');
  final thin = Border(borderStyle: BorderStyle.Thin);
  final dbl = Border(borderStyle: BorderStyle.Double);
  var r = 0;

  CellIndex at(int c) => CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);
  void put(int c, CellValue? v, CellStyle style) {
    sh.updateCell(at(c), v, cellStyle: style);
    sh.setRowHeight(r, r == 0 ? 34 : 20); // 每一列一樣高（照老闆的表）
  }

  // 抬頭
  put(0, TextCellValue(p.title), CellStyle(fontSize: 20));
  sh.merge(at(0), CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r));
  r++;
  // 表頭
  put(0, TextCellValue('摘要'), CellStyle(backgroundColorHex: gray, horizontalAlign: HorizontalAlign.Center));
  put(1, TextCellValue('金額'), CellStyle(backgroundColorHex: gray, horizontalAlign: HorizontalAlign.Center));
  put(2, null, CellStyle(backgroundColorHex: gray));
  put(3, TextCellValue('備註'), CellStyle(horizontalAlign: HorizontalAlign.Center));
  r++;

  void section(String text) {
    put(0, TextCellValue(text), CellStyle(bold: true, horizontalAlign: HorizontalAlign.Center));
    sh.merge(at(0), CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r));
    r++;
  }

  void line(String label, double amount, {bool share = false, String note = '', bool blankZero = false}) {
    put(0, TextCellValue(label), CellStyle());
    put(1, blankZero && amount.round() == 0 ? null : DoubleCellValue(amount.roundToDouble()),
        CellStyle(numberFormat: money, horizontalAlign: HorizontalAlign.Right));
    if (share) put(2, DoubleCellValue(p.share(amount)), CellStyle(numberFormat: percent));
    if (note.isNotEmpty) put(3, TextCellValue(note), CellStyle());
    r++;
  }

  void detail(String label, double amount) {
    put(0, TextCellValue('　$label'), CellStyle(fontColorHex: ExcelColor.fromHexString('#595959')));
    put(1, DoubleCellValue(amount.roundToDouble()),
        CellStyle(numberFormat: money, horizontalAlign: HorizontalAlign.Right, fontColorHex: ExcelColor.fromHexString('#595959')));
    r++;
  }

  void total(String label, double amount, {bool share = false}) {
    put(0, TextCellValue(label), CellStyle(bold: true, topBorder: thin, bottomBorder: dbl));
    put(1, DoubleCellValue(amount.roundToDouble()),
        CellStyle(bold: true, fontSize: 13, numberFormat: money, horizontalAlign: HorizontalAlign.Right, topBorder: thin, bottomBorder: dbl));
    if (share) put(2, DoubleCellValue(p.share(amount)), CellStyle(numberFormat: percent));
    r++;
  }

  section('營業收入');
  for (final l in p.revenue) {
    line(l.label, l.amount);
  }
  total('營業收入合計', p.revenueTotal);

  section('進貨成本');
  for (final l in p.purchase) {
    line(l.label, l.amount);
  }
  total('進貨成本合計', p.purchaseTotal, share: true);

  section('營業費用');
  for (final a in p.expenses) {
    line(a.name, a.amount, share: true, note: a.note, blankZero: true);
    for (final d in a.details) {
      detail(d.label, d.amount);
    }
  }
  total('營業費用類合計', p.expenseTotal);

  // 本期淨利（黃底）
  put(0, TextCellValue('本期淨利'),
      CellStyle(bold: true, fontSize: 14, backgroundColorHex: yellow, horizontalAlign: HorizontalAlign.Center, bottomBorder: dbl));
  put(1, DoubleCellValue(p.profit.roundToDouble()),
      CellStyle(bold: true, fontSize: 14, backgroundColorHex: yellow, numberFormat: money, horizontalAlign: HorizontalAlign.Right, bottomBorder: dbl));
  r++;

  if (p.warnings.isNotEmpty) {
    r++;
    put(0, TextCellValue('注意：${p.warnings.join('；')}'), CellStyle(fontColorHex: ExcelColor.fromHexString('#C00000')));
  }

  excel.setDefaultSheet(sheetName);
  final bytes = excel.encode();
  if (bytes == null) throw Exception('損益表產生失敗');
  return Uint8List.fromList(bytes);
}

