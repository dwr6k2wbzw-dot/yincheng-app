// 進貨品項明細的計算（0087，老闆 2026-11-01：拍照辨識送貨單 → 品項 → 庫存）
// 純函式，方便測試（不依賴畫面）
import 'models.dart';

double round2(double v) => (v * 100).round() / 100;

/// 品項小計加總（每行先四捨五入到分，同資料庫 amount 欄）
double itemsTotal(Iterable<PurchaseItem> items) => round2(items.fold<double>(0, (a, it) => a + it.amount));

const diffItemName = '其他差額（運費、稅、折讓）';

/// 存檔用的明細：品項加總跟單據金額不同時，補一行「其他差額」（不入庫存），
/// 讓明細合計＝進貨金額（老闆／店長核銷時資料庫會檢查，0006）。沒有品項就回傳空清單。
List<PurchaseItem> itemsForSave(List<PurchaseItem> items, double total) {
  final rows = [for (final it in items) if (it.name.trim().isNotEmpty && it.qty != 0) it.copy()];
  if (rows.isEmpty) return const [];
  for (final it in rows) {
    it.unitPrice = round2(it.unitPrice ?? 0);
    if (!it.toStock) {
      it.productId = null;
      it.stockQty = null;
    }
  }
  final diff = round2(total - itemsTotal(rows));
  if (diff != 0) rows.add(PurchaseItem(name: diffItemName, qty: 1, unitPrice: diff, decided: true));
  return rows;
}

/// 已存的明細讀回來時，把「其他差額」那一行拿掉（畫面上另外算）
List<PurchaseItem> withoutDiffLine(List<PurchaseItem> items) => [for (final it in items) if (it.name != diffItemName) it];

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_.·・()（）/]'), '');

/// 品名對不到庫存品項時，用名稱找一個建議（店員確認才算）：
/// 完全相同 > 一邊包含另一邊（取最長的品項名稱）；太短（1 個字）不比
Product? suggestProduct(String itemName, List<Product> products) {
  final n = _norm(itemName);
  if (n.length < 2) return null;
  Product? best;
  var bestLen = 0;
  for (final p in products) {
    final q = _norm(p.name);
    if (q.length < 2) continue;
    if (q == n) return p;
    if ((n.contains(q) || q.contains(n)) && q.length > bestLen) {
      best = p;
      bestLen = q.length;
    }
  }
  return best;
}

/// 選了庫存品項後預設加幾個：辨識給的數量 > 單位相同就等於數量 > 不知道（要店員填）
double? defaultStockQty(PurchaseItem it, Product p) {
  if (it.stockQty != null && it.stockQty! > 0) return it.stockQty;
  final u = it.unit?.trim();
  if (u == null || u.isEmpty || u == p.unit.trim()) return it.qty.abs();
  return null;
}

/// 本月進貨品項總表的一列（同一個庫存品項、或同名同單位的品項合在一起）
class ItemSummary {
  ItemSummary(this.name, this.unit);
  final String name;
  final String? unit;
  double qty = 0; // 退貨是負數，合起來是淨數量
  double total = 0;
  double? minPrice;
  double? maxPrice;
  int lines = 0;
  /// 單價：都一樣就是那個價，不一樣就用平均（總金額÷數量）
  double? get unitPrice => qty == 0 ? null : (minPrice == maxPrice ? minPrice : round2(total / qty));
  bool get priceVaries => minPrice != maxPrice;
}

/// 把一個月的品項明細合成總表：有對應庫存品項的照品項合；沒有的照「品名＋單位」合。
/// 「其他差額」那行不算品項。productNames：庫存品項 id → 名稱（顯示用）。依金額大到小排。
List<ItemSummary> summarizeItems(Iterable<PurchaseItem> items, Map<String, String> productNames) {
  final map = <String, ItemSummary>{};
  for (final it in items) {
    if (it.name == diffItemName || it.qty == 0) continue;
    final pid = it.productId;
    final named = pid != null && productNames.containsKey(pid);
    final unit = it.unit?.trim().isEmpty ?? true ? null : it.unit!.trim();
    final key = named ? 'p:$pid:${unit ?? ''}' : 'n:${_norm(it.name)}:${unit ?? ''}';
    final s = map.putIfAbsent(key, () => ItemSummary(named ? productNames[pid]! : it.name.trim(), unit));
    final price = round2(it.unitPrice ?? 0);
    s.qty = round2(s.qty + it.qty);
    s.total = round2(s.total + it.amount);
    s.minPrice = s.minPrice == null || price < s.minPrice! ? price : s.minPrice;
    s.maxPrice = s.maxPrice == null || price > s.maxPrice! ? price : s.maxPrice;
    s.lines++;
  }
  final out = map.values.where((s) => s.qty != 0 || s.total != 0).toList()
    ..sort((a, b) => b.total != a.total ? b.total.compareTo(a.total) : a.name.compareTo(b.name));
  return out;
}
