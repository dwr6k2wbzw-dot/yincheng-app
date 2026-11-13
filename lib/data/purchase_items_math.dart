// 進貨品項明細的計算（0087，老闆 2026-11-01：拍照辨識送貨單 → 品項）
// 老闆 2026-11-13：新增進貨的畫面不再顯示品項明細，照片讀到的品項在背後存起來，用來更新「進貨報價」。
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

bool isDiffLine(String name) => name == diffItemName;

/// 已存的明細讀回來時，把「其他差額」那一行拿掉（存檔時重新算）
List<PurchaseItem> withoutDiffLine(List<PurchaseItem> items) => [for (final it in items) if (!isDiffLine(it.name)) it];

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_.·・()（）/]'), '');

// ---------------- 進貨報價（老闆 2026-11-13：本月進貨總表改成進貨報價）----------------
// 每個品項最近一次的進貨單價，分酒類、餐食（雜項不列）。資料來自進貨的品項明細；
// 老闆、店長可以手動改品名／單位／單價，或把某一項拿掉（purchase_quote_edits，0105）。

/// 報價的品項鍵：品名（去空白、符號、不分大小寫）＋單位。手動修改也用這個鍵對回去。
String quoteKey(String name, String? unit) => '${_norm(name)}|${(unit ?? '').trim()}';

/// 進貨品項明細的一行（帶上那筆進貨的日期、廠商、類別）
class QuoteLine {
  const QuoteLine({required this.name, this.unit, required this.unitPrice, required this.qty, required this.date,
      this.at, this.vendor, required this.categoryCode});
  final String name;
  final String? unit;
  final double? unitPrice;
  final double qty; // 退貨是負數（不拿來當報價）
  final DateTime date;
  final DateTime? at; // 那筆進貨登記的時間（同一天進兩次時分先後）
  final String? vendor;
  final String categoryCode;
}

/// 手動改過的報價（purchase_quote_edits）
class QuoteEdit {
  const QuoteEdit(
      {required this.key,
      this.name,
      this.unit,
      this.unitPrice,
      this.asOf,
      this.asOfAt,
      this.hidden = false,
      this.by,
      this.group,
      this.manual = false});
  final String key;
  final String? name;
  final String? unit;
  final double? unitPrice;
  final DateTime? asOf; // 改價當時最新一筆進貨的日期
  final DateTime? asOfAt; // …和那筆進貨登記的時間（同一天後來又進一次，手動改的單價也要讓位；Codex 審查）
  final bool hidden;
  final String? by;
  final String? group; // 搬到哪一類（drink／food／misc；null＝照進貨類別，0107）
  final bool manual; // 手動新增的品項（品項鍵 manual: 開頭，0107）

  /// 拿掉（hidden）：品名、單位、類別這些修改照樣留著，放回去時還在
  QuoteEdit copyWithHidden([bool hidden = true]) => QuoteEdit(
      key: key, name: name, unit: unit, unitPrice: unitPrice, asOf: asOf, asOfAt: asOfAt,
      hidden: hidden, by: by, group: group, manual: manual);
  /// 除了「拿掉」以外有沒有其他修改
  bool get hasChanges => name != null || unit != null || unitPrice != null || group != null;

  QuoteEdit copyWith({String? group}) => QuoteEdit(
      key: key, name: name, unit: unit, unitPrice: unitPrice, asOf: asOf, asOfAt: asOfAt,
      hidden: hidden, by: by, group: group ?? this.group, manual: manual);
}

const quoteGroups = [('drink', '酒類'), ('food', '餐食'), ('misc', '雜項')];
String quoteGroupLabel(String g) => quoteGroups.firstWhere((x) => x.$1 == g, orElse: () => (g, g)).$2;

/// 報價表的一列
class ItemQuote {
  ItemQuote({required this.key, required this.name, required this.unit, required this.group, required this.price,
      required this.date, this.at, this.vendor, this.previous, this.manual = false, this.edited = false, this.hidden = false,
      required this.rawName, required this.rawUnit, required this.rawPrice, this.custom = false, this.edit});
  final String key;
  final String name;
  final String? unit;
  final String group; // drink 酒類／food 餐食／misc 雜項
  final double price;
  final DateTime date; // 最近一次進貨的日期
  final DateTime? at; // 最近一次進貨登記的時間
  final String? vendor;
  final double? previous; // 上一次不同的進貨單價（漲跌用）
  final bool manual; // 現在顯示的單價是手動改的
  final bool edited; // 有手動改過（品名、單位或單價）
  final bool hidden; // 已經從報價表拿掉
  final String rawName; // 進貨資料上的品名、單位、單價（還原用）
  final String? rawUnit;
  final double rawPrice;
  final bool custom; // 手動新增的（不是從進貨算出來的）
  final QuoteEdit? edit; // 目前的手動修改（搬移類別時保留其他修改用）
}

