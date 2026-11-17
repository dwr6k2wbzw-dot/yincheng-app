import 'store_features.dart';
import 'models.dart';

/// 班表可以用哪些記號、班別幾小時，全部看資料庫，不看店名：
///   * 功能開關 shiftCodes（0116）：關＝用 V／O 記上班、看天數；開＝用班別代碼、看時數
///   * 班別／時段清單 shift_mark_options（0075）：每家店自己的班別代碼＋時段、兼職時段
/// 清單還沒讀到（[o] 是 null）時先不列班別，讀到就有。

const _workMarks = ['V', 'O'];
const _awayMarks = ['休', '指休', '特休'];

/// 點格子時可選的記號：上班類（V、O、班別）在前，休假類在後
List<String> storeMarks(String store, ShiftOptions? o) => [
      if (!StoreFeatures.of(store).shiftCodes) ..._workMarks,
      if (o != null) ...o.codes.map((c) => c.mark),
      ..._awayMarks,
    ];

/// 班別 → 時段（說明用；停用的班別也查得到）
Map<String, String> storeCodeTimes(String store, ShiftOptions? o) => {
      if (o != null)
        for (final c in o.allCodes) c.mark: c.timeRange ?? '',
    };

/// 以時數統計的店家（開了 shiftCodes）：班別 → 時數（照班別的時段算）；看天數的店 → null
Map<String, double>? storeCodeHours(String store, ShiftOptions? o) {
  if (!StoreFeatures.of(store).shiftCodes) return null;
  return {
    if (o != null)
      for (final c in o.allCodes)
        if (c.timeRange != null) c.mark: ShiftMonth.hoursOf(c.timeRange, const {}),
  };
}

/// 停用的班別（0113）：已經排過的格子照舊顯示、照算時數，但新的排班不能再用
Set<String> hiddenCodes(ShiftOptions? o) =>
    {if (o != null) for (final c in o.allCodes) if (c.hidden) c.mark};

/// 兼職時段選項
List<String> storeRanges(String store, ShiftOptions? o) => o != null ? o.ranges : const [];
