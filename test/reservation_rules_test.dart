// 健檢 2026-11-01 補的第一批單元測試：名額不算現場客、台北時間、營業日
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/reservation_models.dart';
import 'package:yincheng_ops/data/biz_time.dart';
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
    test('同一個時間點，不管手機在哪個時區、資料是 UTC 還是本地，換出來的台北時間都一樣（Codex 審查 PR #137）', () {
      final instant = DateTime.utc(2026, 11, 1, 12, 0); // 台北 20:00
      for (final t in [instant, instant.toLocal(), DateTime.parse('2026-11-01T12:00:00Z').toLocal()]) {
        final tp = toTaipei(t);
        expect([tp.day, tp.hour, tp.minute], [1, 20, 0], reason: 'input $t (isUtc=${t.isUtc})');
      }
    });
    test('營業日：凌晨 6 點前算前一天', () {
      expect(bizToday(DateTime(2026, 11, 1, 2, 30)), DateTime(2026, 10, 31));
      expect(bizToday(DateTime(2026, 11, 1, 6, 0)), DateTime(2026, 11, 1));
    });
  });

  group('入座時間與營業日（Codex 審查 PR #137 的情境）', () {
    // 台北凌晨 04:00 入座（UTC 前一天 20:00）：仍屬 11/1 營業日。
    // 以前資料讀進來先轉一次台北、判斷營業日又轉一次，手機不在台北時會算成 11/2 而把入座紀錄丟掉。
    final r = Reservation.fromRow({
      'id': 'x', 'slot_date': '2026-11-01', 'slot_time': '23:30:00', 'party_size': 2, 'guest_name': '測試',
      'status': 'arrived', 'source': 'app', 'created_at': '2026-11-01T10:00:00Z',
      'seated_at': '2026-11-01T20:00:00Z',
    });
    test('凌晨入座仍算同一個營業日', () {
      expect(onBizDay(r.seatedAt!, DateTime(2026, 11, 1)), isTrue);
      expect(seatedOn(r), isNotNull);
    });
    test('入座的台北時間是 04:00', () {
      final t = toTaipei(r.seatedAt!);
      expect([t.day, t.hour], [2, 4]);
    });
  });
}
