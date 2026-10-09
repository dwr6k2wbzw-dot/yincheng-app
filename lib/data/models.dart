/// 資料模型（欄位名稱對應資料庫）
double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
double? _dn(dynamic v) => v == null ? null : _d(v);
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

enum Role { owner, manager, bartender, staff }

Role roleFrom(String s) => Role.values.firstWhere((r) => r.name == s, orElse: () => Role.staff);

String roleLabel(Role r) => switch (r) {
      Role.owner => '老闆',
      Role.manager => '店長',
      Role.bartender => '調酒師',
      Role.staff => '員工',
    };

class Membership {
  final String storeId;
  final String storeName;
  final Role role;
  final String displayName;
  Membership({required this.storeId, required this.storeName, required this.role, required this.displayName});

  bool get isManager => role == Role.owner || role == Role.manager;

  factory Membership.fromRow(Map<String, dynamic> r) => Membership(
        storeId: r['store_id'] as String,
        storeName: (r['stores'] as Map?)?['name'] as String? ?? '',
        role: roleFrom(r['role'] as String),
        displayName: r['display_name'] as String? ?? '',
      );
}

class MonthlySummary {
  final DateTime month;
  final double revenue;
  final int guests;
  final double? avgTicket;
  final double? dailyAvgTicket;
  final double drinksRevenue;
  final double foodRevenue;
  final double? targetAmount;
  final double? targetRate;
  final double? drinkCostRate;
  final double? foodCostRate;
  final double? totalCostRate;
  final bool hasCostRecords;
  MonthlySummary({
    required this.month,
    required this.revenue,
    required this.guests,
    this.avgTicket,
    this.dailyAvgTicket,
    required this.drinksRevenue,
    required this.foodRevenue,
    this.targetAmount,
    this.targetRate,
    this.drinkCostRate,
    this.foodCostRate,
    this.totalCostRate,
    this.hasCostRecords = false,
  });
}

class DailyRevenue {
  final DateTime date;
  final double revenue;
  final int guests;
  DailyRevenue(this.date, this.revenue, this.guests);
}

class Issue {
  final String checkName;
  final String severity; // error / warning / info
  final String detail;
  Issue(this.checkName, this.severity, this.detail);
}

class CostCategory {
  final String code;
  final String name;
  CostCategory(this.code, this.name);
}

class Supplier {
  final String id;
  final String name;
  final String? defaultCategory;
  Supplier(this.id, this.name, this.defaultCategory);
}

class Purchase {
  final String id;
  final DateTime purchaseDate;
  final String categoryCode;
  final String? supplierName;
  final String? memo;
  final double amount;
  final String paidBy; // vendor / petty_cash
  final bool reconciled;
  final String source; // app / import
  Purchase({
    required this.id,
    required this.purchaseDate,
    required this.categoryCode,
    this.supplierName,
    this.memo,
    required this.amount,
    required this.paidBy,
    required this.reconciled,
    required this.source,
  });

  factory Purchase.fromRow(Map<String, dynamic> r) => Purchase(
        id: r['id'] as String,
        purchaseDate: _date(r['purchase_date'])!,
        categoryCode: r['category_code'] as String,
        supplierName: (r['suppliers'] as Map?)?['name'] as String?,
        memo: r['memo'] as String?,
        amount: _d(r['amount']),
        paidBy: r['paid_by'] as String,
        reconciled: r['reconciled'] as bool? ?? false,
        source: r['source'] as String? ?? 'app',
      );
}

class NewPurchase {
  final String storeId;
  final DateTime purchaseDate;
  final String categoryCode;
  final String? supplierId;
  final String? memo;
  final double amount;
  final String paidBy;
  final String clientRequestId; // 防止網路重送造成重複
  NewPurchase({
    required this.storeId,
    required this.purchaseDate,
    required this.categoryCode,
    this.supplierId,
    this.memo,
    required this.amount,
    required this.paidBy,
    required this.clientRequestId,
  });
}

class Product {
  final String id;
  final String name;
  final String category;
  final String unit;
  Product(this.id, this.name, this.category, this.unit);
}

enum CountStatus { draft, submitted, approved, rejected, voided }

String countStatusLabel(CountStatus s) => switch (s) {
      CountStatus.draft => '草稿',
      CountStatus.submitted => '待核准',
      CountStatus.approved => '已核准',
      CountStatus.rejected => '已退回',
      CountStatus.voided => '已作廢',
    };

class StockCount {
  final String id;
  final DateTime bizDate;
  final String countedBy;
  final CountStatus status;
  final String? note;
  final int lineCount;
  StockCount({
    required this.id,
    required this.bizDate,
    required this.countedBy,
    required this.status,
    this.note,
    required this.lineCount,
  });

  factory StockCount.fromRow(Map<String, dynamic> r) => StockCount(
        id: r['id'] as String,
        bizDate: _date(r['biz_date'])!,
        countedBy: r['counted_by'] as String,
        status: CountStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => CountStatus.draft),
        note: r['note'] as String?,
        lineCount: ((r['stock_count_lines'] as List?)?.isNotEmpty ?? false)
            ? ((r['stock_count_lines'] as List).first as Map)['count'] as int? ?? 0
            : 0,
      );
}

class CountLine {
  final String productId;
  final String productName;
  final String unit;
  final double qty;
  CountLine(this.productId, this.productName, this.unit, this.qty);
}

MonthlySummary summaryFromRows(Map<String, dynamic>? rev, Map<String, dynamic>? cost, DateTime month) => MonthlySummary(
      month: month,
      revenue: _d(rev?['revenue']),
      guests: (_d(rev?['guests'])).round(),
      avgTicket: _dn(rev?['avg_ticket']),
      dailyAvgTicket: _dn(rev?['daily_avg_ticket']),
      drinksRevenue: _d(rev?['drinks_revenue']),
      foodRevenue: _d(rev?['food_revenue']),
      targetAmount: _dn(rev?['target_amount']),
      targetRate: _dn(rev?['target_rate']),
      drinkCostRate: _dn(cost?['drink_cost_rate']),
      foodCostRate: _dn(cost?['food_cost_rate']),
      totalCostRate: _dn(cost?['total_cost_rate']),
      hasCostRecords: cost?['has_cost_records'] as bool? ?? false,
    );

DailyRevenue dailyFromRow(Map<String, dynamic> r) =>
    DailyRevenue(_date(r['biz_date'])!, _d(r['revenue']), (_d(r['guests'])).round());

double toDouble(dynamic v) => _d(v);
DateTime? toDate(dynamic v) => _date(v);
