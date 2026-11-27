// 訂位頁的樣子（公版階段 2 第 2、3 步；ops 0135／0145）：資料轉換、上傳圖片的路徑與網址、封面照取景。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/booking_profile.dart';

const sid = '11111111-2222-4333-8444-555555555555';

void main() {
  test('讀資料庫的列：空字串當成沒填、info_rows 照順序', () {
    final p = BookingProfile.fromRow({
      'langs': ['zh', 'en'],
      'title': {'zh': '測試店', 'en': ''},
      'info_rows': [
        {'label': {'zh': '營業時間'}, 'text': {'zh': '19:00～01:00'}},
      ],
      'min_spend': 600,
      'logo_url': 'logo-xcw.png',
    });
    expect(p.langs, ['zh', 'en']);
    expect(p.title, {'zh': '測試店'});
    expect(p.infoRows.single.label['zh'], '營業時間');
    expect(p.minSpend, 600);
  });

  test('存檔：沒開的語言文字不存、中文一定在、外語地址不存中文、沒有中文標題的資訊卡列不存', () {
    final row = const BookingProfile(
      langs: ['zh'],
      title: {'zh': ' 測試店 ', 'ja': '試験'},
      address: {'zh': '不該存', 'en': 'Taipei'},
      infoRows: [
        BookingInfoRow(label: {'zh': '營業時間', 'en': 'Hours'}, text: {'zh': '每天'}),
        BookingInfoRow(label: {'en': 'Only EN'}, text: {'en': 'x'}),
      ],
    ).toRow();
    expect(row['langs'], ['zh']);
    expect(row['title'], {'zh': '測試店'});
    expect(row['address_i18n'], <String, String>{});
    expect(row['info_rows'], [
      {'label': {'zh': '營業時間'}, 'text': {'zh': '每天'}},
    ]);
  });

  test('語言順序固定 中→英→日', () {
    expect(const BookingProfile(langs: ['ja', 'zh', 'en']).toRow()['langs'], ['zh', 'en', 'ja']);
  });

  test('圖片網址：上傳的走公開檔案區、內建的走訂位頁、格式不對的不給', () {
    String? u(String? p) => bookingAssetUrl(p, supabaseUrl: 'https://x.supabase.co', bookBase: 'https://b/book/');
    expect(u('$sid/logo-abc123.png'), 'https://x.supabase.co/storage/v1/object/public/booking-assets/$sid/logo-abc123.png');
    expect(u('hero-xcw.jpg'), 'https://b/book/hero-xcw.jpg');
    expect(u('$sid/x/logo-abc123.png'), isNull);
    expect(u('https://evil.example/a.png'), isNull);
    expect(u(null), isNull);
    expect(isUploadedBookingAsset('$sid/hero-abc123.webp'), isTrue);
    expect(isUploadedBookingAsset('hero-xcw.jpg'), isFalse);
  });

  test('新上傳的檔名符合資料庫的格式（0145 booking_asset_name_ok）', () {
    final p = newBookingAssetPath(sid, 'logo', 'png', now: DateTime(2026, 11, 27), salt: 12345);
    expect(isUploadedBookingAsset(p), isTrue);
    expect(p.startsWith('$sid/logo-'), isTrue);
    expect(isUploadedBookingAsset(newBookingAssetPath(sid, 'hero', 'jpg')), isTrue);
  });

  test('封面照取景：文字和數字互換、格式不對用置中', () {
    expect(parseHeroPos('22% 45%'), (0.22, 0.45));
    expect(parseHeroPos(null), (0.5, 0.5));
    expect(parseHeroPos('左上'), (0.5, 0.5));
    expect(heroPosText(0.224, 0.456), '22% 46%');
  });
}
