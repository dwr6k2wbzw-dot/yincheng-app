import 'dart:typed_data';

import 'change_request_models.dart';
import 'models.dart';
import 'reservation_models.dart';
import 'shift_planner.dart';
export 'change_request_models.dart';
export 'reservation_models.dart';
export 'shift_planner.dart';

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

  // 上次讀到的資料（打開 App 先顯示、背景再更新；老闆 2026-10-16）。沒有存過就是 null。
  List<Membership>? peekMemberships();
  MonthlySummary? peekMonthlySummary(String storeId, DateTime month);
  List<DailyRevenue>? peekDailyRevenueBetween(String storeId, DateTime from, DateTime to);
  FixedCosts? peekFixedCosts(String storeId, DateTime month);
  List<ExpenseItem>? peekExpenseItems(String storeId, DateTime month);
  List<RecurringExpenseItem>? peekRecurringExpenseItems(String storeId);
  double? peekCardFeeRate(String storeId);
  /// 零用金結餘：外層 null＝沒存過；存過但沒有資料＝(null)
  (double?,)? peekPettyCashBalance(String storeId);

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
  /// 指定期間的每日營收（kind=daily），總覽趨勢線用
  Future<List<DailyRevenue>> dailyRevenueBetween(String storeId, DateTime from, DateTime to);
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
  // 損益手動支出明細（只有老闆；資料庫 0037 RLS 也只允許老闆）
  Future<List<ExpenseItem>> expenseItems(String storeId, DateTime month);
  Future<void> saveExpenseItem(String storeId, DateTime month, ExpenseItem item, {bool isNew = false});
  Future<void> deleteExpenseItem(String itemId);
  // 0039：刷卡手續費率（預設 0.02）＋每月固定支出
  Future<double> cardFeeRate(String storeId);
  Future<void> saveCardFeeRate(String storeId, double rate);
  Future<List<RecurringExpenseItem>> recurringExpenseItems(String storeId);
  Future<void> saveRecurringExpenseItem(String storeId, RecurringExpenseItem item, {bool isNew = false});
  Future<void> deleteRecurringExpenseItem(String itemId);

  // 進貨
  Future<DateTime> businessDate(String storeId);
  Future<List<CostCategory>> costCategories();
  Future<List<Supplier>> suppliers(String storeId);
  /// 各進貨類別常用的廠商（依日報表匯入的近半年進貨統計，最多 4 家）
  Future<VendorHints> vendorHints(String storeId);
  /// 日報表的月結廠商名稱（近 6 個月，依次數排序）
  Future<List<String>> excelVendorNames(String storeId);
  /// 同店成員名字（填表人／請款人選單用；含兼職）
  Future<List<String>> memberNames(String storeId);
  Future<List<Purchase>> recentPurchases(String storeId, {int limit = 30});
  Future<List<Purchase>> monthPurchases(String storeId, DateTime month);
  Future<void> addPurchase(NewPurchase p);
  Future<void> setReconciled(String purchaseId, bool reconciled);
  /// 修改、刪除 App 暫記（日報表匯入的進貨不能改刪：以日報表為準，資料庫 0035）
  Future<void> updatePurchase(String purchaseId, NewPurchase p);
  Future<void> deletePurchase(String purchaseId);

  // 廠商銷貨單明細（小城外）
  Future<List<VendorSlip>> vendorSlips(String storeId, DateTime month);
  /// 自動讀取失敗、需要確認的單據檔名
  Future<List<String>> failedSlipFiles(String storeId);
  /// 新增（id 為 null）或修改一張銷貨單：表頭＋品項一次存（只有老闆／店長）
  Future<String> saveVendorSlip(String storeId, VendorSlip slip);
  Future<void> deleteVendorSlip(String slipId);

  // 班表（同店成員可看；老闆／店長可改）
  Future<ShiftMonth> shiftMonth(String storeId, DateTime month);
  /// mark 為 null＝清除這一格
  Future<void> setShift(String storeId, String personId, DateTime date, String? mark);
  Future<void> setShiftNote(String storeId, DateTime date, String? note);
  Future<void> saveShiftPerson(String storeId, ShiftPerson p, {bool isNew = false});
  Future<void> saveShiftStats(String storeId, String personId, DateTime month, ShiftStats s);
  Future<void> uploadShiftPhoto(String storeId, DateTime month, Uint8List jpeg);
  Future<void> deleteShiftPhoto(String photoId); // 0070：一個月多張，刪掉其中一張
  /// 套用照片辨識草稿（0070）：整月換成照片上的班，回傳寫入格數
  Future<int> applyShiftDraft(ShiftDraft d);
  Future<void> dismissShiftDraft(String draftId);
  Future<String> shiftPhotoUrl(String path);

  // 自動排班（0073）
  /// 這個月的排班設定：每日人力、特別日子、截止日、排班條件（員工只讀得到自己的）、大家填的想休／可上
  Future<ShiftPlanSetup> shiftPlanSetup(String storeId, DateTime month);
  /// 成員自己選「我是班表上的誰」
  Future<void> claimShiftPerson(String personId);
  /// 老闆／店長解除班表人員對應的帳號
  Future<void> clearShiftPersonUser(String personId);
  /// kind：off 想休／on 可以上／null 清掉
  Future<void> setShiftRequest(String storeId, String personId, DateTime date, String? kind);
  Future<void> saveShiftRule(String storeId, ShiftRule r);
  Future<void> saveShiftStaffing(String storeId, Map<int, StaffingNeed> staffing);
  /// need 為 null＝取消這天的特別人力
  Future<void> setShiftStaffingDay(String storeId, DateTime day, int? need);
  Future<void> saveShiftDeadline(String storeId, int day);
  /// 套用自動排班：列出的人這個月整個換成 plan，回傳寫入格數
  Future<int> applyShiftPlan(String storeId, DateTime month, Map<String, Map<int, String>> plan);

  // 交接事項與工作提醒（同店成員可看、可寫交接、可打勾；提醒只有老闆／店長能建立）
  Future<HandoverBoard> handoverBoard(String storeId, {bool withSchedule = false});
  Future<void> addHandover(String storeId, String body, List<String> items, Uint8List? jpeg); // 0060：可帶打勾清單
  Future<void> setHandoverResolved(String noteId, bool resolved);
  Future<void> markHandoverRead(String storeId, List<String> noteIds);
  Future<void> deleteHandover(String noteId);
  Future<void> updateHandover(String noteId, String body, List<String> items); // 0044／0060：任何成員都能改內容與清單
  Future<void> setHandoverItemDone(String itemId, bool done); // 0060：清單打勾
  Future<void> saveReminder(String storeId, WorkReminder r, {bool isNew = false});
  Future<void> deleteReminder(String reminderId);
  Future<void> setReminderDone(String storeId, String reminderId, DateTime occurrence, bool done);

  // App 內通知（小鈴鐺，0042）：最近 30 天、最多 50 則，不含自己做的事
  Future<NotificationFeed> notifications(String storeId);
  Future<List<AppNotification>> reservationEvents(String storeId); // 0062：新訂位、取消、改人數（「今日訂位」卡片用）
  Future<void> markNotificationsSeen(String storeId);

  // 盤點
  Future<List<Product>> products(String storeId);
  Future<List<StockCount>> stockCounts(String storeId);
  Future<String> createStockCount(String storeId, String? note);
  Future<List<CountLine>> countLines(String countId);
  Future<void> upsertCountLine(String countId, String productId, double qty);
  Future<void> setCountStatus(String countId, CountStatus status, {String? voidReason});
  /// 每個品項最近一次盤點到的數量（草稿以外、作廢與退回不算）
  Future<Map<String, StockLevel>> latestStock(String storeId);
  /// 新增或修改品項（老闆／店長）；id 為空字串＝新增
  Future<void> saveProduct(String storeId, Product p);
  /// 停用品項（不刪除，歷史盤點照常顯示）
  Future<void> deactivateProduct(String productId);

  // ---------------- 功能許願（0069，只有老闆／店長） ----------------
  Future<List<ChangeRequest>> changeRequests(String storeId);
  Future<List<ChangeMessage>> changeMessages(String requestId);
  Future<ChangeQuota> changeQuota(String storeId);
  /// photos：附的照片（JPEG data URL，最多 5 張；0071）
  Future<String> createChangeRequest(String storeId, String body, {List<String> photos = const []});
  /// 再改一次（看了預覽想調整、失敗重試、老闆退回後再改）
  Future<void> followupChangeRequest(String requestId, String body, {List<String> photos = const []});
  /// 附的照片（只有老闆／店長看得到）
  Future<Uint8List> changePhoto(String photoId);
  Future<void> submitChangeRequest(String requestId); // 店長送審
  Future<void> approveChangeRequest(String requestId); // 老闆核准上線
  Future<void> returnChangeRequest(String requestId, String reason); // 老闆退回
  Future<void> cancelChangeRequest(String requestId);
  /// 請 Edge Function 處理排隊中的工作（派工給 Claude、合併、關閉）；失敗不影響畫面
  Future<void> kickChangeRequests();

  // ---------------- 訂位（0050） ----------------
  Future<ReservationSettings?> reservationSettings(String storeId);
  Future<void> saveReservationSettings(String storeId, Map<String, dynamic> values);
  Future<List<Reservation>> reservations(String storeId, DateTime from, DateTime to);
  Future<void> addReservation(String storeId,
      {required DateTime date, required String time, required int party, required String name, required String phone, String? email, String? note, List<String> tableIds = const []});
  Future<void> updateReservation(String id, Map<String, dynamic> values);
  // 0061 時間軸：桌位、現場客
  Future<List<ReservationTable>> reservationTables(String storeId);
  Future<void> saveReservationTable(String storeId, ReservationTable t);
  Future<void> addWalkIn(String storeId,
      {required DateTime date, required String time, required int party, required String name, required List<String> tableIds});
  /// 0055 客人申請改人數：同意（人數改成申請的）或不同意
  Future<void> decidePartyRequest(String id, bool approve, int expectedParty);
  // 0052 特殊日期、熟客
  Future<List<ReservationSpecialDay>> specialDays(String storeId, DateTime from, DateTime to);
  Future<void> saveSpecialDay(String storeId, ReservationSpecialDay d);
  Future<void> deleteSpecialDay(String storeId, DateTime day);
  /// 這些電話（只取數字）在這家店的紀錄：來過幾次、未到幾次（解除那天以後）、標籤備註
  Future<Map<String, GuestStats>> guestStats(String storeId, Set<String> phoneDigits);
  Future<void> saveGuestProfile(String storeId, GuestProfile g, {bool resetNoshow = false});
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
  if (msg.contains('change_requests_title_check')) return '第一行請寫個簡短的標題。';
  return msg;
}
