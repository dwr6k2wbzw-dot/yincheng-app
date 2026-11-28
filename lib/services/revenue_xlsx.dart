import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/revenue_import.dart';

/// 營收搬家（ops 0168）：匯入範本、匯出每日營收＋月份彙總。
/// 讀 .xlsx 共用訂位搬家的 readXlsxCells（reservation_xlsx.dart）。

CellStyle get _head => CellStyle(
  bold: true,
  backgroundColorHex: ExcelColor.fromHexString('#E8E2D6'),
);

void _row(Sheet sh, int r, List<CellValue> values, {CellStyle? style}) {
  for (var c = 0; c < values.length; c++) {
    sh.updateCell(
      CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
      values[c],
      cellStyle: style,
    );
  }
}

/// 匯入範本：第一頁「每日營收」第一列是表頭、下面兩列範例（刪掉換成自己的）；第二頁「說明」。
/// [multi]：這家店的營收有分咖啡、拉麵
Uint8List buildRevenueTemplate({required bool multi, DateTime? today}) {
  final t = today ?? DateTime.now();
  final fmt = DateFormat('yyyy-MM-dd');
  final d1 = fmt.format(DateTime(t.year, t.month - 1, 1));
  final d2 = fmt.format(DateTime(t.year, t.month - 1, 2));
  final cols = revenueImportColumns(multi: multi);
  final excel = Excel.createExcel();
  excel.rename('Sheet1', '每日營收');
  final sh = excel['每日營收'];
  for (var c = 0; c < cols.length; c++) {
    sh.setColumnWidth(c, cols[c] == '日期' ? 13 : (cols[c] == '備註' ? 24 : 10));
  }
  _row(sh, 0, [for (final c in cols) TextCellValue(c)], style: _head);
  // 範例：酒水＋餐食（＋咖啡＋拉麵）＝現金＋刷卡＋AE＋訂金
  final samples = multi
      ? [
          [d1, 32, 9800, 14200, 0, 0, 15000, 5500, 0, 2500, 1000, ''],
          [d2, 18, 6400, 7600, 0, 2000, 9000, 3800, 0, 1700, 1500, '颱風提早收'],
        ]
      : [
          [d1, 32, 9800, 14200, 0, 0, 17200, 6800, 0, ''],
          [d2, 18, 6400, 7600, 0, 2000, 11600, 4400, 0, '颱風提早收'],
        ];
  for (var r = 0; r < samples.length; r++) {
    _row(sh, r + 1, [
      for (final v in samples[r])
        v is int ? IntCellValue(v) : TextCellValue('$v'),
    ]);
  }
  final help = excel['說明'];
  help.setColumnWidth(0, 92);
  final lines = [
    '怎麼填（第一頁「每日營收」，一天一列；兩列範例填完請刪掉）',
    '日期：2025-10-24 或 2025/10/24。只能匯入今天以前的日子；一次最多 $revenueImportMax 天、頭尾最多 2 年，再多請分成幾個檔案。',
    '來客數：整數，可以空白。',
    '現金、刷卡、AE、訂金：收到的錢（收款合計＝這四欄加起來）。空白＝0；可以寫 12,345 或 NT\$12,345。',
    multi
        ? '酒水、餐食、專案、咖啡、拉麵：營業收入分類（成本率用）。加起來跟收款合計對不上只會提醒，照樣匯入。'
        : '酒水、餐食、專案：營業收入分類（成本率用）。加起來跟收款合計對不上只會提醒，照樣匯入。',
    '備註：最多 200 個字。',
    '',
    '已經有營收的日子（App 登記過、之前匯入過）會自動略過、不會蓋掉；全部是 0 的日子（公休）也會略過。',
    '有任何一列看不懂，整個檔案都不會匯入，改好再選一次就好。',
    '匯入後在 App「匯入、匯出營收」可以整批復原（匯入之後改過的那幾天會留著）。',
  ];
  for (var i = 0; i < lines.length; i++) {
    help.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i),
      TextCellValue(lines[i]),
      cellStyle: i == 0 ? CellStyle(bold: true) : null,
    );
  }
  excel.setDefaultSheet('每日營收');
  return Uint8List.fromList(excel.save()!);
}

CellValue _money(double v) =>
    v == v.roundToDouble() ? IntCellValue(v.round()) : DoubleCellValue(v);

String _source(RevenueEntry e) => e.source == 'import'
    ? '日報表'
    : e.fileImportId != null
    ? '搬家匯入'
    : 'App 登記';

