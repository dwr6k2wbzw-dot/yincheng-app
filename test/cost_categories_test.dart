// 進貨類別跟著店（ops 0165，公版）：類別屬於哪家店的判斷、示範資料的新增／改名／停用規則（跟資料庫一樣）、
// 錯誤代碼拿掉。示範資料都是虛構的。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/repository.dart';

void main() {
  group('belongsTo', () {
    test('有店的 id 就只比 id（同名的別家店不算）', () {
      final c = CostCategory.full('c1', '酒水', '阿明咖啡',
          costGroup: 'drink', inMiscRate: false, storeId: 's1');
      expect(c.belongsTo('s1', '阿明咖啡'), isTrue);
      expect(c.belongsTo('s2', '阿明咖啡'), isFalse);
    });
    test('沒有店的 id（資料庫還沒更新）照舊比店名；店名空白＝每家店都能用', () {
      final yc = CostCategory.full('yc_drink', '酒水', '隱城',
          costGroup: 'drink', inMiscRate: false);
      expect(yc.belongsTo('any', '隱城'), isTrue);
      expect(yc.belongsTo('any', '小城外'), isFalse);
      final shared = CostCategory.full('x', '酒水', null,
          costGroup: 'drink', inMiscRate: false);
      expect(shared.belongsTo('any', '小城外'), isTrue);
    });
  });

  test('錯誤訊息前面的代碼拿掉', () {
    expect(
        friendlyError(
            Exception('message: CATEGORY_TAKEN：這家店已經有同名的類別, code: 23505')),
        '這家店已經有同名的類別');
    expect(
        friendlyError(
            Exception('message: CATEGORY_USED：這個類別已經有進貨, code: 22023')),
        '這個類別已經有進貨');
  });

  group('示範資料（同資料庫 0165 的規則）', () {
    late DemoRepository repo;
    setUp(() async {
      repo = DemoRepository();
      await repo.signIn('new@demo', 'x');
      await repo.signupCreateStore('阿明咖啡', '阿明');
    });

    test('新店自動有 酒水／餐食／雜項，只看得到自己店的', () async {
      final cats = await repo.costCategories();
      expect(cats.map((c) => '${c.name}|${c.costGroup}|${c.inMiscRate}'),
          ['酒水|drink|false', '餐食|food|false', '雜項|other|true']);
      expect(cats.every((c) => c.storeId == 'demo-new'), isTrue);
      expect(await repo.seedCostCategories('demo-new'), 0,
          reason: '已經有類別就不再帶入');
    });

    test('新增、改名、停用', () async {
      final code = await repo.saveCostCategory('demo-new',
          name: ' 咖啡豆 ', costGroup: 'food', inMiscRate: false);
      var cats = await repo.costCategories();
      expect(cats.firstWhere((c) => c.code == code).name, '咖啡豆');
      await repo.saveCostCategory('demo-new',
          code: code,
          name: '咖啡生豆',
          costGroup: 'food',
          inMiscRate: false,
          selectable: false);
      cats = await repo.costCategories();
      final c = cats.firstWhere((c) => c.code == code);
      expect((c.name, c.selectable), ('咖啡生豆', false));
    });

    test('擋：空白、太長、同名、不認得的類、別家店', () async {
      Future<String> err(Future<Object?> f) async {
        try {
          await f;
          return 'ok';
        } catch (e) {
          return friendlyError(e);
        }
      }

      expect(
          await err(repo.saveCostCategory('demo-new',
              name: ' ', costGroup: 'food', inMiscRate: false)),
          contains('1～20'));
      expect(
          await err(repo.saveCostCategory('demo-new',
              name: '字' * 21, costGroup: 'food', inMiscRate: false)),
          contains('1～20'));
      expect(
          await err(repo.saveCostCategory('demo-new',
              name: '酒水', costGroup: 'drink', inMiscRate: false)),
          contains('同名'));
      expect(
          await err(repo.saveCostCategory('demo-new',
              name: '咖啡', costGroup: 'coffee', inMiscRate: false)),
          contains('酒水、餐食或雜項'));
      expect(
          await err(repo.saveCostCategory('yc',
              name: '咖啡', costGroup: 'food', inMiscRate: false)),
          contains('照日報表'));
    });

    test('一家店最多 50 個', () async {
      for (var i = 0; i < 47; i++) {
        await repo.saveCostCategory('demo-new',
            name: '類別$i', costGroup: 'other', inMiscRate: true);
      }
      expect((await repo.costCategories()).length, 50);
      expect(
          () => repo.saveCostCategory('demo-new',
              name: '第五十一', costGroup: 'other', inMiscRate: true),
          throwsA(predicate((e) => friendlyError(e!).contains('最多 50'))));
    });
  });
}
