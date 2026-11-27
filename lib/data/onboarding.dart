/// 開店精靈（公版，ops 0155）：新店一步一步把線上訂位設好。
/// 這裡只有不用連資料庫的部分（檢查、預設值、進度），畫面在 lib/screens/onboarding_screen.dart。
library;

/// 開店設定做到哪（`onboarding_status`）
class OnboardingStatus {
  final bool booking; // 訂位設定建好了
  final String? slug; // 訂位網址代號
  final bool page; // 訂位頁的樣子（有 logo、封面照或介紹）
  final bool members; // 有其他成員或等待加入的邀請
  final bool staffing; // 設過排班人力
  const OnboardingStatus({
    this.booking = false,
    this.slug,
    this.page = false,
    this.members = false,
    this.staffing = false,
  });

  factory OnboardingStatus.fromJson(Map<String, dynamic> j) => OnboardingStatus(
    booking: j['booking'] == true,
    slug: j['slug'] as String?,
    page: j['page'] == true,
    members: j['members'] == true,
    staffing: j['staffing'] == true,
  );

  /// 精靈要做的三件事（排班人力在班表頁設，只當參考、不算在「還沒完成」）
  int get done => [booking, page, members].where((x) => x).length;
  static const total = 3;
  bool get complete => done == total;
}

/// 新店常見的訂位時段（晚上 18:00～21:00 每 30 分鐘），老闆可以增刪
const defaultOnboardingSlots = [
  '18:00',
  '18:30',
  '19:00',
  '19:30',
  '20:00',
  '20:30',
  '21:00',
];

/// 系統保留、不能當訂位網址代號的字（跟資料庫 app.booking_slug_reserved 同一份）
const reservedBookingSlugs = {
  'admin',
  'api',
  'app',
  'apps',
  'assets',
  'auth',
  'book',
  'booking',
  'bookings',
  'cancel',
  'demo',
  'dev',
  'help',
  'login',
  'logout',
  'mail',
  'new',
  'official',
  'preview',
  'previews',
  'reserve',
  'reservation',
  'reservations',
  'root',
  'signup',
  'static',
  'staging',
  'support',
  'system',
  'test',
  'www',
  'claude',
  'anthropic',
  'yincheng',
  'xcw',
};

/// 訂位網址代號的問題（沒問題回 null）。資料庫會再檢查一次，這裡只是讓老闆打字時就知道。
String? slugError(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return '請填訂位網址代號';
  if (s.length < 2 || s.length > 30) return '代號要 2～30 個字';
  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(s)) return '只能用小寫英文、數字和減號（-）';
  if (s.startsWith('-') || s.endsWith('-')) return '開頭、結尾不能是減號';
  if (s.contains('--')) return '不能連續兩個減號';
  if (reservedBookingSlugs.contains(s)) return '這個代號是系統保留的，請換一個';
  return null;
}

/// 從店名猜一個代號：只留英文數字（中文店名猜不出來就回空白，請老闆自己取）
String suggestSlug(String storeName) {
  final s = storeName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  if (s.length < 2) return '';
  final cut = s.length > 30
      ? s.substring(0, 30).replaceAll(RegExp(r'-$'), '')
      : s;
  return slugError(cut) == null ? cut : '';
}

/// 時段整理：去空白、補兩位數、排序、去重（「9:5」→ 09:05）；看不懂的丟掉
List<String> normalizeSlots(Iterable<String> raw) {
  final out = <String>{};
  for (final r in raw) {
    final m = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(r.trim());
    if (m == null) continue;
    final h = int.parse(m[1]!), mi = int.parse(m[2]!);
    if (h > 23 || mi > 59) continue;
    out.add('${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}');
  }
  return out.toList()..sort();
}

/// 每天名額欄位：空白＝不限；回 (數字, 問題)
(int?, String?) parseDayLimit(String raw, int max, String label) {
  final t = raw.trim();
  if (t.isEmpty) return (null, null);
  final n = int.tryParse(t);
  if (n == null || n < 1 || n > max) return (null, '$label請填 1～$max，空白＝不限');
  return (n, null);
}

/// 開店精靈的錯誤代號 → 是哪一欄的問題（slug／name／phone／address／slots／weekdays／limits／other）
String onboardingErrorField(String raw) {
  if (raw.contains('ONBOARD_SLUG')) return 'slug';
  if (raw.contains('ONBOARD_NAME')) return 'name';
  if (raw.contains('ONBOARD_PHONE')) return 'phone';
  if (raw.contains('ONBOARD_ADDRESS')) return 'address';
  if (raw.contains('ONBOARD_SLOTS')) return 'slots';
  if (raw.contains('ONBOARD_WEEKDAYS')) return 'weekdays';
  if (raw.contains('ONBOARD_LIMITS')) return 'limits';
  return 'other';
}
