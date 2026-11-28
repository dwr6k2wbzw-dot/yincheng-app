import 'shift_off_rules.dart';
import 'dart:typed_data';

import 'attendance_models.dart';
import 'change_request_models.dart';
import 'booking_profile.dart';
import 'booking_assist.dart';
import 'booking_import.dart';
import 'line_bind.dart';
import 'models.dart';
import 'pl_template.dart';
import 'onboarding.dart';
import 'payroll.dart';
import 'platform_wish.dart';
import 'purchase_items_math.dart';
import 'reservation_models.dart';
import 'shift_links.dart';
import 'shift_planner.dart';
import 'store_ai.dart';
import 'store_line.dart';
export 'attendance_models.dart';
export 'booking_assist.dart';
export 'change_request_models.dart';
export 'line_bind.dart';
export 'payroll.dart';
export 'platform_wish.dart';
export 'reservation_models.dart';
export 'shift_planner.dart';
export 'store_ai.dart';
export 'store_line.dart';

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
  /// 自助註冊（ops 0119，只有公版環境開放）：建立「組織＋第一家店」，自己是老闆。回傳店的 id
  /// [kind]：店的類型（ops 0152 排班範本 bar／cafe／restaurant／other），給了就照範本帶入排班的起手設定
  Future<String> signupCreateStore(String storeName, String displayName, {String? kind});
  /// 排班的業態範本（ops 0152，只有老闆、只有全新的店）：帶入每天要幾人、班別／時段、排班設定
  Future<void> applyShiftTemplate(String storeId, String kind);
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
  /// 指定期間（含頭尾）的每日營收，新到舊；營收頁換月份用
  Future<List<RevenueEntry>> revenueEntriesBetween(String storeId, DateTime from, DateTime to);
  /// 最早一筆每日營收的營業日；還沒有任何紀錄回 null（營收頁月份最早切到哪）
  Future<DateTime?> firstRevenueDate(String storeId);
  Future<RevenueEntry?> revenueEntryFor(String storeId, DateTime bizDate);
  Future<void> saveRevenueEntry(String storeId, RevenueEntry e);
  Future<DateTime?> lastExcelSync(String storeId);
  /// 有 iCHEF 資料的營業日（0096）：這些天的來客、酒水、餐食、現金、刷卡以 iCHEF 為準
  /// 給 [from]／[to] 只查那段期間（不限筆數）
  Future<Set<DateTime>> ichefDays(String storeId, {int limit = 120, DateTime? from, DateTime? to});
  /// 某營業日 iCHEF 的現金；那天還沒有 iCHEF 資料回 null。
  /// 小城外有 iCHEF 的日子，現金＝這個數字＋咖啡＋拉麵（資料庫 0096 每次寫入都這樣重算）
  Future<double?> ichefCash(String storeId, DateTime bizDate);
  /// 某營業日的 iCHEF 品項銷售，金額（含服務費）由大到小
  Future<List<ItemSale>> itemSales(String storeId, DateTime bizDate);
  /// 當月銷售品項累計（ops 0102）：只算有 iCHEF 資料的日子，金額含服務費、由大到小；舊資料庫回空清單
  Future<List<ItemSale>> monthItemSales(String storeId, DateTime month);

  // 租金／人事成本（只有老闆；資料庫 RLS 也只允許老闆）
  Future<FixedCosts> fixedCosts(String storeId, DateTime month);
  Future<void> saveFixedCost(String storeId, DateTime month, String category, double amount);
  /// 清掉手動填的租金／人事基底（人事清掉後改用薪資預估；ops 0129）
  Future<void> clearFixedCost(String storeId, DateTime month, String category);
  // 損益手動支出明細（只有老闆；資料庫 0037 RLS 也只允許老闆）
  Future<List<ExpenseItem>> expenseItems(String storeId, DateTime month);
  Future<void> saveExpenseItem(String storeId, DateTime month, ExpenseItem item, {bool isNew = false});
  Future<void> deleteExpenseItem(String itemId);
  // 0039：刷卡手續費率（預設 0.02）＋每月固定支出
  Future<double> cardFeeRate(String storeId);
  /// 損益表的會計科目（ops 0142，只有老闆）。資料庫還沒更新回空的（匯出用舊格式）
  Future<List<PlAccount>> plAccounts(String storeId);
  /// 損益表抬頭用的店名（ops 0142 store_settings.pl_title；沒設回 null＝用店名）
  Future<String?> plTitle(String storeId);
  /// 損益設定（ops 0169，只有公版、只有老闆）：業態範本清單、套範本（回寫入幾個科目）、新增／修改科目、損益表抬頭
  Future<List<PlTemplate>> plTemplates();
  Future<int> applyPlTemplate(String storeId, String kind);
  Future<void> savePlAccount(String storeId, PlAccount account, {bool isNew = false});
  Future<void> savePlTitle(String storeId, String? title);
  Future<void> saveCardFeeRate(String storeId, double rate);
  Future<List<RecurringExpenseItem>> recurringExpenseItems(String storeId);
  Future<void> saveRecurringExpenseItem(String storeId, RecurringExpenseItem item, {bool isNew = false});
  Future<void> deleteRecurringExpenseItem(String itemId);
  /// 0090：固定支出從某月起改成多少錢（過去月份不變）
  Future<void> setRecurringAmountFrom(String itemId, DateTime month, double amount);

  // 廠商資料（0076：只有老闆、店長；資料庫 RLS 也只允許這兩種角色）
  Future<List<VendorContact>> vendorContacts(String storeId);
  Future<void> saveVendorContact(String storeId, VendorContact v);
  Future<void> deleteVendorContact(String id);

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
  /// 拍照辨識送貨單（0087，Claude 讀圖；每店每天有次數上限）。image＝JPEG data URL
  Future<SlipReading> readSlip(String storeId, String image);
  /// 進貨報價用：最近一年進貨的品項明細，帶進貨日期、廠商、類別（退貨的數量是負數）
  Future<List<QuoteLine>> purchaseQuoteLines(String storeId);
  /// 手動改過的進貨報價（0105；資料庫還沒更新時回傳空清單）
  Future<List<QuoteEdit>> purchaseQuoteEdits(String storeId);
  /// 改報價（品名、單位、單價）或把那一項拿掉（hidden）；只有老闆、店長
  Future<void> savePurchaseQuoteEdit(String storeId, QuoteEdit edit);
  /// 還原成進貨資料（刪掉手動修改）
  Future<void> deletePurchaseQuoteEdit(String storeId, String key);
  /// 進貨的品項明細（0087；畫面不再顯示，存檔時在背後一起存，用來更新進貨報價）
  Future<List<PurchaseItem>> purchaseItems(String purchaseId);
  /// 新增或修改進貨主檔＋品項明細，一次存完，全部成功才算（0089 修復：原本分兩次存，中途斷線會變成
  /// 帳改了、庫存沒改）。purchaseId＝null 表示新增（日報表匯入的進貨不能改：以日報表為準，資料庫 0035）；
  /// items＝null 表示不動明細（例如改進貨時原品項讀不到）；negate＝退貨（庫存數量用負數）。
  /// 新增時用 purchase.clientRequestId 擋網路重送：同一張表單重送會接續存好既有那筆，不會被擋住（0089 修復）。
  /// 回傳進貨 id。
  Future<String> savePurchaseWithItems(
      {String? purchaseId, required NewPurchase purchase, List<PurchaseItem>? items, bool negate = false});
  Future<void> setReconciled(String purchaseId, bool reconciled);
  Future<void> deletePurchase(String purchaseId);
  /// 進貨待確認清單（0104，只有老闆、店長；資料庫還沒更新或沒權限時回傳空清單）
  Future<List<PurchaseMatch>> purchaseMatchQueue(String storeId);
  /// 確認「是同一筆」（可以一次好幾筆）
  Future<void> confirmPurchaseMatches(List<String> appIds);
  /// 「不是同一筆」：後台幾分鐘內拆開、重新比對
  Future<void> rejectPurchaseMatch(String appId);
  /// 日報表沒有這一筆：「知道了」（那筆仍然不計入，只是從清單拿掉）
  Future<void> dismissUnmatchedPurchase(String appId);

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
  /// 班表照片辨識的方式（ops 0153）：subscription＝每小時同步（隱城、小城外）／api＝上傳完直接辨識（公版）。
  /// 只有老闆、店長讀得到；讀不到（舊資料庫、沒權限）一律當 subscription
  Future<String> shiftPhotoAiMode(String storeId);
  /// api 模式：叫後臺立刻辨識這個月的照片（成功回讀到幾格；照片途中有變動回 null，請再按一次）
  Future<int?> readShiftPhotos(String storeId, DateTime month);
  Future<void> deleteShiftPhoto(String photoId); // 0070：一個月多張，刪掉其中一張
  /// 套用照片辨識草稿（0070）：整月換成照片上的班，回傳寫入格數
  Future<int> applyShiftDraft(ShiftDraft d);
  Future<void> dismissShiftDraft(String draftId);
  Future<String> shiftPhotoUrl(String path);
  /// 班別／時段清單（0075）：id 空白＝新增
  Future<void> saveShiftMarkOption(String storeId, ShiftMarkOption o);
  Future<void> deleteShiftMarkOption(String id);
  /// 0113：停用／恢復班別（排過的班別不能刪、不能改時段）
  Future<void> setShiftMarkOptionHidden(String id, bool hidden);
  /// 0113：這個月班表的修改紀錄（老闆店長）、整批還原一次修改
  Future<List<ShiftChange>> shiftChangeHistory(String storeId, DateTime month);
  Future<int> undoShiftChange(String storeId, String changeId);
  /// 0113：老闆直接替班表人員指定 App 帳號（＝確認）；userId null＝解除
  Future<void> assignShiftAccount(String personId, String? userId);
  Future<List<ShiftAccountCandidate>> shiftAccountCandidates(String storeId);
  /// 兩家店同一個人（0098）：我也是老闆、同一個組織的其他店，和那幾家店班表上的人（不是這家店的老闆＝空的）
  Future<List<ShiftLinkStore>> shiftLinkStores(String storeId);
  /// 連結兩家店的兩個人（shift_link_people；只有兩家都是老闆的人）
  Future<void> linkShiftPeople(String personId, String otherPersonId);
  /// 解除這個人的連結（shift_unlink_person；只剩一個人的連結資料庫會一起清掉）
  Future<void> unlinkShiftPerson(String personId);

  // 自動排班（0073）
  /// 這個月的排班設定：每日人力、特別日子、截止日、排班條件（員工只讀得到自己的）、大家填的想休／可上
  Future<ShiftPlanSetup> shiftPlanSetup(String storeId, DateTime month);
  /// kind：off 想休／on 可以上／null 清掉
  Future<void> setShiftRequest(String storeId, String personId, DateTime date, String? kind);
  /// 這個月哪幾天已經有正職指休（日 → 人員 id；ops 0137）。null＝資料庫還沒更新，App 自己算
  Future<Map<int, Set<String>>?> shiftOffTaken(String storeId, DateTime month);
  /// 這個月每位正職的特休（ops 0138）。null＝資料庫還沒更新，照舊手動填
  Future<Map<String, SpecialLeave>?> specialLeaveStatus(String storeId, DateTime month);
  /// 我在這家店看不看得到薪資頁（ops 0139：小城外的店長看不到）。資料庫還沒更新回 true
  Future<bool> payrollAccess(String storeId);
  /// 把某人「現在剩幾天」改成 balance（老闆；店長不能改自己的）
  Future<void> setSpecialLeave(String personId, double balance, {String? note});
  Future<void> saveShiftRule(String storeId, ShiftRule r);
  Future<void> saveShiftStaffing(String storeId, Map<int, StaffingNeed> staffing);
  /// need 為 null＝取消這天的特別人力
  Future<void> setShiftStaffingDay(String storeId, DateTime day, int? need);
  Future<void> saveShiftDeadline(String storeId, int day);
  /// 自訂規則：kind apart（不能同一天上班）／with（a 上班時 b 也要上）
  Future<void> addShiftPairRule(String storeId, String a, String b, String kind);
  Future<void> deleteShiftPairRule(String id);
  /// 套用自動排班：列出的人這個月整個換成 plan，回傳寫入格數
  /// expected：畫面載入時的班表版本（shiftMonthVersion）；有帶就會檢查班表有沒有被別人改過，並在成功後清掉草稿（0098）
  Future<int> applyShiftPlan(String storeId, DateTime month, Map<String, Map<int, String>> plan, {String? expected});
  // 0098：班表版本、排班草稿（只有老闆店長）、盡量不連上幾天、LINE 指休提醒
  Future<String> shiftMonthVersion(String storeId, DateTime month);
  Future<ShiftPlanDraft?> shiftPlanDraft(String storeId, DateTime month);
  Future<void> saveShiftPlanDraft(String storeId, DateTime month, Map<String, Map<int, String>> plan, Map<String, Set<int>> locked);
  Future<void> deleteShiftPlanDraft(String storeId, DateTime month);
  Future<void> saveShiftPreferRun(String storeId, int? days);
  /// 0150 指休規則：同一天最多幾位正職、每人每月最多幾天（null＝不限）；只有老闆店長
  Future<void> saveShiftOffLimits(String storeId, int? perDay, int? monthMax);
  Future<String> remindShiftRequests(String storeId, DateTime month);

  // 交接事項與工作提醒（同店成員可看、可寫交接、可打勾；提醒只有老闆／店長能建立）
  Future<HandoverBoard> handoverBoard(String storeId, {bool withSchedule = false});
  Future<void> addHandover(String storeId, String body, List<String> items, Uint8List? jpeg, {bool important = false}); // 0060：可帶打勾清單；0079：重要→發 LINE
  Future<void> setHandoverResolved(String noteId, bool resolved);
  Future<void> markHandoverRead(String storeId, List<String> noteIds);
  Future<void> deleteHandover(String noteId);
  Future<void> updateHandover(String noteId, String body, List<String> items, {bool? important}); // 0044／0060：任何成員都能改內容與清單；0079：null＝不改重要
  Future<bool> lineNotifyEnabled(String storeId); // 0079：這家店重要交接發不發 LINE（只有老闆讀得到，其他人回 true）
  Future<void> saveLineNotifyEnabled(String storeId, bool on); // 0079：只有老闆
  Future<int> lineOwnerLinks(); // 0081：我綁了幾個 LINE 私訊
  Future<void> linkLineOwner(String code); // 0081：老闆輸入 LINE 私訊給的代碼
  Future<void> unlinkLineOwner(); // 0081：解除自己的 LINE 私訊綁定
  Future<bool> lineGroupBound(String storeId); // 0156：這家店綁了 LINE 群組沒（只有老闆讀得到）
  Future<LineBindCode> createLineGroupBindCode(String storeId); // 0156：老闆產生群組綁定代碼（10 分鐘、一次性）
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
  /// 每個品項目前的庫存：最近一次盤點（草稿、作廢、退回不算）＋之後進貨明細加進來的（0087）
  Future<Map<String, StockLevel>> latestStock(String storeId);
  /// 每個品項最後一次盤點的數量、哪天、誰盤的（0104：庫存只看最後盤點量）
  Future<Map<String, LastCount>> stockLastCounts(String storeId);
  /// 盤點一次存完（0104）：建立＋每一項＋送出同一個交易；requestId 相同的重送不會存兩張。
  /// seenAt＝開始盤時看到的最新一次盤點時間（之後別人也盤過的品項會回報）
  Future<StockSubmitResult> submitStockCount(String storeId, Map<String, double> lines,
      {required String requestId, DateTime? seenAt});
  /// 新增或修改品項（老闆／店長）；id 為空字串＝新增
  /// 回傳品項 id。setCycle＝true 才會寫入「多久盤一次」（只有老闆、店長能改，0104）
  Future<String> saveProduct(String storeId, Product p, {bool setCycle = false});
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
  // 訂位頁的樣子（ops 0135／0145；只有老闆能改）
  /// 這家店的訂位頁資料；還沒建立過＝null
  Future<BookingProfile?> bookingProfile(String storeId);
  // 開店精靈（ops 0155，公版）：新店建第一份訂位設定、看開店設定做到哪
  Future<OnboardingStatus> onboardingStatus(String storeId);
  /// 建好回訂位網址代號；這家店已經有訂位設定、代號有人用了、格式不對都會丟錯（訊息開頭 ONBOARD_…）
  Future<String> setupOnlineBooking(String storeId,
      {required String slug,
      required String displayName,
      String? address,
      String? phone,
      required List<String> slotTimes,
      List<int> closedWeekdays = const [],
      int? maxGroups,
      int? maxGuests});
  /// 新增或更新（老闆）
  Future<void> saveBookingProfile(String storeId, BookingProfile p);
  /// 上傳 logo／封面照到公開檔案區，回傳路徑（{店的 id}/{kind}-xxxx.{ext}）。kind＝logo／hero
  Future<String> uploadBookingAsset(String storeId, String kind, Uint8List bytes, String contentType);
  /// 刪掉沒在用的舊圖（失敗不影響畫面；訂位頁正在用的資料庫會擋）
  Future<void> deleteBookingAsset(String path);
  // 訂位的 AI 設定助理（ops 0147；只有老闆）：AI 只提出建議，老闆按確認才套用、可以整筆改回去
  /// 問 AI（Edge Function booking-assistant）；[history] 是前面幾則對話（最多 6 則）
  Future<AssistReply> askBookingAssistant(String storeId, String message, List<AssistTurn> history);
  /// 套用 AI 的建議（老闆自己的身分；問完之後設定被改過會整筆不套用）
  Future<void> applyBookingAssist(String storeId, String request, List<AssistChange> changes);
  /// 最近用 AI 改過的紀錄
  Future<List<AssistRecord>> bookingAssistHistory(String storeId);
  /// 整筆改回去（之後又被改過的不能改回去）
  Future<void> undoBookingAssist(String id);
  // 排班的 AI 設定助理（ops 0154；老闆、店長；只有公版有入口）：同上，改的是每日人力、排班設定、個人排班條件
  Future<AssistReply> askShiftAssistant(String storeId, String message, List<AssistTurn> history);
  Future<void> applyShiftAssist(String storeId, String request, List<AssistChange> changes);
  Future<List<AssistRecord>> shiftAssistHistory(String storeId);
  Future<void> undoShiftAssist(String id);
  // 訂位搬家（ops 0148；老闆、店長）：先預覽（資料庫檢查每一列、不寫入），沒問題再匯入；每一批可以整批復原
  Future<ImportResult> previewReservationImport(String storeId, List<ImportRow> rows);
  /// [requestId]：同一個檔案按兩次只匯一次
  Future<ImportResult> importReservations(String storeId, List<ImportRow> rows, String? fileName, String requestId);
  Future<List<ImportBatch>> reservationImports(String storeId);
  /// 回取消了幾筆（已經到店、未到、過去的不動）
  Future<int> undoReservationImport(String batchId);
  /// 匯出用：這家店全部的訂位（含已取消、隱藏的）
  Future<List<Reservation>> allReservations(String storeId);
  // 許願單（ops 0149，公版；只有老闆、店長）：寫一則送到平台待辦，平台回覆狀態和說明
  /// 這家店的許願單（新的在前）
  Future<List<PlatformWish>> platformWishes(String storeId);
  /// 寫一則（每家店每個月最多 20 則），回傳 id
  Future<String> createPlatformWish(String storeId, String title, String body);
  // 平台回覆許願單（ops 0159，公版；只有平台管理者，後台在 app.platform_admins 加的人）
  /// 我是不是平台管理者（不是、或資料庫還沒更新都回 false）
  Future<bool> platformAdminMe();
  /// 所有店的許願（新的在前，最多 500 則）
  Future<List<PlatformAdminWish>> platformAdminWishes();
  /// 各狀態有幾則
  Future<Map<PlatformWishStatus, int>> platformAdminWishCounts();
  /// 改狀態、寫回覆（回覆空白＝拿掉回覆）。畫面上看到的跟現在不同 → 丟 WISH_STALE
  Future<void> platformAdminReply(PlatformAdminWish w, PlatformWishStatus status, String reply);
  // 店家接自己的 AI（ops 0157，公版；只有老闆）：金鑰存進加密保管庫，App 只拿得到末 4 碼
  /// 這家店目前的設定；null＝用平台內建的 AI
  Future<StoreAiSetting?> storeAiSetting(String storeId);
  /// 先用這把金鑰實際打一次 AI，成功才存
  Future<StoreAiResult> saveStoreAi(String storeId, StoreAiProvider provider, String model, String key);
  /// 用已存的金鑰再測一次
  Future<StoreAiResult> testStoreAi(String storeId);
  /// 清除，改回用平台內建的 AI
  Future<void> clearStoreAi(String storeId);
  // 店家接自己的 LINE 官方帳號（ops 0160，公版；只有老闆）：金鑰存進加密保管庫，App 只拿得到末 4 碼
  /// 目前的狀態（還沒接上回 StoreLineStatus.none）
  Future<StoreLineStatus> storeLineStatus(String storeId);
  /// 先用 access token 打 LINE 確認能用才存，再試著設好 Webhook、請 LINE 測試
  Future<StoreLineResult> saveStoreLine(String storeId, String secret, String token);
  /// 用已存的金鑰再驗證一次
  Future<StoreLineResult> testStoreLine(String storeId);
  /// 清除（透過這個帳號綁的群組一起拿掉）
  Future<void> clearStoreLine(String storeId);
  Future<List<Reservation>> reservations(String storeId, DateTime from, DateTime to);
  Future<void> addReservation(String storeId,
      {required DateTime date, required String time, required int party, required String name, required String phone, String? email, String? note, List<String> tableIds = const []});
  Future<void> updateReservation(String id, Map<String, dynamic> values);
  // 0061 時間軸：桌位、現場客
  Future<List<ReservationTable>> reservationTables(String storeId);
  Future<void> saveReservationTable(String storeId, ReservationTable t);
  /// 刪除桌位（ops 0132；老闆、店長）：今天以後還有訂位排在這張桌就不能刪
  Future<void> deleteReservationTable(String tableId);
  /// 某張桌某一天不開（ops 0133；老闆、店長）：那天已經有訂位排在這張桌就不能設
  Future<List<TableDayOff>> tableDaysOff(String storeId, DateTime from, DateTime to);
  Future<void> setTableDayOff(String tableId, DateTime date, bool off);
  /// 座位圖排版（老闆 2026-11-01）：只存每張桌的位置與大小
  Future<void> saveTableLayout(String storeId, List<ReservationTable> tables);
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

  // ---------------- 打卡、員工資料（ops 0109，目前只開隱城） ----------------
  /// 我在這家店的打卡狀態；資料庫還沒更新時回 null（畫面就不顯示打卡）
  Future<AttendanceMe?> attendanceMe(String storeId);
  /// 掃碼打卡（時間＝伺服器現在；上班／下班由伺服器判斷）
  Future<PunchResult> punch(PunchLink link);
  /// 我的打卡與補登（跨店都列；營業日 from～to）
  Future<List<MyAttendanceRecord>> myAttendance(String storeId, DateTime from, DateTime to);
  /// 補登申請（本人，或店長替店裡的人）；核准後才算數。fromSchedule＝時間是從班表帶入的
  Future<String> requestAmendment(String storeId, String personId, String punchType, DateTime at, String reason,
      {bool fromSchedule = false});
  Future<void> cancelAmendment(String id);
  /// 店長、老闆核准或退回（退回要寫原因）
  Future<void> decideAmendment(String id, bool approve, {String? note});
  /// 待確認的打卡：確認或不採用（要原因，可以再改）
  Future<void> reviewPunch(String punchId, bool confirm, String reason);
  /// 一筆打卡的完整歷程（老闆、店長）：補登、每一次確認／不採用
  Future<List<PunchHistoryEntry>> punchHistory(String punchId);
  /// 補登可以選的人（老闆、店長）：這家店的人＋期間前後 31 天內來支援過的別家店員工
  Future<List<AttendancePerson>> attendancePeople(String storeId, DateTime from, DateTime to);
  Future<List<AttendanceAnomaly>> attendanceAnomalies(String storeId, DateTime from, DateTime to);
  Future<List<AttendanceSession>> attendanceSessions(String storeId, DateTime from, DateTime to);
  Future<List<AttendanceExportRow>> attendanceExport(String storeId, DateTime from, DateTime to);
  /// 打卡跟班表比對（ops 0127；老闆、店長）：早到、遲到、早退、晚走超過 30 分鐘、沒排班有打卡、有排班沒打卡
  Future<List<ScheduleCheckRow>> scheduleCheck(String storeId, DateTime from, DateTime to);
  /// 加班申請：老闆、店長看全店（待審的不管日期都列）；其他人只有自己的
  Future<List<OvertimeRequest>> overtimeList(String storeId, DateTime from, DateTime to);
  /// 申請加班（本人，或老闆、店長替店裡的人）；以營業日為單位、0.5 小時為一格、一定要寫原因
  Future<String> requestOvertime(String storeId, String personId, DateTime day, double hours, String reason);
  /// 核准（可以改時數）或退回（要寫原因）
  Future<void> decideOvertime(String id, bool approve, {double? hours, String? note});
  Future<void> cancelOvertime(String id);
  /// 隱城 V、O 的時間（平常＋照星期另設）；資料庫還沒更新回空的
  Future<List<ShiftMarkTime>> shiftMarkTimes(String storeId);
  Future<void> saveShiftMarkTime(String storeId, ShiftMarkTime t);
  Future<void> deleteShiftMarkTime(String storeId, String mark, int weekday);
  // 打卡機（老闆、店長設定；打卡機畫面本身不登入）
  Future<List<KioskInfo>> kiosks(String storeId);
  /// 回傳打卡機 id 與密鑰（密鑰只有這次拿得到，存在那台裝置上）
  Future<({String id, String secret})> registerKiosk(String storeId, String name);
  Future<void> disableKiosk(String kioskId);
  Future<KioskCode> kioskCode(String kioskId, String secret);
  /// 老闆：可以設成打卡用帳號的人（ops 0112）
  Future<List<KioskAccountCandidate>> kioskAccountCandidates(String storeId);
  /// 老闆：把這個帳號設成這家店的打卡用帳號（權限照舊，第一頁多一個密碼打卡）
  Future<void> setKioskAccount(String storeId, String userId);
  /// 登入的帳號是打卡用帳號就回它的店；不是（或資料庫還沒更新）回 null
  Future<KioskMine?> kioskMine();
  /// 打卡用帳號：輸入自己的 4 位數密碼打卡（ops 0131：靠密碼認人，時間是伺服器時間）
  Future<PinPunchResult> pinPunch(String pin);
  /// 打卡密碼有沒有設定（看不到密碼本身）；資料庫還沒更新回 null
  Future<List<PinStatus>?> pinStatus(String storeId);
  /// 設定／重設打卡密碼；pin 是 null＝隨機產生（只在回傳這次看得到）
  Future<PinSetResult> pinSet(String personId, String? pin);
  /// 老闆、店長：清除打卡密碼
  Future<void> pinClear(String personId);
  /// 員工資料一覽：老闆全部；店長身分證、帳號遮罩，看得到別人的薪率（ops 0110）、看不到可改自己的；其他人只有自己
  Future<List<StaffEntry>> staffDirectory(String storeId);
  /// 不用打卡的人（ops 0134；老闆、店長讀得到）：異常清單、打卡比對不列，薪資天數不從打卡帶
  Future<Set<String>> punchExemptIds(String storeId);
  /// 設定／取消不用打卡（只有老闆）
  Future<void> setPunchExempt(String storeId, String personId, bool exempt);
  /// 老闆確認（或取消確認）班表名字綁定的 App 帳號；userId＝畫面上看到的那個帳號，對不上就失敗
  Future<void> verifyBinding(String personId, String userId, {bool verify = true});
  /// 聯絡資料（老闆、店長）；payType 老闆、店長（不是自己）能改，傳 null＝不動
  Future<void> saveStaffHr(String storeId, String personId,
      {String? phone, String? emergencyContact, String? emergencyPhone, DateTime? leaveDate, String? payType});
  /// 到職日（班表人員 shift_people.hire_date；老闆、店長能改，ops 0028）；null＝清掉
  Future<void> saveHireDate(String storeId, String personId, DateTime? hireDate);
  Future<List<PayRate>> payRates(String personId);
  /// 新增薪率（老闆；店長只能替別人，ops 0110）。ops 0123 起生效日不用晚於既有的，同一個生效日只能一筆
  Future<void> addPayRate(String storeId, String personId, PayRate r);
  /// 修改一筆薪率的生效日、計薪方式、金額、投保級距、勞退自提（ops 0123；用 r.id 認）
  Future<void> updatePayRate(PayRate r);
  /// 刪除一筆薪率（ops 0123 起已生效的也可以刪）
  Future<void> deletePayRate(String id);
  /// 身分證、匯款帳號（只有老闆）
  Future<void> saveStaffIdentity(String storeId, String personId, {String? nationalId, String? bankCode, String? bankAccount});

  // ---------------- 薪資（ops 0110）：老闆、店長算；員工看自己已發布的薪資單 ----------------
  Future<PayrollSettings> payrollSettings(String storeId);
  /// 加班費算法（只有老闆）：fixed 固定時薪／lsa 依勞基法
  Future<void> setPayrollOvertime(String storeId, String mode, double rate);
  /// 建立或重新帶入這個月（薪率、打卡時數；不動手動填的）；回傳幾個人
  Future<int> preparePayroll(String storeId, DateTime month);
  Future<List<PayrollRow>> payrollMonth(String storeId, DateTime month);
  Future<PayrollReport> payrollReport(String storeId, DateTime month);
  /// 薪資預估（ops 0129）：每個人照薪率×班表算應發；老闆、店長（店長看不到自己那列）
  Future<PayrollEstimate> payrollEstimate(String storeId, DateTime month);
  /// 上次讀到的薪資預估（總覽先顯示用；沒有＝null）
  PayrollEstimate? peekPayrollEstimate(String storeId, DateTime month) => null;
  /// 存一個人的薪資；days／hours 傳 null＝用打卡帶入的值。回傳實發金額。
  /// extras（ops 0126）：全勤、勞保、健保、眷屬健保、所得稅、領現、自訂項目；傳 null＝不動
  Future<double?> savePayrollEntry(String storeId, String personId, DateTime month,
      {double? days, double? hours, double otHours = 0, double otHours2 = 0, double bonus = 0, double insurance = 0,
      double deduction = 0, PayExtras? extras, String? note, String? reason});
  /// 設公司登記全名（薪資單抬頭，ops 0126；只有老闆）。空白＝清掉，抬頭回到店名
  Future<void> setPayrollCompany(String storeId, String name);
  Future<void> publishPayroll(String storeId, DateTime month);
  /// 重新開啟已發布的月份（只有老闆，要寫原因）
  Future<void> reopenPayroll(String storeId, DateTime month, String reason);
  /// 不計薪（只有老闆）：不領薪的人（例如老闆自己）從應計薪名單拿掉；有修改紀錄
  Future<void> setPayrollExempt(String storeId, String personId, bool exempt);
  /// 我的薪資單（已發布、綁定經老闆確認）
  Future<List<PayrollSlip>> myPayslips(String storeId);
}

