import '../config.dart';
import 'models.dart';

/// 班別／時段清單（0075，老闆 2026-10-28：兩家店都可以自己新增、刪除；隱城兼職也可排時段）
/// 清單讀不到（例如舊資料庫）時，照 lib/config.dart 原本的設定。

/// 點格子時可選的記號：上班類（V、O、班別）在前，休假類在後
List<String> storeMarks(String store, ShiftOptions? o) {
  final cfg = AppConfig.shiftMarks[store] ?? const ['V', '休', '指休', 'O'];
  if (o == null || !o.loaded) return cfg;
  final legacyCodes = AppConfig.shiftCodeTimes[store]?.keys.toSet() ?? const <String>{};
  final base = cfg.where((m) => !legacyCodes.contains(m)).toList();
  return [
    ...base.where((m) => !ShiftMonth.isAway(m)),
    ...o.codes.map((c) => c.mark),
    ...base.where(ShiftMonth.isAway),
  ];
}

/// 班別 → 時段（說明用；舊代碼也查得到）
Map<String, String> storeCodeTimes(String store, ShiftOptions? o) => {
      ...?AppConfig.shiftCodeTimes[store],
      if (o != null && o.loaded)
        for (final c in o.codes) c.mark: c.timeRange ?? '',
    };

/// 以時數統計的店家（小城外）：班別 → 時數；隱城看天數 → null
Map<String, double>? storeCodeHours(String store, ShiftOptions? o) {
  final cfg = AppConfig.shiftHours[store];
  if (cfg == null) return null;
  return {
    ...cfg,
    if (o != null && o.loaded)
      for (final c in o.codes)
        if (c.timeRange != null) c.mark: ShiftMonth.hoursOf(c.timeRange, const {}),
  };
}

/// 兼職時段選項
List<String> storeRanges(String store, ShiftOptions? o) {
  if (o != null && o.loaded) return o.ranges;
  return store == '小城外' ? AppConfig.shiftQuickRanges : const [];
}
