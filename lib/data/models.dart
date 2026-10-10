import 'dart:typed_data';

/// 資料模型（欄位名稱對應資料庫）
double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
double? _dn(dynamic v) => v == null ? null : _d(v);
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

enum Role { owner, manager, bartender, staff, parttime }

Role roleFrom(String s) => Role.values.firstWhere((r) => r.name == s, orElse: () => Role.staff);

String roleLabel(Role r) => switch (r) {
      Role.owner => '老闆',
      Role.manager => '店長',
      Role.bartender => '調酒師',
      Role.staff => '正職',
      Role.parttime => '兼職',
    };

class Membership {
  final String storeId;
  final String storeName;
  final Role role;
  final String displayName;
  Membership({required this.storeId, required this.storeName, required this.role, required this.displayName});

  bool get isManager => role == Role.owner || role == Role.manager;
  /// 看得到營收：老闆、店長、員工（員工只能看，資料庫 0020）；調酒師看不到
  bool get canSeeRevenue => isManager || role == Role.staff;
  /// 兼職：只看得到班表與交接、提醒（資料庫 0033）
  bool get isPartTime => role == Role.parttime;

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
  final double drinkCost; // 酒水進貨金額
  final double foodCost; // 餐食進貨金額
  final double totalCost; // 總進貨金額（酒水＋餐食＋咖啡＋拉麵，與總進貨成本率同一算法）
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
    this.drinkCost = 0,
    this.foodCost = 0,
    this.totalCost = 0,
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
  final String? storeName; // 這個類別屬於哪家店（隱城／小城外）
  CostCategory(this.code, this.name, [this.storeName]);
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
  final String? supersededBy; // App 暫記已被 Excel 同一筆取代（不再計入）
  final bool excelCovered; // App 暫記：日報表已涵蓋那天，以日報表為準（不再計入，0035）
  final String? createdBy;
  bool get superseded => supersededBy != null;
  /// 有沒有計入成本、零用金（被 Excel 取代或以日報表為準的 App 暫記不計入）
  bool get counted => supersededBy == null && !excelCovered;
  bool get fromExcel => source == 'import';
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
    this.supersededBy,
    this.excelCovered = false,
    this.createdBy,
  });

  factory Purchase.fromRow(Map<String, dynamic> r) => Purchase(
        id: r['id'] as String,
        purchaseDate: _date(r['purchase_date'])!,
        categoryCode: r['category_code'] as String,
        supplierName: (r['suppliers'] as Map?)?['name'] as String? ?? r['vendor_name'] as String?,
        memo: r['memo'] as String?,
        amount: _d(r['amount']),
        paidBy: r['paid_by'] as String,
        reconciled: r['reconciled'] as bool? ?? false,
        source: r['source'] as String? ?? 'app',
        supersededBy: r['superseded_by'] as String?,
        excelCovered: r['excel_covered_at'] != null,
        createdBy: r['created_by'] as String?,
      );
}

