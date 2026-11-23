// 損益表（會計科目格式，ops 0142，老闆 2026-11-23）：照科目加總，分成
// 營業收入／進貨成本／營業費用／本期淨利，順序固定；沒有金額的科目也列出來；
// 一個科目有多筆時，科目那一行是合計，下面逐筆列出明細。
// 只負責把數字排好（純 Dart，可測試）；Excel 排版在 services/pl_export.dart。

import 'models.dart';

class PlDetail {
  final String label;
  final double amount;
  const PlDetail(this.label, this.amount);
}

class PlAccountRow {
  final String name;
  final double amount;
  final String note; // 備註（這個科目底下每一筆的備註，用「；」接起來）
  final List<PlDetail> details; // 兩筆以上才有
  const PlAccountRow(this.name, this.amount, this.note, this.details);
}

class AccountStatement {
  final String title; // 例：小城外(一店)_10月份損益表
  final String sheetName;
  final String fileName;
  final List<PlDetail> revenue;
  final double revenueTotal;
  final List<PlDetail> purchase;
  final double purchaseTotal;
  final List<PlAccountRow> expenses;
  final double expenseTotal;
  final List<String> warnings;
  const AccountStatement({
    required this.title,
    required this.sheetName,
    required this.fileName,
    required this.revenue,
    required this.revenueTotal,
    required this.purchase,
    required this.purchaseTotal,
    required this.expenses,
    required this.expenseTotal,
    this.warnings = const [],
  });
  double get profit => revenueTotal - purchaseTotal - expenseTotal;
  double share(double v) => revenueTotal == 0 ? 0 : v / revenueTotal;
}

/// 一筆支出（還沒歸到科目）
class PlEntry {
  final String? accountId;
  final String? autoKind; // 自動進來的：payroll_base、rent_base、card_fee、purchase_misc
  final String label;
  final double amount;
  final String? note;
  const PlEntry({this.accountId, this.autoKind, required this.label, required this.amount, this.note});
}

/// 把支出照科目排好。找不到科目的（沒選、科目停用了、自動項目沒有對應的科目）放在最後「未選科目」，不會不見。
List<PlAccountRow> groupByAccount(List<PlAccount> accounts, List<PlEntry> entries) {
  final sorted = [...accounts]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final byId = {for (final a in sorted) a.id: a};
  final byAuto = {for (final a in sorted) if (a.autoKind != null) a.autoKind!: a};
  final buckets = <String, List<PlEntry>>{};
  final orphan = <PlEntry>[];
  for (final e in entries) {
    final a = e.accountId != null ? byId[e.accountId] : (e.autoKind != null ? byAuto[e.autoKind] : null);
    if (a == null) {
      if (e.amount != 0) orphan.add(e);
    } else {
      buckets.putIfAbsent(a.id, () => []).add(e);
    }
  }
  PlAccountRow row(String name, List<PlEntry> es) {
    final shown = es.where((e) => e.amount != 0).toList();
    return PlAccountRow(
      name,
      es.fold(0.0, (t, e) => t + e.amount),
      [for (final e in es) if ((e.note ?? '').trim().isNotEmpty) e.note!.trim()].join('；'),
      shown.length > 1 ? [for (final e in shown) PlDetail(e.label, e.amount)] : const [],
    );
  }

  return [
    // 停用的科目：有金額才列
    for (final a in sorted)
      if (a.active || (buckets[a.id] ?? const []).any((e) => e.amount != 0)) row(a.name, buckets[a.id] ?? const []),
    if (orphan.isNotEmpty) row('（未選科目）', orphan),
  ];
}

/// 營業收入：小城外（營收分四項的店）＝調酒／咖啡／拉麵（＋訂金）；其他店＝調酒／餐食。
/// 名稱照老闆的損益表（老闆 2026-11-23 附圖；App 畫面上小城外的「調酒」叫「酒吧」）。合計一律＝當月營收。
List<PlDetail> revenueLines(MonthlySummary s, {required bool multiLine}) {
  final lines = multiLine
      ? [
          PlDetail('調酒收入', s.drinksRevenue + s.foodRevenue + s.projectAmount),
          PlDetail('咖啡收入', s.coffeeRevenue),
          PlDetail('拉麵收入', s.ramenRevenue),
          if (s.deposit != 0) PlDetail('訂金收入', s.deposit),
        ]
      : [
          PlDetail('調酒收入', s.drinksRevenue),
          PlDetail('餐食收入', s.foodRevenue),
          if (s.projectAmount != 0) PlDetail('專案收入', s.projectAmount),
        ];
  final rest = s.revenue - lines.fold(0.0, (t, l) => t + l.amount);
  return [...lines, if (rest.round() != 0) PlDetail('其他收入', rest)];
}

/// 進貨成本：酒水、餐食（不含算進雜項的類別；雜項類進貨在「其他費用-雜項」）
List<PlDetail> purchaseLines(MonthlySummary s) {
  final rest = s.purchaseCost - s.drinkCost - s.foodCost;
  return [
    PlDetail('酒水', s.drinkCost),
    PlDetail('餐食', s.foodCost),
    if (rest.round() != 0) PlDetail('其他進貨', rest),
  ];
}

String plTitle(String storeLabel, DateTime month) => '${storeLabel}_${month.month}月份損益表';

/// 組出整張損益表（跟總覽「本月損益」卡片同一算法：營收 − 進貨（不含雜項類）− 雜項 − 租金 − 人事）
AccountStatement accountStatementOf({
  required List<PlAccount> accounts,
  required String storeLabel,
  required String storeName,
  required DateTime month,
  required MonthlySummary summary,
  required bool multiLineRevenue,
  required double? payrollBase,
  String payrollBaseLabel = '人事（基底）',
  required double? rentBase,
  required double cardFee,
  String cardFeeLabel = '刷卡手續費',
  required List<ExpenseItem> items,
  required List<RecurringExpenseItem> recurring,
  List<String> warnings = const [],
}) {
  final entries = <PlEntry>[
    if (payrollBase != null) PlEntry(autoKind: 'payroll_base', label: payrollBaseLabel, amount: payrollBase),
    if (rentBase != null) PlEntry(autoKind: 'rent_base', label: '租金（基底）', amount: rentBase),
    if (cardFee != 0) PlEntry(autoKind: 'card_fee', label: cardFeeLabel, amount: cardFee),
    PlEntry(autoKind: 'purchase_misc', label: '雜項類進貨', amount: summary.miscCost),
    for (final it in recurring)
      PlEntry(accountId: it.accountId, label: it.name, amount: it.amountFor(month), note: it.note),
    for (final it in items) PlEntry(accountId: it.accountId, label: it.name, amount: it.amount, note: it.note),
  ];
  final rows = groupByAccount(accounts, entries);
  final m = month.month.toString().padLeft(2, '0');
  return AccountStatement(
    title: plTitle(storeLabel, month),
    sheetName: '損益表',
    fileName: '${storeName}_損益表_${month.year}-$m.xlsx',
    revenue: revenueLines(summary, multiLine: multiLineRevenue),
    revenueTotal: summary.revenue,
    purchase: purchaseLines(summary),
    purchaseTotal: summary.purchaseCost,
    expenses: rows,
    expenseTotal: entries.fold(0.0, (t, e) => t + e.amount),
    warnings: warnings,
  );
}
