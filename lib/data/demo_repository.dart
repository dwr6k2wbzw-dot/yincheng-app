import 'dart:async';

import 'models.dart';
import 'repository.dart';

/// 示範資料：不連線，數字全部是虛構的示範值（不是真實營收），只用來看畫面與操作流程。
/// 登入任何帳號都會以「老闆」身分進入；帳號含 staff 則以員工身分進入（可測試權限差異）。
class DemoRepository implements Repository {
  final _auth = StreamController<bool>.broadcast();
  bool _signedIn = false;
  String _email = '';
  int _seq = 0;

  final _categories = [
    CostCategory('liquor_monthly', '月結酒商'),
    CostCategory('liquor_cash', '現結酒商'),
    CostCategory('fruit', '酒水副材料-德哥'),
    CostCategory('ice', '酒水副材料-冰塊'),
    CostCategory('bar_misc', '酒水副材料-雜項'),
    CostCategory('food', '餐食進貨'),
    CostCategory('petty_misc', '零用金-其他雜支'),
  ];
  final _suppliers = [
    Supplier('s1', '示範酒商A', 'liquor_monthly'),
    Supplier('s2', '示範酒商B', 'liquor_monthly'),
    Supplier('s3', '示範水果行', 'fruit'),
    Supplier('s4', '示範冷凍食品', 'food'),
    Supplier('s5', '示範食材行', 'food'),
  ];
  final _products = [
    Product('p1', "Hendrick's Gin", '酒水', '瓶'),
    Product('p2', 'Bombay Sapphire', '酒水', '瓶'),
    Product('p3', 'Campari', '酒水', '瓶'),
    Product('p4', 'Chartreuse', '酒水', '瓶'),
    Product('p5', '檸檬', '水果', '顆'),
  ];
  late final List<Purchase> _purchases = [
    Purchase(id: 'x1', purchaseDate: DateTime(2026, 9, 25), categoryCode: 'liquor_monthly', supplierName: '示範酒商', amount: 2000, paidBy: 'vendor', reconciled: true, source: 'import'),
    Purchase(id: 'x2', purchaseDate: DateTime(2026, 9, 24), categoryCode: 'food', supplierName: null, memo: '示範食材', amount: 3000, paidBy: 'vendor', reconciled: true, source: 'import'),
    Purchase(id: 'x3', purchaseDate: DateTime(2026, 9, 30), categoryCode: 'petty_misc', memo: '運費', amount: 300, paidBy: 'petty_cash', reconciled: false, source: 'import'),
  ];
  final _counts = <StockCount>[];
  final _lines = <String, Map<String, double>>{};

  bool get _isStaff => _email.contains('staff');

  @override
  Stream<bool> get signedInChanges => _auth.stream;
  @override
  bool get isSignedIn => _signedIn;
  @override
  String? get currentUserId => _signedIn ? 'demo-user' : null;
  @override
  String? get currentUserEmail => _email;

  @override
  Future<void> signIn(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _email = email;
    _signedIn = true;
    _auth.add(true);
  }

  @override
  Future<bool> signUp(String email, String password) async {
    await signIn(email, password);
    return true;
  }

  final _demoMembers = [
    MemberInfo(userId: 'demo-user', displayName: '示範老闆', role: Role.owner, active: true, email: 'owner@demo'),
    MemberInfo(userId: 'u2', displayName: '示範店長', role: Role.manager, active: true, email: 'manager@demo'),
    MemberInfo(userId: 'u3', displayName: '示範員工', role: Role.staff, active: true, email: 'staff@demo'),
  ];
  final _demoInvites = <MemberInvite>[];
  @override
  Future<int> claimInvite(String code) async => -1;
  @override
  Future<String> createInvite(List<String> storeIds, Role role, String name) async {
    _demoInvites.insert(0, MemberInvite(id: 'i${_demoInvites.length}', displayName: name, role: role,
        createdAt: DateTime.now(), expiresAt: DateTime.now().add(const Duration(days: 14))));
    return 'DEMO2-CODE9';
  }
  @override
  Future<List<MemberInfo>> storeMembers(String storeId) async => List.of(_demoMembers);
  @override
  Future<List<MemberInvite>> openInvites(String storeId) async => List.of(_demoInvites);
  @override
  Future<void> revokeInvite(String inviteId) async => _demoInvites.removeWhere((i) => i.id == inviteId);
  @override
  Future<void> updateMember(String storeId, String userId, {Role? role, bool? active}) async {
    final i = _demoMembers.indexWhere((m) => m.userId == userId);
    final m = _demoMembers[i];
    _demoMembers[i] = MemberInfo(userId: m.userId, displayName: m.displayName, role: role ?? m.role,
        active: active ?? m.active, email: m.email);
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _auth.add(false);
  }