class NewPurchase {
  final String storeId;
  final DateTime purchaseDate;
  final String categoryCode;
  final String? supplierId;
  final String? vendorName; // 自行輸入的廠商名稱（不是既有廠商時）
  final String? memo;
  final double amount;
  final String paidBy;
  final String clientRequestId; // 防止網路重送造成重複
  final Uint8List? photoJpeg; // 送貨單照片（存到 receipts/{店家}/slips/）
  final bool slipDraft; // 照片要不要辨識成銷貨單草稿（有銷貨單分頁的店）
  final String? slipVendor; // 銷貨單草稿用的廠商名稱（選既有廠商時也帶名稱）
  NewPurchase({
    required this.storeId,
    required this.purchaseDate,
    required this.categoryCode,
    this.supplierId,
    this.vendorName,
    this.memo,
    required this.amount,
    required this.paidBy,
    required this.clientRequestId,
    this.photoJpeg,
    this.slipDraft = false,
    this.slipVendor,
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
      drinkCost: _d(cost?['drink_cost']),
      foodCost: _d(cost?['food_cost']),
      totalCost: _d(cost?['drink_cost']) + _d(cost?['food_cost']) + _d(cost?['coffee_cost']) + _d(cost?['ramen_cost']),
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

/// 廠商銷貨單（小城外：掃描單據整理；只是明細參考，不影響成本率）
class VendorSlipLine {
  final int lineNo;
  final String? itemCode;
  final String itemName;
  final double qty;
  final String? unit;
  final double? unitPrice;
  final double amount;
  VendorSlipLine(this.lineNo, this.itemCode, this.itemName, this.qty, this.unit, this.unitPrice, this.amount);
}

class VendorSlip {
  final String id;
  final String vendor;
  final String slipNo;
  final DateTime date;
  final double total;
  final String? note;
  final List<VendorSlipLine> lines;
  final String status; // draft＝文字辨識草稿待確認、confirmed＝已確認
  final String source; // manual／ocr／app
  final String? sourceFile;
  final DateTime? periodMonth; // 歸屬月份（Dropbox「M月份」資料夾）；修改時 null＝維持原本
  final String? photoPath; // App 拍的送貨單照片（0034）
  VendorSlip(this.id, this.vendor, this.slipNo, this.date, this.total, this.note, this.lines,
      {this.status = 'confirmed', this.source = 'manual', this.sourceFile, this.periodMonth, this.photoPath});
  bool get isDraft => status == 'draft';
  double get linesTotal => lines.fold(0.0, (a, l) => a + l.amount);
  factory VendorSlip.fromRow(Map<String, dynamic> r) => VendorSlip(
        r['id'] as String,
        r['vendor'] as String,
        r['slip_no'] as String,
        _date(r['slip_date'])!,
        _d(r['total']),
        r['note'] as String?,
        ((r['vendor_slip_lines'] as List?) ?? [])
            .map((l) => VendorSlipLine(
                  (l['line_no'] as num).toInt(),
                  l['item_code'] as String?,
                  l['item_name'] as String,
                  _d(l['qty']),
                  l['unit'] as String?,
                  l['unit_price'] == null ? null : _d(l['unit_price']),
                  _d(l['amount']),
                ))
            .toList()
          ..sort((a, b) => a.lineNo.compareTo(b.lineNo)),
        status: r['status'] as String? ?? 'confirmed',
        source: r['source'] as String? ?? 'manual',
        sourceFile: r['source_file'] as String?,
        photoPath: r['photo_path'] as String?,
      );
}


/// 從進貨紀錄統計各類別常用廠商：廠商資料的名稱 > 自行輸入的名稱 > 摘要「廠商(品項)」括號前的名稱 >
/// 出現 2 次以上、像店名的摘要。每類取次數最多的 4 個
Map<String, List<String>> vendorHintsFromRows(List<Map<String, dynamic>> rows) {
  final strong = <String, Map<String, int>>{}; // 確定是廠商
  final weak = <String, Map<String, int>>{}; // 可能是品項，出現 2 次以上才採用
  for (final r in rows) {
    final cat = r['category_code'] as String;
    final sup = (r['suppliers'] as Map?)?['name'] as String?;
    final vn = r['vendor_name'] as String?;
    final memo = (r['memo'] as String?)?.trim() ?? '';
    String? name;
    var sure = true;
    if (sup != null && sup.isNotEmpty) {
      name = sup;
    } else if (vn != null && vn.trim().isNotEmpty) {
      name = vn.trim();
    } else {
      final m = RegExp(r'^([^()（）]{2,10})\s*[(（]').firstMatch(memo);
      if (m != null) {
        name = m.group(1)!.trim();
      } else if (memo.length >= 2 && memo.length <= 8 && !RegExp(r'[\s.\d@*/]').hasMatch(memo)) {
        name = memo;
        sure = false;
      }
    }
    if (name == null) continue;
    // 「德哥(水果)」→「德哥」
    name = name.replaceAll(RegExp(r'\s*[(（].*$'), '').trim();
    if (name.length < 2) continue;
    final bucket = (sure ? strong : weak).putIfAbsent(cat, () => {});
    bucket[name] = (bucket[name] ?? 0) + 1;
  }
  final out = <String, List<String>>{};
  for (final cat in {...strong.keys, ...weak.keys}) {
    final counts = <String, int>{...?strong[cat]};
    weak[cat]?.forEach((k, v) {
      if (v >= 2 && !counts.containsKey(k)) counts[k] = v;
    });
    final list = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (list.isNotEmpty) out[cat] = list.take(4).map((e) => e.key).toList();
  }
  return out;
}

/// 班表上的人（正職 full／兼職 part）
class ShiftPerson {
  final String id;
  final String name;
  final String kind; // full / part
  final int sortOrder;
  final DateTime? hireDate;
  final bool active;
  final String? roleCode; // 班別（例 B／R）
  ShiftPerson(
      {required this.id, required this.name, this.kind = 'full', this.sortOrder = 0, this.hireDate, this.active = true, this.roleCode});
  bool get isFull => kind == 'full';
  factory ShiftPerson.fromRow(Map<String, dynamic> r) => ShiftPerson(
        id: r['id'] as String,
        name: r['name'] as String,
        kind: r['kind'] as String? ?? 'full',
        sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0,
        hireDate: _date(r['hire_date']),
        active: r['active'] as bool? ?? true,
        roleCode: r['role_code'] as String?,
      );
}

/// 每人每月手動填的數字
class ShiftStats {
  final double? shouldOff; // 本月應休
  final double? prevUnused; // 原未休特休
  final double? compUnused; // 未休／補休（小城外）
  final double? specialTotal; // 累計特休（小城外）
  const ShiftStats({this.shouldOff, this.prevUnused, this.compUnused, this.specialTotal});
}

/// 一個月的班表
class ShiftMonth {
  final DateTime month;
  final List<ShiftPerson> people;
  final Map<String, Map<int, String>> marks; // 人 → 日 → 記號（V／休／指休／O）
  final Map<int, String> notes; // 日 → 備註
  final Map<String, ShiftStats> stats; // 人 → 手動填的數字
  final String? photoPath;
  ShiftMonth(this.month, this.people, this.marks, this.notes, this.stats, this.photoPath);

  int get days => DateTime(month.year, month.month + 1, 0).day;
  String? mark(String personId, int day) => marks[personId]?[day];
  static bool isOff(String? m) => m == '休' || m == '指休';
  /// 有排班（V、O、班別代碼、時段）＝上班；休、指休、空白＝沒上班
  static bool isOn(String? m) => m != null && m.isNotEmpty && !isOff(m);
  static bool isRange(String? m) => m != null && m.contains(':') && m.contains('-');

  /// 一格的時數：時段照實際（過午夜算隔天）；班別代碼查表；其他 0
  static double hoursOf(String? m, Map<String, double> codeHours) {
    if (m == null) return 0;
    if (isRange(m)) {
      final p = m.split('-');
      double t(String s) {
        final x = s.split(':');
        return int.parse(x[0]) + int.parse(x[1]) / 60;
      }
      var a = t(p[0]), b = t(p[1]);
      if (b <= a) b += 24;
      return b - a;
    }
    return codeHours[m] ?? 0;
  }

  double hours(String personId, Map<String, double> codeHours, {int? throughDay}) => (marks[personId] ?? {})
      .entries
      .where((e) => throughDay == null || e.key <= throughDay)
      .fold(0.0, (a, e) => a + hoursOf(e.value, codeHours));
  /// 人力＝當天 V＋O 的人數
  int staffing(int day) => people.where((p) => isOn(mark(p.id, day))).length;
  int offDays(String personId) => (marks[personId] ?? {}).values.where(isOff).length;
  int workDays(String personId) => (marks[personId] ?? {}).values.where(isOn).length;
}

// ---------------- 交接事項與工作提醒（0031） ----------------

/// 營業日：早上 6 點前算前一天（酒吧凌晨還在營業）
DateTime bizToday([DateTime? now]) {
  final n = now ?? DateTime.now();
  final d = DateTime(n.year, n.month, n.day);
  return n.hour < 6 ? d.subtract(const Duration(days: 1)) : d;
}

class HandoverNote {
  final String id;
  final String body;
  final String? photoPath;
  final String authorId;
  final String authorName;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedName;
  final Map<String, String> readers; // userId → 名字
  HandoverNote({
    required this.id,
    required this.body,
    this.photoPath,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.resolvedAt,
    this.resolvedName,
    this.readers = const {},
  });
  bool get resolved => resolvedAt != null;
  /// 對我來說是未讀：不是我寫的、我沒讀過、還沒處理
  bool unreadFor(String? me) => !resolved && me != null && authorId != me && !readers.containsKey(me);

  factory HandoverNote.fromRow(Map<String, dynamic> r) => HandoverNote(
        id: r['id'] as String,
        body: r['body'] as String,
        photoPath: r['photo_path'] as String?,
        authorId: r['author_id'] as String,
        authorName: r['author_name'] as String? ?? '',
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        resolvedAt: r['resolved_at'] == null ? null : DateTime.parse(r['resolved_at'] as String).toLocal(),
        resolvedName: r['resolved_name'] as String?,
        readers: {
          for (final x in (r['handover_reads'] as List? ?? const []))
            (x as Map)['user_id'] as String: x['user_name'] as String? ?? '',
        },
      );
}

class WorkReminder {
  final String id;
  final String title;
  final String? detail;
  final String repeat; // once / daily / weekly / monthly
  final DateTime? dueDate;
  final int? weekday; // 0＝週日
  final int? monthDay;
  final DateTime startDate;
  final String? assignPersonId;
  final bool assignOnShift;
  final bool active;
  WorkReminder({
    required this.id,
    required this.title,
    this.detail,
    required this.repeat,
    this.dueDate,
    this.weekday,
    this.monthDay,
    required this.startDate,
    this.assignPersonId,
    this.assignOnShift = false,
    this.active = true,
  });

  factory WorkReminder.fromRow(Map<String, dynamic> r) => WorkReminder(
        id: r['id'] as String,
        title: r['title'] as String,
        detail: r['detail'] as String?,
        repeat: r['repeat'] as String,
        dueDate: r['due_date'] == null ? null : DateTime.parse(r['due_date'] as String),
        weekday: (r['weekday'] as num?)?.toInt(),
        monthDay: (r['month_day'] as num?)?.toInt(),
        startDate: DateTime.parse(r['start_date'] as String),
        assignPersonId: r['assign_person_id'] as String?,
        assignOnShift: r['assign_on_shift'] as bool? ?? false,
        active: r['active'] as bool? ?? true,
      );

  static const weekdayNames = ['日', '一', '二', '三', '四', '五', '六'];

  String get repeatLabel => switch (repeat) {
        'daily' => '每天',
        'weekly' => '每週${weekdayNames[weekday ?? 0]}',
        'monthly' => '每月 $monthDay 號',
        _ => dueDate == null ? '一次' : '${dueDate!.month}/${dueDate!.day}',
      };

  /// 到 today 為止最近的一次（還沒開始、或一次性的日子還沒到 → null）
  DateTime? lastOccurrence(DateTime today) {
    DateTime? d;
    switch (repeat) {
      case 'once':
        d = dueDate;
        if (d != null && d.isAfter(today)) return null;
        return d; // 一次性的不受開始日限制
      case 'daily':
        d = today;
      case 'weekly':
        d = today.subtract(Duration(days: (today.weekday % 7 - (weekday ?? 0) + 7) % 7));
      case 'monthly':
        DateTime inMonth(int y, int m) {
          final last = DateTime(y, m + 1, 0).day;
          return DateTime(y, m, (monthDay ?? 1).clamp(1, last));
        }
        d = inMonth(today.year, today.month);
        if (d.isAfter(today)) d = inMonth(today.year, today.month - 1);
    }
    if (d == null || d.isBefore(DateTime(startDate.year, startDate.month, startDate.day))) return null;
    return d;
  }

  /// 下一次（今天之後）；一次性的已過就是 null
  DateTime? nextOccurrence(DateTime today) {
    for (var i = 1; i <= 62; i++) {
      final d = today.add(Duration(days: i));
      final ok = switch (repeat) {
        'once' => dueDate != null && _same(dueDate!, d),
        'daily' => true,
        'weekly' => d.weekday % 7 == weekday,
        'monthly' => d.day == (monthDay ?? 1).clamp(1, DateTime(d.year, d.month + 1, 0).day),
        _ => false,
      };
      if (ok) return d;
    }
    return null;
  }

  static bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

class ReminderDone {
  final String reminderId;
  final DateTime occurrence;
  final String doneBy;
  final String doneName;
  final DateTime doneAt;
  ReminderDone(this.reminderId, this.occurrence, this.doneBy, this.doneName, this.doneAt);
  factory ReminderDone.fromRow(Map<String, dynamic> r) => ReminderDone(
        r['reminder_id'] as String,
        DateTime.parse(r['occurrence'] as String),
        r['done_by'] as String,
        r['done_name'] as String? ?? '',
        DateTime.parse(r['done_at'] as String).toLocal(),
      );
  String get key => '$reminderId|${occurrence.year}-${occurrence.month}-${occurrence.day}';
  static String keyOf(String id, DateTime d) => '$id|${d.year}-${d.month}-${d.day}';
}

/// 交接・提醒一次載入的資料
class HandoverBoard {
  final List<HandoverNote> notes;
  final List<WorkReminder> reminders;
  final Map<String, ReminderDone> done; // key → 完成紀錄
  final List<ShiftPerson> people;
  final Map<String, String?> todayMarks; // personId → 今天的班表記號
  HandoverBoard(this.notes, this.reminders, this.done, this.people, this.todayMarks);

  /// 今天要看的提醒：最近一次（今天或之前）還沒做的，或今天剛做完的
  List<(WorkReminder, DateTime, ReminderDone?)> todayItems(DateTime today) {
    final out = <(WorkReminder, DateTime, ReminderDone?)>[];
    for (final r in reminders.where((r) => r.active)) {
      final occ = r.lastOccurrence(today);
      if (occ == null) continue;
      final dn = done[ReminderDone.keyOf(r.id, occ)];
      if (dn != null && occ.isBefore(today)) continue; // 之前那次已做完 → 今天沒事
      out.add((r, occ, dn));
    }
    // 沒做的在前（過期的最前面），做完的在後
    out.sort((a, b) {
      int rank((WorkReminder, DateTime, ReminderDone?) x) => x.$3 != null ? 2 : (x.$2.isBefore(today) ? 0 : 1);
      return rank(a).compareTo(rank(b));
    });
    return out;
  }

  int pendingCount(DateTime today) => todayItems(today).where((x) => x.$3 == null).length;
  int unreadCount(String? me) => notes.where((n) => n.unreadFor(me)).length;
}
