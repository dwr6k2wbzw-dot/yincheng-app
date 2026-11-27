/// 訂位搬家（ops 0148）：把舊系統的未來訂位從 Excel／CSV 讀進來，交給資料庫檢查、匯入。
/// 這裡只管「看懂檔案」：找出每一欄是什麼、把日期時間整理成資料庫看得懂的樣子；
/// 對不對（日期過了沒、電話格式…）一律由資料庫的 reservation_import 檢查，App 不重複判斷。
library;

/// 範本的欄位（順序就是範本的順序）
const importColumns = ['日期', '時間', '人數', '姓名', '電話', 'Email', '備註', '語言'];

/// 每一欄認得的表頭寫法（不分大小寫、去掉空白）
const _headerAliases = <String, List<String>>{
  'date': ['日期', '訂位日期', '用餐日期', 'date'],
  'time': ['時間', '訂位時間', '用餐時間', '時段', 'time'],
  'party': ['人數', '位數', '大人', '人', 'party', 'guests', 'pax', 'size'],
  'name': ['姓名', '名字', '訂位人', '客人', '聯絡人', 'name', 'guest'],
  'phone': ['電話', '手機', '聯絡電話', 'phone', 'mobile', 'tel'],
  'email': ['email', 'e-mail', '信箱', '電子郵件'],
  'note': ['備註', '需求', '特殊需求', 'note', 'notes', 'memo', 'remark'],
  'lang': ['語言', 'lang', 'language'],
};

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// 檔案裡的一列（line＝在檔案裡是第幾列，給人看的）
class ImportRow {
  final int line;
  final String date, time, party, name, phone, email, note, lang;
  const ImportRow({
    required this.line,
    this.date = '',
    this.time = '',
    this.party = '',
    this.name = '',
    this.phone = '',
    this.email = '',
    this.note = '',
    this.lang = '',
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'time': time,
        'party': party,
        'name': name,
        'phone': phone,
        'email': email,
        'note': note,
        if (lang.isNotEmpty) 'lang': lang,
      };
}

/// 讀檔的結果：讀到的列，或看不懂的原因（例如找不到「日期」那一欄）
class ImportTable {
  final List<ImportRow> rows;
  final String? problem;
  const ImportTable(this.rows, [this.problem]);
}

/// 第一個有「日期」「姓名」的列當表頭（前面幾列可以是標題、說明）；表頭之後的空白列跳過。
/// cells：每一列每一格的文字（Excel 的日期、時間格已經換成 2026-12-24、19:30）
ImportTable readImportTable(List<List<String>> cells) {
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
        }
      }
    }
    if (found.containsKey('date') && found.containsKey('name')) {
      head = i;
      col.addAll(found);
      break;
    }
  }
  if (head == null) {
    return const ImportTable(
        [], '找不到「日期」和「姓名」這兩欄。請用範本，或把第一列改成：日期、時間、人數、姓名、電話、Email、備註');
  }
  final missing = [
    for (final k in ['time', 'party'])
      if (!col.containsKey(k)) k == 'time' ? '時間' : '人數'
  ];
  if (missing.isNotEmpty) {
    return ImportTable(const [], '找不到「${missing.join('」「')}」這一欄');
  }

  String at(List<String> r, String k) {
    final c = col[k];
    return c == null || c >= r.length ? '' : r[c].trim();
  }

  final rows = <ImportRow>[];
  for (var i = head + 1; i < cells.length; i++) {
    final r = cells[i];
    if (r.every((v) => v.trim().isEmpty)) continue;
    rows.add(ImportRow(
      line: i + 1,
      date: normDate(at(r, 'date')),
      time: normTime(at(r, 'time')),
      party: normParty(at(r, 'party')),
      name: at(r, 'name'),
      phone: at(r, 'phone'),
      email: at(r, 'email'),
      note: at(r, 'note'),
      lang: normLang(at(r, 'lang')),
    ));
  }
  if (rows.isEmpty) return const ImportTable([], '表頭下面沒有任何訂位');
  return ImportTable(rows);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 2026/12/24、2026-12-24、2026.12.24、2026年12月24日、2026-12-24 19:30 → 2026-12-24；看不懂的照原樣交給資料庫（會回「日期看不懂」）
String normDate(String s) {
  final v = s.trim();
  // 日之後只能是結尾，或空白／T 加時間（2026-12-240 不能變成 2026-12-24，照原樣交給資料庫說看不懂）
  final m = RegExp(r'^(\d{4})\s*[/\-.年]\s*(\d{1,2})\s*[/\-.月]\s*(\d{1,2})\s*日?(?:[\sT]+\d{1,2}:\d{2}(?::\d{2}(?:\.\d+)?)?)?$')
      .firstMatch(v);
  if (m != null) return '${m[1]}-${_two(int.parse(m[2]!))}-${_two(int.parse(m[3]!))}';
  // Excel 的日期序號（公式算出來的日期格，檔案裡存的是天數，例 46010）
  final serial = RegExp(r'^\d{5}(?:\.\d+)?$').hasMatch(v) ? double.parse(v) : null;
  if (serial != null && serial >= 36526 && serial < 73051) {
    final d = DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()));
    return '${d.year}-${_two(d.month)}-${_two(d.day)}';
  }
  return v;
}

