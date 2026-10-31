/// 店裡的時間一律用台北時間（健檢 2026-11-01，Bug 3）：
/// 以前「今天」「現在」用手機時間，老闆出國或手機時區跑掉時，今日訂位、時間軸紅線、交接「今天」、提醒逾期全部會錯。
/// 台灣沒有日光節約，固定 +8 即可。手機本來就在台北時，這兩個函式的結果跟以前一模一樣。
const taipeiOffset = Duration(hours: 8);

/// 把任何時間（資料庫回來的 UTC、手機時間）換成「台北牆上時鐘」的 DateTime（isUtc＝false，欄位是台北的年月日時分）
DateTime toTaipei(DateTime t) {
  final u = t.toUtc().add(taipeiOffset);
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second, u.millisecond);
}

/// 現在的台北時間（牆上時鐘）
DateTime taipeiNow() => toTaipei(DateTime.now());