/// 月份彙總的一列
class RevenueMonthSum {
  final DateTime month;
  int days = 0, guests = 0;
  double cash = 0,
      card = 0,
      amex = 0,
      deposit = 0,
      drinks = 0,
      food = 0,
      project = 0,
      coffee = 0,
      ramen = 0;
  RevenueMonthSum(this.month);
  double get received => cash + card + amex + deposit;
}

/// 照月份加總（舊到新）；收款合計和營業收入分類都是 0、來客也是 0 的日子不算營業天數
List<RevenueMonthSum> revenueByMonth(List<RevenueEntry> rows) {
  final map = <DateTime, RevenueMonthSum>{};
  for (final e in rows) {
    final m = DateTime(e.bizDate.year, e.bizDate.month);
    final s = map[m] ??= RevenueMonthSum(m);
    if (e.received != 0 || e.detailTotal != 0 || e.guests != 0) s.days++;
    s
      ..guests += e.guests
      ..cash += e.cash
      ..card += e.creditCard
      ..amex += e.amex
      ..deposit += e.deposit
      ..drinks += e.drinks
      ..food += e.food
      ..project += e.project
      ..coffee += e.coffee
      ..ramen += e.ramen;
  }
  return map.values.toList()..sort((a, b) => a.month.compareTo(b.month));
}

/// 匯出：第一頁「每日營收」（舊到新，含來源）、第二頁「月份彙總」
Uint8List buildRevenueXlsx(List<RevenueEntry> rows, {required bool multi}) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', '每日營收');
  final sh = excel['每日營收'];
  final cols = [
    '日期',
    '星期',
    '來客數',
    '現金',
    '刷卡',
    'AE',
    '訂金',
    '收款合計',
    '酒水',
    '餐食',
    '專案',
    if (multi) ...['咖啡', '拉麵'],
    '備註',
    '來源',
  ];
  for (var c = 0; c < cols.length; c++) {
    sh.setColumnWidth(c, switch (cols[c]) {
      '日期' => 12,
      '星期' => 6,
      '備註' => 26,
      _ => 10,
    });
  }
  _row(sh, 0, [for (final c in cols) TextCellValue(c)], style: _head);
  final sorted = [...rows]..sort((a, b) => a.bizDate.compareTo(b.bizDate));
  final day = DateFormat('yyyy-MM-dd');
  const wd = ['一', '二', '三', '四', '五', '六', '日'];
  for (var i = 0; i < sorted.length; i++) {
    final e = sorted[i];
    _row(sh, i + 1, [
      TextCellValue(day.format(e.bizDate)),
      TextCellValue(wd[e.bizDate.weekday - 1]),
      IntCellValue(e.guests),
      _money(e.cash),
      _money(e.creditCard),
      _money(e.amex),
      _money(e.deposit),
      _money(e.received),
      _money(e.drinks),
      _money(e.food),
      _money(e.project),
      if (multi) ...[_money(e.coffee), _money(e.ramen)],
      TextCellValue(e.note ?? ''),
      TextCellValue(_source(e)),
    ]);
  }

  final ms = excel['月份彙總'];
  final mcols = [
    '月份',
    '營業天數',
    '來客數',
    '收款合計',
    '現金',
    '刷卡',
    'AE',
    '訂金',
    '酒水',
    '餐食',
    '專案',
    if (multi) ...['咖啡', '拉麵'],
    '平均每天',
  ];
  for (var c = 0; c < mcols.length; c++) {
    ms.setColumnWidth(c, c == 0 ? 10 : 11);
  }
  _row(ms, 0, [for (final c in mcols) TextCellValue(c)], style: _head);
  final months = revenueByMonth(rows);
  for (var i = 0; i < months.length; i++) {
    final m = months[i];
    _row(ms, i + 1, [
      TextCellValue(DateFormat('yyyy-MM').format(m.month)),
      IntCellValue(m.days),
      IntCellValue(m.guests),
      _money(m.received),
      _money(m.cash),
      _money(m.card),
      _money(m.amex),
      _money(m.deposit),
      _money(m.drinks),
      _money(m.food),
      _money(m.project),
      if (multi) ...[_money(m.coffee), _money(m.ramen)],
      _money(m.days == 0 ? 0 : (m.received / m.days).roundToDouble()),
    ]);
  }
  excel.setDefaultSheet('每日營收');
  return Uint8List.fromList(excel.save()!);
}

String revenueXlsxName(String store, {DateTime? now}) =>
    '${store}_每日營收_${DateFormat('yyyyMMdd').format(now ?? DateTime.now())}.xlsx';
