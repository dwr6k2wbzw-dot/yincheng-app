// 許願單（ops 0149）：資料轉換、狀態文字、送出前檢查、這個月寫了幾則
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/platform_wish.dart';

void main() {
  test('從資料庫的一列轉過來', () {
    final w = PlatformWish.fromRow({
      'id': 'x',
      'title': '想要會員點數',
      'body': '來五次送一杯',
      'author_name': '老闆',
      'status': 'planned',
      'reply': '下個月做',
      'created_at': '2026-11-27T07:00:00Z',
      'replied_at': '2026-11-28T01:00:00Z',
    });
    expect(w.status, PlatformWishStatus.planned);
    expect(w.reply, '下個月做');
    expect(w.repliedAt, isNotNull);
    final n = PlatformWish.fromRow({'id': 'y', 'title': 't', 'body': 'b', 'status': 'new', 'created_at': '2026-11-27T07:00:00Z'});
    expect(n.status, PlatformWishStatus.received);
    expect(n.authorName, '');
    expect(n.reply, isNull);
  });

  test('狀態文字', () {
    expect(platformWishStatusLabel(platformWishStatusOf('new')), '平台收到了');
    expect(platformWishStatusLabel(platformWishStatusOf('planned')), '排進待辦');
    expect(platformWishStatusLabel(platformWishStatusOf('declined')), '先不做');
    expect(platformWishStatusLabel(platformWishStatusOf('done')), '做好了');
    expect(platformWishStatusOf('奇怪的值'), PlatformWishStatus.received);
  });

  test('想要什麼＋為什麼合成內容；為什麼可以不寫', () {
    expect(composeWishBody(' 選座位 ', ''), '選座位');
    expect(composeWishBody('選座位', ' 常有人問 '), '選座位\n\n為什麼需要：常有人問');
  });

  test('送出前檢查跟資料庫同一套', () {
    expect(validateWish('', '要', ''), '請寫一個標題');
    expect(validateWish('   ', '要', ''), '請寫一個標題');
    expect(validateWish('長' * 61, '要', ''), '標題最多 60 個字');
    expect(validateWish('長' * 60, '要', ''), isNull);
    expect(validateWish('標題', '  ', '為什麼'), '請寫你想要什麼');
    expect(validateWish('標題', '長' * 990, '長' * 20), '內容最多 1000 個字');
    expect(validateWish('標題', '要', ''), isNull);
  });

  test('這個月寫了幾則（用台北時間切月份）', () {
    PlatformWish at(String utc) => PlatformWish(
        id: utc, title: 't', body: 'b', authorName: '', status: PlatformWishStatus.received, createdAt: DateTime.parse(utc));
    final items = [
      at('2026-11-30T15:59:00Z'), // 台北 11/30 23:59 → 11 月
      at('2026-11-30T16:00:00Z'), // 台北 12/1 00:00 → 12 月
      at('2026-12-05T03:00:00Z'),
      at('2026-10-31T17:00:00Z'), // 台北 11/1 01:00 → 11 月
    ];
    expect(wishesThisMonth(items, DateTime(2026, 12, 10)), 2);
    expect(wishesThisMonth(items, DateTime(2026, 11, 10)), 2);
  });
}
