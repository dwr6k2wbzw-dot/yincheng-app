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

  /// 建立帳號。回傳 true：已直接登入；false：需要先到信箱點確認連結
  Future<bool> signUp(String email, String password);

  // 店家
  Future<List<Membership>> myMemberships();

  // 成員管理（產生邀請碼、成員清單只有老闆；資料庫函式也會檢查）
  /// 用邀請碼加入店家。回傳加入的店家數；-1＝邀請碼無效、已用過或已過期
  Future<int> claimInvite(String code);
  Future<String> createInvite(List<String> storeIds, Role role, String name);
  Future<List<MemberInfo>> storeMembers(String storeId);
  Future<List<MemberInvite>> openInvites(String storeId);
  Future<void> revokeInvite(String inviteId);
  Future<void> updateMember(String storeId, String userId, {Role? role, bool? active});

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

  // 廠商銷貨單明細（小城外）
  Future<List<VendorSlip>> vendorSlips(String storeId, DateTime month);
  /// 自動讀取失敗、需要確認的單據檔名
  Future<List<String>> failedSlipFiles(String storeId);
  /// 新增（id 為 null）或修改一張銷貨單：表頭＋品項一次存（只有老闆／店長）
  Future<String> saveVendorSlip(String storeId, VendorSlip slip);
  Future<void> deleteVendorSlip(String slipId);

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
  if (msg.contains('vendor_slips_store_id_vendor_slip_no_key')) return '這個廠商已經有相同單號的單據了。';
  if (msg.contains('Email not confirmed')) return '這個 Email 還沒確認，請先到信箱點確認連結。';
  if (msg.contains('User already registered') || msg.contains('already been registered')) return '這個 Email 已經有帳號了，請直接登入。';
  if (msg.contains('rate limit')) return '操作太頻繁，請稍後再試。';
  if (msg.contains('Signups not allowed') || msg.contains('signups are disabled')) return '目前沒有開放建立帳號，請聯絡老闆。';
  if (msg.contains('Password should be')) return '密碼太短，請至少 8 個字。';
  return msg;
}
