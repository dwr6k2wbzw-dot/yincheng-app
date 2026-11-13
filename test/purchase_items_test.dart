import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/purchase_items_math.dart';

void main() {
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

  test('辨識結果：直接列進總表，不對應庫存', () {
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
    expect(r.items.every((i) => i.productId == null && i.stockQty == null), isTrue);
    expect(r.items.last.sure, isFalse);
    expect(r.date, DateTime(2026, 10, 30));
    expect(r.items.every((i) => i.source == 'ai'), isTrue);
  });

  group('進貨報價 buildQuotes', () {
    String? group(String c) => {'d': 'drink', 'f': 'food', 'm': 'other'}[c];
    QuoteLine line(String name, double price, int day, {String cat = 'd', String? unit = '瓶', double qty = 1, String? vendor}) =>
        QuoteLine(name: name, unit: unit, unitPrice: price, qty: qty, date: DateTime(2026, 11, day), vendor: vendor, categoryCode: cat);

    test('每個品項取最近一次的單價，帶上一次不同的價錢；分酒類、餐食，雜項不列', () {
      final rows = buildQuotes([
        line('琴酒 700ml', 500, 2, vendor: '甲'),
        line('琴酒700ML', 560, 9, vendor: '乙'),
        line('檸檬', 100, 5, cat: 'f', unit: '斤'),
        line('塑膠袋', 30, 5, cat: 'm', unit: '包'),
      ], const [], group);
      expect(rows.map((r) => r.name), ['檸檬', '琴酒700ML']);
      final gin = rows.last;
      expect([gin.group, gin.price, gin.previous, gin.vendor, gin.date.day], ['drink', 560, 500, '乙', 9]);
      expect(rows.first.group, 'food');
      expect(rows.first.previous, isNull);
    });
    test('退貨、沒單價、其他差額不算；單位不同分開列', () {
      final rows = buildQuotes([
        line('可樂', 20, 3, unit: '罐'),
        line('可樂', 450, 4, unit: '箱'),
        line('可樂', 25, 5, unit: '罐', qty: -2),
        line('萊姆', 0, 5),
        line(diffItemName, 80, 5, unit: null),
      ], const [], group);
      expect(rows.map((r) => '${r.name}${r.unit}:${r.price}'), ['可樂罐:20.0', '可樂箱:450.0']);
    });
    test('手動改單價：之後沒有更新的進貨才算數；改的品名、單位一直保留', () {
      final lines = [line('琴酒', 500, 2), line('琴酒', 560, 9)];
      final key = quoteKey('琴酒', '瓶');
      final still = buildQuotes(lines, [QuoteEdit(key: key, name: 'Gordon 琴酒', unitPrice: 540, asOf: DateTime(2026, 11, 9))], group).single;
      expect([still.name, still.price, still.manual, still.previous, still.edited], ['Gordon 琴酒', 540, true, 560, true]);
      final newer = buildQuotes(lines, [QuoteEdit(key: key, name: 'Gordon 琴酒', unitPrice: 540, asOf: DateTime(2026, 11, 2))], group).single;
      expect([newer.name, newer.price, newer.manual, newer.previous], ['Gordon 琴酒', 560, false, 500]);
      expect([newer.rawName, newer.rawPrice], ['琴酒', 560]);
    });
    test('手動拿掉的標成 hidden（畫面另外收起來），還原後照進貨資料', () {
      final lines = [line('琴酒', 500, 2)];
      final hidden = buildQuotes(lines, [QuoteEdit(key: quoteKey('琴酒', '瓶'), hidden: true)], group).single;
      expect([hidden.hidden, hidden.edited], [true, false]);
      expect(buildQuotes(lines, const [], group).single.hidden, isFalse);
    });
    test('手動改價後，同一天後來又進一次：改看新的進貨單價', () {
      QuoteLine at(double price, int hour) => QuoteLine(
          name: '琴酒', unit: '瓶', unitPrice: price, qty: 1, date: DateTime(2026, 11, 9), at: DateTime(2026, 11, 9, hour), categoryCode: 'd');
      final edit = QuoteEdit(key: quoteKey('琴酒', '瓶'), unitPrice: 540, asOf: DateTime(2026, 11, 9), asOfAt: DateTime(2026, 11, 9, 15));
      expect(buildQuotes([at(560, 15)], [edit], group).single.price, 540);
      // 登記順序跟讀回來的順序相反也一樣：照登記時間
      final later = buildQuotes([at(580, 21), at(560, 15)], [edit], group).single;
      expect([later.price, later.manual, later.previous], [580, false, 560]);
    });
    test('同一天進兩次，取後面那一行', () {
      final rows = buildQuotes([line('琴酒', 500, 2), line('琴酒', 520, 2)], const [], group);
      expect([rows.single.price, rows.single.previous], [520, 500]);
    });
  });
}
