import 'dart:js_interop';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

/// 一鍵匯出當月損益表（老闆 2026-10-12）：產生 Excel（.xlsx），用手機的分享選單「儲存到檔案」。
/// 數字與 App「本月損益」卡片同一算法（由畫面算好傳進來，這裡只負責排版）。
class PlLine {
  final String label;
  final double amount;
  final String? note;
  const PlLine(this.label, this.amount, [this.note]);
}

class ProfitStatement {
  final String storeName;
  final DateTime month;
  final double revenue;
  final List<PlLine> revenueParts; // 營收組成（隱城：酒水／餐食；小城外：咖啡／調酒／拉麵／訂金）
  final int guests;
  final double cash;
  final double card;
  final double purchaseCost; // 進貨（不含雜項類）
  final double drinkCost;
  final double foodCost;
  final double misc;
  final double rent;
  final double payroll;
  final List<PlLine> miscDetail; // 雜項的組成（進貨雜項、刷卡手續費、手動明細）
  final List<PlLine> rentDetail;
  final List<PlLine> payrollDetail;
  final List<String> warnings; // 例：尚未輸入租金
  const ProfitStatement({
    required this.storeName,
    required this.month,
    required this.revenue,
    required this.revenueParts,
    required this.guests,
    required this.cash,
    required this.card,
    required this.purchaseCost,
    required this.drinkCost,
    required this.foodCost,
    required this.misc,
    required this.rent,
    required this.payroll,
    required this.miscDetail,
    required this.rentDetail,
    required this.payrollDetail,
    this.warnings = const [],
  });
  double get profit => revenue - purchaseCost - misc - rent - payroll;
  String get fileName => '${storeName}_損益表_${DateFormat('yyyy-MM').format(month)}.xlsx';
}

Uint8List buildProfitXlsx(ProfitStatement p) {
  final excel = Excel.createExcel();
  const sheetName = '損益表';
  excel.rename('Sheet1', sheetName);
  final sh = excel[sheetName];
  sh.setColumnWidth(0, 30);
  sh.setColumnWidth(1, 16);
  sh.setColumnWidth(2, 12);
  sh.setColumnWidth(3, 30);

  final bold = CellStyle(bold: true);
  const money = NumFormat.standard_3; // #,##0
  const percent = NumFormat.standard_10; // 0.00%
  var r = 0;

  void put(int c, CellValue v, {CellStyle? style}) {
    sh.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r), v, cellStyle: style);
  }

  void row(String label, double? amount, {bool share = true, String? note, bool strong = false, bool indent = false}) {
    put(0, TextCellValue(indent ? '　　$label' : label), style: strong ? CellStyle(bold: true) : null);
    if (amount != null) {
      put(1, DoubleCellValue(amount.roundToDouble()), style: CellStyle(bold: strong, numberFormat: money));
      if (share && p.revenue > 0) {
        put(2, DoubleCellValue(amount / p.revenue), style: CellStyle(bold: strong, numberFormat: percent));
      }
    }
    if (note != null && note.isNotEmpty) put(3, TextCellValue(note));
    r++;
  }

  void header(String text) {
    put(0, TextCellValue(text), style: bold);
    r++;
  }

  put(0, TextCellValue('${p.storeName}　${DateFormat('yyyy 年 M 月').format(p.month)} 損益表'),
      style: CellStyle(bold: true, fontSize: 14));
  r++;
  put(0, TextCellValue('產生時間：${DateFormat('yyyy/M/d HH:mm').format(DateTime.now())}（App 匯出，營收、進貨以日報表為準）'));
  r += 2;
  put(0, TextCellValue('項目'), style: bold);
  put(1, TextCellValue('金額'), style: bold);
  put(2, TextCellValue('占營收'), style: bold);
  put(3, TextCellValue('說明'), style: bold);
  r++;

  header('一、營業收入');
  for (final x in p.revenueParts) {
    row(x.label, x.amount, indent: true, note: x.note);
  }
  row('營業收入合計', p.revenue, strong: true, note: '來客 ${p.guests} 位；現金 ${_n(p.cash)}、刷卡 ${_n(p.card)}');
  r++;

  header('二、進貨（不含雜項類）');
  row('酒水進貨', p.drinkCost, indent: true);
  row('餐食進貨', p.foodCost, indent: true);
  row('進貨合計（損益用）', p.purchaseCost, strong: true, note: '不含算進雜項的類別');
  r++;

  header('三、雜項');
  for (final x in p.miscDetail) {
    row(x.label, x.amount, indent: true, note: x.note);
  }
  row('雜項合計', p.misc, strong: true);
  r++;

  header('四、租金');
  for (final x in p.rentDetail) {
    row(x.label, x.amount, indent: true, note: x.note);
  }
  row('租金合計', p.rent, strong: true);
  r++;

  header('五、人事');
  for (final x in p.payrollDetail) {
    row(x.label, x.amount, indent: true, note: x.note);
  }
  row('人事合計', p.payroll, strong: true);
  r++;

  row('本月損益（營收－進貨－雜項－租金－人事）', p.profit, strong: true, note: '占營收＝淨利率');
  if (p.warnings.isNotEmpty) {
    r++;
    put(0, TextCellValue('注意：${p.warnings.join('；')}'));
    r++;
  }

  excel.setDefaultSheet(sheetName);
  final bytes = excel.encode();
  if (bytes == null) throw Exception('損益表產生失敗');
  return Uint8List.fromList(bytes);
}

String _n(double v) => NumberFormat('#,##0').format(v.round());

@JS('ycSaveFile')
external JSPromise<JSString> _ycSaveFile(JSUint8Array bytes, JSString name, JSString mime);

/// 存檔：手機跳出分享選單（可選「儲存到檔案」）；不支援分享的瀏覽器直接下載。
/// 回傳 shared／downloaded／cancel
Future<String> saveFile(Uint8List bytes, String name, String mime) async =>
    (await _ycSaveFile(bytes.toJS, name.toJS, mime.toJS).toDart).toDart;

const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
