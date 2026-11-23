import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../data/pl_statement.dart';

/// 損益表（ops 0142 第二版，老闆 2026-11-23）：摘要｜金額｜占營收；
/// 營業收入／進貨／雜項／租金／人事五大項＋本期淨利；% 只在各大項合計和本期淨利。
Uint8List buildAccountPlXlsx(AccountStatement p) {
  final excel = Excel.createExcel();
  final sheetName = p.sheetName;
  excel.rename('Sheet1', sheetName);
  final sh = excel[sheetName];
  sh.setColumnWidth(0, 30);
  sh.setColumnWidth(1, 14);
  sh.setColumnWidth(2, 10);

  const money = NumFormat.standard_3; // #,##0
  const percent = NumFormat.standard_10; // 0.00%
  final gray = ExcelColor.fromHexString('#D9D9D9');
  final yellow = ExcelColor.fromHexString('#FFFF00');
  final muted = ExcelColor.fromHexString('#595959');
  final thin = Border(borderStyle: BorderStyle.Thin);
  final dbl = Border(borderStyle: BorderStyle.Double);
  var r = 0;

  CellIndex at(int c) => CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);
  void put(int c, CellValue? v, CellStyle style) {
    sh.updateCell(at(c), v, cellStyle: style);
    sh.setRowHeight(r, r == 0 ? 34 : 20); // 每一列一樣高
  }

  put(0, TextCellValue(p.title), CellStyle(fontSize: 20));
  sh.merge(at(0), CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r));
  r++;
  for (final (c, t) in [(0, '摘要'), (1, '金額'), (2, '占營收')]) {
    put(c, TextCellValue(t), CellStyle(backgroundColorHex: gray, horizontalAlign: HorizontalAlign.Center));
  }
  r++;

  void section(String text) {
    put(0, TextCellValue(text), CellStyle(bold: true, horizontalAlign: HorizontalAlign.Center));
    sh.merge(at(0), CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r));
    r++;
  }

  void line(String label, double amount, {bool detail = false}) {
    final color = detail ? muted : ExcelColor.black;
    put(0, TextCellValue(detail ? '　$label' : label), CellStyle(fontColorHex: color));
    put(1, DoubleCellValue(amount.roundToDouble()),
        CellStyle(numberFormat: money, horizontalAlign: HorizontalAlign.Right, fontColorHex: color));
    r++;
  }

  void total(String label, double amount) {
    put(0, TextCellValue(label), CellStyle(bold: true, topBorder: thin, bottomBorder: dbl));
    put(1, DoubleCellValue(amount.roundToDouble()),
        CellStyle(bold: true, fontSize: 13, numberFormat: money, horizontalAlign: HorizontalAlign.Right, topBorder: thin, bottomBorder: dbl));
    put(2, DoubleCellValue(p.share(amount)), CellStyle(bold: true, numberFormat: percent));
    r++;
  }

  section('營業收入');
  for (final l in p.revenue) {
    line(l.label, l.amount);
  }
  total('營業收入合計', p.revenueTotal);

  section('進貨');
  for (final l in p.purchase) {
    line(l.label, l.amount);
  }
  total('進貨合計', p.purchaseTotal);

  section('雜項');
  for (final a in p.misc) {
    line(a.name, a.amount);
    for (final d in a.details) {
      line(d.label, d.amount, detail: true);
    }
  }
  total('雜項合計', p.miscTotal);

  section('租金');
  for (final l in p.rent) {
    line(l.label, l.amount);
  }
  total('租金合計', p.rentTotal);

  section('人事');
  for (final l in p.payroll) {
    line(l.label, l.amount);
  }
  total('人事合計', p.payrollTotal);

  put(0, TextCellValue('本期淨利'),
      CellStyle(bold: true, fontSize: 14, backgroundColorHex: yellow, horizontalAlign: HorizontalAlign.Center, bottomBorder: dbl));
  put(1, DoubleCellValue(p.profit.roundToDouble()),
      CellStyle(bold: true, fontSize: 14, backgroundColorHex: yellow, numberFormat: money, horizontalAlign: HorizontalAlign.Right, bottomBorder: dbl));
  put(2, DoubleCellValue(p.share(p.profit)), CellStyle(bold: true, numberFormat: percent));
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
