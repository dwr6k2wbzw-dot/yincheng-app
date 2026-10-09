import 'models.dart';

/// App 與資料來源之間的介面。正式使用 SupabaseRepository；示範模式使用 DemoRepository。
abstract class Repository {
  // 帳號
  Stream<bool> get signedInChanges;
  bool get isSignedIn;
  String? get currentUserId;
  String? get currentUserEmail;
  Future<void> signIn(String email, String password);
  Future<void> signOut();

  // 店家
  Future<List<Membership>> myMemberships();

  // 營運總覽（老闆／店長）
  Future<MonthlySummary> monthlySummary(String storeId, DateTime month);
  Future<List<DailyRevenue>> recentDailyRevenue(String storeId, int days);
  Future<List<Issue>> consistencyIssues(String storeId);
  Future<double?> pettyCashBalance(String storeId);

  // 每日營收（老闆／店長）
  Future<List<RevenueEntry>> revenueEntries(String storeId, {int limit = 60});
  Future<RevenueEntry?> revenueEntryFor(String storeId, DateTime bizDate);
  Future<void> saveRevenueEntry(String storeId, RevenueEntry e);
  Future<DateTime?> lastExcelSync(String storeId);

  // 租金／人事成本（只有老闆；資料庫 RLS 也只允許老闆）
  Future<FixedCosts> fixedCosts(String storeId, DateTime month);
  Future<void> saveFixedCost(String storeId, DateTime month, String category, double amount);

  // 進貨
  Future<DateTime> businessDate(String storeId);
  Future<List<CostCategory>> costCategories();
  Future<List<Supplier>> suppliers(String storeId);
  Future<List<Purchase>> recentPurchases(String storeId, {int limit = 30});
  Future<List<Purchase>> monthPurchases(String storeId, DateTime month);
  Future<void> addPurchase(NewPurchase p);
  Future<void> setReconciled(String purchaseId, bool reconciled);

  // 盤點
  Future<List<Product>> products(String storeId);
  Future<List<StockCount>> stockCounts(String storeId);
  Future<String> createStockCount(String storeId, String? note);
  Future<List<CountLine>> countLines(String countId);
  Future<void> upsertCountLine(String countId, String productId, double qty);
  Future<void> setCountStatus(String countId, CountStatus status, {String? voidReason});
}

/// 把資料庫的錯誤訊息轉成店員看得懂的話（資料庫守衛的訊息本來就是中文）
String friendlyError(Object e) {
  final s = e.toString();
  final m = RegExp(r'message: ([^,]+)').firstMatch(s);
  final msg = m?.group(1) ?? s;
  if (msg.contains('duplicate key') && msg.contains('client_request')) return '這筆已經送出過了，不會重複新增。';
  if (msg.contains('row-level security')) return '沒有權限執行這個動作。';
  if (msg.contains('daily_revenue_one_per_day')) return '這一天已經有營收紀錄了，請從列表點進去修改。';
  if (msg.contains('Invalid login credentials')) return '帳號或密碼錯誤。';
  return msg;
}
