/// 訂位頁上每家店自己的樣子（ops 0135 booking_profiles；0145 起 logo、封面照可以自己上傳）。
/// 只有老闆能改；客人看到的是訂位頁讀資料庫的這一份。
class BookingProfile {
  static const langsAll = ['zh', 'en', 'ja'];
  static const langNames = {'zh': '中文', 'en': 'English', 'ja': '日本語'};

  final List<String> langs; // 一定有 zh
  final Map<String, String> title; // 大標（沒填＝訂位設定的店名）
  final Map<String, String> shortName; // 簡稱（姊妹店卡片用）
  final Map<String, String> intro; // 一句話介紹
  final Map<String, String> address; // 外語地址（中文用訂位設定的地址）
  final Map<String, String> directions; // 外語交通說明
  final int? minSpend;
  final Map<String, String> minSpendText; // {amount} 會換成「每人 800 元」
  final List<BookingInfoRow> infoRows;
  final String? logoUrl; // 內建檔名（logo-xcw.png）或上傳的路徑（{店的 id}/logo-xxxx.png）
  final String? heroUrl;
  final String? heroPos; // 封面照取景，例「22% 45%」
  final String? sisterStoreId;

  const BookingProfile({
    this.langs = const ['zh'],
    this.title = const {},
    this.shortName = const {},
    this.intro = const {},
    this.address = const {},
    this.directions = const {},
    this.minSpend,
    this.minSpendText = const {},
    this.infoRows = const [],
    this.logoUrl,
    this.heroUrl,
    this.heroPos,
    this.sisterStoreId,
  });

  static Map<String, String> _texts(Object? v) => {
        if (v is Map)
          for (final e in v.entries)
            if (e.value is String && (e.value as String).isNotEmpty) e.key as String: e.value as String,
      };

  factory BookingProfile.fromRow(Map<String, dynamic> r) => BookingProfile(
        langs: [for (final l in (r['langs'] as List? ?? const ['zh'])) l as String],
        title: _texts(r['title']),
        shortName: _texts(r['short_name']),
        intro: _texts(r['intro']),
        address: _texts(r['address_i18n']),
        directions: _texts(r['directions_i18n']),
        minSpend: (r['min_spend'] as num?)?.toInt(),
        minSpendText: _texts(r['min_spend_text']),
        infoRows: [
          for (final x in (r['info_rows'] as List? ?? const []))
            if (x is Map) BookingInfoRow(label: _texts(x['label']), text: _texts(x['text'])),
        ],
        logoUrl: r['logo_url'] as String?,
        heroUrl: r['hero_url'] as String?,
        heroPos: r['hero_pos'] as String?,
        sisterStoreId: r['sister_store_id'] as String?,
      );

  /// 存進資料庫的欄位（只存開著的語言的文字；沒開的語言不留，訂位頁也不會顯示）
  Map<String, dynamic> toRow() {
    Map<String, String> keep(Map<String, String> m) => {
          for (final e in m.entries)
            if (langs.contains(e.key) && e.value.trim().isNotEmpty) e.key: e.value.trim(),
        };
    return {
      'langs': [for (final l in langsAll) if (l == 'zh' || langs.contains(l)) l],
      'title': keep(title),
      'short_name': keep(shortName),
      'intro': keep(intro),
      'address_i18n': keep({...address}..remove('zh')),
      'directions_i18n': keep({...directions}..remove('zh')),
      'min_spend': minSpend,
      'min_spend_text': keep(minSpendText),
      'info_rows': [
        for (final row in infoRows)
          if ((row.label['zh'] ?? '').trim().isNotEmpty) {'label': keep(row.label), 'text': keep(row.text)},
      ],
      'logo_url': logoUrl,
      'hero_url': heroUrl,
      'hero_pos': heroPos,
      'sister_store_id': sisterStoreId,
    };
  }
}

class BookingInfoRow {
  final Map<String, String> label; // 標題（中文必填，12 字以內）
  final Map<String, String> text; // 內容（300 字以內）
  const BookingInfoRow({this.label = const {}, this.text = const {}});
}

/// 老闆自己上傳的圖（ops 0145）：{店的 id}/logo-xxxx.png、{店的 id}/hero-xxxx.jpg
final _uploaded = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(logo|hero)-[a-z0-9]{6,40}\.(png|jpg|jpeg|webp)$');
final _builtin = RegExp(r'^[a-z0-9][a-z0-9-]{0,60}\.(png|jpg|jpeg|webp)$');

bool isUploadedBookingAsset(String? path) => path != null && _uploaded.hasMatch(path);

/// 圖片的網址：上傳的在公開檔案區，內建的在訂位頁那裡；其他（格式不對）＝null
String? bookingAssetUrl(String? path, {required String supabaseUrl, required String bookBase}) {
  if (path == null || path.isEmpty) return null;
  if (_uploaded.hasMatch(path)) return '$supabaseUrl/storage/v1/object/public/booking-assets/$path';
  if (_builtin.hasMatch(path)) return '$bookBase$path';
  return null;
}

/// 新上傳的檔名：{店的 id}/{logo|hero}-{時間＋亂數}.{副檔名}（每次換圖都是新檔名，不覆蓋舊的）
String newBookingAssetPath(String storeId, String kind, String ext, {DateTime? now, int? salt}) {
  final t = (now ?? DateTime.now()).millisecondsSinceEpoch.toRadixString(36);
  final r = (salt ?? DateTime.now().microsecond * 7919).toRadixString(36);
  return '$storeId/$kind-$t$r.$ext';
}

/// 封面照取景「22% 45%」⇄ (0.22, 0.45)
(double, double) parseHeroPos(String? s) {
  final m = RegExp(r'^(\d{1,3})% (\d{1,3})%$').firstMatch(s ?? '');
  if (m == null) return (0.5, 0.5);
  return ((int.parse(m[1]!) / 100).clamp(0, 1).toDouble(), (int.parse(m[2]!) / 100).clamp(0, 1).toDouble());
}

String heroPosText(double x, double y) => '${(x * 100).round()}% ${(y * 100).round()}%';
