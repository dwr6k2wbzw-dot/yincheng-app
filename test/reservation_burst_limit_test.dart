import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/reservation_models.dart';

// ops 0151：每家店自己的網路訂位流量上限
void main() {
  Map<String, dynamic> row([Map<String, dynamic> extra = const {}]) => {
        'store_id': 's1', 'slug': 'demo', 'first_slot': '19:00', 'last_slot': '23:00', 'same_day_cutoff': '17:00',
        ...extra,
      };

  test('資料庫有這一欄：讀得到設定的數字', () {
    expect(ReservationSettings.fromRow(row({'web_burst_limit': 80})).webBurstLimit, 80);
  });

  test('資料庫還沒有這一欄（還沒套用 0151）：是 null，畫面不顯示、存檔不送', () {
    expect(ReservationSettings.fromRow(row()).webBurstLimit, isNull);
  });
}
