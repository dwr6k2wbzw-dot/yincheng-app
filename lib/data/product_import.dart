/// 盤點品項搬家（ops 0167，公版階段 5）：把舊系統或自己整理的品項清單從 Excel／CSV 讀進來，
/// 交給資料庫 product_import 檢查、匯入。這裡只管「看懂檔案」：找出每一欄是什麼、把數字和
/// 「多久盤一次」整理成資料庫看得懂的樣子；對不對（字數、範圍、同名…）一律由資料庫檢查。
library;

import 'booking_import.dart' show ImportIssue, ImportResult;

/// 範本的欄位（順序就是範本的順序）；成本價只有老闆的範本有
const productImportColumns = ['品名', '單位', '分類', '安全量', '多久盤一次'];
const productCostColumn = '成本價';

/// 每一欄認得的表頭寫法（不分大小寫、去掉空白）
const _headerAliases = <String, List<String>>{
  'name': ['品名', '名稱', '品項', '品項名稱', '商品名稱', '商品', 'name', 'item', 'product'],
  'unit': ['單位', 'unit', 'uom'],
  'category': ['分類', '類別', '種類', 'category', 'type'],
  'par': [
    '安全量',
    '安全庫存',
    '安全存量',
    '最低庫存',
    '最低量',
    'par',
    'parlevel',
    'min',
    'minimum',
  ],
  'cycle': ['多久盤一次', '盤點頻率', '盤點週期', '重點品項', 'cycle', 'countcycle'],
  'cost': ['成本價', '成本', '進價', '單價', 'cost', 'costprice', 'price'],
};

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// 檔案裡的一列（line＝在檔案裡是第幾列，給人看的）
class ProductImportRow {
  final int line;
  final String name, unit, category, par, cycle, cost;
  const ProductImportRow({
    required this.line,
    this.name = '',
    this.unit = '',
    this.category = '',
    this.par = '',
    this.cycle = '',
    this.cost = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'unit': unit,
    'category': category,
    'par_level': par,
    'count_cycle': cycle,
    if (cost.isNotEmpty) 'cost_price': cost,
  };
}

/// 讀檔的結果：讀到的列，或看不懂的原因（例如找不到「品名」那一欄）
class ProductImportTable {
  final List<ProductImportRow> rows;
  final String? problem;

  /// 檔案有成本價那一欄，而且至少一列有填
  final bool hasCost;
  const ProductImportTable(this.rows, [this.problem, this.hasCost = false]);
}

/// 數字：去掉千分位逗號、NT$、$、「元」（例：NT$1,200 → 1200）；其他照原樣交給資料庫判斷
String normProductNumber(String s) {
  final t = s.trim();
  if (t.isEmpty) return '';
  final cleaned = t
      .replaceAll(RegExp(r'^(nt\$|NT\$|\$)'), '')
      .replaceAll(RegExp(r'元$'), '')
      .replaceAll(',', '')
      .replaceAll('，', '')
      .trim();
  return double.tryParse(cleaned) == null ? t : cleaned;
}

/// 多久盤一次：每天盤／每天／daily → 每天；每週盤／每周／weekly → 每週；空白、不追蹤 → 空白。
/// 看不懂的照原樣交給資料庫（會回「只能是每天、每週或空白」）
String normCycle(String s) {
  final t = _norm(s);
  if (t.isEmpty ||
      t == '不追蹤' ||
      t == '不用' ||
      t == '無' ||
      t == '-' ||
      t == 'none') {
    return '';
  }
  if (const {'每天', '每天盤', '每日', '每日盤', '天', 'daily', 'day'}.contains(t)) {
    return '每天';
  }
  if (const {'每週', '每周', '每週盤', '每周盤', '週', '周', 'weekly', 'week'}.contains(t)) {
    return '每週';
  }
  return s.trim();
}

/// 第一個有「品名」「單位」的列當表頭（前面幾列可以是標題、說明）；表頭之後的空白列跳過。
ProductImportTable readProductImportTable(List<List<String>> cells) {
  for (var h = 0; h < cells.length && h < 20; h++) {
    final head = [for (final c in cells[h]) _norm(c)];
    int col(String key) {
      final names = [for (final a in _headerAliases[key]!) _norm(a)];
      for (final n in names) {
        final i = head.indexOf(n);
        if (i >= 0) return i;
      }
      return -1;
    }

    final name = col('name');
    if (name < 0) continue;
    final unit = col('unit'), category = col('category');
    if (unit < 0) {
      return const ProductImportTable([], '找不到「單位」那一欄（第一列要有品名、單位、分類）');
    }
    if (category < 0) {
      return const ProductImportTable([], '找不到「分類」那一欄（第一列要有品名、單位、分類）');
    }
    final par = col('par'), cycle = col('cycle'), cost = col('cost');
    String at(List<String> r, int i) =>
        i >= 0 && i < r.length ? r[i].trim() : '';
    final rows = <ProductImportRow>[];
    var hasCost = false;
    for (var r = h + 1; r < cells.length; r++) {
      final row = cells[r];
      if (row.every((c) => c.trim().isEmpty)) continue;
      final c = normProductNumber(at(row, cost));
      if (c.isNotEmpty) hasCost = true;
      rows.add(
        ProductImportRow(
          line: r + 1,
          name: at(row, name),
          unit: at(row, unit),
          category: at(row, category),
          par: normProductNumber(at(row, par)),
          cycle: normCycle(at(row, cycle)),
          cost: c,
        ),
      );
    }
    return ProductImportTable(rows, null, hasCost);
  }
  return const ProductImportTable([], '找不到「品名」那一欄（第一列要有品名、單位、分類）');
}

/// 資料庫 product_import 回的結果（預覽或真的匯入）；rows：送出去的那些列（row 從 1 開始，換成檔案裡的列號）
ImportResult productImportResult(
  Map<String, dynamic> j,
  List<ProductImportRow> rows,
) {
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
