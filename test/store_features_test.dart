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

  test('班表記號、班別時數只看功能開關和資料庫的班別清單，不看店名', () {
    final xcOpts = ShiftOptions([
      ShiftMarkOption.fromRow({'id': 'b', 'kind': 'code', 'mark': 'B', 'time_range': '17:00-00:30', 'sort_order': 10}),
      ShiftMarkOption.fromRow({'id': 'bh', 'kind': 'code', 'mark': 'BH', 'time_range': '17:00-01:30', 'sort_order': 20}),
      ShiftMarkOption.fromRow({'id': 'rbk', 'kind': 'code', 'mark': 'RBK', 'time_range': '16:00-23:00', 'sort_order': 30}),
      ShiftMarkOption.fromRow(
          {'id': 'old', 'kind': 'code', 'mark': 'BP', 'time_range': '19:00-00:30', 'sort_order': 40, 'hidden': true}),
      ShiftMarkOption.fromRow({'id': 'r1', 'kind': 'range', 'mark': '18:00-00:30', 'sort_order': 10}),
    ]);
    final ycOpts = ShiftOptions([
      ShiftMarkOption.fromRow({'id': 'r1', 'kind': 'range', 'mark': '18:00-00:30', 'sort_order': 10}),
    ]);

    // 小城外（班別代碼）：跟以前 App 內建的結果一樣
    expect(storeMarks('小城外', xcOpts), ['B', 'BH', 'RBK', '休', '指休', '特休']);
    expect(storeCodeHours('小城外', xcOpts), {'B': 7.5, 'BH': 8.5, 'RBK': 7.0, 'BP': 5.5});
    expect(storeCodeTimes('小城外', xcOpts)['BH'], '17:00-01:30');
    expect(storeRanges('小城外', xcOpts), ['18:00-00:30']);
    expect(hiddenCodes(xcOpts), {'BP'});

    // 隱城（V／O 記號、看天數）
    expect(storeMarks('隱城', ycOpts), ['V', 'O', '休', '指休', '特休']);
    expect(storeCodeHours('隱城', ycOpts), isNull);
    expect(storeRanges('隱城', ycOpts), ['18:00-00:30']);

    // 清單還沒讀到：不列班別、時數表是空的（不拿 App 內建的數字頂替）
    expect(storeMarks('小城外', null), ['休', '指休', '特休']);
    expect(storeCodeHours('小城外', null), isEmpty);
    expect(storeRanges('小城外', null), isEmpty);
    expect(storeMarks('隱城', null), ['V', 'O', '休', '指休', '特休']);

    // 新的店：沒開班別代碼＝V／O；開了＝照它自己的班別清單
    expect(storeMarks('新客戶的店', null), ['V', 'O', '休', '指休', '特休']);
    expect(storeCodeHours('新客戶的店', null), isNull);
    Membership.fromRow(_member('新客戶的店', {'shift_codes': true}));
    final opts = ShiftOptions([
      ShiftMarkOption.fromRow({'id': 'o1', 'kind': 'code', 'mark': 'A', 'time_range': '10:00-18:00', 'sort_order': 1}),
    ]);
    expect(storeMarks('新客戶的店', opts), ['A', '休', '指休', '特休']);
    expect(storeCodeHours('新客戶的店', opts), {'A': 8.0});

    // 資料庫把小城外的班別代碼關掉：改用 V／O、照天數
    Membership.fromRow(_member('小城外', {'shift_codes': false}));
    expect(storeCodeHours('小城外', xcOpts), isNull);
    expect(storeMarks('小城外', xcOpts).take(2), ['V', 'O']);
  });

  test('不認得的 logo 代號不顯示 logo', () {
    Membership.fromRow(_member('新客戶的店', {'logo': 'somebody-else'}));
    expect(storeLogo('新客戶的店'), isNull);
  });
}