  @override
  Future<List<Membership>> myMemberships() async => [
        Membership(storeId: 'yc', storeName: '隱城', role: _isStaff ? Role.staff : Role.owner, displayName: '示範'),
        Membership(storeId: 'xc', storeName: '小城外', role: Role.staff, displayName: '示範'),
      ];

  final _revenue = <RevenueEntry>[
    RevenueEntry(id: 'r1', bizDate: DateTime(2026, 9, 30), cash: 8000, creditCard: 20000, guests: 28, drinks: 24000, food: 4000, source: 'import'),
    RevenueEntry(id: 'r2', bizDate: DateTime(2026, 9, 29), cash: 5000, creditCard: 16000, amex: 1000, guests: 21, drinks: 18000, food: 4000, source: 'import'),
  ];

  @override
  Future<List<RevenueEntry>> revenueEntries(String storeId, {int limit = 60}) async {
    if (_isStaff) throw Exception('message: 沒有權限執行這個動作。,');
    return storeId == 'yc' ? (List.of(_revenue)..sort((a, b) => b.bizDate.compareTo(a.bizDate))) : [];
  }

  @override
  Future<RevenueEntry?> revenueEntryFor(String storeId, DateTime bizDate) async {
    if (storeId != 'yc') return null;
    for (final e in _revenue) {
      if (e.bizDate.year == bizDate.year && e.bizDate.month == bizDate.month && e.bizDate.day == bizDate.day) return e;
    }
    return null;
  }

