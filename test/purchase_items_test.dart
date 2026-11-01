import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/purchase_items_math.dart';

void main() {
  final gin = Product('p1', '琴酒 Gordon', '酒水', '瓶');
  final lemon = Product('p2', '檸檬', '餐食', '顆');
  final tonic = Product('p3', '通寧水', '酒水', '瓶');

  group('itemsForSave', () {
    test('加總等於金額時不補差額', () {
      final rows = itemsForSave([
        PurchaseItem(name: '琴酒', qty: 2, unitPrice: 500, productId: 'p1', stockQty: 2),
      ], 1000);
      expect(rows, hasLength(1));
      expect(itemsTotal(rows), 1000);
    });

    test('有運費時補一行「其他差額」，明細合計＝進貨金額', () {
      final rows = itemsForSave([
        PurchaseItem(name: '琴酒', qty: 3, unitPrice: 333.333, productId: 'p1', stockQty: 3),
      ], 1100);
      expect(rows.last.name, diffItemName);
      expect(rows.last.toStock, isFalse);
      expect(itemsTotal(rows), 1100);
      expect(rows.first.unitPrice, 333.33); // 單價存到分
    });

    test('折讓（品項比金額多）補負的差額', () {
      final rows = itemsForSave([PurchaseItem(name: 'A', qty: 1, unitPrice: 1050)], 1000);
      expect(rows.last.unitPrice, -50);
      expect(itemsTotal(rows), 1000);
    });

    test('沒有品項就不存任何明細（不會只有一行差額）', () {
      expect(itemsForSave([], 500), isEmpty);
      expect(itemsForSave([PurchaseItem(name: ' ', qty: 1, unitPrice: 5)], 500), isEmpty);
    });

    test('選了品項但沒填庫存數量＝不入庫存', () {
      final rows = itemsForSave([PurchaseItem(name: 'A', qty: 1, unitPrice: 10, productId: 'p1')], 10);
      expect(rows.single.productId, isNull);
      expect(rows.single.stockQty, isNull);
    });

    test('不改到畫面上的那份清單', () {
      final it = PurchaseItem(name: 'A', qty: 1, unitPrice: 10.456);
      itemsForSave([it], 10);
      expect(it.unitPrice, 10.456);
    });
  });

  group('退貨', () {
    test('數量與庫存都用負數，明細合計＝負的進貨金額', () {
      final rows = itemsForSave([
        PurchaseItem(name: '琴酒', qty: 2, unitPrice: 500, productId: 'p1', stockQty: 2),
      ], 1080);
      final json = [for (final r in rows) r.toJson(negate: true)];
      expect(json.first['qty'], -2);
      expect(json.first['stock_qty'], -2);
      final total = json.fold<double>(0, (a, j) => a + (j['qty'] as num) * (j['unit_price'] as num));
      expect(total, -1080);
    });
  });

  group('suggestProduct', () {
    final ps = [gin, lemon, tonic];
    test('名稱相同或包含就建議', () {
      expect(suggestProduct('檸檬', ps), lemon);
      expect(suggestProduct('通寧水 200ml', ps), tonic);
      expect(suggestProduct('Gordon', ps), gin);
    });
    test('一個字不比', () {
      expect(suggestProduct('水', ps), isNull);
    });
    test('對不到回傳 null', () {
      expect(suggestProduct('冰塊', ps), isNull);
    });
  });

  group('defaultStockQty', () {
    test('單位相同＝數量', () {
      expect(defaultStockQty(PurchaseItem(name: '琴酒', qty: 6, unit: '瓶'), gin), 6);
    });
    test('單位不同要店員填', () {
      expect(defaultStockQty(PurchaseItem(name: '通寧水', qty: 2, unit: '箱'), tonic), isNull);
    });
    test('辨識給了換算就用', () {
      expect(defaultStockQty(PurchaseItem(name: '通寧水', qty: 2, unit: '箱', stockQty: 48), tonic), 48);
    });
  });

  test('辨識結果：有對應的算已決定，沒有的要店員決定', () {
    final r = SlipReading.fromJson({
      'ok': true,
      'vendor': '大倉捷',
      'date': '2026-10-30',
      'total': 1300,
      'category': '酒水',
      'items': [
        {'name': '琴酒', 'qty': 2, 'unit': '瓶', 'unit_price': 500, 'amount': 1000, 'product_id': 'p1', 'stock_qty': 2, 'sure': true},
        {'name': '冰塊', 'qty': 1, 'unit': '包', 'unit_price': 300, 'amount': 300, 'product_id': null, 'stock_qty': null, 'sure': false},
      ],
      'notes': null,
    });
    expect(r.items.first.decided, isTrue);
    expect(r.items.last.decided, isFalse);
    expect(r.items.last.sure, isFalse);
    expect(r.date, DateTime(2026, 10, 30));
    expect(r.items.every((i) => i.source == 'ai'), isTrue);
  });

  group('本月進貨總表 summarizeItems', () {
    test('同一個庫存品項合在一起，單價不同用平均', () {
      final rows = summarizeItems([
        PurchaseItem(name: '琴酒 700ml', qty: 2, unit: '瓶', unitPrice: 500, productId: 'p1'),
        PurchaseItem(name: 'Gordon 琴酒', qty: 1, unit: '瓶', unitPrice: 560, productId: 'p1'),
        PurchaseItem(name: '檸檬', qty: 3, unit: '斤', unitPrice: 100),
      ], {'p1': '琴酒 Gordon'});
      expect(rows.first.name, '琴酒 Gordon');
      expect(rows.first.qty, 3);
      expect(rows.first.total, 1560);
      expect(rows.first.priceVaries, isTrue);
      expect(rows.first.unitPrice, 520);
      expect(rows.last.unitPrice, 100);
    });
    test('退貨扣回、其他差額不算品項', () {
      final rows = summarizeItems([
        PurchaseItem(name: '檸檬', qty: 5, unit: '斤', unitPrice: 100),
        PurchaseItem(name: '檸檬', qty: -1, unit: '斤', unitPrice: 100),
        PurchaseItem(name: diffItemName, qty: 1, unitPrice: 80),
      ], {});
      expect(rows, hasLength(1));
      expect(rows.single.qty, 4);
      expect(rows.single.total, 400);
    });
    test('依金額大到小', () {
      final rows = summarizeItems([
        PurchaseItem(name: 'A', qty: 1, unitPrice: 10),
        PurchaseItem(name: 'B', qty: 1, unitPrice: 99),
      ], {});
      expect(rows.map((r) => r.name), ['B', 'A']);
    });
  });
}
