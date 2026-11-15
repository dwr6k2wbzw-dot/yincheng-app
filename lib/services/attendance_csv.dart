import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../data/attendance_models.dart';
import 'clock.dart';

/// 出勤匯出 CSV（店長每天看異常、月底自己算薪資用；這階段不算薪資）。
/// 時間一律台北時間；開頭加 UTF-8 BOM，Excel 打開中文才不會變亂碼。
const csvMime = 'text/csv';

String csvCell(String? v) {
  final s = v ?? '';
  // 公式注入：= + - @ 開頭的字 Excel 會當公式算，前面加 ' 當成文字
  final safe = RegExp(r'^[=+\-@\t\r]').hasMatch(s) ? "'$s" : s;
  return RegExp(r'[",\r\n]').hasMatch(safe) ? '"${safe.replaceAll('"', '""')}"' : safe;
}

String buildAttendanceCsv(List<AttendanceExportRow> rows) {
  final day = DateFormat('yyyy-MM-dd'), time = DateFormat('yyyy-MM-dd HH:mm:ss');
  final out = StringBuffer()
    ..write([
      '營業日', '姓名', '上班／下班', '打卡時間（台北）', '打卡店家', '來源', '狀態', '提醒', '審核', '審核原因', '補登原因', '算不算', '紀錄編號'
    ].map(csvCell).join(','))
    ..write('\r\n');
  for (final r in rows) {
    out
      ..write([
        day.format(r.businessDate),
        r.personName,
        punchTypeLabel(r.punchType),
        time.format(toTaipei(r.punchedAt)),
        r.storeName,
        r.source == 'amendment' ? '補登' : 'QR',
        r.status == 'pending' ? '待確認' : '正常',
        r.flags.split(' ').where((f) => f.isNotEmpty).map(punchFlagLabel).join('、'),
        switch (r.review) { 'confirmed' => '已確認', 'rejected' => '不採用', _ => '' },
        r.reviewReason,
        r.amendmentReason,
        r.counted ? '算' : '不算',
        r.punchId,
      ].map(csvCell).join(','))
      ..write('\r\n');
  }
  return out.toString();
}

Uint8List attendanceCsvBytes(List<AttendanceExportRow> rows) =>
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(buildAttendanceCsv(rows))]);

String attendanceCsvName(String store, DateTime from, DateTime to) {
  final f = DateFormat('yyyyMMdd');
  return '出勤_${store}_${f.format(from)}-${f.format(to)}.csv';
}
