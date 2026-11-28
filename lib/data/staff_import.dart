/// 員工名冊搬家（ops 0170，只有公版）：把舊系統的員工名單與起薪從 Excel／CSV 讀進來，
/// 交給資料庫 staff_import 檢查、匯入。這裡只管「看懂檔案」；對不對（電話格式、日期、
/// 有沒有權限設薪資…）一律由資料庫檢查，App 不重複判斷。
///
/// 身分證、銀行帳號不放進匯入（太敏感，一筆一筆在員工資料裡填）。
library;

import 'booking_import.dart' show normDate;

/// 範本的欄位（順序就是範本的順序）
const staffImportColumns = [
  '暱稱',
  '全名',
  '正職／兼職',
  '到職日',
  '電話',
  '緊急聯絡人',
  '緊急聯絡電話',
  '計薪方式',
  '起薪金額',
  '起薪生效日',
  '投保級距',
];

/// 每一欄認得的表頭寫法（不分大小寫、去掉空白與斜線）
const _headerAliases = <String, List<String>>{
  'name': ['暱稱', '班表名字', '班表上的名字', '綽號', '稱呼', 'nickname'],
  'full_name': ['全名', '本名', '真實姓名', '姓名', '員工姓名', 'fullname', 'name'],
  'kind': ['正職／兼職', '正職/兼職', '正職兼職', '身分', '職別', '類別', '雇用類別', 'type', 'kind'],
  'hire_date': ['到職日', '到職日期', '入職日', '到職', 'hiredate', 'startdate'],
  'phone': ['電話', '手機', '聯絡電話', 'phone', 'mobile', 'tel'],
  'emergency_contact': ['緊急聯絡人', 'emergencycontact'],
  'emergency_phone': ['緊急聯絡電話', '緊急聯絡人電話', '緊急電話', 'emergencyphone'],
  'pay_type': ['計薪方式', '薪資方式', '計薪', 'paytype'],
  'amount': [
    '起薪金額',
    '起薪',
    '薪資',
    '金額',
    '月薪／時薪',
    '底薪',
    'salary',
    'amount',
    'rate',
  ],
  'effective_from': ['起薪生效日', '生效日', '薪資生效日', 'effectivefrom'],
  'insured_salary': ['投保級距', '投保薪資', '勞保級距', 'insuredsalary'],
};

String _norm(String s) => s.replaceAll(RegExp(r'[\s/／_\-]+'), '').toLowerCase();

/// 檔案裡的一列（line＝在檔案裡是第幾列，給人看的）
class StaffImportRow {
  final int line;
  final String name, fullName, kind, hireDate, phone;
  final String emergencyContact, emergencyPhone;
  final String payType, amount, effectiveFrom, insuredSalary;
  const StaffImportRow({
    required this.line,
    this.name = '',
    this.fullName = '',
    this.kind = '',
    this.hireDate = '',
    this.phone = '',
    this.emergencyContact = '',
    this.emergencyPhone = '',
    this.payType = '',
    this.amount = '',
    this.effectiveFrom = '',
    this.insuredSalary = '',
  });

  bool get hasPay =>
      payType.isNotEmpty ||
      amount.isNotEmpty ||
      effectiveFrom.isNotEmpty ||
      insuredSalary.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'name': name,
    'full_name': fullName,
    'kind': kind,
    'hire_date': hireDate,
    'phone': phone,
    'emergency_contact': emergencyContact,
    'emergency_phone': emergencyPhone,
    'pay_type': payType,
    'amount': amount,
    'effective_from': effectiveFrom,
    'insured_salary': insuredSalary,
  };

  /// 把起薪那幾欄清空（店長沒有權限設薪資時，可以只匯名冊）
  StaffImportRow withoutPay() => StaffImportRow(
    line: line,
    name: name,
    fullName: fullName,
    kind: kind,
    hireDate: hireDate,
    phone: phone,
    emergencyContact: emergencyContact,
    emergencyPhone: emergencyPhone,
  );
}

/// 讀檔的結果：讀到的列，或看不懂的原因（例如找不到「暱稱」那一欄）
class StaffImportTable {
  final List<StaffImportRow> rows;
  final String? problem;
  const StaffImportTable(this.rows, [this.problem]);
}

/// 第一個有「暱稱」（或沒有暱稱欄時的「全名／姓名」）的列當表頭；前面幾列可以是標題、說明。
/// 沒有暱稱欄時，暱稱就用全名那一欄（舊系統多半只有姓名）。
StaffImportTable readStaffImportTable(List<List<String>> cells) {
  int? head;
  final col = <String, int>{};
  for (var i = 0; i < cells.length && i < 20; i++) {
    final found = <String, int>{};
    for (var c = 0; c < cells[i].length; c++) {
      final h = _norm(cells[i][c]);
      if (h.isEmpty) continue;
      for (final e in _headerAliases.entries) {
        if (!found.containsKey(e.key) && e.value.any((a) => _norm(a) == h)) {
          found[e.key] = c;
          break;
        }
      }
    }
    if (found.containsKey('name') || found.containsKey('full_name')) {
      head = i;
      col.addAll(found);
      break;
    }
  }
  if (head == null) {
    return const StaffImportTable(
      [],
      '找不到「暱稱」或「姓名」這一欄。請用範本，或把第一列改成：暱稱、全名、正職／兼職、到職日、電話…',
    );
  }
  final nameCol = col['name'] ?? col['full_name']!;

  String at(List<String> r, String k) {
    final c = k == 'name' ? nameCol : col[k];
    return c == null || c >= r.length ? '' : r[c].trim();
  }

  final rows = <StaffImportRow>[];
  for (var i = head + 1; i < cells.length; i++) {
    final r = cells[i];
    if (r.every((v) => v.trim().isEmpty)) continue;
    final full = col.containsKey('name') ? at(r, 'full_name') : '';
    rows.add(
      StaffImportRow(
        line: i + 1,
        name: at(r, 'name'),
        fullName: full,
        kind: at(r, 'kind'),
        hireDate: _date(at(r, 'hire_date')),
        phone: at(r, 'phone'),
        emergencyContact: at(r, 'emergency_contact'),
        emergencyPhone: at(r, 'emergency_phone'),
        payType: at(r, 'pay_type'),
        amount: _amount(at(r, 'amount')),
        effectiveFrom: _date(at(r, 'effective_from')),
        insuredSalary: _amount(at(r, 'insured_salary')),
      ),
    );
  }
  if (rows.isEmpty) return const StaffImportTable([], '表頭下面沒有任何員工');
  return StaffImportTable(rows);
}

