// 健檢 2026-11-01 補的第一批單元測試：名額不算現場客、台北時間、營業日
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/reservation_models.dart';
import 'package:yincheng_ops/services/clock.dart';

Reservation _r(String id, int party, {bool walkIn = false, String status = 'confirmed'}) => Reservation(
      id: id, date: DateTime(2026, 11, 1), time: '20:00', party: party, name: id, phone: '',
      status: status, source: 'app', createdAt: DateTime(2026, 11, 1), walkIn: walkIn,
    );

void main() {
  group('每日名額 DayLimits.overBy', () {
    const lim = DayLimits(closed: false, maxGroups: 2, maxGuests: 6, maxLarge: 1, largeSize: 4);
    test('現場客不算進組數、人數、大桌（跟資料庫 reservation_day_usage 一樣）', () {
      final others = [_r('a', 2), _r('w1', 4, walkIn: true), _r('w2', 4, walkIn: true)];
      expect(lim.overBy(others, 2), isEmpty);
    });
    test('訂位本身仍會算', () {
      final others = [_r('a', 2), _r('b', 2)];
      expect(lim.overBy(others, 2), contains(contains('一天最多 2 組')));
    });
    test('取消的不算', () {
      final others = [_r('a', 2), _r('c', 2, status: 'cancelled')];
      expect(lim.overBy(others, 2), isEmpty);
    });
  });

  group('台北時間', () {
    test('UTC 轉台北 +8', () {
      final t = toTaipei(DateTime.utc(2026, 10, 31, 18, 30));
      expect([t.year, t.month, t.day, t.hour, t.minute], [2026, 11, 1, 2, 30]);
      expect(t.isUtc, isFalse);
    });
    test('營業日：凌晨 6 點前算前一天', () {
      expect(bizToday(DateTime(2026, 11, 1, 2, 30)), DateTime(2026, 10, 31));
      expect(bizToday(DateTime(2026, 11, 1, 6, 0)), DateTime(2026, 11, 1));
    });
  });
}
