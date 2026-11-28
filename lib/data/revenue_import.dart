/// 營收搬家（ops 0168，公版階段 6）：把過去的每日營收從 Excel／CSV 讀進來，交給資料庫檢查、匯入。
/// 跟訂位搬家（booking_import.dart）同一個做法：這裡只管「看懂檔案」（找出每一欄是什麼、把日期和數字整理好），
/// 對不對（日期過了沒、金額範圍、這家店有沒有分咖啡拉麵…）一律由資料庫的 revenue_import 檢查，App 不重複判斷。
library;

import '../services/reservation_xlsx.dart' show columnLetter;
import 'booking_import.dart' show ImportIssue, normDate;

/// 範本的欄位（順序就是範本的順序）；[multi]＝這家店的營收有分咖啡、拉麵（功能開關 multi_line_revenue）
List<String> revenueImportColumns({required bool multi}) => [
  '日期',
  '來客數',
  '現金',
  '刷卡',
  'AE',
  '訂金',
  '酒水',
  '餐食',
  '專案',
  if (multi) ...['咖啡', '拉麵'],
  '備註',
];

/// 一次最多幾天（資料庫也擋）
const revenueImportMax = 800;

/// 每一欄認得的表頭寫法（不分大小寫、去掉空白）；key 就是送給資料庫的欄位名稱
const _headerAliases = <String, List<String>>{
  'date': ['日期', '營業日', '營業日期', '日', 'date', 'day'],
  'guests': ['來客數', '來客', '客數', '人數', '來客人數', 'guests', 'pax', 'covers'],
  'cash': ['現金', '現金收入', 'cash'],
  'credit_card': ['刷卡', '信用卡', '刷卡收入', 'card', 'creditcard', 'credit'],
  'amex': ['ae', 'amex', '美國運通', '運通'],
  'deposit': ['訂金', '定金', 'deposit'],
  'drinks_revenue': [
    '酒水',
    '酒吧',
    '調酒',
    '飲料',
    '酒水收入',
    'drinks',
    'drink',
    'bar',
    'beverage',
  ],
  'food_revenue': ['餐食', '餐點', '食物', '餐食收入', 'food'],
  'project_amount': ['專案', '活動', 'project'],
  'coffee_revenue': ['咖啡', 'coffee'],
  'ramen_revenue': ['拉麵', 'ramen'],
  'note': ['備註', '說明', 'note', 'notes', 'memo', 'remark'],
};

const _moneyKeys = [
  'cash',
  'credit_card',
  'amex',
  'deposit',
  'drinks_revenue',
  'food_revenue',
  'project_amount',
  'coffee_revenue',
  'ramen_revenue',
];

/// 日期那一格寫這些的是合計列（舊報表最下面常有），不是一天
const _totalWords = {'合計', '總計', '小計', '總和', '加總', 'total', 'sum', 'subtotal'};

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// 欄名前加「#」或「略過」＝這一欄不要（例如舊系統的合計欄）
bool _ignoredHeader(String h) => h.startsWith('#') || h.startsWith('＃') || h.startsWith('略過');

/// 檔案裡的一天（line＝在檔案裡是第幾列，給人看的）；values 的 key＝資料庫的欄位名稱（沒有這一欄就沒有 key）
class RevenueImportRow {
  final int line;
  final String date;
  final Map<String, String> values;
  const RevenueImportRow({
    required this.line,
    required this.date,
    this.values = const {},
  });

  String v(String k) => values[k] ?? '';

  /// 收款合計（預覽用；看不懂的格子當 0）
  double get received => [
    for (final k in ['cash', 'credit_card', 'amex', 'deposit']) _num(v(k)),
  ].fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {'date': date, ...values};
}

double _num(String s) => double.tryParse(s) ?? 0;

/// 讀檔的結果
class RevenueImportTable {
  final List<RevenueImportRow> rows;
  final String? problem;

  /// 合計列（不送資料庫）
  final List<ImportIssue> skipped;

  /// 認得的欄位（資料庫的欄位名稱，含 date）
  final List<String> columns;
  const RevenueImportTable(
    this.rows, [
    this.problem,
    this.skipped = const [],
    this.columns = const [],
  ]);
}