/// 2026/3/1、2026年3月1日 → 2026-03-01（看不懂照原樣交給資料庫）
String _date(String s) => s.isEmpty ? '' : normDate(s);

/// 「NT$ 30,000」「30000 元」「190.0」→ 30000、190；看不懂的照原樣（資料庫會說金額看不懂）
String _amount(String s) {
  final v = s
      .replaceAll(
        RegExp(r'(NT\$|NTD|\$|元|/月|/時|/日|／月|／時|／日)', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'[,\s]'), '');
  final m = RegExp(r'^(\d+)(?:\.0+)?$').firstMatch(v);
  if (m != null) return m[1]!;
  return RegExp(r'^\d+\.\d{1,2}$').hasMatch(v) ? v : s.trim();
}

/// 一列的問題或略過原因（line＝檔案裡的列號）
class StaffImportIssue {
  final int line;
  final String text;
  const StaffImportIssue(this.line, this.text);
}

/// 資料庫 staff_import 回的結果（預覽或真的匯入）
class StaffImportResult {
  final String? batchId;
  final int inserted, withPay;
  final int ready, readyPay; // 預覽：可以匯入幾位、其中幾位有起薪
  final List<StaffImportIssue> errors;
  final List<StaffImportIssue> skipped;
  final bool repeat;
  const StaffImportResult({
    this.batchId,
    this.inserted = 0,
    this.withPay = 0,
    this.ready = 0,
    this.readyPay = 0,
    this.errors = const [],
    this.skipped = const [],
    this.repeat = false,
  });

  /// rows：送出去的那些列（資料庫回的 row 是第幾個，從 1 開始；換成檔案裡的列號）
  factory StaffImportResult.fromJson(
    Map<String, dynamic> j,
    List<StaffImportRow> rows,
  ) {
    int line(dynamic r) {
      final i = (r as num).toInt() - 1;
      return i >= 0 && i < rows.length ? rows[i].line : i + 1;
    }

    List<StaffImportIssue> list(String k, String field) => [
      for (final e in (j[k] as List? ?? const []))
        StaffImportIssue(line((e as Map)['row']), '${e[field] ?? ''}'),
    ];
    return StaffImportResult(
      batchId: j['batch'] as String?,
      inserted: (j['inserted'] as num?)?.toInt() ?? 0,
      withPay: (j['with_pay'] as num?)?.toInt() ?? 0,
      ready: (j['ready'] as num?)?.toInt() ?? 0,
      readyPay: (j['ready_pay'] as num?)?.toInt() ?? 0,
      errors: list('errors', 'message'),
      skipped: list('skipped', 'reason'),
      repeat: j['repeat'] == true,
    );
  }
}

/// 匯入過的一批
class StaffImportBatch {
  final String id;
  final DateTime createdAt;
  final String? fileName;
  final int total, inserted, withPay, skipped;
  final DateTime? undoneAt;
  final int? undoneCount, undoneKept;
  const StaffImportBatch({
    required this.id,
    required this.createdAt,
    this.fileName,
    required this.total,
    required this.inserted,
    this.withPay = 0,
    required this.skipped,
    this.undoneAt,
    this.undoneCount,
    this.undoneKept,
  });

  factory StaffImportBatch.fromRow(Map<String, dynamic> r) => StaffImportBatch(
    id: r['id'] as String,
    createdAt: DateTime.parse(r['created_at'] as String),
    fileName: r['file_name'] as String?,
    total: (r['total_rows'] as num).toInt(),
    inserted: (r['inserted'] as num).toInt(),
    withPay: (r['with_pay'] as num?)?.toInt() ?? 0,
    skipped: (r['skipped'] as num).toInt(),
    undoneAt: r['undone_at'] == null
        ? null
        : DateTime.parse(r['undone_at'] as String),
    undoneCount: (r['undone_count'] as num?)?.toInt(),
    undoneKept: (r['undone_kept'] as num?)?.toInt(),
  );
}

/// 整批復原的結果：停用了幾位、哪些人有打卡或薪資所以留著
class StaffImportUndo {
  final int deactivated;
  final List<String> keptNames;
  const StaffImportUndo(this.deactivated, this.keptNames);

  factory StaffImportUndo.fromJson(Map<String, dynamic> j) => StaffImportUndo(
    (j['deactivated'] as num?)?.toInt() ?? 0,
    [for (final n in (j['kept_names'] as List? ?? const [])) '$n'],
  );
}
