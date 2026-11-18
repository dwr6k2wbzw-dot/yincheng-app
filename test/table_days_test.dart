// 桌位只在某一天加開、只在某一天不開（ops 0133）：時間軸、座位圖、排桌看到的桌
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/reservation_models.dart';

void main() {
  final d = DateTime(2026, 11, 20), other = DateTime(2026, 11, 21);
  final all = [
    const ReservationTable(id: 'A', name: 'A'),
    const ReservationTable(id: 'B', name: 'B'),
    ReservationTable(id: 'X', name: '加開', onlyDate: d),
  ];

  test('加開那天看得到加開的桌，設了不開的變停用並標出來', () {
    final a = tablesForDay(all, d, {'B'});
    expect(a.map((t) => t.id), ['A', 'B', 'X']);
    expect(a[0].active, isTrue);
    expect(a[1].active, isFalse);
    expect(a[1].dayOff, isTrue);
  });

  test('別天不出現加開的桌，不開的設定也不影響別天', () {
    final b = tablesForDay(all, other, {});
    expect(b.map((t) => t.id), ['A', 'B']);
    expect(b.every((t) => t.active && !t.dayOff), isTrue);
  });
}
