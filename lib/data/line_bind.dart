/// LINE 群組綁定代碼（ops 0156）：老闆在 App 產生，群組裡打「綁定 店名 代碼」才綁得上。
/// 8 位數、10 分鐘有效、用一次就失效；資料庫只存雜湊，代碼只在產生的這一次看得到。
class LineBindCode {
  final String code;
  final DateTime expiresAt;
  const LineBindCode(this.code, this.expiresAt);

  factory LineBindCode.fromJson(Map<String, dynamic> j) => LineBindCode(
    j['code'] as String,
    DateTime.parse(j['expires_at'] as String).toLocal(),
  );

  /// 群組裡要打的那一句（店名中間的空白照打也可以）
  String command(String storeName) => '綁定 $storeName $code';

  /// 「還有 9 分 05 秒」／「已過期，請重新產生」
  String remaining(DateTime now) {
    final left = expiresAt.difference(now);
    if (left.inSeconds <= 0) return '已過期，請重新產生';
    final m = left.inMinutes;
    final s = (left.inSeconds % 60).toString().padLeft(2, '0');
    return '還有 $m 分 $s 秒';
  }

  bool expired(DateTime now) => !expiresAt.isAfter(now);
}