  @override
  Future<void> saveRevenueEntry(String storeId, RevenueEntry e) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (_isStaff) throw Exception('message: 沒有權限執行這個動作。,');
    final saved = RevenueEntry(
      id: e.id ?? 'r${++_seq}', bizDate: e.bizDate, cash: e.cash, creditCard: e.creditCard, amex: e.amex,
      deposit: e.deposit, guests: e.guests, drinks: e.drinks, food: e.food, project: e.project, note: e.note,
      source: e.source,
    );
    _revenue.removeWhere((x) => x.id == saved.id);
    _revenue.add(saved);
  }

  @override
  Future<DateTime?> lastExcelSync(String storeId) async =>
      storeId == 'yc' ? DateTime.now().subtract(const Duration(minutes: 25)) : null;

  final _fixed = <String, double>{};

  @override
  Future<FixedCosts> fixedCosts(String storeId, DateTime month) async {
    if (_isStaff) return const FixedCosts();
    final k = '$storeId-${month.year}-${month.month}';
    return FixedCosts(rent: _fixed['$k-rent'], payroll: _fixed['$k-payroll']);
  }

  @override
  Future<void> saveFixedCost(String storeId, DateTime month, String category, double amount) async {
    if (_isStaff) throw Exception('message: 沒有權限執行這個動作。,');
    _fixed['$storeId-${month.year}-${month.month}-$category'] = amount;
  }

  @override
  Future<MonthlySummary> monthlySummary(String storeId, DateTime month) async {
    if (_isStaff || storeId != 'yc') {
      return MonthlySummary(month: month, revenue: 0, guests: 0, drinksRevenue: 0, foodRevenue: 0);
    }
    return MonthlySummary(
      month: month,
      revenue: 500000,
      guests: 723,
      avgTicket: 1000,
      dailyAvgTicket: 1000,
      drinksRevenue: 420000,
      foodRevenue: 80000,
      targetAmount: 600000,
      targetRate: 0.8333,
      drinkCostRate: 0.2200,
      foodCostRate: 0.4000,
      totalCostRate: 0.2500,
      miscCostRate: 0.0200,
      purchaseCost: 125000,
      miscCost: 10000,
      hasCostRecords: true,
    );
  }

  @override
  Future<List<DailyRevenue>> recentDailyRevenue(String storeId, int days) async {
    if (_isStaff || storeId != 'yc') return [];
    const v = [20000, 10000, 25000, 40000, 50000, 20000, 15000, 22000, 24000, 45000, 38000, 42000, 21000, 30000];
    return [for (var i = 0; i < v.length; i++) DailyRevenue(DateTime(2026, 9, 17).add(Duration(days: i)), v[i].toDouble(), 20 + i)];
  }

  @override
  Future<List<Issue>> consistencyIssues(String storeId) async {
    if (_isStaff) throw Exception('message: 只有老闆或店長可以執行一致性檢查,');
    return [
      Issue('月結請款對帳', 'error', '示範食材行：金額不符（進貨 5,000／請款 4,000）'),
      Issue('月結進貨未對應廠商', 'warning', '示範：一筆進貨未對應廠商'),
    ];
  }

  @override
  Future<double?> pettyCashBalance(String storeId) async => storeId == 'yc' ? 5000 : null;

  @override
  Future<DateTime> businessDate(String storeId) async {
    final now = DateTime.now();
    final d = now.hour < 6 ? now.subtract(const Duration(days: 1)) : now;
    return DateTime(d.year, d.month, d.day);
  }

  @override
  Future<List<CostCategory>> costCategories() async => _categories;
  @override
  Future<List<Supplier>> suppliers(String storeId) async => _suppliers;
  @override
  Future<List<Purchase>> recentPurchases(String storeId, {int limit = 30}) async =>
      (List.of(_purchases)..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate))).take(limit).toList();

  @override
  Future<List<Purchase>> monthPurchases(String storeId, DateTime month) async => _purchases
      .where((p) => p.purchaseDate.year == month.year && p.purchaseDate.month == month.month)
      .toList()
    ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));

  final _requestIds = <String>{};
  @override
  Future<void> addPurchase(NewPurchase p) async {
    if (!_requestIds.add(p.clientRequestId)) throw Exception('duplicate key client_request');
    if (p.amount == 0) throw Exception('message: 金額不能為 0,');
    _purchases.add(Purchase(
      id: 'n${_seq++}',
      purchaseDate: p.purchaseDate,
      categoryCode: p.categoryCode,
      supplierName: _suppliers.where((s) => s.id == p.supplierId).map((s) => s.name).firstOrNull,
      memo: p.memo,
      amount: p.amount,
      paidBy: p.paidBy,
      reconciled: false,
      source: 'app',
    ));
  }

  @override
  Future<void> setReconciled(String purchaseId, bool reconciled) async {
    if (_isStaff) throw Exception('message: 只有老闆或店長可以核銷,');
    final i = _purchases.indexWhere((p) => p.id == purchaseId);
    final p = _purchases[i];
    _purchases[i] = Purchase(
        id: p.id, purchaseDate: p.purchaseDate, categoryCode: p.categoryCode, supplierName: p.supplierName,
        memo: p.memo, amount: p.amount, paidBy: p.paidBy, reconciled: reconciled, source: p.source);
  }

  @override
  Future<List<Product>> products(String storeId) async => _products;

  @override
  Future<List<StockCount>> stockCounts(String storeId) async => List.of(_counts.reversed);

  @override
  Future<String> createStockCount(String storeId, String? note) async {
    final id = 'c${_seq++}';
    _counts.add(StockCount(id: id, bizDate: await businessDate(storeId), countedBy: 'demo-user',
        status: CountStatus.draft, note: note, lineCount: 0));
    _lines[id] = {};
    return id;
  }

  @override
  Future<List<CountLine>> countLines(String countId) async => [
        for (final e in (_lines[countId] ?? {}).entries)
          () {
            final p = _products.firstWhere((p) => p.id == e.key);
            return CountLine(p.id, p.name, p.unit, e.value);
          }()
      ];

  @override
  Future<void> upsertCountLine(String countId, String productId, double qty) async {
    final c = _counts.firstWhere((c) => c.id == countId);
    if (c.status != CountStatus.draft && c.status != CountStatus.rejected) {
      throw Exception('message: 盤點已送出或已核准，明細不能修改,');
    }
    _lines[countId]![productId] = qty;
    _replace(c, c.status);
  }

  @override
  Future<void> setCountStatus(String countId, CountStatus status, {String? voidReason}) async {
    final c = _counts.firstWhere((c) => c.id == countId);
    if (status == CountStatus.approved && _isStaff) throw Exception('message: 員工不能核准盤點,');
    _replace(c, status);
  }

  void _replace(StockCount c, CountStatus s) {
    final i = _counts.indexOf(c);
    _counts[i] = StockCount(id: c.id, bizDate: c.bizDate, countedBy: c.countedBy, status: s, note: c.note,
        lineCount: _lines[c.id]?.length ?? 0);
  }
}
