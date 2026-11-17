/// 每家店的功能開關（資料庫 0116 `store_features`，一家店一列；只有後臺能改）。
/// 以前是用店名寫死在 `lib/config.dart`；公版的店名是客戶自己取的，不能再靠店名判斷。
class StoreFeatures {
  /// 有「班表」分頁、交接頁可以指定班表人員
  final bool schedule;

  /// 營收、進貨以日報表為準（顯示同步狀態、匯入的資料不能改）
  final bool excelSynced;

  /// 營收分「咖啡／調酒／拉麵／訂金」四項（調酒＝酒水＋餐食；客單＝調酒收入 ÷ 來客數）
  final bool multiLineRevenue;

  /// 新增進貨拍照時順便建立銷貨單草稿
  final bool vendorSlips;

  /// 班表用班別代碼＋時段、照時數統計（關＝用 V／休 記號）
  final bool shiftCodes;

  /// 新增進貨時，依付款方式隱藏不適用的舊類別
  final bool paidByCategories;

  /// App 內建 logo 的代號（沒有＝不顯示 logo）
  final String? logo;

  const StoreFeatures({
    this.schedule = false,
    this.excelSynced = false,
    this.multiLineRevenue = false,
    this.vendorSlips = false,
    this.shiftCodes = false,
    this.paidByCategories = false,
    this.logo,
  });

  /// 資料庫讀不到開關時（0116 還沒套用、示範資料）照以前寫死的內容；之後可以拿掉
  factory StoreFeatures.legacy(String storeName) => switch (storeName) {
        '隱城' => const StoreFeatures(
            schedule: true, excelSynced: true, vendorSlips: true, paidByCategories: true, logo: 'yincheng'),
        '小城外' => const StoreFeatures(
            schedule: true, excelSynced: true, vendorSlips: true, multiLineRevenue: true, shiftCodes: true, logo: 'xcw'),
        _ => const StoreFeatures(),
      };

  /// 資料庫的一列（PostgREST 可能回物件，也可能回只有一筆的陣列）；讀不到回 null
  static StoreFeatures? fromRow(dynamic raw) {
    if (raw is List) raw = raw.isEmpty ? null : raw.first;
    if (raw is! Map) return null;
    return StoreFeatures(
      schedule: raw['schedule'] == true,
      excelSynced: raw['excel_synced'] == true,
      multiLineRevenue: raw['multi_line_revenue'] == true,
      vendorSlips: raw['vendor_slips'] == true,
      shiftCodes: raw['shift_codes'] == true,
      paidByCategories: raw['paid_by_categories'] == true,
      logo: raw['logo'] as String?,
    );
  }

  static final _loaded = <String, StoreFeatures>{};

  /// 讀到成員資格時記下這家店的開關（[f] 是 null＝資料庫沒給，改用寫死的內容）
  static void remember(String storeName, StoreFeatures? f) {
    if (f == null) {
      _loaded.remove(storeName);
    } else {
      _loaded[storeName] = f;
    }
  }

  /// 這家店的開關
  static StoreFeatures of(String? storeName) =>
      storeName == null ? const StoreFeatures() : _loaded[storeName] ?? StoreFeatures.legacy(storeName);
}
