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
  final double projectAmount; // 專案（另計收入，Excel 計成本率時併入酒水）
  final double cash; // 收款：現金
  final double card; // 收款：刷卡（信用卡＋AE卡）
  final double deposit; // 收款：訂金
  final double coffeeRevenue; // 小城外：咖啡
  final double ramenRevenue; // 小城外：拉麵
  final double? targetAmount;
  final double? targetRate;
  final double? drinkCostRate;
  final double? foodCostRate;
  final double? totalCostRate;
  final double? miscCostRate; // 雜項成本率（不計入總進貨）
  final double purchaseCost; // 損益用進貨金額：酒水＋餐食，但不含計入雜項的類別（酒水副材料-雜項只算雜項）
  final double miscCost; // 雜項總金額（零用金-其他雜支＋酒水副材料-雜項）
  final bool hasCostRecords;
  MonthlySummary({
    required this.month,
    required this.revenue,
    required this.guests,
    this.avgTicket,
    this.dailyAvgTicket,
    required this.drinksRevenue,
    required this.foodRevenue,
    this.projectAmount = 0,
    this.cash = 0,
    this.card = 0,
    this.deposit = 0,
    this.coffeeRevenue = 0,
    this.ramenRevenue = 0,
    this.targetAmount,
    this.targetRate,
    this.drinkCostRate,
    this.foodCostRate,
    this.totalCostRate,
    this.miscCostRate,
    this.purchaseCost = 0,
    this.miscCost = 0,
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
      projectAmount: _d(rev?['project_amount']),
      cash: _d(rev?['cash']),
      card: _d(rev?['credit_card']) + _d(rev?['amex']),
      deposit: _d(rev?['deposit']),
      coffeeRevenue: _d(rev?['coffee_revenue']),
      ramenRevenue: _d(rev?['ramen_revenue']),
      targetAmount: _dn(rev?['target_amount']),
      targetRate: _dn(rev?['target_rate']),
      drinkCostRate: _dn(cost?['drink_cost_rate']),
      foodCostRate: _dn(cost?['food_cost_rate']),
      totalCostRate: _dn(cost?['total_cost_rate']),
      miscCostRate: _dn(cost?['misc_cost_rate']),
      purchaseCost: _d(cost?['purchase_cost_excl_misc']),
      miscCost: _d(cost?['misc_cost']),
      hasCostRecords: cost?['has_cost_records'] as bool? ?? false,
    );

DailyRevenue dailyFromRow(Map<String, dynamic> r) =>
    DailyRevenue(_date(r['biz_date'])!, _d(r['revenue']), (_d(r['guests'])).round());

double toDouble(dynamic v) => _d(v);
DateTime? toDate(dynamic v) => _date(v);

/// 一天的營收（對應 daily_revenue 的一列，kind = daily）
class RevenueEntry {
  final String? id; // null：新的一天
  final DateTime bizDate;
  final double cash;
  final double creditCard;
  final double amex;
  final double deposit; // 訂金
  final int guests;
  final double drinks;
  final double food;
  final double project; // 專案（成本率計算時併入酒水，與 Excel 相同）
  final double coffee; // 小城外：咖啡
  final double ramen; // 小城外：拉麵
  final String? note;
  final String source; // app / import
  RevenueEntry({
    this.id,
    required this.bizDate,
    this.cash = 0,
    this.creditCard = 0,
    this.amex = 0,
    this.deposit = 0,
    this.guests = 0,
    this.drinks = 0,
    this.food = 0,
    this.project = 0,
    this.coffee = 0,
    this.ramen = 0,
    this.note,
    this.source = 'app',
  });

  /// 收款合計（＝資料庫的 revenue）
  double get received => cash + creditCard + amex + deposit;

  /// 營業收入明細合計
  double get detailTotal => drinks + food + project + coffee + ramen;

  factory RevenueEntry.fromRow(Map<String, dynamic> r) => RevenueEntry(
        id: r['id'] as String,
        bizDate: _date(r['biz_date'])!,
        cash: _d(r['cash']),
        creditCard: _d(r['credit_card']),
        amex: _d(r['amex']),
        deposit: _d(r['deposit']),
        guests: _d(r['guests']).round(),
        drinks: _d(r['drinks_revenue']),
        food: _d(r['food_revenue']),
        project: _d(r['project_amount']),
        coffee: _d(r['coffee_revenue']),
        ramen: _d(r['ramen_revenue']),
        note: r['note'] as String?,
        source: r['source'] as String? ?? 'app',
      );

  Map<String, dynamic> toValues() => {
        'cash': cash,
        'credit_card': creditCard,
        'amex': amex,
        'deposit': deposit,
        'guests': guests,
        'drinks_revenue': drinks,
        'food_revenue': food,
        'project_amount': project,
        'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      };
}

/// 某月的租金與人事成本（老闆手動輸入；null＝尚未輸入）
class FixedCosts {
  final double? rent;
  final double? payroll;
  const FixedCosts({this.rent, this.payroll});
}

/// 成員管理：店家成員（含 Email，只有老闆看得到）
class MemberInfo {
  final String userId;
  final String displayName;
  final Role role;
  final bool active;
  final String email;
  MemberInfo({required this.userId, required this.displayName, required this.role, required this.active, required this.email});
  factory MemberInfo.fromRow(Map<String, dynamic> r) => MemberInfo(
        userId: r['user_id'] as String,
        displayName: r['display_name'] as String? ?? '',
        role: roleFrom(r['role'] as String),
        active: r['active'] as bool? ?? true,
        email: r['email'] as String? ?? '',
      );
}

/// 成員管理：還沒被使用的邀請
class MemberInvite {
  final String id;
  final String displayName;
  final Role role;
  final DateTime createdAt;
  final DateTime expiresAt;
  MemberInvite({required this.id, required this.displayName, required this.role, required this.createdAt, required this.expiresAt});
  bool get expired => expiresAt.isBefore(DateTime.now());
  factory MemberInvite.fromRow(Map<String, dynamic> r) => MemberInvite(
        id: r['id'] as String,
        displayName: r['display_name'] as String? ?? '',
        role: roleFrom(r['role'] as String),
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        expiresAt: DateTime.parse(r['expires_at'] as String).toLocal(),
      );
}
