import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../data/attendance_models.dart';
import '../data/models.dart';
import '../data/staff_import.dart';
import 'reservation_xlsx.dart' show readXlsxCells, XlsxCells;

/// 員工名冊搬家（ops 0170）：範本、讀 Excel、匯出名冊。
/// 身分證、銀行帳號一律不進範本、不進匯出（太敏感）。

/// 讀 .xlsx：第一個看得懂員工名冊的工作表（範本是「員工」）
XlsxCells readStaffXlsx(Uint8List bytes) => readXlsxCells(
  bytes,
  accept: (cells) => readStaffImportTable(cells).problem == null,
);

final _head = CellStyle(
  bold: true,
  backgroundColorHex: ExcelColor.fromHexString('#E8E2D6'),
);

const _widths = [
  10.0,
  12.0,
  10.0,
  12.0,
  14.0,
  12.0,
  14.0,
  9.0,
  10.0,
  12.0,
  10.0,
];

void _writeHead(Sheet sh, List<String> cols) {
  for (var c = 0; c < cols.length; c++) {
    sh.setColumnWidth(c, c < _widths.length ? _widths[c] : 10.0);
    sh.updateCell(
      CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      TextCellValue(cols[c]),
      cellStyle: _head,
    );
  }
}

/// 匯入範本：第一頁「員工」第一列是表頭、下面兩列範例（刪掉換成自己的）；第二頁「說明」
Uint8List buildStaffImportTemplate({DateTime? today}) {
  final t = today ?? DateTime.now();
  final d = DateFormat('yyyy-MM-dd');
  final excel = Excel.createExcel();
  excel.rename('Sheet1', '員工');
  final sh = excel['員工'];
  _writeHead(sh, staffImportColumns);
  final samples = [
    [
      '小明',
      '王小明',
      '正職',
      d.format(DateTime(t.year, 1, 2)),
      '0912345678',
      '王媽媽',
      '0922333444',
      '月薪',
      '32000',
      '',
      '33300',
    ],
    [
      '阿華',
      '林阿華',
      '兼職',
      d.format(DateTime(t.year, t.month, 1)),
      '0933111222',
      '',
      '',
      '時薪',
      '196',
      '',
      '',
    ],
  ];
  for (var r = 0; r < samples.length; r++) {
    for (var c = 0; c < samples[r].length; c++) {
      sh.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
        TextCellValue(samples[r][c]),
      );
    }
  }
  final help = excel['說明'];
  help.setColumnWidth(0, 90);
  const lines = [
    '員工名冊匯入說明',
    '',
    '暱稱：必填，最多 20 個字，就是班表上顯示的名字（照片辨識、排班都靠它）。同一份檔案裡不能重複。',
    '全名：可以空白，最多 40 個字（薪資單上用全名）。',
    '正職／兼職：正職或兼職，空白＝正職。',
    '到職日：例 2026-03-01；可以空白。',
    '電話、緊急聯絡電話：可以空白；有填要是正確的電話。',
    '',
    '起薪（可以整段空白，之後在員工資料再填）：',
    '計薪方式：月薪、時薪或日薪。',
    '起薪金額：月薪填一個月、時薪填一小時、日薪填一天的金額。',
    '起薪生效日：空白＝用到職日；兩個都空白就不能填起薪。',
    '投保級距：可以空白。',
    '只有老闆（或老闆允許看薪資的店長）能匯入起薪；不能看薪資的人請把起薪那幾欄清空。',
    '',
    '身分證、銀行帳號不放進匯入：請在 App「員工資料」一位一位填。',
    '班表上已經有同一個暱稱的人（包含已停用的）會略過、不改原本的資料。',
    '任何一列有問題就整批不匯入，改好再選一次檔案。',
    '匯入後在 App「匯入、匯出員工名冊」可以整批復原（停用，不刪除；已經有打卡或薪資的人會留著）。',
  ];
  for (var i = 0; i < lines.length; i++) {
    help.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i),
      TextCellValue(lines[i]),
      cellStyle: i == 0 ? CellStyle(bold: true) : null,
    );
  }
  excel.setDefaultSheet('員工');
  return Uint8List.fromList(excel.save()!);
}

String _payType(String? t) => switch (t) {
  'monthly' => '月薪',
  'hourly' => '時薪',
  'daily' => '日薪',
  _ => '',
};

String _money(double? v) => v == null
    ? ''
    : (v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2));

/// 匯出名冊（欄位跟範本一樣，可以拿去別的店匯入）：最後多一欄「狀態」。
/// 薪資欄位只有看得到這個人薪資的人（StaffEntry.canSeePay）才寫；身分證、銀行帳號不匯出。
Uint8List buildStaffRosterXlsx(
  List<ShiftPerson> people,
  List<StaffEntry> directory,
) {
  final byId = {for (final e in directory) e.personId: e};
  final excel = Excel.createExcel();
  excel.rename('Sheet1', '員工');
  final sh = excel['員工'];
  _writeHead(sh, [...staffImportColumns, '狀態']);
  final d = DateFormat('yyyy-MM-dd');
  final sorted = [...people]
    ..sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return a.sortOrder.compareTo(b.sortOrder);
    });
  for (var i = 0; i < sorted.length; i++) {
    final p = sorted[i];
    final e = byId[p.id];
    final pay = e != null && e.canSeePay;
    final hire = e?.hireDate ?? p.hireDate;
    final values = [
      p.name,
      p.fullName ?? '',
      p.isFull ? '正職' : '兼職',
      hire == null ? '' : d.format(hire),
      e?.phone ?? '',
      e?.emergencyContact ?? '',
      e?.emergencyPhone ?? '',
      pay ? _payType(e.ratePayType) : '',
      pay ? _money(e.rateAmount) : '',
      pay && e.rateEffectiveFrom != null ? d.format(e.rateEffectiveFrom!) : '',
      pay ? _money(e.insuredSalary) : '',
      p.active ? '在職' : '停用',
    ];
    for (var c = 0; c < values.length; c++) {
      sh.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: i + 1),
        TextCellValue(values[c]),
      );
    }
  }
  return Uint8List.fromList(excel.save()!);
}

String staffRosterXlsxName(String store, {DateTime? now}) =>
    '${store}_員工名冊_${DateFormat('yyyyMMdd').format(now ?? DateTime.now())}.xlsx';
