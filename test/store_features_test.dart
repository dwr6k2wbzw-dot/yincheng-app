import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/store_features.dart';
import 'package:yincheng_ops/theme.dart';

Map<String, dynamic> _member(String name, dynamic features, {bool withKey = true}) => {
      'store_id': 's-$name',
      'role': 'owner',
      'display_name': '測試',
      'stores': {'name': name, if (withKey) 'store_features': features},
    };

void main() {
  tearDown(() {
    for (final n in ['隱城', '小城外', '新客戶的店']) {
      StoreFeatures.remember(n, null);
    }
  });

  test('資料庫沒給開關：兩家店照以前寫死的內容，不認得的店全部關閉', () {
    final yc = StoreFeatures.of('隱城');
    expect([yc.schedule, yc.excelSynced, yc.vendorSlips, yc.paidByCategories], everyElement(isTrue));
    expect([yc.multiLineRevenue, yc.shiftCodes], everyElement(isFalse));
    expect(yc.logo, 'yincheng');
    final xc = StoreFeatures.of('小城外');
    expect([xc.schedule, xc.excelSynced, xc.vendorSlips, xc.multiLineRevenue, xc.shiftCodes], everyElement(isTrue));
    expect(xc.paidByCategories, isFalse);
    expect(xc.logo, 'xcw');
    final other = StoreFeatures.of('新客戶的店');
    expect(
        [other.schedule, other.excelSynced, other.vendorSlips, other.multiLineRevenue, other.shiftCodes, other.paidByCategories],
        everyElement(isFalse));
    expect(other.logo, isNull);
    expect(StoreFeatures.of(null).schedule, isFalse);
  });

  test('讀到成員資格時用資料庫的開關，不看店名', () {
    Membership.fromRow(_member('新客戶的店', {
      'schedule': true,
      'excel_synced': false,
      'multi_line_revenue': true,
      'vendor_slips': false,
      'shift_codes': true,
      'paid_by_categories': false,
      'logo': 'xcw',
    }));
    final f = StoreFeatures.of('新客戶的店');
    expect([f.schedule, f.multiLineRevenue, f.shiftCodes], everyElement(isTrue));
    expect([f.excelSynced, f.vendorSlips, f.paidByCategories], everyElement(isFalse));
    expect(storeLogo('新客戶的店'), 'assets/logos/xcw.png');

    // 資料庫把隱城的開關關掉 → 以資料庫為準，不會退回寫死的內容
    Membership.fromRow(_member('隱城', {'schedule': false, 'logo': null}));
    expect(StoreFeatures.of('隱城').schedule, isFalse);
    expect(storeLogo('隱城'), isNull);
  });

  test('PostgREST 回陣列也讀得到；空的、沒有這個欄位（資料庫還沒更新）照以前寫死的', () {
    Membership.fromRow(_member('新客戶的店', [
      {'schedule': true}
    ]));
    expect(StoreFeatures.of('新客戶的店').schedule, isTrue);

    Membership.fromRow(_member('小城外', const []));
    expect(StoreFeatures.of('小城外').multiLineRevenue, isTrue);
    Membership.fromRow(_member('小城外', null));
    expect(StoreFeatures.of('小城外').shiftCodes, isTrue);
    final m = Membership.fromRow(_member('隱城', null, withKey: false));
    expect(m.storeName, '隱城');
    expect(StoreFeatures.of('隱城').schedule, isTrue);
    expect(storeLogo('隱城'), 'assets/logos/yincheng.png');
  });

  test('不認得的 logo 代號不顯示 logo', () {
    Membership.fromRow(_member('新客戶的店', {'logo': 'somebody-else'}));
    expect(storeLogo('新客戶的店'), isNull);
  });
}
