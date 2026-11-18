import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../data/payroll.dart';

/// 匯出一個月的薪資表（.xlsx；老闆 2026-11-18「薪資要有匯出報表的功能」）。
/// 一個人一列：收入、支出各項照薪資單上的項目展開成欄位（自訂項目也各一欄），最後一列合計。
/// 數字跟 App 薪資單同一套算法（[PayrollSlip]）；看不到的那一列（店長自己）不匯出。
class PayrollExport {
  final String storeName;
  final String? companyName;
  final DateTime month;
  final bool published;
  final List<PayrollRow> rows;
  /// 營業額、人事成本率（店長看不到時是 null，不印）
  final double? revenue;
  final double? costRate;
  const PayrollExport({
    required this.storeName,
    required this.month,
    required this.rows,
    this.companyName,
    this.published = false,
    this.revenue,
    this.costRate,
  });

  String get fileName => '${storeName}_薪資表_${DateFormat('yyyy-MM').format(month)}.xlsx';
  String get title => (companyName == null || companyName!.trim().isEmpty) ? storeName : companyName!.trim();

  /// 會匯出的人：有薪資列、看得到的（不計薪、看不到的不列；還沒有薪資的列出來並標註）
  List<PayrollRow> get people => [for (final r in rows) if (!r.hidden && !r.exempt) r];
  bool get hasHidden => rows.any((r) => r.hidden);

  PayrollSlip slipOf(PayrollRow r) => PayrollSlip.fromPayrollRow(r, month, storeName, companyName: companyName);

  /// 收入、支出的欄位（照出現的順序；第一項的本薪統一叫「本薪」）
  ({List<String> income, List<String> deduction}) columns() {
    final inc = <String>['本薪'], ded = <String>[];
    for (final r in people) {
      if (r.missingRate) continue;
      final s = slipOf(r);
      for (final l in s.incomeLines().skip(1)) {
        if (!inc.contains(l.label)) inc.add(l.label);
      }
      for (final l in s.deductionLines()) {
        if (!ded.contains(l.label)) ded.add(l.label);
      }
    }
    return (income: inc, deduction: ded);
  }

  /// 一個人每一欄的金額（照 [columns] 的欄位名）
  Map<String, double> amountsOf(PayrollRow r) {
    final s = slipOf(r), m = <String, double>{};
    final inc = s.incomeLines();
    for (final (i, l) in inc.indexed) {
      final k = i == 0 ? '本薪' : l.label;
      m[k] = (m[k] ?? 0) + l.amount;
    }
    for (final l in s.deductionLines()) {
      m[l.label] = (m[l.label] ?? 0) + l.amount;
    }
    return m;
  }

  static String qtyOf(PayrollRow r) => switch (r.payType) {
        'daily' => '${_q(r.days ?? 0)} 天',
        'hourly' => '${_q(r.hours ?? 0)} 小時',
        _ => r.otHours + r.otHours2 > 0 ? '加班 ${_q(r.otHours + r.otHours2)} 小時' : '',
      };
  static String _q(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
}

Uint8List buildPayrollXlsx(PayrollExport p) {
  final excel = Excel.createExcel();
  const sheetName = '薪資表';
  excel.rename('Sheet1', sheetName);
  final sh = excel[sheetName];
  final bold = CellStyle(bold: true);
  final money = CellStyle(numberFormat: NumFormat.standard_3); // #,##0
  final moneyBold = CellStyle(bold: true, numberFormat: NumFormat.standard_3);
  var r = 0;
  void put(int c, CellValue v, {CellStyle? style}) =>
      sh.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r), v, cellStyle: style);

  final cols = p.columns();
  final head = <String>[
    '姓名', '計薪方式', '薪資', '天數／時數',
    ...cols.income, '收入合計',
    ...cols.deduction, '支出合計',
    '實領金額', '領現金額', '實際入帳金額', '備註',
  ];

  put(0, TextCellValue('${p.title}　${DateFormat('yyyy 年 M 月').format(p.month)} 薪資表（${p.published ? '已發布' : '草稿，還沒發布'}）'),
      style: CellStyle(bold: true, fontSize: 14));
  r++;
  put(0, TextCellValue('產生時間：${DateFormat('yyyy/M/d HH:mm').format(DateTime.now())}（App 匯出，金額跟薪資單同一套算法）'));
  r++;
  if (p.revenue != null) {
    put(0, TextCellValue('營業額'));
    put(1, DoubleCellValue(p.revenue!.roundToDouble()), style: money);
    if (p.costRate != null) {
      put(2, TextCellValue('人事成本率'));
      put(3, DoubleCellValue(p.costRate!), style: CellStyle(numberFormat: NumFormat.standard_10));
    }
    r++;
  }
  if (p.hasHidden) {
    put(0, TextCellValue('不含你自己那一列（你的薪資由老闆處理）'));
    r++;
  }
  r++;
  for (final (c, h) in head.indexed) {
    put(c, TextCellValue(h), style: bold);
  }
  r++;

  final totals = <String, double>{};
  void addTotal(String k, double v) => totals[k] = (totals[k] ?? 0) + v;
  for (final row in p.people) {
    var c = 0;
    put(c++, TextCellValue(row.slipName));
    put(c++, TextCellValue(payrollTypeLabel(row.payType)));
    if (row.baseAmount != null) put(c, DoubleCellValue(row.baseAmount!), style: money);
    c++;
    put(c++, TextCellValue(PayrollExport.qtyOf(row)));
    if (row.missingRate || row.gross == null) {
      put(head.length - 1, TextCellValue('還沒有薪資資料，沒有算'));
      r++;
      continue;
    }
    final s = p.slipOf(row), a = p.amountsOf(row);
    for (final k in cols.income) {
      if (a[k] != null) {
        put(c, DoubleCellValue(a[k]!), style: money);
        addTotal(k, a[k]!);
      }
      c++;
    }
    put(c++, DoubleCellValue(s.incomeTotal), style: moneyBold);
    addTotal('收入合計', s.incomeTotal);
    for (final k in cols.deduction) {
      if (a[k] != null) {
        put(c, DoubleCellValue(a[k]!), style: money);
        addTotal(k, a[k]!);
      }
      c++;
    }
    put(c++, DoubleCellValue(s.deductionTotal), style: moneyBold);
    addTotal('支出合計', s.deductionTotal);
    final gross = s.gross!.roundToDouble();
    put(c++, DoubleCellValue(gross), style: money);
    addTotal('實領金額', gross);
    put(c++, DoubleCellValue(s.cashPaid), style: money);
    addTotal('領現金額', s.cashPaid);
    put(c++, DoubleCellValue(s.transfer!), style: moneyBold);
    addTotal('實際入帳金額', s.transfer!);
    if ((row.note ?? '').trim().isNotEmpty) put(c, TextCellValue(row.note!.trim()));
    r++;
  }

  put(0, TextCellValue('合計（${p.people.length} 人）'), style: bold);
  for (final (c, h) in head.indexed) {
    if (c < 4 || totals[h] == null) continue;
    put(c, DoubleCellValue(totals[h]!), style: moneyBold);
  }

  sh.setColumnWidth(0, 14);
  sh.setColumnWidth(3, 14);
  for (var c = 4; c < head.length - 1; c++) {
    sh.setColumnWidth(c, 12);
  }
  sh.setColumnWidth(head.length - 1, 30);
  excel.setDefaultSheet(sheetName);
  final bytes = excel.encode();
  if (bytes == null) throw Exception('薪資表產生失敗');
  return Uint8List.fromList(bytes);
}
