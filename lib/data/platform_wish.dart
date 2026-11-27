/// 許願單（ops 0149，公版）：店家想要 App 沒有的功能，寫一則送到平台待辦；平台回覆狀態和說明。
/// 只有公版那一份（SELF_SIGNUP）有入口；隱城、小城外用的是「功能許願」（change_requests）。
library;

/// 一家店每個月最多寫幾則（資料庫 platform_wish_create 也擋同一個數字）
const platformWishMonthlyLimit = 20;
const platformWishTitleMax = 60;
const platformWishBodyMax = 1000;

enum PlatformWishStatus { received, planned, declined, done }

PlatformWishStatus platformWishStatusOf(String? s) => switch (s) {
  'planned' => PlatformWishStatus.planned,
  'declined' => PlatformWishStatus.declined,
  'done' => PlatformWishStatus.done,
  _ => PlatformWishStatus.received,
};

String platformWishStatusLabel(PlatformWishStatus s) => switch (s) {
  PlatformWishStatus.received => '平台收到了',
  PlatformWishStatus.planned => '排進待辦',
  PlatformWishStatus.declined => '先不做',
  PlatformWishStatus.done => '做好了',
};

class PlatformWish {
  final String id;
  final String title;
  final String body;
  final String authorName;
  final PlatformWishStatus status;
  final String? reply;
  final DateTime createdAt;
  final DateTime? repliedAt;
  const PlatformWish({
    required this.id,
    required this.title,
    required this.body,
    required this.authorName,
    required this.status,
    this.reply,
    required this.createdAt,
    this.repliedAt,
  });

  factory PlatformWish.fromRow(Map<String, dynamic> r) => PlatformWish(
    id: r['id'] as String,
    title: r['title'] as String,
    body: r['body'] as String,
    authorName: (r['author_name'] as String?) ?? '',
    status: platformWishStatusOf(r['status'] as String?),
    reply: r['reply'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
    repliedAt: r['replied_at'] == null
        ? null
        : DateTime.parse(r['replied_at'] as String),
  );
}

/// 「想要什麼」「為什麼」合成資料庫的一段內容（為什麼可以不寫）
String composeWishBody(String what, String why) {
  final w = what.trim(), y = why.trim();
  return y.isEmpty ? w : '$w\n\n為什麼需要：$y';
}

/// 這個月（台北時間，傳進來的 now 已經是台北時間）寫了幾則
int wishesThisMonth(List<PlatformWish> items, DateTime now) => items.where((w) {
  final t = w.createdAt.toUtc().add(const Duration(hours: 8));
  return t.year == now.year && t.month == now.month;
}).length;

/// 送出前檢查（跟資料庫同一套規則，先在 App 講清楚）；沒問題回 null
String? validateWish(String title, String what, String why) {
  final t = title.trim();
  if (t.isEmpty) return '請寫一個標題';
  if (t.length > platformWishTitleMax) return '標題最多 $platformWishTitleMax 個字';
  if (what.trim().isEmpty) return '請寫你想要什麼';
  if (composeWishBody(what, why).length > platformWishBodyMax) {
    return '內容最多 $platformWishBodyMax 個字';
  }
  return null;
}
