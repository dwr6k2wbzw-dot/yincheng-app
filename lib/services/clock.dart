/// 店裡的時間一律用台北時間（健檢 2026-11-01，Bug 3）：
/// 以前「今天」「現在」用手機時間，老闆出國或手機時區跑掉時，今日訂位、時間軸紅線、交接「今天」、提醒逾期全部會錯。
/// 台灣沒有日光節約，固定 +8 即可。手機本來就在台北時，這兩個函式的結果跟以前一模一樣。
const taipeiOffset = Duration(hours: 8);

/// 把一個「真實時間點」換成「台北牆上時鐘」的 DateTime（isUtc＝false，欄位是台北的年月日時分）。
/// ⚠ 回傳值只拿來讀年月日時分，不能再傳進 toTaipei，也不能存回資料庫或拿來跟其他時間點比先後：
///   它的欄位是台北時間，但 Dart 會把它當成手機本地時間，手機不在台北時就差了好幾小時。
///   所以資料模型（Reservation.seatedAt 等）一律保留真實時間點，只在要畫在時間軸／判斷營業日的地方呼叫一次。
DateTime toTaipei(DateTime t) {
  final u = t.toUtc().add(taipeiOffset);
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second, u.millisecond);
}

/// 現在的台北時間（牆上時鐘）
DateTime taipeiNow() => toTaipei(DateTime.now());