/// 把品項明細整理成報價表。groupOf：進貨類別代碼 → drink／food／其他（其他不列）。
/// 單價：最近一次進貨（同一天照登記時間，取後面那一行）；手動改的單價在「之後沒有更新的進貨」時才算數
/// （之後＝進貨日期比較新，或同一天但登記得比較晚）。
/// 回傳含已拿掉的（hidden），畫面自己分開顯示；單價高到低排（一樣價錢照品名）。
/// 0107：手動搬過的照搬過去的類別（可以搬到雜項）；手動新增的品項（manual）也列進來。
/// 從進貨自動帶進來的只有酒類、餐食（老闆 2026-11-13「雜項品項不用列」）。
List<ItemQuote> buildQuotes(Iterable<QuoteLine> lines, Iterable<QuoteEdit> edits, String? Function(String code) groupOf) {
  final byKey = <String, List<QuoteLine>>{};
  for (final l in lines) {
    final price = l.unitPrice;
    if (isDiffLine(l.name) || l.name.trim().isEmpty || l.qty <= 0 || price == null || price <= 0) continue;
    final g = groupOf(l.categoryCode);
    if (g != 'drink' && g != 'food') continue;
    byKey.putIfAbsent(quoteKey(l.name, l.unit), () => []).add(l);
  }
  final editOf = {for (final e in edits) e.key: e};
  final out = <ItemQuote>[];
  for (final e in byKey.entries) {
    final list = e.value; // 依日期舊→新（同一天照登記時間，再照原本順序）
    final sorted = [
      for (var i = 0; i < list.length; i++) (i, list[i])
    ]..sort((a, b) {
        var c = a.$2.date.compareTo(b.$2.date);
        if (c == 0 && a.$2.at != null && b.$2.at != null) c = a.$2.at!.compareTo(b.$2.at!);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    final last = sorted.last.$2;
    final lastPrice = round2(last.unitPrice!);
    double? prev;
    for (final x in sorted.reversed.skip(1)) {
      if (round2(x.$2.unitPrice!) != lastPrice) {
        prev = round2(x.$2.unitPrice!);
        break;
      }
    }
    final ed = editOf[e.key];
    final newer = ed?.asOf != null &&
        (last.date.isAfter(ed!.asOf!) ||
            (!last.date.isBefore(ed.asOf!) && ed.asOfAt != null && last.at != null && last.at!.isAfter(ed.asOfAt!)));
    final manual = ed?.unitPrice != null && !newer;
    final unit = last.unit?.trim().isEmpty ?? true ? null : last.unit!.trim();
    final edUnit = ed?.unit?.trim().isEmpty ?? true ? null : ed!.unit!.trim();
    out.add(ItemQuote(
      key: e.key,
      name: ed?.name?.trim().isNotEmpty ?? false ? ed!.name!.trim() : last.name.trim(),
      unit: edUnit ?? unit,
      group: ed?.group ?? groupOf(last.categoryCode)!,
      price: manual ? round2(ed!.unitPrice!) : lastPrice,
      date: last.date,
      at: last.at,
      vendor: last.vendor,
      previous: manual ? (round2(ed!.unitPrice!) == lastPrice ? null : lastPrice) : prev,
      manual: manual,
      edited: ed != null && !ed.hidden && (ed.name != null || ed.unit != null || manual || ed.group != null),
      hidden: ed?.hidden ?? false,
      rawName: last.name.trim(),
      rawUnit: unit,
      rawPrice: lastPrice,
      edit: ed,
    ));
  }
  for (final ed in edits) {
    if (!ed.manual || ed.name == null || ed.unitPrice == null) continue;
    final day = ed.asOf ?? DateTime(2000);
    final unit = ed.unit?.trim().isEmpty ?? true ? null : ed.unit!.trim();
    out.add(ItemQuote(
      key: ed.key,
      name: ed.name!.trim(),
      unit: unit,
      group: ed.group ?? 'misc',
      price: round2(ed.unitPrice!),
      date: day,
      at: ed.asOfAt,
      rawName: ed.name!.trim(),
      rawUnit: unit,
      rawPrice: round2(ed.unitPrice!),
      custom: true,
      edit: ed,
    ));
  }
  // 單價高的在上面（老闆 2026-11-13 18:37）；一樣價錢照品名
  out.sort((a, b) => a.price != b.price ? b.price.compareTo(a.price) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// 進貨類別代碼 → 報價表的分區（drink 酒類／food 餐食；其他不列）。照進貨頁合併後的類別判斷（0047／0048）
String? Function(String) quoteGroupOf(List<CostCategory> cats) {
  final by = {for (final c in cats) c.code: c};
  return (code) {
    final c = by[by[code]?.displayAs ?? code] ?? by[code];
    return switch (c?.costGroup) {
      'drink' => 'drink',
      'food' || 'coffee' || 'ramen' => 'food',
      _ => null,
    };
  };
}

/// 複製成日報表那一列：日期、類別、摘要、金額（用 Tab 分開，貼到日報表「日期」那一格會分到四格）。
/// 兩家店的日報表 9 月起都是 B 日期、C 類別、D 摘要、E 金額（月結、零用金相同）。
String dailyReportRow(DateTime date, String category, String memo, double amount) => [
      '${date.month}/${date.day}',
      category,
      memo.trim(),
      amount == amount.roundToDouble() ? amount.toInt().toString() : amount.toStringAsFixed(2),
    ].join('\t');
