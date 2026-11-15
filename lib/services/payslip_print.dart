import 'dart:js_interop';

import '../data/payroll.dart';
import 'payslip_html.dart';

export 'payslip_html.dart';

@JS('ycPrintHtml')
external JSString _ycPrintHtml(JSString html);

/// 薪資單列印／存成 PDF：另開一頁、自動跳出列印視窗（印表機選「儲存為 PDF」就是 PDF 檔）。
/// 要在按鈕按下去的當下呼叫（不能先 await），不然瀏覽器會擋彈出視窗。回傳 false＝被擋了
bool printPayslips(List<PayrollSlip> slips) => _ycPrintHtml(payslipHtml(slips).toJS).toDart == 'opened';
