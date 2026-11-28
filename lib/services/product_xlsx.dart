import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/product_import.dart';
import '../data/purchase_items_math.dart';

/// 盤點品項搬家（ops 0167）：範本、匯出目前品項＋最後盤點量＋進貨報價。
const productXlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

CellStyle get _head => CellStyle(
  bold: true,
  backgroundColorHex: ExcelColor.fromHexString('#E8E2D6'),
);

void _row(Sheet sh, int r, List<CellValue?> values, {CellStyle? style}) {
  for (var c = 0; c < values.length; c++) {
    if (values[c] == null) continue;
    sh.updateCell(
      CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
      values[c],
      cellStyle: style,
    );
  }
}

CellValue _num(double v) =>
    v == v.roundToDouble() ? IntCellValue(v.round()) : DoubleCellValue(v);

String _cycle(String? c) => switch (c) {
  'daily' => '每天',
  'weekly' => '每週',
  _ => '',
};

/// 匯入範本：第一頁「品項」表頭＋三列範例（刪掉換成自己的）；第二頁「說明」。
/// withCost：老闆的範本多一欄成本價（店長、正職不能匯入成本價）
Uint8List buildProductTemplate({bool withCost = false}) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', '品項');
  final sh = excel['品項'];
  final cols = [...productImportColumns, if (withCost) productCostColumn];
  const widths = [24.0, 8.0, 10.0, 9.0, 12.0, 10.0];
  for (var c = 0; c < cols.length; c++) {
    sh.setColumnWidth(c, widths[c]);
  }
  _row(sh, 0, [for (final c in cols) TextCellValue(c)], style: _head);
  final samples = [
    ['琴酒 700ml', '瓶', '酒水', '2', '每天', '780'],
    ['檸檬', '顆', '餐食', '20', '每週', '8'],
    ['杯墊', '包', '雜項', '', '', ''],
  ];
  for (var r = 0; r < samples.length; r++) {
    _row(sh, r + 1, [
      for (var c = 0; c < cols.length; c++) TextCellValue(samples[r][c]),
    ]);
  }
  final help = excel['說明'];
  help.setColumnWidth(0, 90);
  final lines = [
    '怎麼填（第一頁「品項」，一列一個品項；三列範例填完請刪掉）',
    '品名：必填，最多 60 個字。同一家店不能有兩個一樣的品名（大小寫、空白不同也算一樣）。',
    '單位：必填，最多 10 個字（例：瓶、包、顆、公斤）。',
    '分類：必填，最多 20 個字（例：酒水、餐食、雜項，也可以自己取）。',
    '安全量：可以空白；低於這個數量會提醒叫貨。',
    '多久盤一次：每天／每週／空白（空白＝不是重點品項）。',
    if (withCost) '成本價：可以空白；只有老闆能匯入，店長和正職看不到。',
    '',
    '已經有同名品項的那一列會自動略過，重複匯入不會變兩個。',
    '匯入後在 App「匯入、匯出品項」可以整批復原（品項會停用，不會刪掉）。',
  ];
  for (var i = 0; i < lines.length; i++) {
    help.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i),
      TextCellValue(lines[i]),
      cellStyle: i == 0 ? CellStyle(bold: true) : null,
    );
  }
  excel.setDefaultSheet('品項');
  return Uint8List.fromList(excel.save()!);
}

/// 匯出：第一頁「品項」（目前啟用中的品項＋最後盤點量；costs 有給才多一欄成本價），
/// 第二頁「進貨報價」（拿掉的不列）。第一頁的格式就是匯入的格式，可以直接拿去另一家店匯入。
Uint8List buildProductsXlsx({
  required List<Product> products,
  required Map<String, LastCount> lastCounts,
  Map<String, double?>? costs,
  List<ItemQuote> quotes = const [],
}) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', '品項');
  final sh = excel['品項'];
  final withCost = costs != null;
  final cols = [
    ...productImportColumns,
    if (withCost) productCostColumn,
    '最後盤點量',
    '盤點日期',
    '盤點的人',
  ];
  const widths = [24.0, 8.0, 10.0, 9.0, 12.0, 10.0, 11.0, 12.0, 12.0];
  for (var c = 0; c < cols.length; c++) {
    sh.setColumnWidth(c, widths[c]);
  }
  _row(sh, 0, [for (final c in cols) TextCellValue(c)], style: _head);
  final day = DateFormat('yyyy-MM-dd');
  for (var i = 0; i < products.length; i++) {
    final p = products[i];
    final last = lastCounts[p.id];
    final cost = costs?[p.id];
    _row(sh, i + 1, [
      TextCellValue(p.name),
      TextCellValue(p.unit),
      TextCellValue(p.category),
      p.parLevel == null ? null : _num(p.parLevel!),
      TextCellValue(_cycle(p.countCycle)),
      if (withCost) cost == null ? null : _num(cost),
      last == null ? null : _num(last.qty),
      last == null ? null : TextCellValue(day.format(last.date)),
      last?.by == null ? null : TextCellValue(last!.by!),
    ]);
  }

  final q = excel['進貨報價'];
  const qCols = ['類別', '品名', '單位', '單價', '最近進貨日', '廠商', '手動改過'];
  const qWidths = [8.0, 24.0, 8.0, 10.0, 12.0, 16.0, 10.0];
  for (var c = 0; c < qCols.length; c++) {
    q.setColumnWidth(c, qWidths[c]);
  }
  _row(q, 0, [for (final c in qCols) TextCellValue(c)], style: _head);
  final shown = [
    for (final x in quotes)
      if (!x.hidden) x,
  ];
  for (var i = 0; i < shown.length; i++) {
    final x = shown[i];
    _row(q, i + 1, [
      TextCellValue(quoteGroupLabel(x.group)),
      TextCellValue(x.name),
      x.unit == null ? null : TextCellValue(x.unit!),
      _num(x.price),
      x.custom ? null : TextCellValue(day.format(x.date)),
      x.vendor == null ? null : TextCellValue(x.vendor!),
      x.custom ? TextCellValue('手動新增') : (x.edited ? TextCellValue('是') : null),
    ]);
  }
  excel.setDefaultSheet('品項');
  return Uint8List.fromList(excel.save()!);
}

String productsXlsxName(String store, {DateTime? now}) =>
    '$store 品項_${DateFormat('yyyyMMdd').format(now ?? DateTime.now())}.xlsx';
