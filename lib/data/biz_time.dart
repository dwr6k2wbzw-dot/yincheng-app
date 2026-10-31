// 營業日與時間軸用的純計算（不碰畫面、不碰網頁 API，可直接單元測試；健檢 2026-11-01 從 reservation_timeline.dart 搬出來）
import '../services/clock.dart';
import 'reservation_models.dart';

/// 營業日的分鐘數：凌晨 6 點前算前一天（加 24 小時）
int bizMinute(int m) => m < 360 ? m + 1440 : m;

/// 這個時間是不是在這個營業日（凌晨 6 點前算前一天）
bool onBizDay(DateTime t, DateTime day) {
  final s = toTaipei(t).subtract(const Duration(hours: 6));
  return s.year == day.year && s.month == day.month && s.day == day.day;
}

/// 入座／清桌時間只在同一個營業日才拿來畫（補登別天的到店，時間是補登當下，不能拿來畫；Codex 審查）
DateTime? seatedOn(Reservation r) => r.seatedAt != null && onBizDay(r.seatedAt!, r.date) ? r.seatedAt : null;
DateTime? clearedOn(Reservation r) => r.clearedAt != null && onBizDay(r.clearedAt!, r.date) ? r.clearedAt : null;

String minuteLabel(int m) {
  final x = m % 1440;
  return '${(x ~/ 60).toString().padLeft(2, '0')}:${(x % 60).toString().padLeft(2, '0')}';
}

/// 時間軸上點到的位置 → 訂位要存的（營業日, HH:mm）。
/// 營業日到隔天早上 6 點（分鐘數 < 1800 仍是這一天，凌晨的時段照慣例存在同一個營業日）；
/// 時間軸畫得到 6 點以後，那一段算下一個營業日（Codex 審查 PR #137）。
(DateTime, String) slotFromTimeline(DateTime day, int bizMin) {
  var d = day;
  var m = bizMin;
  if (m >= 30 * 60) {
    d = DateTime(day.year, day.month, day.day + 1);
    m -= 1440;
  }
  return (d, minuteLabel(m));
}
