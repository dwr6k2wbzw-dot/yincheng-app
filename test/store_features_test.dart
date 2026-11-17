import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/shift_marks.dart';
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

  test('照時數統計看功能開關，不看店名（Codex P2）', () {
    // 沒有資料庫開關：小城外照時數、隱城和不認得的店照天數
    expect(storeCodeHours('小城外', null)?['B'], 7.5);
    expect(storeCodeHours('隱城', null), isNull);
    expect(storeCodeHours('新客戶的店', null), isNull);

    // 新的店開了班別代碼：照時數，時數從這家店自己的班別時段算
    Membership.fromRow(_member('新客戶的店', {'shift_codes': true}));
    final opts = ShiftOptions([
      ShiftMarkOption.fromRow({'id': 'o1', 'kind': 'code', 'mark': 'A', 'time_range': '10:00-18:00', 'sort_order': 1}),
    ]);
    expect(storeCodeHours('新客戶的店', opts), {'A': 8.0});
    expect(storeCodeHours('新客戶的店', null), isEmpty);

    // 資料庫把小城外的班別代碼關掉：改照天數
    Membership.fromRow(_member('小城外', {'shift_codes': false}));
    expect(storeCodeHours('小城外', null), isNull);
  });

  test('不認得的 logo 代號不顯示 logo', () {
    Membership.fromRow(_member('新客戶的店', {'logo': 'somebody-else'}));
    expect(storeLogo('新客戶的店'), isNull);
  });
}
