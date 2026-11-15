import 'package:shared_preferences/shared_preferences.dart';

/// 掃了打卡 QR 但還沒登入：先記下「有一次打卡還沒打到」。
/// 員工如果去收信（註冊確認信）再登入，新開的頁面已經沒有那次的碼，打卡就沒打到；
/// 登入後看到這個記號，要明確告訴他「這次沒打到，請重新掃碼」，不能讓他以為打卡成功。
const missedPunchPref = 'attendance_punch_unfinished_at';

Future<void> markPunchStarted([DateTime? now]) async =>
    (await SharedPreferences.getInstance()).setInt(missedPunchPref, (now ?? DateTime.now()).millisecondsSinceEpoch);

Future<void> clearPunchStarted() async => (await SharedPreferences.getInstance()).remove(missedPunchPref);

/// 有沒有一次沒打到的打卡（24 小時內）；看過就清掉
Future<bool> takeMissedPunch({DateTime? now}) async {
  final prefs = await SharedPreferences.getInstance();
  final at = prefs.getInt(missedPunchPref);
  if (at == null) return false;
  await prefs.remove(missedPunchPref);
  final age = (now ?? DateTime.now()).difference(DateTime.fromMillisecondsSinceEpoch(at));
  return !age.isNegative && age < const Duration(hours: 24);
}