/// 把資料庫的錯誤訊息轉成店員看得懂的話（資料庫守衛的訊息本來就是中文）
String friendlyError(Object e) {
  final s = e.toString();
  final m = RegExp(r'message: ([^,]+)').firstMatch(s);
  // 0113：資料庫擋下來的訊息前面有代碼（給 App 判斷用），顯示時拿掉
  final msg = (m?.group(1) ?? s).replaceFirst(RegExp(r'^(SHIFT_BLOCKED|SHIFT_CODE_USED|SHIFT_UNDO_CONFLICT|SIGNUP_[A-Z]+|BOOKING_ASSIST_STALE|SHIFT_ASSIST_STALE|WISH_STALE|ONBOARD_[A-Z_]+|PL_TEMPLATE_[A-Z_]+)：'), '');
  if (msg.contains('duplicate key') && msg.contains('client_request')) return '這筆已經送出過了，不會重複新增。';
  if (msg.contains('row-level security')) return '沒有權限執行這個動作。';
  if (msg.contains('function public.payroll_')) return '資料庫還沒更新到薪資版本，請等老闆核准上線。';
  if (msg.contains('daily_revenue_one_per_day')) return '這一天已經有營收紀錄了，請從列表點進去修改。';
  if (msg.contains('Invalid login credentials')) return '帳號或密碼錯誤。';
  if (msg.contains('vendor_slips_store_id_vendor_slip_no_key')) return '這個廠商已經有相同單號的單據了。';
  if (msg.contains('Email not confirmed')) return '這個 Email 還沒確認，請先到信箱點確認連結。';
  if (msg.contains('User already registered') || msg.contains('already been registered')) return '這個 Email 已經有帳號了，請直接登入。';
  if (msg.contains('rate limit')) return '操作太頻繁，請稍後再試。';
  if (msg.contains('Signups not allowed') || msg.contains('signups are disabled')) return '目前沒有開放建立帳號，請聯絡老闆。';
  if (msg.contains('Password should be')) return '密碼太短，請至少 8 個字。';
  if (msg.contains('change_requests_title_check')) return '第一行請寫個簡短的標題。';
  if (msg.contains('staff_pay_rates_person_id_effective_from_key')) return '這個生效日已經有一筆薪資了，請直接點那一筆修改。';
  // ops 0169 損益設定：科目名稱重複、自動帶入指定兩次、自動帶入跟大項對不上
  if (msg.contains('pl_accounts_store_id_name_key')) return '這個科目名稱已經有了，請換一個名字。';
  if (msg.contains('pl_accounts_store_auto')) return '這種自動帶入已經指定給別的科目了，請先把那個科目改成「不自動帶入」。';
  if (msg.contains('pl_accounts_auto_category')) return '自動帶入跟大項對不上（人事基底放人事、租金基底放租金、刷卡手續費和進貨雜項放雜項）。';
  return msg.replaceAll('薪率', '薪資'); // 畫面上一律叫「薪資」（2026-11-15 老闆）；資料庫守衛的訊息還寫「薪率」（ops 0109、0110）
}
