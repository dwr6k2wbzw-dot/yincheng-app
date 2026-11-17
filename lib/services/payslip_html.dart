// 薪資單網頁（純 Dart，測試可在 VM 跑；列印走 payslip_print.dart）
import 'package:intl/intl.dart';

import '../data/payroll.dart';

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
final _money = NumberFormat('#,##0');
String _m(num v) => v < 0 ? '−${_money.format(-v)}' : _money.format(v);

/// 薪資單網頁（一人一頁）；A5 直式、黑字白底，方便印出來。
/// 版面（老闆 2026-11-17）：抬頭＝公司登記全名、年月、姓名（全名）；分「收入／支出」兩欄、有金額才列；
/// 收入合計／支出合計；實發金額；有領現才多「領現金額」「實際入帳金額」；備註。
String payslipHtml(List<PayrollSlip> slips) {
  final pages = StringBuffer();
  for (final s in slips) {
    final draft = !s.published;
    final inc = s.incomeLines(), ded = s.deductionLines();
    String cell(SlipLine? l) => l == null
        ? '<td></td><td></td>'
        : '<td>${_esc(l.label)}${l.detail.isEmpty ? '' : '<small>${_esc(l.detail)}</small>'}</td><td class="n">${_m(l.amount.round())}</td>';
    final rows = StringBuffer();
    for (var k = 0; k < (inc.length > ded.length ? inc.length : ded.length); k++) {
      rows.write('<tr>${cell(k < inc.length ? inc[k] : null)}${cell(k < ded.length ? ded[k] : null)}</tr>');
    }
    final cash = s.cashPaid;
    pages.write('''
<section class="slip">
  <h1>${_esc(s.title)}${draft ? ' <span class="draft">草稿／尚未發布</span>' : ''}</h1>
  <p class="ym">${s.month.year} 年 ${s.month.month} 月薪資單</p>
  <div class="who"><span>姓名：${_esc(s.personName)}</span><span>計薪方式：${payrollTypeLabel(s.payType)}</span></div>
  <table>
    <thead><tr><th colspan="2">收入</th><th colspan="2">支出</th></tr></thead>
    <tbody>$rows</tbody>
    <tfoot>
      <tr class="sum"><td>收入合計</td><td class="n">${_m(s.incomeTotal.round())}</td><td>支出合計</td><td class="n">${_m(s.deductionTotal.round())}</td></tr>
      <tr class="net"><td colspan="3">實發金額</td><td class="n">${s.gross == null ? '—' : _m(s.gross!.round())}</td></tr>
      ${cash == 0 ? '' : '<tr class="cash"><td colspan="3">領現金額</td><td class="n">${_m(cash.round())}</td></tr>'
          '<tr class="net"><td colspan="3">實際入帳金額</td><td class="n">${s.transfer == null ? '—' : _m(s.transfer!.round())}</td></tr>'}
    </tfoot>
  </table>
  ${s.note == null || s.note!.isEmpty ? '' : '<p class="note">備註：${_esc(s.note!)}</p>'}
  <p class="foot">${draft ? '尚未發布（草稿）' : s.publishedAt == null ? '已發布' : '發布日期 ${DateFormat('yyyy/M/d').format(s.publishedAt!)}'}・金額・新臺幣（元），四捨五入到元</p>
</section>''');
  }
  final docTitle = slips.length == 1
      ? '${slips.first.published ? '' : '【草稿】'}${slips.first.personName} ${slips.first.month.year}-${slips.first.month.month.toString().padLeft(2, '0')} 薪資單'
      : slips.any((s) => !s.published) ? '【草稿】薪資單' : '薪資單';
  return '''<!doctype html>
<html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${_esc(docTitle)}</title>
<style>
  @page { size: A5 portrait; margin: 12mm; }
  body { font-family: -apple-system, "PingFang TC", "Noto Sans TC", "Microsoft JhengHei", sans-serif; color: #111; background: #fff; margin: 0; }
  .bar { position: sticky; top: 0; padding: 10px 16px; background: #f2f2f2; border-bottom: 1px solid #ddd; }
  .bar button { font-size: 16px; padding: 8px 16px; }
  .slip { max-width: 520px; margin: 24px auto; padding: 0 16px; page-break-after: always; }
  .slip:last-child { page-break-after: auto; }
  h1 { font-size: 18px; margin: 0 0 4px; text-align: center; }
  .ym { font-size: 15px; margin: 0 0 10px; text-align: center; }
  .draft { display: inline-block; margin-left: 8px; padding: 2px 8px; border: 2px solid #b00020; color: #b00020; font-size: 14px; font-weight: 700; vertical-align: middle; }
  .who { display: flex; justify-content: space-between; gap: 24px; font-size: 14px; margin-bottom: 8px; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; table-layout: fixed; }
  th, td { border: 1px solid #bbb; padding: 7px 6px; text-align: left; vertical-align: top; }
  th { font-weight: 600; background: #eef5ea; text-align: center; }
  td small { display: block; color: #555; font-size: 11px; }
  .n { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; width: 22%; }
  tr.sum td { font-weight: 600; background: #f6f6f6; }
  tr.net td { font-weight: 700; font-size: 16px; }
  .note { font-size: 13px; border: 1px solid #bbb; border-top: none; margin: 0; padding: 7px 6px; }
  .foot { font-size: 11px; color: #666; margin-top: 12px; }
  @media print { .bar { display: none; } .slip { margin: 0 auto; } }
</style></head>
<body>
<div class="bar"><button onclick="print()">列印／儲存為 PDF</button></div>
$pages
<script>addEventListener('load', function () { setTimeout(function () { print(); }, 300); });</script>
</body></html>''';
}
