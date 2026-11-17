/// 自助註冊（ops 0119）的欄位檢查：跟資料庫同一套——去掉前後空白後 1～40 個字。
/// 回傳要顯示的錯誤，沒問題回 null。
String? signupNameError(String v, String what) {
  final t = v.trim();
  if (t.isEmpty) return '請填$what';
  if (t.runes.length > 40) return '$what最多 40 個字';
  return null;
}
