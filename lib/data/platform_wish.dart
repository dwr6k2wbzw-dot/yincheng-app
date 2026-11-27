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

/// 資料庫的狀態代碼（new／planned／declined／done）
String platformWishStatusCode(PlatformWishStatus s) => switch (s) {
  PlatformWishStatus.received => 'new',
  PlatformWishStatus.planned => 'planned',
  PlatformWishStatus.declined => 'declined',
  PlatformWishStatus.done => 'done',
};

/// 平台管理者看的狀態名稱（ops 0159）：分頁、回覆時選狀態用
String platformAdminStatusLabel(PlatformWishStatus s) => switch (s) {
  PlatformWishStatus.received => '新的',
  PlatformWishStatus.planned => '規劃中',
  PlatformWishStatus.declined => '不做',
  PlatformWishStatus.done => '完成',
};

/// 平台管理者看到的一則許願（ops 0159）：多帶店名；回覆時要把看到的狀態、回覆時間原樣送回去比對
class PlatformAdminWish {
  final PlatformWish wish;
  final String storeId;
  final String storeName;
  /// 資料庫給的回覆時間原字串（不經過 DateTime 轉換，送回去比對才不會差到微秒）
  final String? repliedAtRaw;
  const PlatformAdminWish({required this.wish, required this.storeId, required this.storeName, this.repliedAtRaw});

  factory PlatformAdminWish.fromRow(Map<String, dynamic> r) => PlatformAdminWish(
    wish: PlatformWish.fromRow(r),
    storeId: r['store_id'] as String,
    storeName: (r['store_name'] as String?) ?? '',
    repliedAtRaw: r['replied_at'] as String?,
  );
}

/// 各狀態有幾則（分頁上的數字）；沒有的狀態算 0
Map<PlatformWishStatus, int> platformWishCountsOf(Iterable<MapEntry<String, int>> rows) => {
  for (final s in PlatformWishStatus.values) s: 0,
  for (final e in rows) platformWishStatusOf(e.key): e.value,
};

/// 回覆前檢查：回覆最多 1000 字（資料庫同一個數字）；沒問題回 null
String? validateAdminReply(String reply) =>
    reply.trim().length > platformWishBodyMax ? '回覆最多 $platformWishBodyMax 個字' : null;

/// 資料庫說「別人剛回覆過」（ops 0159，40001 WISH_STALE）
bool isWishStale(Object e) => e.toString().contains('WISH_STALE');