/// 第一個有「日期」和至少一個營收欄位的列當表頭（前面幾列可以是標題、說明）；表頭之後的空白列跳過。
/// cells：每一列每一格的文字（Excel 的日期格已經換成 2026-10-24）
RevenueImportTable readRevenueTable(List<List<String>> cells) {
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
    if (found.containsKey('date') &&
        found.keys.any((k) => k == 'guests' || _moneyKeys.contains(k))) {
      head = i;
      col.addAll(found);
      break;
    }
  }
  if (head == null) {
    return const RevenueImportTable(
      [],
      '找不到「日期」和營收的欄位。請用範本，或把第一列改成：日期、來客數、現金、刷卡、訂金、酒水、餐食',
    );
  }

  String at(List<String> r, String k) {
    final c = col[k];
    return c == null || c >= r.length ? '' : r[c].trim();
  }

  // 表頭認不得、底下卻有資料的欄位：不默默丟掉（例如「刷卡金額」沒對上，刷卡的錢就會少算），
  // 要使用者改成範本的欄名，或在欄名前加「#」表示這欄不要
  final mapped = col.values.toSet();
  final width = cells.skip(head).fold<int>(0, (w, r) => r.length > w ? r.length : w);
  final unknown = <String>[];
  for (var c = 0; c < width; c++) {
    if (mapped.contains(c)) continue;
    final h = c < cells[head].length ? cells[head][c].trim() : '';
    if (_ignoredHeader(h)) continue;
    final hasData = cells.skip(head + 1).any((r) => c < r.length && r[c].trim().isNotEmpty);
    if (!hasData) continue;
    unknown.add(h.isEmpty ? '第 ${columnLetter(c)} 欄（沒有欄名）' : '「$h」（第 ${columnLetter(c)} 欄）');
  }
  if (unknown.isNotEmpty) {
    return RevenueImportTable(
      const [],
      '這幾欄看不懂：${unknown.join('、')}。'
      '請把欄名改成範本的寫法（日期、來客數、現金、刷卡、AE、訂金、酒水、餐食、專案…），'
      '不要的欄位在欄名前加「#」或整欄刪掉，再選一次檔案',
    );
  }

  final rows = <RevenueImportRow>[];
  final skipped = <ImportIssue>[];
  for (var i = head + 1; i < cells.length; i++) {
    final r = cells[i];
    if (r.every((v) => v.trim().isEmpty)) continue;
    final rawDate = at(r, 'date');
    if (_totalWords.contains(_norm(rawDate))) {
      skipped.add(ImportIssue(i + 1, '合計列'));
      continue;
    }
    rows.add(
      RevenueImportRow(
        line: i + 1,
        date: normDate(rawDate),
        values: {
          for (final k in col.keys)
            if (k == 'guests')
              k: normGuests(at(r, k))
            else if (k == 'note')
              k: at(r, k)
            else if (k != 'date')
              k: normMoney(at(r, k)),
        },
      ),
    );
  }
  if (rows.isEmpty && skipped.isEmpty) {
    return const RevenueImportTable([], '表頭下面沒有任何一天的營收');
  }
  return RevenueImportTable(rows, null, skipped, [for (final k in col.keys) k]);
}

/// 全形數字換成半形
String _ascii(String s) => s.replaceAllMapped(RegExp('[０-９．，]'), (m) {
  final c = m[0]!;
  if (c == '．') return '.';
  if (c == '，') return ',';
  return String.fromCharCode(c.codeUnitAt(0) - 0xFF10 + 0x30);
});

/// 「NT$ 12,345」「$12,345.0」「12,345 元」「－」→ 12345（「-」「－」「—」單獨一格＝0 元，報表常這樣寫）；其他照原樣交給資料庫（會說看不懂）
String normMoney(String s) {
  var v = _ascii(s.trim());
  if (RegExp(r'^[-－—–]$').hasMatch(v)) return '';
  v = v.replaceAll(
    RegExp(r'(?:NT\$|NTD|TWD|\$|元|圓|,|\s)', caseSensitive: false),
    '',
  );
  final m = RegExp(r'^(\d+)\.0+$').firstMatch(v);
  return m == null ? v : m[1]!;
}

