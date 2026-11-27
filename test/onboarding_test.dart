import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/onboarding.dart';
import 'package:yincheng_ops/data/repository.dart';

void main() {
  group('訂位網址代號', () {
    test('合格的代號', () {
      expect(slugError('lane-bar'), isNull);
      expect(slugError('Bar2026'), isNull); // 大寫會轉小寫
      expect(slugError('ab'), isNull);
    });
    test('格式不對', () {
      expect(slugError(''), '請填訂位網址代號');
      expect(slugError('a'), '代號要 2～30 個字');
      expect(slugError('a' * 31), '代號要 2～30 個字');
      expect(slugError('my_bar'), '只能用小寫英文、數字和減號（-）');
      expect(slugError('小酒館'), '只能用小寫英文、數字和減號（-）');
      expect(slugError('-bar'), '開頭、結尾不能是減號');
      expect(slugError('bar-'), '開頭、結尾不能是減號');
      expect(slugError('my--bar'), '不能連續兩個減號');
    });
    test('保留字', () {
      for (final s in ['admin', 'BOOK', 'yincheng', 'xcw', 'www']) {
        expect(slugError(s), '這個代號是系統保留的，請換一個', reason: s);
      }
    });
    test('從店名猜代號：只留英文數字，中文店名猜不出來', () {
      expect(suggestSlug('Lane Bar 2F'), 'lane-bar-2f');
      expect(suggestSlug('巷口小酒館'), '');
      expect(suggestSlug('Admin'), ''); // 保留字不建議
      expect(suggestSlug('  Moon & Tide  '), 'moon-tide');
      expect(suggestSlug('a' * 40).length, 30);
    });
  });

  test('時段整理：補兩位數、排序、去重、看不懂的丟掉', () {
    expect(normalizeSlots(['19:00', '9:5', '18:30', '19:00', '25:00', 'x']),
        ['09:05', '18:30', '19:00']);
    expect(normalizeSlots(defaultOnboardingSlots), defaultOnboardingSlots);
  });

  test('每天名額：空白＝不限、超出範圍有說明', () {
    expect(parseDayLimit('', 500, '每天最多幾組'), (null, null));
    expect(parseDayLimit(' 8 ', 500, '每天最多幾組'), (8, null));
    expect(parseDayLimit('0', 500, '每天最多幾組').$2, '每天最多幾組請填 1～500，空白＝不限');
    expect(parseDayLimit('501', 500, '每天最多幾組').$2, isNotNull);
  });

  test('開店進度：訂位、訂位頁、成員三項；排班人力不算', () {
    final s = OnboardingStatus.fromJson({
      'booking': true,
      'slug': 'lane-bar',
      'page': false,
      'members': true,
      'staffing': false
    });
    expect(s.done, 2);
    expect(s.complete, isFalse);
    expect(
        const OnboardingStatus(booking: true, page: true, members: true)
            .complete,
        isTrue);
  });

  test('資料庫的錯誤代號對到哪一欄、訊息拿掉代號', () {
    expect(onboardingErrorField('message: ONBOARD_SLUG_TAKEN：這個訂位網址代號有人用了'),
        'slug');
    expect(onboardingErrorField('message: ONBOARD_PHONE：電話只能有數字'), 'phone');
    expect(onboardingErrorField('message: ONBOARD_EXISTS：已經設定過'), 'other');
    expect(
        friendlyError(
            Exception('message: ONBOARD_SLUG_TAKEN：這個訂位網址代號有人用了，請換一個,')),
        '這個訂位網址代號有人用了，請換一個');
  });

  test('新店網址用 ?s=代號', () {
    expect(onboardingBookingUrl('lane-bar'),
        'https://dwr6k2wbzw-dot.github.io/yincheng-app/book/?s=lane-bar');
  });

  group('示範版走一遍', () {
    test('建店 → 還沒有訂位設定 → 精靈建好 → 不能再建、代號有人用了', () async {
      final repo = DemoRepository();
      final id = await repo.signupCreateStore('巷口小酒館', '阿明');
      expect(await repo.reservationSettings(id), isNull);
      expect(await repo.bookingProfile(id), isNull);
      var st = await repo.onboardingStatus(id);
      expect([st.booking, st.page, st.members], [false, false, false]);

      await expectLater(
          repo.setupOnlineBooking(id,
              slug: 'lane-bar', displayName: '巷口小酒館', slotTimes: ['19:00']),
          throwsA(
              predicate((e) => e.toString().contains('ONBOARD_SLUG_TAKEN'))));
      await expectLater(
          repo.setupOnlineBooking(id,
              slug: 'admin', displayName: '巷口小酒館', slotTimes: ['19:00']),
          throwsA(predicate(
              (e) => e.toString().contains('ONBOARD_SLUG_RESERVED'))));
      await expectLater(
          repo.setupOnlineBooking(id,
              slug: 'moon-bar', displayName: '巷口小酒館', slotTimes: []),
          throwsA(predicate((e) => e.toString().contains('ONBOARD_SLOTS'))));

      final slug = await repo.setupOnlineBooking(id,
          slug: 'Moon-Bar',
          displayName: '巷口小酒館',
          slotTimes: ['20:00', '19:00'],
          closedWeekdays: [3, 1],
          maxGroups: 8);
      expect(slug, 'moon-bar');
      final s = (await repo.reservationSettings(id))!;
      expect([
        s.slug,
        s.displayName,
        s.slotTimes,
        s.closedWeekdays,
        s.maxGroupsPerDay
      ], [
        'moon-bar',
        '巷口小酒館',
        ['19:00', '20:00'],
        [1, 3],
        8
      ]);
      expect((await repo.bookingProfile(id))!.title, {'zh': '巷口小酒館'});
      st = await repo.onboardingStatus(id);
      expect([st.booking, st.slug, st.page], [true, 'moon-bar', false]);

      await expectLater(
          repo.setupOnlineBooking(id,
              slug: 'moon-bar-2', displayName: 'x', slotTimes: ['19:00']),
          throwsA(predicate((e) => e.toString().contains('ONBOARD_EXISTS'))));

      await repo.createInvite([id], Role.staff, '新同事');
      st = await repo.onboardingStatus(id);
      expect(st.members, isTrue);
    });
  });
}