/// 19:30、19:30:00、19：30、7:30 PM、晚上 7:30、1930、Excel 的時間（一天的幾分之幾，例 0.8125）→ 19:30；看不懂的照原樣
String normTime(String s) {
  var t = s.trim().replaceAll('：', ':');
  if (RegExp(r'^0?\.\d+$').hasMatch(t)) {
    final mins = (double.parse(t) * 24 * 60).round();
    if (mins < 24 * 60) return '${_two(mins ~/ 60)}:${_two(mins % 60)}';
  }
  final pm = RegExp(r'(pm|下午|晚上)', caseSensitive: false).hasMatch(t);
  final am = RegExp(r'(am|上午|早上)', caseSensitive: false).hasMatch(t);
  t = t
      .replaceAll(RegExp(r'(am|pm|上午|下午|晚上|早上)', caseSensitive: false), '')
      .trim();
  var m = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(t);
  m ??= RegExp(r'^(\d{1,2})(\d{2})$').firstMatch(t);
  if (m == null) return s.trim();
  var h = int.parse(m[1]!);
  final mi = int.parse(m[2]!);
  if (pm && h < 12) h += 12;
  if (am && h == 12) h = 0;
  if (h > 23 || mi > 59) return s.trim();
  return '${_two(h)}:${_two(mi)}';
}

/// 「4」「4 位」「4人」「4.0」→ 4；其他照原樣
String normParty(String s) {
  final m = RegExp(r'^(\d+)(?:\.0+)?\s*(位|人|pax)?$', caseSensitive: false)
      .firstMatch(s.trim());
  return m == null ? s.trim() : m[1]!;
}

/// 中文／英文／日文、zh／en／ja → zh／en／ja；空白＝中文；其他照原樣（資料庫會說不認得）
String normLang(String s) {
  final v = _norm(s);
  if (v.isEmpty) return '';
  if (['zh', '中文', '中', 'chinese', 'zh-tw'].contains(v)) return 'zh';
  if (['en', '英文', '英', 'english'].contains(v)) return 'en';
  if (['ja', 'jp', '日文', '日', '日本語', 'japanese'].contains(v)) return 'ja';
  return s.trim();
}

/// CSV（Excel 存的、Google 試算表下載的）：處理引號、BOM、\r\n
List<List<String>> parseCsv(String text) {
  var s = text.startsWith('﻿') ? text.substring(1) : text;
  // Excel 存成「CSV（分號分隔）」的檔案：第一列沒有逗號、有分號就用分號
  final first = s.split('\n').first;
  final sep = !first.contains(',') && first.contains(';') ? ';' : ',';
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"' && cell.isEmpty) {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// 一列的問題或略過原因（line＝檔案裡的列號）
class ImportIssue {
  final int line;
  final String text;
  const ImportIssue(this.line, this.text);
}

/// 資料庫 reservation_import 回的結果（預覽或真的匯入）
class ImportResult {
  final String? batchId;
  final int inserted;
  final int ready; // 預覽：可以匯入幾筆
  final List<ImportIssue> errors;
  final List<ImportIssue> skipped;
  final bool repeat;
  const ImportResult({
    this.batchId,
    this.inserted = 0,
    this.ready = 0,
    this.errors = const [],
    this.skipped = const [],
    this.repeat = false,
  });

  /// rows：送出去的那些列（資料庫回的 row 是第幾個，從 1 開始；換成檔案裡的列號）
  factory ImportResult.fromJson(Map<String, dynamic> j, List<ImportRow> rows) {
    int line(dynamic r) {
      final i = (r as num).toInt() - 1;
      return i >= 0 && i < rows.length ? rows[i].line : i + 1;
    }

    List<ImportIssue> list(String k, String field) => [
          for (final e in (j[k] as List? ?? const []))
            ImportIssue(line((e as Map)['row']), '${e[field] ?? ''}'),
        ];
    return ImportResult(
      batchId: j['batch'] as String?,
      inserted: (j['inserted'] as num?)?.toInt() ?? 0,
      ready: (j['ready'] as num?)?.toInt() ?? 0,
      errors: list('errors', 'message'),
      skipped: list('skipped', 'reason'),
      repeat: j['repeat'] == true,
    );
  }
}

/// 匯入過的一批
class ImportBatch {
  final String id;
  final DateTime createdAt;
  final String? fileName;
  final int total, inserted, skipped;
  final DateTime? undoneAt;
  final int? undoneCount;
  const ImportBatch({
    required this.id,
    required this.createdAt,
    this.fileName,
    required this.total,
    required this.inserted,
    required this.skipped,
    this.undoneAt,
    this.undoneCount,
  });

  factory ImportBatch.fromRow(Map<String, dynamic> r) => ImportBatch(
        id: r['id'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        fileName: r['file_name'] as String?,
        total: (r['total_rows'] as num).toInt(),
        inserted: (r['inserted'] as num).toInt(),
        skipped: (r['skipped'] as num).toInt(),
        undoneAt: r['undone_at'] == null
            ? null
            : DateTime.parse(r['undone_at'] as String),
        undoneCount: (r['undone_count'] as num?)?.toInt(),
      );
}