/// 「12」「12 位」「12人」「12.0」→ 12；其他照原樣
String normGuests(String s) {
  final v = _ascii(s.trim()).replaceAll(',', '');
  if (RegExp(r'^[-－—–]$').hasMatch(v)) return '';
  final m = RegExp(r'^(\d+)(?:\.0+)?\s*(位|人|組)?$').firstMatch(v);
  return m == null ? v : m[1]!;
}

/// 資料庫 revenue_import 回的結果（預覽或真的匯入）
class RevenueImportResult {
  final String? batchId;
  final int inserted;
  final int ready; // 預覽：可以匯入幾天
  final List<ImportIssue> errors;
  final List<ImportIssue> skipped;
  final List<ImportIssue> warnings;
  final DateTime? dateFrom, dateTo;
  final bool repeat;
  const RevenueImportResult({
    this.batchId,
    this.inserted = 0,
    this.ready = 0,
    this.errors = const [],
    this.skipped = const [],
    this.warnings = const [],
    this.dateFrom,
    this.dateTo,
    this.repeat = false,
  });

  /// 加上 App 讀檔時就略過的列（合計列），照列號排好
  RevenueImportResult withLocal(List<ImportIssue> localSkipped) =>
      RevenueImportResult(
        batchId: batchId,
        inserted: inserted,
        ready: ready,
        errors: errors,
        skipped: [...localSkipped, ...skipped]
          ..sort((a, b) => a.line.compareTo(b.line)),
        warnings: warnings,
        dateFrom: dateFrom,
        dateTo: dateTo,
        repeat: repeat,
      );

  /// rows：送出去的那些列（資料庫回的 row 是第幾個，從 1 開始；換成檔案裡的列號；0＝整個檔案）
  factory RevenueImportResult.fromJson(
    Map<String, dynamic> j,
    List<RevenueImportRow> rows,
  ) {
    int line(dynamic r) {
      final n = (r as num?)?.toInt() ?? 0;
      if (n <= 0) return 0;
      return n <= rows.length ? rows[n - 1].line : n;
    }

    List<ImportIssue> list(String k, String field) => [
      for (final e in (j[k] is List ? j[k] as List : const []))
        ImportIssue(line((e as Map)['row']), '${e[field] ?? ''}'),
    ];
    DateTime? day(dynamic v) => v == null ? null : DateTime.tryParse('$v');
    return RevenueImportResult(
      batchId: j['batch'] as String?,
      inserted: (j['inserted'] as num?)?.toInt() ?? 0,
      ready: (j['ready'] as num?)?.toInt() ?? 0,
      errors: list('errors', 'message'),
      skipped: list('skipped', 'reason'),
      warnings: list('warnings', 'message'),
      dateFrom: day(j['date_from']),
      dateTo: day(j['date_to']),
      repeat: j['repeat'] == true,
    );
  }
}

/// 匯入過的一批營收
class RevenueImportBatch {
  final String id;
  final DateTime createdAt;
  final String? fileName;
  final int total, inserted, skipped;
  final DateTime dateFrom, dateTo;
  final DateTime? undoneAt;

  /// 復原時刪掉幾天、留下幾天（匯入後改過的、鎖帳月份的）
  final int? undoneCount, undoneKept;
  const RevenueImportBatch({
    required this.id,
    required this.createdAt,
    this.fileName,
    required this.total,
    required this.inserted,
    required this.skipped,
    required this.dateFrom,
    required this.dateTo,
    this.undoneAt,
    this.undoneCount,
    this.undoneKept,
  });

  factory RevenueImportBatch.fromRow(Map<String, dynamic> r) =>
      RevenueImportBatch(
        id: r['id'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        fileName: r['file_name'] as String?,
        total: (r['total_rows'] as num).toInt(),
        inserted: (r['inserted'] as num).toInt(),
        skipped: (r['skipped'] as num).toInt(),
        dateFrom: DateTime.parse(r['date_from'] as String),
        dateTo: DateTime.parse(r['date_to'] as String),
        undoneAt: r['undone_at'] == null
            ? null
            : DateTime.parse(r['undone_at'] as String),
        undoneCount: (r['undone_count'] as num?)?.toInt(),
        undoneKept: (r['undone_kept'] as num?)?.toInt(),
      );
}
